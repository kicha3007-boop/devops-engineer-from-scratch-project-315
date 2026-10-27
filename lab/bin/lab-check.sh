#!/bin/sh
# Проверка развёрнутого стенда (make lab-check). Выполняется в toolbox внутри сети p315-lab:
# домен приложения там указывает на «ВМ», а корень сертификатов берётся у Pebble.
set -eu

DOMAIN=${DOMAIN:-bulletins.127.0.0.1.nip.io}
PUBLIC_PORT=${PUBLIC_PORT:-28443}
VM=${VM:-p315-vm}
SSH="ssh -q -i /lab-ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@$VM"
TMP=$(mktemp -d)
BASE="https://$DOMAIN"
failed=0

ok()   { printf '  [ok]   %s\n' "$*"; }
fail() { printf '  [FAIL] %s\n' "$*"; failed=1; }

# Корень сертификатов Pebble (у Let's Encrypt он и так есть в системе)
curl -fsSk https://pebble:15000/roots/0 > "$TMP/root.pem"
CURL="curl -sS --cacert $TMP/root.pem"

echo "HTTPS и nginx"
code=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "http://$DOMAIN/some/page?x=1")
[ "$code" = "301 https://$DOMAIN:$PUBLIC_PORT/some/page?x=1" ] && ok "HTTP -> HTTPS: $code" || fail "редирект HTTP: $code"

$CURL -o "$TMP/index.html" -D "$TMP/index.h" "$BASE/" && ok "сертификат проверен по цепочке до корня ACME" || fail "TLS"
head -1 "$TMP/index.h" | grep -q ' 200' && ok "главная страница: $(head -1 "$TMP/index.h" | tr -d '\r')" || fail "главная страница"
grep -qi 'strict-transport-security' "$TMP/index.h" && ok "заголовок HSTS" || fail "нет HSTS"
issuer=$(echo | $SSH "openssl s_client -connect 127.0.0.1:443 -servername $DOMAIN 2>/dev/null | openssl x509 -noout -issuer -enddate" | tr '\n' ' ')
ok "сертификат: $issuer"

if curl -s -o /dev/null --cacert "$TMP/root.pem" --tlsv1.1 --tls-max 1.1 "$BASE/" 2>/dev/null; then
    fail "TLS 1.1 принят"
else
    ok "TLS 1.1 отклонён, разрешены только TLS 1.2/1.3"
fi

asset=$(grep -o 'assets/[^"]*\.js' "$TMP/index.html" | head -1)
$CURL -o /dev/null "$BASE/$asset"
cache=$($CURL -o /dev/null -D - "$BASE/$asset" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-cache-status"{print $2}')
[ "$cache" = "HIT" ] && ok "статика /$asset отдаётся из кеша nginx (X-Cache-Status: HIT)" || fail "кеш статики: '$cache'"

echo "Приложение и БД"
total=$($CURL "$BASE/api/bulletins?page=1&perPage=1" | python3 -c 'import sys,json; print(json.load(sys.stdin)["total"])')
ok "объявлений в БД: $total"

echo "S3: загрузка и скачивание через приложение"
python3 -c 'import os,sys; sys.stdout.buffer.write(b"\x89PNG\r\n\x1a\n" + os.urandom(2048))' > "$TMP/upload.png"
$CURL -o "$TMP/upload.json" -F "file=@$TMP/upload.png;type=image/png" "$BASE/api/files/upload"
key=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["key"])' "$TMP/upload.json")
url=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["url"])' "$TMP/upload.json")
ok "загружен файл: key=$key"
case "$url" in
    "https://$DOMAIN:$PUBLIC_PORT/media/$key") ok "ссылка на файл: $url" ;;
    *) fail "неожиданная ссылка: $url" ;;
esac
$CURL -o "$TMP/download.png" "$BASE/media/$key"
cmp -s "$TMP/upload.png" "$TMP/download.png" && ok "скачанный через nginx файл совпадает с загруженным" || fail "файл из /media/ отличается"
cache=$($CURL -o /dev/null -D - "$BASE/media/$key" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-cache-status"{print $2}')
[ "$cache" = "HIT" ] && ok "картинка отдаётся из кеша nginx (HIT)" || fail "кеш картинок: '$cache'"

title="Проверка стенда $(date +%s)"
id=$($CURL -H 'Content-Type: application/json' \
    -d "{\"title\":\"$title\",\"description\":\"Создано make lab-check\",\"state\":\"PUBLISHED\",\"contact\":\"lab@example.com\",\"price\":100,\"imageKey\":\"$key\"}" \
    "$BASE/api/bulletins" | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')
image=$($CURL "$BASE/api/bulletins/$id" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("imageUrl"))')
[ "$image" = "$url" ] && ok "объявление #$id с картинкой из S3 сохранено" || fail "imageUrl объявления: $image"

echo "Сеть: наружу открыты только 22/80/443"
for port in 5432 8080 9090; do
    if curl -s -o /dev/null --connect-timeout 3 "telnet://$VM:$port" 2>/dev/null; then
        fail "порт $port доступен снаружи «ВМ»"
    else
        ok "порт $port снаружи закрыт"
    fi
done
fw=$($SSH "sudo ufw status" | head -1)
ok "ufw: $fw"

echo "Продление сертификата"
$SSH "systemctl is-enabled certbot.timer && systemctl is-active certbot.timer" | tr '\n' ' ' | grep -q 'enabled active' \
    && ok "certbot.timer включён: $($SSH 'systemctl list-timers certbot.timer --no-legend' | awk '{print $1, $2, $3}')" \
    || fail "certbot.timer не активен"
serial_before=$(echo | $SSH "openssl s_client -connect 127.0.0.1:443 -servername $DOMAIN 2>/dev/null | openssl x509 -noout -serial")
$SSH "sudo certbot renew --force-renewal --no-random-sleep-on-renew -q"
serial_after=$(echo | $SSH "openssl s_client -connect 127.0.0.1:443 -servername $DOMAIN 2>/dev/null | openssl x509 -noout -serial")
[ "$serial_before" != "$serial_after" ] \
    && ok "после продления nginx отдаёт новый сертификат (хук reload): $serial_before -> $serial_after" \
    || fail "nginx не перечитал сертификат после продления"

rm -rf "$TMP"
if [ "$failed" -ne 0 ]; then
    echo "Есть ошибки"
    exit 1
fi
echo "Все проверки пройдены"
