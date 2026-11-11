terraform {
  required_version = ">= 1.5"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.130"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# IAM-токен берётся из переменной окружения YC_TOKEN (см. scripts/tf.sh).
provider "yandex" {
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
}
