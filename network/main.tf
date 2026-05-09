resource "docker_network" "homelab" {
  name = "homelab"

  options = {
    "dns_enabled" = "false"
  }
}
