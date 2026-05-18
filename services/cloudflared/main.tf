# ============================================================
# Data Sources — Docker Network
# ============================================================

data "docker_network" "homelab" {
  name = "homelab"
}

# ============================================================
# Data Sources — Container IPs
# ============================================================

data "external" "homepage_ip" {
  program = ["${path.module}/../../scripts/get_homepage_ip.sh"]
}

data "external" "it_tools_ip" {
  program = ["${path.module}/../../scripts/get_it_tools_ip.sh"]
}

data "external" "grafana_ip" {
  program = ["${path.module}/../../scripts/get_grafana_ip.sh"]
}

data "external" "minepanel_ip" {
  program = ["${path.module}/../../scripts/get_minepanel_ip.sh"]
}

# ============================================================
# Cloudflare Tunnel
# ============================================================

resource "cloudflare_zero_trust_tunnel_cloudflared" "homelab" {
  account_id = "a1d47b88a31b30932d1974da0a55e80e"
  name       = "homelab"
  secret     = var.tunnel_secret
}

# ============================================================
# DNS Records
# ============================================================

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

resource "cloudflare_record" "grafana" {
  zone_id = var.cloudflare_zone_id
  name    = "grafana"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_record" "minepanel" {
  zone_id = var.cloudflare_zone_id
  name    = "minepanel"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_record" "minepanel_api" {
  zone_id = var.cloudflare_zone_id
  name    = "minepanel-api"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

# ============================================================
# Cloudflare Access — IT Tools
# ============================================================

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

# ============================================================
# Cloudflare Access — Grafana
# ============================================================

resource "cloudflare_zero_trust_access_application" "grafana" {
  account_id       = "a1d47b88a31b30932d1974da0a55e80e"
  name             = "Grafana"
  domain           = "grafana.nuga.dev"
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_zero_trust_access_policy" "grafana" {
  account_id     = "a1d47b88a31b30932d1974da0a55e80e"
  application_id = cloudflare_zero_trust_access_application.grafana.id
  name           = "Allow hunternuga293"
  precedence     = 1
  decision       = "allow"

  include {
    email = ["hunternuga293@gmail.com"]
  }
}

# ============================================================
# Cloudflare Access — MinePanel (frontend, email auth)
# ============================================================

resource "cloudflare_zero_trust_access_application" "minepanel" {
  account_id       = "a1d47b88a31b30932d1974da0a55e80e"
  name             = "MinePanel"
  domain           = "minepanel.nuga.dev"
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_zero_trust_access_policy" "minepanel" {
  account_id     = "a1d47b88a31b30932d1974da0a55e80e"
  application_id = cloudflare_zero_trust_access_application.minepanel.id
  name           = "Allow hunternuga293"
  precedence     = 1
  decision       = "allow"

  include {
    email = ["hunternuga293@gmail.com"]
  }
}

# ============================================================
# Cloudflare Access — MinePanel API (bypass, JWT handles auth)
# ============================================================

resource "cloudflare_zero_trust_access_application" "minepanel_api" {
  account_id       = "a1d47b88a31b30932d1974da0a55e80e"
  name             = "MinePanel API"
  domain           = "minepanel-api.nuga.dev"
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_zero_trust_access_policy" "minepanel_api_bypass" {
  account_id     = "a1d47b88a31b30932d1974da0a55e80e"
  application_id = cloudflare_zero_trust_access_application.minepanel_api.id
  name           = "Bypass API"
  precedence     = 1
  decision       = "bypass"

  include {
    everyone = true
  }
}

# ============================================================
# Cloudflared Container
# ============================================================

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
    tunnel_id    = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
    homepage_ip  = data.external.homepage_ip.result.ip
    it_tools_ip  = data.external.it_tools_ip.result.ip
    grafana_ip   = data.external.grafana_ip.result.ip
    minepanel_ip = data.external.minepanel_ip.result.ip
  }

  provisioner "local-exec" {
    command = "${path.module}/../../scripts/write_cloudflared_config.sh ${cloudflare_zero_trust_tunnel_cloudflared.homelab.id} ${var.tunnel_secret} ${data.external.homepage_ip.result.ip} ${data.external.it_tools_ip.result.ip} ${data.external.grafana_ip.result.ip} ${data.external.minepanel_ip.result.ip}"
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
