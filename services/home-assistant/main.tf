# local-path (k3s's default StorageClass) binds in WaitForFirstConsumer
# mode — it only binds once a pod using it is scheduled. wait_until_bound
# defaults to true and would deadlock waiting for a bind that can't happen
# until the Deployment below exists (same fix previously needed for the
# grafana/prometheus PVCs).

resource "kubernetes_persistent_volume_claim" "home_assistant_config" {
  metadata {
    name      = "home-assistant-config"
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

resource "kubernetes_deployment" "home_assistant" {
  metadata {
    name      = "home-assistant"
    namespace = "homelab"
    labels    = { app = "home-assistant" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "home-assistant" }
    }

    template {
      metadata {
        labels = { app = "home-assistant" }
      }

      spec {
        container {
          name  = "home-assistant"
          image = "ghcr.io/home-assistant/home-assistant:stable"

          env {
            name  = "TZ"
            value = var.timezone
          }

          port {
            container_port = 8123
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
          }
        }

        volume {
          name = "config"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.home_assistant_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "home_assistant" {
  metadata {
    name      = "home-assistant"
    namespace = "homelab"
  }

  spec {
    selector = { app = "home-assistant" }

    port {
      port        = 8123
      target_port = 8123
    }
  }
}

resource "kubernetes_ingress_v1" "home_assistant" {
  metadata {
    name      = "home-assistant"
    namespace = "homelab"
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "home.nuga.dev"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.home_assistant.metadata[0].name

              port {
                number = 8123
              }
            }
          }
        }
      }
    }
  }
}
