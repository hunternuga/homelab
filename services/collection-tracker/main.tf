locals {
  image        = "ghcr.io/hunternuga/collection-tracker:${var.collection_image_tag}"
  database_url = "postgresql://collection:${var.collection_postgres_password}@collection-postgres.homelab.svc.cluster.local:5432/collection"
  common_env = [
    { name = "DATABASE_URL", value = local.database_url },
  ]
}

# local-path (k3s's default StorageClass) binds in WaitForFirstConsumer
# mode — wait_until_bound would deadlock waiting for a bind that can't
# happen until a pod using the PVC is scheduled (same fix as the
# home-assistant and (historically) grafana/prometheus PVCs).

resource "kubernetes_persistent_volume_claim" "collection_postgres_data" {
  metadata {
    name      = "collection-postgres-data"
    namespace = "homelab"
  }

  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "local-path"

    resources {
      requests = { storage = "2Gi" }
    }
  }
}

resource "kubernetes_secret" "collection_tracker" {
  metadata {
    name      = "collection-tracker"
    namespace = "homelab"
  }

  data = {
    "postgres-password"  = var.collection_postgres_password
    "ebay-client-id"     = var.collection_ebay_client_id
    "ebay-client-secret" = var.collection_ebay_client_secret
    "ha-token"           = var.collection_ha_token
  }
}

# ============================================================
# Postgres
# ============================================================

resource "kubernetes_deployment" "collection_postgres" {
  metadata {
    name      = "collection-postgres"
    namespace = "homelab"
    labels    = { app = "collection-postgres" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "collection-postgres" }
    }

    template {
      metadata {
        labels = { app = "collection-postgres" }
      }

      spec {
        # The official postgres image runs as uid 999; k3s's local-path
        # provisioner can hand back a directory the container can't write
        # to without this, same class of bug as kcal's distroless PVC fix.
        security_context {
          fs_group = 999
        }

        container {
          name  = "postgres"
          image = "postgres:16-alpine"

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.collection_tracker.metadata[0].name
                key  = "postgres-password"
              }
            }
          }

          env {
            name  = "POSTGRES_USER"
            value = "collection"
          }

          env {
            name  = "POSTGRES_DB"
            value = "collection"
          }

          port {
            container_port = 5432
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
            sub_path   = "pgdata"
          }

          resources {
            requests = { cpu = "50m", memory = "128Mi" }
            limits   = { cpu = "250m", memory = "256Mi" }
          }
        }

        volume {
          name = "data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.collection_postgres_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "collection_postgres" {
  metadata {
    name      = "collection-postgres"
    namespace = "homelab"
  }

  spec {
    selector = { app = "collection-postgres" }

    port {
      port        = 5432
      target_port = 5432
    }
  }
}

# ============================================================
# API + dashboard
# ============================================================

resource "kubernetes_deployment" "collection_api" {
  metadata {
    name      = "collection-api"
    namespace = "homelab"
    labels    = { app = "collection-api" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "collection-api" }
    }

    template {
      metadata {
        labels = { app = "collection-api" }
      }

      spec {
        # Applies schema.sql + seed.sql on every pod start. Both files are
        # idempotent (IF NOT EXISTS / ON CONFLICT), so this is safe to
        # re-run — deliberately not a separate kubernetes_job, since a
        # Job's pod template is immutable once created and would need an
        # awkward force-replace every time the image tag changes.
        init_container {
          name    = "migrate"
          image   = local.image
          command = ["python", "-m", "common.migrate"]

          dynamic "env" {
            for_each = local.common_env
            content {
              name  = env.value.name
              value = env.value.value
            }
          }
        }

        container {
          name  = "api"
          image = local.image

          dynamic "env" {
            for_each = local.common_env
            content {
              name  = env.value.name
              value = env.value.value
            }
          }

          env {
            name  = "HA_BASE_URL"
            value = "https://home.nuga.dev"
          }

          env {
            name  = "HA_NOTIFY_SERVICE"
            value = var.collection_ha_notify_service
          }

          env {
            name = "HA_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.collection_tracker.metadata[0].name
                key  = "ha-token"
              }
            }
          }

          port {
            container_port = 8080
          }

          resources {
            requests = { cpu = "25m", memory = "64Mi" }
            limits   = { cpu = "200m", memory = "128Mi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "collection_api" {
  metadata {
    name      = "collection-api"
    namespace = "homelab"
  }

  spec {
    selector = { app = "collection-api" }

    port {
      port        = 8080
      target_port = 8080
    }
  }
}

resource "kubernetes_ingress_v1" "collection_api" {
  metadata {
    name      = "collection-api"
    namespace = "homelab"
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "collection.nuga.dev"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.collection_api.metadata[0].name

              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
}

# ============================================================
# Watcher (daily CronJob)
# ============================================================

resource "kubernetes_cron_job_v1" "collection_watcher" {
  metadata {
    name      = "collection-watcher"
    namespace = "homelab"
  }

  spec {
    schedule                      = "0 13 * * *"
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {
        name = "collection-watcher"
      }

      spec {
        template {
          metadata {
            labels = { app = "collection-watcher" }
          }

          spec {
            restart_policy = "OnFailure"

            container {
              name    = "watcher"
              image   = local.image
              command = ["python", "-m", "watcher.main"]

              dynamic "env" {
                for_each = local.common_env
                content {
                  name  = env.value.name
                  value = env.value.value
                }
              }

              env {
                name  = "HA_BASE_URL"
                value = "https://home.nuga.dev"
              }

              env {
                name  = "HA_NOTIFY_SERVICE"
                value = var.collection_ha_notify_service
              }

              env {
                name = "HA_TOKEN"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.collection_tracker.metadata[0].name
                    key  = "ha-token"
                  }
                }
              }

              env {
                name = "EBAY_CLIENT_ID"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.collection_tracker.metadata[0].name
                    key  = "ebay-client-id"
                  }
                }
              }

              env {
                name = "EBAY_CLIENT_SECRET"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.collection_tracker.metadata[0].name
                    key  = "ebay-client-secret"
                  }
                }
              }

              resources {
                requests = { cpu = "25m", memory = "64Mi" }
                limits   = { cpu = "200m", memory = "128Mi" }
              }
            }
          }
        }
      }
    }
  }
}
