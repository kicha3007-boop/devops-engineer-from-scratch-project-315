variable "folder_id" {
  description = "ID каталога Yandex Cloud"
  type        = string
}

variable "zone" {
  description = "Зона доступности"
  type        = string
  default     = "ru-central1-a"
}

variable "bucket_name" {
  description = "Имя бакета для картинок объявлений (уникально во всём Object Storage)"
  type        = string
  default     = "bulletins-kicha3007-boop"
}

variable "vm_user" {
  description = "Пользователь на ВМ, под которым заходит Ansible"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key" {
  description = "Публичный SSH-ключ для пользователя ВМ (содержимое ~/.ssh/id_ed25519.pub)"
  type        = string
}

variable "dns_zone" {
  description = "Домен, делегированный на NS Yandex Cloud (пусто — DNS настраивается у регистратора вручную)"
  type        = string
  default     = ""
}

variable "app_subdomain" {
  description = "Имя приложения внутри dns_zone (bulletins -> bulletins.<dns_zone>)"
  type        = string
  default     = "bulletins"
}
