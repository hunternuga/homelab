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
#
# Add one cloudflare_record per service here as services are (re)added —
# see README "Adding a Service" for the full pattern, including the
# matching cloudflare_zero_trust_access_application/_policy pair if the
# service should sit behind Cloudflare Access.

resource "cloudflare_record" "home_assistant" {
  zone_id = var.cloudflare_zone_id
  name    = "home"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

# No Cloudflare Access application in front of Home Assistant — the iOS
# Companion App's raw (non-browser) API calls can't get through Access's
# interactive login (it returns an HTML challenge page where the app expects
# JSON, and Access has no native way to exempt a mobile app's traffic short
# of enrolling every device in Cloudflare WARP). Home Assistant's own login
# is the auth boundary here instead; it has IP-ban-after-failed-attempts
# enabled by default.

# ============================================================
# Cloudflared — Ingress Config
# ============================================================
#
# One static rule: every hostname routes to Traefik (k3s's bundled
# ingress controller), which does the actual per-service host-based
# routing via each service's own Ingress resource.

locals {
  cloudflared_config = yamlencode({
    tunnel             = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
    "credentials-file" = "/etc/cloudflared/creds/credentials.json"
    ingress = [
      {
        hostname = "*.nuga.dev"
        service  = "http://traefik.kube-system.svc.cluster.local:80"
      },
      {
        service = "http_status:404"
      }
    ]
  })
}

resource "kubernetes_config_map" "cloudflared_config" {
  metadata {
    name      = "cloudflared-config"
    namespace = "homelab"
  }

  data = {
    "config.yml" = local.cloudflared_config
  }
}

resource "kubernetes_secret" "cloudflared_credentials" {
  metadata {
    name      = "cloudflared-credentials"
    namespace = "homelab"
  }

  data = {
    "credentials.json" = jsonencode({
      AccountTag   = "a1d47b88a31b30932d1974da0a55e80e"
      TunnelID     = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
      TunnelSecret = var.tunnel_secret
    })
  }
}

# ============================================================
# Cloudflared Deployment
# ============================================================

resource "kubernetes_deployment" "cloudflared" {
  metadata {
    name      = "cloudflared"
    namespace = "homelab"
    labels    = { app = "cloudflared" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "cloudflared" }
    }

    template {
      metadata {
        labels = { app = "cloudflared" }
      }

      spec {
        # Default (ClusterFirst) DNS policy — cloudflared's ingress config
        # points at traefik.kube-system.svc.cluster.local, which only the
        # cluster's own CoreDNS can resolve.

        container {
          name  = "cloudflared"
          image = "cloudflare/cloudflared:latest"

          args = [
            "tunnel",
            "--no-autoupdate",
            "--config", "/etc/cloudflared/config.yml",
            "run",
          ]

          volume_mount {
            name       = "config"
            mount_path = "/etc/cloudflared"
            read_only  = true
          }

          volume_mount {
            name       = "creds"
            mount_path = "/etc/cloudflared/creds"
            read_only  = true
          }
        }

        volume {
          name = "config"

          config_map {
            name = kubernetes_config_map.cloudflared_config.metadata[0].name
          }
        }

        volume {
          name = "creds"

          secret {
            secret_name = kubernetes_secret.cloudflared_credentials.metadata[0].name
          }
        }
      }
    }
  }
}
