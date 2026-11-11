# Аккаунт, от имени которого Terraform создаёт бакет и объекты.
resource "yandex_iam_service_account" "tf_storage" {
  name        = "slae-tf-storage"
  description = "Создание бакета и объектов из Terraform"
}

resource "yandex_resourcemanager_folder_iam_member" "tf_storage_admin" {
  folder_id = var.folder_id
  role      = "storage.admin"
  member    = "serviceAccount:${yandex_iam_service_account.tf_storage.id}"
}

resource "yandex_iam_service_account_static_access_key" "tf_storage" {
  service_account_id = yandex_iam_service_account.tf_storage.id
  description        = "Ключ для ресурсов yandex_storage_*"
}


resource "yandex_iam_service_account" "node" {
  name        = "slae-node"
  description = "Узлы кластера: чтение и запись бакета, отправка логов и метрик"
}

resource "yandex_resourcemanager_folder_iam_member" "node" {
  for_each = toset(concat(
    ["storage.editor"],
    var.enable_logging ? ["monium.logs.writer"] : [],
    var.prometheus_workspace_id != "" ? ["monitoring.editor"] : [],
  ))

  folder_id = var.folder_id
  role      = each.key
  member    = "serviceAccount:${yandex_iam_service_account.node.id}"
}
