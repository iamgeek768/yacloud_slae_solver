resource "yandex_storage_bucket" "slae" {
  bucket     = var.bucket_name
  access_key = yandex_iam_service_account_static_access_key.tf_storage.access_key
  secret_key = yandex_iam_service_account_static_access_key.tf_storage.secret_key

  # Матрица и результаты удаляются вместе с бакетом при terraform destroy.
  force_destroy = true

  depends_on = [yandex_resourcemanager_folder_iam_member.tf_storage_admin]
}

# Исходники решателя: узлы скачивают их при запуске и собирают бинарник.
resource "yandex_storage_object" "solver_src" {
  for_each = {
    "src/slae_solver.c" = "${path.module}/../solver/src/slae_solver.c"
    "src/Makefile"      = "${path.module}/../solver/Makefile"
  }

  bucket      = yandex_storage_bucket.slae.bucket
  key         = each.key
  source      = each.value
  source_hash = filemd5(each.value)
  access_key  = yandex_iam_service_account_static_access_key.tf_storage.access_key
  secret_key  = yandex_iam_service_account_static_access_key.tf_storage.secret_key
}
