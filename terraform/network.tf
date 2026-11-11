locals {
  network_cidr = "10.10.0.0/16"
  zones        = distinct(var.node_zones)

  alphabet     = split("", "abcdefghijklmnopqrstuvwxyz")
  subnet_cidrs = { for z in local.zones : z => cidrsubnet(local.network_cidr, 8, index(local.alphabet, substr(z, -1, 1)) + 1) }
}

resource "yandex_vpc_network" "slae" {
  name = "slae-net"
}

# Выход в интернет для узлов без публичного адреса (apt, Object Storage, Monium).
resource "yandex_vpc_gateway" "nat" {
  name = "slae-nat"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "egress" {
  name       = "slae-egress"
  network_id = yandex_vpc_network.slae.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat.id
  }
}

resource "yandex_vpc_subnet" "node" {
  for_each = local.subnet_cidrs

  name           = "slae-${each.key}"
  zone           = each.key
  network_id     = yandex_vpc_network.slae.id
  v4_cidr_blocks = [each.value]
  route_table_id = yandex_vpc_route_table.egress.id
}
