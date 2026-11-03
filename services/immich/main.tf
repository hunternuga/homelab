# Immich — self-hosted photo/video backup with phone apps that do
# automatic background upload. Four pieces, matching the project's own
# docker-compose (https://github.com/immich-app/immich/blob/main/docker/docker-compose.yml):
# Postgres (with a vector-search extension, hence the custom image),
# Valkey/Redis (job queue), the ML service (face/object recognition),
# and the server itself. No Cloudflare Access in front of it — same
# reasoning as Home Assistant/Jellyfin: the mobile apps' background
# upload is a raw API call that Access's interactive login would break.
# Immich's own login is the auth boundary instead.

resource "kubernetes_secret" "immich" {
  metadata {
    name      = "immich"
    namespace = "homelab"
  }

  data = {
    "db-password" = var.immich_db_password
  }
}

# ============================================================
# Database (Postgres + vector search extension)
# ============================================================

resource "kubernetes_persistent_volume_claim" "immich_db_data" {
  metadata {
    name      = "immich-db-data"
    namespace = "homelab"
  }

  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "local-path"

    resources {
      requests = { storage = "10Gi" }
    }
  }
}

resource "kubernetes_deployment" "immich_database" {
  metadata {
    name      = "immich-database"
    namespace = "homelab"
    labels    = { app = "immich-database" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "immich-database" }
    }

    template {
      metadata {
        labels = { app = "immich-database" }
      }

      spec {
        # The postgres image runs as uid 999; k3s's local-path provisioner
        # can hand back a directory the container can't write to without
        # this — same fix as collection-tracker's postgres PVC.
        security_context {
          fs_group = 999
        }

        container {
          name  = "database"
          image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0"

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.immich.metadata[0].name
                key  = "db-password"
              }
            }
          }

          env {
            name  = "POSTGRES_USER"
            value = "postgres"
          }

          env {
            name  = "POSTGRES_DB"
            value = "immich"
          }

          env {
            name  = "POSTGRES_INITDB_ARGS"
            value = "--data-checksums"
          }

          port {
            container_port = 5432
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }

          # Matches the official compose's shm_size: 128mb — Postgres uses
          # /dev/shm for some query operations and the container default
          # (64Mi) is too small.
          volume_mount {
            name       = "dshm"
            mount_path = "/dev/shm"
          }

          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { cpu = "1000m", memory = "1Gi" }
          }
        }

        volume {
          name = "data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.immich_db_data.metadata[0].name
          }
        }

        volume {
          name = "dshm"

          empty_dir {
            medium     = "Memory"
            size_limit = "128Mi"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "immich_database" {
  metadata {
    name      = "immich-database"
    namespace = "homelab"
  }

  spec {
    selector = { app = "immich-database" }

    port {
      port        = 5432
      target_port = 5432
    }
  }
}

# ============================================================
# Redis (Valkey) — job queue
# ============================================================

resource "kubernetes_deployment" "immich_redis" {
  metadata {
    name      = "immich-redis"
    namespace = "homelab"
    labels    = { app = "immich-redis" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "immich-redis" }
    }

    template {
      metadata {
        labels = { app = "immich-redis" }
      }

      spec {
        container {
          name  = "redis"
          image = "docker.io/valkey/valkey:9"

          port {
            container_port = 6379
          }

          resources {
            requests = { cpu = "25m", memory = "32Mi" }
            limits   = { cpu = "200m", memory = "128Mi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "immich_redis" {
  metadata {
    name      = "immich-redis"
    namespace = "homelab"
  }

  spec {
    selector = { app = "immich-redis" }

    port {
      port        = 6379
      target_port = 6379
    }
  }
}

# ============================================================
# Machine Learning — face/object recognition, smart search
# ============================================================

resource "kubernetes_persistent_volume_claim" "immich_ml_cache" {
  metadata {
    name      = "immich-ml-cache"
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

resource "kubernetes_deployment" "immich_machine_learning" {
  metadata {
    name      = "immich-machine-learning"
    namespace = "homelab"
    labels    = { app = "immich-machine-learning" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "immich-machine-learning" }
    }

    template {
      metadata {
        labels = { app = "immich-machine-learning" }
      }

      spec {
        container {
          name  = "machine-learning"
          image = "ghcr.io/immich-app/immich-machine-learning:release"

          env {
            name  = "MACHINE_LEARNING_MODEL_REVISION"
            value = "v2"
          }

          env {
            name  = "REDIS_HOSTNAME"
            value = kubernetes_service.immich_redis.metadata[0].name
          }

          env {
            name  = "TZ"
            value = var.timezone
          }

          port {
            container_port = 3003
          }

          volume_mount {
            name       = "cache"
            mount_path = "/cache"
          }

          # CPU-only inference (no GPU passthrough) — fine for a
          # family-scale library; revisit if indexing new photos feels
          # slow.
          resources {
            requests = { cpu = "250m", memory = "512Mi" }
            limits   = { cpu = "2000m", memory = "2Gi" }
          }
        }

        volume {
          name = "cache"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.immich_ml_cache.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "immich_machine_learning" {
  metadata {
    name      = "immich-machine-learning"
    namespace = "homelab"
  }

  spec {
    selector = { app = "immich-machine-learning" }

    port {
      port        = 3003
      target_port = 3003
    }
  }
}

# ============================================================
# Server — the API/web app itself
# ============================================================

resource "kubernetes_deployment" "immich_server" {
  metadata {
    name      = "immich-server"
    namespace = "homelab"
    labels    = { app = "immich-server" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "immich-server" }
    }

    template {
      metadata {
        labels = { app = "immich-server" }
      }

      spec {
        container {
          name  = "server"
          image = "ghcr.io/immich-app/immich-server:release"

          env {
            name  = "DB_HOSTNAME"
            value = kubernetes_service.immich_database.metadata[0].name
          }

          env {
            name  = "DB_USERNAME"
            value = "postgres"
          }

          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.immich.metadata[0].name
                key  = "db-password"
              }
            }
          }

          env {
            name  = "DB_DATABASE_NAME"
            value = "immich"
          }

          env {
            name  = "REDIS_HOSTNAME"
            value = kubernetes_service.immich_redis.metadata[0].name
          }

          env {
            name  = "MACHINE_LEARNING_URL"
            value = "http://${kubernetes_service.immich_machine_learning.metadata[0].name}:3003"
          }

          env {
            name  = "TZ"
            value = var.timezone
          }

          port {
            container_port = 2283
          }

          # Bind-mounts straight to the 8TB USB drive mounted at
          # /mnt/storage on the node — Immich manages its own
          # library/upload/thumbs subfolder structure underneath this.
          volume_mount {
            name       = "photos"
            mount_path = "/data"
          }

          resources {
            requests = { cpu = "250m", memory = "512Mi" }
            limits   = { cpu = "2000m", memory = "2Gi" }
          }
        }

        volume {
          name = "photos"

          host_path {
            path = "/mnt/storage/photos"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "immich_server" {
  metadata {
    name      = "immich-server"
    namespace = "homelab"
  }

  spec {
    selector = { app = "immich-server" }

    port {
      port        = 2283
      target_port = 2283
    }
  }
}

resource "kubernetes_ingress_v1" "immich" {
  metadata {
    name      = "immich"
    namespace = "homelab"
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "immich.nuga.dev"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.immich_server.metadata[0].name

              port {
                number = 2283
              }
            }
          }
        }
      }
    }
  }
}
