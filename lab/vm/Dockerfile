# «ВМ» локального стенда: чистая Ubuntu 24.04, как образ ВМ в Yandex Cloud, но в контейнере.
# Внутри — systemd (PID 1), sshd и пользователь ubuntu с sudo без пароля: всё остальное
# (Docker, nginx, certbot, ufw) ставит playbook.yml так же, как на настоящем сервере.
ARG BASE_REGISTRY=mirror.gcr.io/library
ARG PEBBLE_IMAGE=ghcr.io/letsencrypt/pebble:2.10.1

FROM ${PEBBLE_IMAGE} AS pebble

FROM ${BASE_REGISTRY}/ubuntu:24.04
ENV container=docker

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        systemd systemd-sysv dbus openssh-server sudo python3 python3-apt \
        iproute2 iptables kmod ca-certificates curl less \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/sbin/policy-rc.d \
    && systemctl mask getty.target console-getty.service systemd-logind.service \
        systemd-udevd.service systemd-udev-trigger.service systemd-firstboot.service \
    && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-ubuntu \
    && chmod 0440 /etc/sudoers.d/90-ubuntu \
    && passwd -l ubuntu

# Стенд доверяет корню локального ACME-сервера Pebble, как настоящий сервер — Let's Encrypt:
# certbot ходит на https://pebble:14000 без отключения проверки TLS
COPY --from=pebble /test/certs/pebble.minica.pem /usr/local/share/ca-certificates/pebble-minica.crt
RUN update-ca-certificates

# Публичный ключ стенда (том p315-lab-ssh) -> ~ubuntu/.ssh/authorized_keys при каждой загрузке
COPY lab-authorized-keys.sh /usr/local/sbin/lab-authorized-keys
COPY lab-authorized-keys.service /etc/systemd/system/lab-authorized-keys.service
RUN chmod 0755 /usr/local/sbin/lab-authorized-keys \
    && systemctl enable lab-authorized-keys.service

STOPSIGNAL SIGRTMIN+3
CMD ["/lib/systemd/systemd"]
