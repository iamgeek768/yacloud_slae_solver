# Общая группа всех узлов: внутри кластера разрешено всё (MPI открывает
# произвольные TCP-порты, плюс SSH между узлами), наружу любой исходящий трафик.
resource "yandex_vpc_security_group" "cluster" {
  name       = "slae-cluster"
  network_id = yandex_vpc_network.slae.id

  ingress {
    description       = "Любой трафик между узлами кластера"
    protocol          = "ANY"
    predefined_target = "self_security_group"
    from_port         = 0
    to_port           = 65535
  }

  egress {
    description    = "Исходящий трафик: пакеты, Object Storage, Monium"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

# Только для главной ВМ: вход по SSH с адреса администратора.
resource "yandex_vpc_security_group" "ssh" {
  name       = "slae-ssh"
  network_id = yandex_vpc_network.slae.id

  ingress {
    description    = "SSH администратора"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = var.admin_cidrs
  }

  dynamic "ingress" {
    for_each = var.ssh_alt_port > 0 ? [var.ssh_alt_port] : []
    content {
      description    = "SSH администратора на дополнительном порту"
      protocol       = "TCP"
      port           = ingress.value
      v4_cidr_blocks = var.admin_cidrs
    }
  }
}
