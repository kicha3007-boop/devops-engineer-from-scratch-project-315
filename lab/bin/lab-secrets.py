"""Секреты локального стенда (запускается в toolbox: make lab-secrets).

* .vault_pass — пароль Ansible Vault (если его ещё нет);
* inventories/lab/group_vars/all/vault.yml — случайные пароли и ключи, зашифрованные Vault;
* lab/minio.env — учётка администратора MinIO для контейнера p315-minio (из того же vault);
* /lab-ssh/id_ed25519 — SSH-ключ, которым Ansible ходит на «ВМ».

Существующие файлы не перезаписываются: повторный запуск ничего не меняет.
"""

import os
import secrets
import subprocess
import sys

import yaml

ROOT = "/work"
VAULT_PASS = os.path.join(ROOT, ".vault_pass")
VAULT = os.path.join(ROOT, "inventories/lab/group_vars/all/vault.yml")
MINIO_ENV = os.path.join(ROOT, "lab/minio.env")
SSH_KEY = "/lab-ssh/id_ed25519"


def vault_cmd(*args):
    env = dict(os.environ, ANSIBLE_VAULT_PASSWORD_FILE="/root/.vault_pass")
    return subprocess.run(["ansible-vault", *args], check=True, env=env,
                          capture_output=True, text=True).stdout


def main():
    if not os.path.exists(VAULT_PASS) or os.path.getsize(VAULT_PASS) == 0:
        with open(VAULT_PASS, "w", encoding="utf-8") as f:
            f.write(secrets.token_urlsafe(32) + "\n")
        print("создан .vault_pass (пароль Ansible Vault, в git не попадает)")
    # Внутрь контейнера с правами 0600, иначе Ansible сочтёт файл исполняемым
    subprocess.run(["install", "-m", "0600", VAULT_PASS, "/root/.vault_pass"], check=True)

    if not os.path.exists(VAULT):
        data = {
            "vault_postgres_password": secrets.token_hex(16),
            "vault_s3_access_key": "bulletins-" + secrets.token_hex(6),
            "vault_s3_secret_key": secrets.token_hex(20),
            "vault_minio_root_user": "lab-admin",
            "vault_minio_root_password": secrets.token_hex(20),
        }
        with open(VAULT, "w", encoding="utf-8") as f:
            f.write("---\n# Секреты локального стенда (сгенерированы make lab-secrets)\n")
            yaml.safe_dump(data, f, sort_keys=False)
        vault_cmd("encrypt", VAULT)
        print("создан и зашифрован", os.path.relpath(VAULT, ROOT))

    data = yaml.safe_load(vault_cmd("view", VAULT))
    content = (
        "# Сгенерировано make lab-secrets из inventories/lab/group_vars/all/vault.yml\n"
        f"MINIO_ROOT_USER={data['vault_minio_root_user']}\n"
        f"MINIO_ROOT_PASSWORD={data['vault_minio_root_password']}\n"
    )
    current = open(MINIO_ENV, encoding="utf-8").read() if os.path.exists(MINIO_ENV) else None
    if current != content:
        with open(MINIO_ENV, "w", encoding="utf-8") as f:
            f.write(content)
        print("записан lab/minio.env")

    if not os.path.exists(SSH_KEY):
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "p315-lab",
                        "-f", SSH_KEY], check=True)
        print("создан SSH-ключ стенда", SSH_KEY)
    return 0


if __name__ == "__main__":
    sys.exit(main())
