output "vm_public_ip" {
  description = "Публичный IP сервера: vault_server_host в Ansible Vault и A-запись домена"
  value       = yandex_vpc_address.web.external_ipv4_address[0].address
}

output "bucket_name" {
  description = "Имя бакета: s3_bucket в group_vars"
  value       = yandex_storage_bucket.images.bucket
}

output "app_access_key" {
  description = "Ключ доступа приложения к бакету: vault_s3_access_key"
  value       = yandex_iam_service_account_static_access_key.app.access_key
}

output "app_secret_key" {
  description = "Секретный ключ приложения: vault_s3_secret_key (terraform output -raw app_secret_key)"
  value       = yandex_iam_service_account_static_access_key.app.secret_key
  sensitive   = true
}

output "app_fqdn" {
  description = "Имя приложения, если DNS-зона управляется здесь"
  value       = var.dns_zone == "" ? null : trimsuffix(yandex_dns_recordset.app[0].name, ".")
}
