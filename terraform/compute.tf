# Сервер приложения: одна ВМ с Ubuntu 24.04 и статическим публичным адресом.
# Снаружи открыты только SSH, HTTP и HTTPS (группа безопасности + ufw на самой ВМ).

resource "yandex_vpc_network" "main" {
  name = "bulletins"
}

resource "yandex_vpc_subnet" "main" {
  name           = "bulletins-${var.zone}"
  zone           = var.zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["10.10.0.0/24"]
}

resource "yandex_vpc_security_group" "web" {
  name       = "bulletins-web"
  network_id = yandex_vpc_network.main.id

  dynamic "ingress" {
    for_each = { ssh = 22, http = 80, https = 443 }
    content {
      description    = ingress.key
      protocol       = "TCP"
      port           = ingress.value
      v4_cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    description    = "Исходящие: реестр образов, Object Storage, Let's Encrypt, apt"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_address" "web" {
  name = "bulletins-web"

  external_ipv4_address {
    zone_id = var.zone
  }
}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2404-lts"
}

resource "yandex_compute_instance" "web" {
  name        = "bulletins-web"
  platform_id = "standard-v3"

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 50
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 20
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.main.id
    nat                = true
    nat_ip_address     = yandex_vpc_address.web.external_ipv4_address[0].address
    security_group_ids = [yandex_vpc_security_group.web.id]
  }

  metadata = {
    user-data = <<-EOT
      #cloud-config
      users:
        - name: ${var.vm_user}
          groups: sudo
          shell: /bin/bash
          sudo: "ALL=(ALL) NOPASSWD:ALL"
          ssh_authorized_keys:
            - ${var.ssh_public_key}
    EOT
  }
}
