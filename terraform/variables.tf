variable "cloud_id" {
  description = "Идентификатор облака"
  type        = string
}

variable "folder_id" {
  description = "Идентификатор каталога"
  type        = string
}

variable "node_zones" {
  description = "Зона для каждого узла кластера; первый элемент — главная ВМ. Число элементов = число узлов N"
  type        = list(string)
  default     = ["ru-central1-a", "ru-central1-d", "ru-central1-e"]

  validation {
    condition     = length(var.node_zones) >= 1 && length(var.node_zones) <= 200
    error_message = "Нужен хотя бы один узел."
  }
}

variable "node_cores" {
  description = "Число vCPU на узел (оно же число потоков OpenMP по умолчанию)"
  type        = number
  default     = 2
}

variable "node_memory_gb" {
  description = "Объём RAM на узел, ГБ"
  type        = number
  default     = 4
}

variable "node_disk_gb" {
  description = "Размер загрузочного диска, ГБ"
  type        = number
  default     = 20
}

variable "node_disk_type" {
  description = "Тип загрузочного диска: network-hdd или network-ssd"
  type        = string
  default     = "network-hdd"
}

variable "preemptible" {
  description = "Создавать прерываемые ВМ (дешевле, но останавливаются облаком не позже чем через 24 часа)"
  type        = bool
  default     = true
}

variable "admin_cidrs" {
  description = "Адреса, с которых разрешён SSH на главную ВМ, в формате CIDR"
  type        = list(string)
}

variable "ssh_alt_port" {
  description = "Дополнительный порт SSH на главной ВМ (0 — только 22). Нужен, если VPN на машине администратора пускает порт 22 не тем маршрутом"
  type        = number
  default     = 0
}

variable "admin_ssh_public_key_path" {
  description = "Путь к публичному SSH-ключу администратора"
  type        = string
  default     = "~/.ssh/yalab_ed25519.pub"
}

variable "bucket_name" {
  description = "Имя бакета Object Storage (глобально уникальное)"
  type        = string
}

variable "enable_logging" {
  description = "Ставить на узлы Unified Agent и отправлять логи вычислений в Monium Logs"
  type        = bool
  default     = true
}

variable "prometheus_workspace_id" {
  description = "Воркспейс Managed Service for Prometheus (создаётся в Monium вручную); пусто — мониторинг не ставится"
  type        = string
  default     = ""
}
