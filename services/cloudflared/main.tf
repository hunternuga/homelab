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
# Cloudflared — Ingress Config
# ============================================================
#
# One static rule: every hostname routes to Traefik (k3s's bundled
# ingress controller), which does the actual per-service host-based
# routing via each service's own Ingress resource. This replaces the
# old per-service, dynamically-resolved-container-IP config entirely —
# Kubernetes Services give every backend a stable DNS name, so there's
# nothing left to resolve at apply time.

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
        node_selector = { "homelab/role" = "apps" }

        # Default (ClusterFirst) DNS policy — cloudflared's ingress config
        # points at traefik.kube-system.svc.cluster.local, which only the
        # cluster's own CoreDNS can resolve. The old Docker setup pinned to
        # public resolvers because it never needed to resolve anything
        # internal; that assumption no longer holds here.

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
