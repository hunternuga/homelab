resource "kubernetes_daemonset" "cadvisor" {
  metadata {
    name      = "cadvisor"
    namespace = "homelab"
    labels    = { app = "cadvisor" }
  }

  spec {
    selector {
      match_labels = { app = "cadvisor" }
    }

    template {
      metadata {
        labels = { app = "cadvisor" }
      }

      spec {
        # No node_selector — cadvisor is a DaemonSet precisely because it
        # needs one pod per node (including the control-plane node) to
        # report that node's own metrics.

        # cadvisor never calls the Kubernetes API, and the default
        # serviceaccount-token mount can't coexist with the read-only
        # hostPath bind-mount of /var/run below (both want to create
        # /var/run/secrets inside the container).
        automount_service_account_token = false

        container {
          name  = "cadvisor"
          image = "gcr.io/cadvisor/cadvisor:latest"

          security_context {
            privileged = true
          }

          port {
            container_port = 8080
            # Binds cadvisor to the node's own IP so Prometheus can reach
            # each node's metrics individually via node service discovery
            # (a ClusterIP Service would round-robin across nodes and only
            # ever sample one of them per scrape).
            host_port = 8080
          }

          volume_mount {
            name       = "rootfs"
            mount_path = "/rootfs"
            read_only  = true
          }

          volume_mount {
            name       = "var-run"
            mount_path = "/var/run"
            read_only  = true
          }

          volume_mount {
            name       = "sys"
            mount_path = "/sys"
            read_only  = true
          }

          volume_mount {
            name       = "containerd"
            mount_path = "/var/lib/docker"
            read_only  = true
          }
        }

        volume {
          name = "rootfs"
          host_path {
            path = "/"
          }
        }

        volume {
          name = "var-run"
          host_path {
            path = "/var/run"
          }
        }

        volume {
          name = "sys"
          host_path {
            path = "/sys"
          }
        }

        volume {
          name = "containerd"
          host_path {
            path = "/var/lib/rancher/k3s/agent/containerd"
          }
        }
      }
    }
  }
}
