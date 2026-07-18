resource "kubernetes_deployment" "it_tools" {
  metadata {
    name      = "it-tools"
    namespace = "homelab"
    labels    = { app = "it-tools" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "it-tools" }
    }

    template {
      metadata {
        labels = { app = "it-tools" }
      }

      spec {
        node_selector = { "homelab/role" = "apps" }

        container {
          name  = "it-tools"
          image = "corentinth/it-tools:latest"

          port {
            container_port = 80
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "it_tools" {
  metadata {
    name      = "it-tools"
    namespace = "homelab"
  }

  spec {
    selector = { app = "it-tools" }

    port {
      port        = 80
      target_port = 80
    }
  }
}

resource "kubernetes_ingress_v1" "it_tools" {
  metadata {
    name      = "it-tools"
    namespace = "homelab"
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "tools.nuga.dev"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.it_tools.metadata[0].name

              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
