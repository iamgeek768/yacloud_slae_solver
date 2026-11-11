locals {
  # Узел i получает адрес .10+i в подсети своей зоны; нулевой узел главный.
  nodes = {
    for i, z in var.node_zones : (i == 0 ? "slae-master" : "slae-worker-${i}") => {
      index     = i
      zone      = z
      ip        = cidrhost(local.subnet_cidrs[z], 10 + i)
      is_master = i == 0
    }
  }

  # Порядок строк по номеру узла, главная ВМ первой.
  node_names = [for i, z in var.node_zones : i == 0 ? "slae-master" : "slae-worker-${i}"]
  etc_hosts  = join("", [for name in local.node_names : "${local.nodes[name].ip} ${name}\n"])
  hostfile   = join("", [for name in local.node_names : "${name} slots=${var.node_cores}\n"])

  # Логи уходят в проект Monium каталога: folder__<идентификатор_каталога>.
  monium_project = "folder__${var.folder_id}"

  prometheus_config = templatefile("${path.module}/cloud-init/prometheus.yml.tftpl", {
    workspace_id = var.prometheus_workspace_id
    targets      = jsonencode([for name in local.node_names : "${name}:9100"])
  })
}

# Внутренний ключ кластера: пользователь mpi ходит по SSH между узлами без пароля.
resource "tls_private_key" "cluster" {
  algorithm = "ED25519"
}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

resource "yandex_compute_instance" "node" {
  for_each = local.nodes

  name               = each.key
  hostname           = each.key
  zone               = each.value.zone
  platform_id        = "standard-v3"
  service_account_id = yandex_iam_service_account.node.id

  resources {
    cores         = var.node_cores
    memory        = var.node_memory_gb
    core_fraction = 100
  }

  scheduling_policy {
    preemptible = var.preemptible
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = var.node_disk_gb
      type     = var.node_disk_type
    }
  }

  network_interface {
    subnet_id  = yandex_vpc_subnet.node[each.value.zone].id
    ip_address = each.value.ip
    nat        = each.value.is_master
    security_group_ids = concat(
      [yandex_vpc_security_group.cluster.id],
      each.value.is_master ? [yandex_vpc_security_group.ssh.id] : [],
    )
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init/node.yaml.tftpl", {
      node_name           = each.key
      admin_public_key    = trimspace(file(pathexpand(var.admin_ssh_public_key_path)))
      cluster_public_key  = trimspace(tls_private_key.cluster.public_key_openssh)
      cluster_private_key = tls_private_key.cluster.private_key_openssh
      etc_hosts           = local.etc_hosts
      hostfile            = local.hostfile
      env_file = join("", [
        "BUCKET=${yandex_storage_bucket.slae.bucket}\n",
        "NODE_NAME=${each.key}\n",
        "NODE_CORES=${var.node_cores}\n",
        "NETWORK_CIDR=${local.network_cidr}\n",
        "IS_MASTER=${each.value.is_master ? 1 : 0}\n",
        "ENABLE_LOGGING=${var.enable_logging ? 1 : 0}\n",
        "PROMETHEUS_WORKSPACE_ID=${var.prometheus_workspace_id}\n",
      ])
      otelcol_config = templatefile("${path.module}/cloud-init/otelcol.yaml.tftpl", {
        project   = local.monium_project
        node_name = each.key
      })
      prometheus_config     = local.prometheus_config
      prometheus_rules      = file("${path.module}/cloud-init/prometheus-rules.yml")
      install_monitoring_sh = file("${path.module}/cloud-init/install_monitoring.sh")
      install_logging_sh    = file("${path.module}/cloud-init/install_logging.sh")
      iam_token_sh          = file("${path.module}/cloud-init/slae-iam-token.sh")
      iam_token_service     = file("${path.module}/cloud-init/slae-iam-token.service")
      iam_token_timer       = file("${path.module}/cloud-init/slae-iam-token.timer")
      ssh_alt_port          = each.value.is_master ? var.ssh_alt_port : 0
      fetch_data_sh         = file("${path.module}/cloud-init/fetch_data.sh")
      run_solver_sh         = file("${path.module}/cloud-init/run_solver.sh")
      fetch_service         = file("${path.module}/cloud-init/slae-fetch.service")
    })
  }

  # Выход новой сборки образа не должен пересоздавать работающий кластер.
  lifecycle {
    ignore_changes = [boot_disk[0].initialize_params[0].image_id]
  }

  # К первому запуску ВМ должны существовать права аккаунта, исходники в бакете и маршрут наружу.
  depends_on = [
    yandex_resourcemanager_folder_iam_member.node,
    yandex_storage_object.solver_src,
    yandex_vpc_route_table.egress,
  ]
}
