output "master_public_ip" {
  description = "Публичный адрес главной ВМ"
  value       = yandex_compute_instance.node["slae-master"].network_interface[0].nat_ip_address
}

output "ssh_port" {
  description = "Порт SSH главной ВМ для скриптов (дополнительный, если задан)"
  value       = var.ssh_alt_port > 0 ? var.ssh_alt_port : 22
}

output "nodes" {
  description = "Узлы кластера: зона и внутренний адрес"
  value       = { for name, n in local.nodes : name => { zone = n.zone, ip = n.ip } }
}

output "bucket" {
  description = "Бакет с матрицей, исходниками и результатами"
  value       = yandex_storage_bucket.slae.bucket
}

output "logs_url" {
  description = "Логи вычислений в Monium (пусто, если enable_logging = false)"
  value       = var.enable_logging ? "https://monium.yandex.cloud/projects/${local.monium_project}/logs" : ""
}

output "prometheus_workspace_id" {
  description = "Воркспейс Managed Service for Prometheus (пусто — мониторинг выключен)"
  value       = var.prometheus_workspace_id
}
