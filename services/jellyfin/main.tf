# Jellyfin — LAN-only for now (no Cloudflare Tunnel route). Its official
# TV/mobile apps make direct API calls that would choke on Cloudflare
# Access's interactive login, same class of problem documented for Home
# Assistant in the README — simplest to just not put it behind Access
# until/unless external access is actually wanted.

# local-path (k3s's default StorageClass) binds in WaitForFirstConsumer
# mode — wait_until_bound would deadlock waiting for a bind that can't
# happen until the Deployment below exists (same fix as home-assistant).

resource "kubernetes_persistent_volume_claim" "jellyfin_config" {
  metadata {
    name      = "jellyfin-config"
    namespace = "homelab"
  }

  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "local-path"

    resources {
      requests = { storage = "5Gi" }
    }
  }
}

resource "kubernetes_deployment" "jellyfin" {
  metadata {
    name      = "jellyfin"
    namespace = "homelab"
    labels    = { app = "jellyfin" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "jellyfin" }
    }

    template {
      metadata {
        labels = { app = "jellyfin" }
      }

      spec {
        # render (992) + video (44) on the node — lets the container's
        # process open /dev/dri/renderD128 for Intel Quick Sync hardware
        # transcoding (this node's i7-7700T has an HD Graphics 630 iGPU).
        # Confirm with `getent group render video` on the node if this
        # box's GIDs ever change.
        security_context {
          supplemental_groups = [992, 44]
        }

        container {
          name  = "jellyfin"
          image = "jellyfin/jellyfin:latest"

          env {
            name  = "TZ"
            value = var.timezone
          }

          port {
            container_port = 8096
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
          }

          volume_mount {
            name       = "media"
            mount_path = "/media"
          }

          volume_mount {
            name       = "dri"
            mount_path = "/dev/dri"
          }

          resources {
            requests = { cpu = "250m", memory = "512Mi" }
            limits   = { cpu = "4000m", memory = "4Gi" }
          }
        }

        volume {
          name = "config"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.jellyfin_config.metadata[0].name
          }
        }

        # Bind-mounts straight to the 8TB USB drive mounted at
        # /mnt/storage on the node (see homelab README/history — not
        # Terraform-managed, it's physical hardware formatted by hand).
        volume {
          name = "media"

          host_path {
            path = "/mnt/storage/media"
          }
        }

        volume {
          name = "dri"

          host_path {
            path = "/dev/dri"
          }
        }
      }
    }
  }
}

# type = LoadBalancer, same as Traefik — k3s's bundled ServiceLB binds the
# port directly on the node's real LAN IP, so this is reachable at
# http://<node-ip>:8096 on the home network with no tunnel hop (lower
# latency, works even if Cloudflare or the internet connection is down).
# The Ingress below additionally routes jellyfin.nuga.dev through this
# same Service for access away from home — both paths work at once.
resource "kubernetes_service" "jellyfin" {
  metadata {
    name      = "jellyfin"
    namespace = "homelab"
  }

  spec {
    type     = "LoadBalancer"
    selector = { app = "jellyfin" }

    port {
      port        = 8096
      target_port = 8096
    }
  }
}

resource "kubernetes_ingress_v1" "jellyfin" {
  metadata {
    name      = "jellyfin"
    namespace = "homelab"
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "jellyfin.nuga.dev"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.jellyfin.metadata[0].name

              port {
                number = 8096
              }
            }
          }
        }
      }
    }
  }
}
