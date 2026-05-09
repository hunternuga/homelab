data "docker_network" "homelab" {
  name = "homelab"
}

data "external" "homepage_ip" {
  program = ["${path.module}/../../scripts/get_homepage_ip.sh"]
}

data "external" "it_tools_ip" {
  program = ["${path.module}/../../scripts/get_it_tools_ip.sh"]
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "homelab" {
  account_id = "a1d47b88a31b30932d1974da0a55e80e"
  name       = "homelab"
  secret     = var.tunnel_secret
}

resource "cloudflare_record" "homepage" {
  zone_id = var.cloudflare_zone_id
  name    = "homepage"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_record" "it_tools" {
  zone_id = var.cloudflare_zone_id
  name    = "tools"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_zero_trust_access_application" "it_tools" {
  account_id       = "a1d47b88a31b30932d1974da0a55e80e"
  name             = "IT Tools"
  domain           = "tools.nuga.dev"
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_zero_trust_access_policy" "it_tools" {
  account_id     = "a1d47b88a31b30932d1974da0a55e80e"
  application_id = cloudflare_zero_trust_access_application.it_tools.id
  name           = "Allow hunternuga293"
  precedence     = 1
  decision       = "allow"

  include {
    email = ["hunternuga293@gmail.com"]
  }
}

resource "docker_image" "cloudflared" {
  name         = "cloudflare/cloudflared:latest"
  keep_locally = true
}

resource "docker_volume" "cloudflared_config" {
  name = "cloudflared_config"
}

resource "null_resource" "cloudflared_credentials" {
  depends_on = [docker_volume.cloudflared_config]

  triggers = {
    tunnel_id   = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
    homepage_ip = data.external.homepage_ip.result.ip
    it_tools_ip = data.external.it_tools_ip.result.ip
  }

  provisioner "local-exec" {
    command = "${path.module}/../../scripts/write_cloudflared_config.sh ${cloudflare_zero_trust_tunnel_cloudflared.homelab.id} ${var.tunnel_secret} ${data.external.homepage_ip.result.ip} ${data.external.it_tools_ip.result.ip}"
  }
}

resource "docker_container" "cloudflared" {
  depends_on = [null_resource.cloudflared_credentials]

  name  = "cloudflared"
  image = docker_image.cloudflared.image_id

  command = [
    "tunnel",
    "--no-autoupdate",
    "--config", "/etc/cloudflared/config.yml",
    "run"
  ]

  dns = ["1.1.1.1", "1.0.0.1"]

  volumes {
    volume_name    = docker_volume.cloudflared_config.name
    container_path = "/etc/cloudflared"
  }

  networks_advanced {
    name = data.docker_network.homelab.name
  }

  restart = "unless-stopped"
}
