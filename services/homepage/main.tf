resource "kubernetes_config_map" "homepage_config" {
  metadata {
    name      = "homepage-config"
    namespace = "homelab"
  }

  # homepage's config-init step aborts entirely if ANY of these skeleton
  # files is missing, since it can't fall back to copying its own defaults
  # into a read-only mount — so every file it ever checks for must be
  # present, not just the ones we actually customize.
  data = {
    "services.yaml"   = file("${path.module}/config/services.yaml")
    "settings.yaml"   = file("${path.module}/config/settings.yaml")
    "widgets.yaml"    = file("${path.module}/config/widgets.yaml")
    "bookmarks.yaml"  = file("${path.module}/config/bookmarks.yaml")
    "kubernetes.yaml" = file("${path.module}/config/kubernetes.yaml")
    "docker.yaml"     = file("${path.module}/config/docker.yaml")
    "proxmox.yaml"    = file("${path.module}/config/proxmox.yaml")
    "custom.css"      = file("${path.module}/config/custom.css")
    "custom.js"       = file("${path.module}/config/custom.js")
  }
}

resource "kubernetes_deployment" "homepage" {
  metadata {
    name      = "homepage"
    namespace = "homelab"
    labels    = { app = "homepage" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "homepage" }
    }

    template {
      metadata {
        labels = { app = "homepage" }
      }

      spec {
        node_selector = { "homelab/role" = "apps" }

        container {
          name  = "homepage"
          image = "ghcr.io/gethomepage/homepage:latest"

          env {
            name  = "HOMEPAGE_ALLOWED_HOSTS"
            value = "homepage.nuga.dev"
          }

          port {
            container_port = 3000
          }

          volume_mount {
            name       = "config"
            mount_path = "/app/config"
          }

          # homepage writes its own log file under config/logs at runtime,
          # which the read-only ConfigMap mount above can't support — layer
          # a writable emptyDir over just that subpath.
          volume_mount {
            name       = "logs"
            mount_path = "/app/config/logs"
          }
        }

        volume {
          name = "config"

          config_map {
            name = kubernetes_config_map.homepage_config.metadata[0].name
          }
        }

        volume {
          name = "logs"

          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service" "homepage" {
  metadata {
    name      = "homepage"
    namespace = "homelab"
  }

  spec {
    selector = { app = "homepage" }

    port {
      port        = 3000
      target_port = 3000
    }
  }
}

resource "kubernetes_ingress_v1" "homepage" {
  metadata {
    name      = "homepage"
    namespace = "homelab"
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "homepage.nuga.dev"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.homepage.metadata[0].name

              port {
                number = 3000
              }
            }
          }
        }
      }
    }
  }
}
