resource "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = "homelab"
  }

  data = {
    password = var.grafana_admin_password
  }
}

resource "kubernetes_config_map" "grafana_datasources" {
  metadata {
    name      = "grafana-datasources"
    namespace = "homelab"
  }

  data = {
    "prometheus.yaml" = file("${path.module}/provisioning/datasources/prometheus.yaml")
  }
}

resource "kubernetes_config_map" "grafana_dashboards" {
  metadata {
    name      = "grafana-dashboards"
    namespace = "homelab"
  }

  data = {
    "dashboards.yaml" = file("${path.module}/provisioning/dashboards/dashboards.yaml")
    "cadvisor.json"   = file("${path.module}/provisioning/dashboards/cadvisor.json")
  }
}

resource "kubernetes_persistent_volume_claim" "grafana_data" {
  metadata {
    name      = "grafana-data"
    namespace = "homelab"
  }

  # local-path (k3s's default storage class) binds in WaitForFirstConsumer
  # mode — the PVC only binds once a pod using it is scheduled. Waiting for
  # bind here would deadlock against the Deployment below that hasn't been
  # created yet.
  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "local-path"

    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "grafana" {
  metadata {
    name      = "grafana"
    namespace = "homelab"
    labels    = { app = "grafana" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "grafana" }
    }

    template {
      metadata {
        labels = { app = "grafana" }
      }

      spec {
        node_selector = { "homelab/role" = "apps" }

        container {
          name  = "grafana"
          image = "grafana/grafana:latest"

          env {
            name  = "GF_SERVER_ROOT_URL"
            value = "https://grafana.nuga.dev"
          }

          env {
            name  = "GF_AUTH_DISABLE_LOGIN_FORM"
            value = "false"
          }

          env {
            name  = "GF_SECURITY_ADMIN_USER"
            value = "admin"
          }

          env {
            name = "GF_SECURITY_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.grafana_admin.metadata[0].name
                key  = "password"
              }
            }
          }

          env {
            name  = "GF_PATHS_PROVISIONING"
            value = "/var/lib/grafana/provisioning"
          }

          port {
            container_port = 3000
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/grafana"
          }

          volume_mount {
            name       = "datasources"
            mount_path = "/var/lib/grafana/provisioning/datasources"
            read_only  = true
          }

          volume_mount {
            name       = "dashboards"
            mount_path = "/var/lib/grafana/provisioning/dashboards"
            read_only  = true
          }
        }

        volume {
          name = "data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.grafana_data.metadata[0].name
          }
        }

        volume {
          name = "datasources"

          config_map {
            name = kubernetes_config_map.grafana_datasources.metadata[0].name
          }
        }

        volume {
          name = "dashboards"

          config_map {
            name = kubernetes_config_map.grafana_dashboards.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "grafana" {
  metadata {
    name      = "grafana"
    namespace = "homelab"
  }

  spec {
    selector = { app = "grafana" }

    port {
      port        = 3000
      target_port = 3000
    }
  }
}

resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = "homelab"
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "grafana.nuga.dev"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.grafana.metadata[0].name

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
