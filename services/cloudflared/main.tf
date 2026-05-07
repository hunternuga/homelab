data "docker_network" "homelab" {
  name = "homelab"
}

data "external" "homepage_ip" {
  program = ["${path.module}/../../scripts/get_homepage_ip.sh"]
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "homelab" {
  account_id = "a1d47b88a31b30932d1974da0a55e80e"
  name       = "homelab"
  secret     = var.tunnel_secret
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab" {
  account_id = "a1d47b88a31b30932d1974da0a55e80e"
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id

  config {
    ingress_rule {
      hostname = "homepage.nuga.dev"
      service  = "http://homepage:3000"
    }
    ingress_rule {
      service = "http_status:404"
    }
  }
}

resource "cloudflare_record" "homepage" {
  zone_id = var.cloudflare_zone_id
  name    = "homepage"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
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
    tunnel_id = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      podman run --rm -v cloudflared_config:/etc/cloudflared alpine sh -c 'cat > /etc/cloudflared/${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.json << EOF
      {
        "AccountTag": "a1d47b88a31b30932d1974da0a55e80e",
        "TunnelID": "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}",
        "TunnelSecret": "${var.tunnel_secret}"
      }
      EOF'
    EOT
  }
}

resource "docker_container" "cloudflared" {
  depends_on = [null_resource.cloudflared_credentials]

  name  = "cloudflared"
  image = docker_image.cloudflared.image_id

  command = [
    "tunnel",
    "--no-autoupdate",
    "--credentials-file", "/etc/cloudflared/${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.json",
    "run",
    cloudflare_zero_trust_tunnel_cloudflared.homelab.id
  ]

  dns = ["1.1.1.1", "1.0.0.1"]

  host {
    ip   = data.external.homepage_ip.result.ip
    host = "homepage"
  }

  volumes {
    volume_name    = docker_volume.cloudflared_config.name
    container_path = "/etc/cloudflared"
  }

  networks_advanced {
    name = data.docker_network.homelab.name
  }

  restart = "unless-stopped"
}