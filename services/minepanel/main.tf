# MinePanel manages its own Minecraft server containers via the Docker
# socket, which doesn't belong inside Kubernetes — this module runs it as
# plain Docker directly on the node, alongside the k3s-based services.
# https://github.com/Ketbome/minepanel

locals {
  data_dir = pathexpand("~/homelab-data/minepanel")
}

resource "docker_network" "minepanel" {
  name   = "minepanel"
  driver = "bridge"
}

resource "docker_image" "minepanel_backend" {
  name         = "ketbom/minepanel-backend:latest"
  keep_locally = true
}

resource "docker_image" "minepanel_frontend" {
  name         = "ketbom/minepanel-frontend:latest"
  keep_locally = true
}

# ============================================================
# Backend — manages server containers, needs the Docker socket
# ============================================================

resource "docker_container" "minepanel_backend" {
  name    = "minepanel-backend"
  image   = docker_image.minepanel_backend.image_id
  restart = "unless-stopped"

  env = [
    "NODE_ENV=production",
    "FRONTEND_URL=https://minepanel.nuga.dev",
    "JWT_SECRET=${var.minepanel_jwt_secret}",
  ]

  networks_advanced {
    name = docker_network.minepanel.name
  }

  ports {
    internal = 8091
    external = 8091
  }

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }

  volumes {
    host_path      = "${local.data_dir}/servers"
    container_path = "/app/servers"
  }

  volumes {
    host_path      = "${local.data_dir}/data"
    container_path = "/app/data"
  }
}

# ============================================================
# Frontend — the web UI, calls the backend directly from the browser
# ============================================================

resource "docker_container" "minepanel_frontend" {
  name    = "minepanel-frontend"
  image   = docker_image.minepanel_frontend.image_id
  restart = "unless-stopped"

  env = [
    "NEXT_PUBLIC_BACKEND_URL=https://minepanel-api.nuga.dev",
  ]

  networks_advanced {
    name = docker_network.minepanel.name
  }

  ports {
    internal = 3000
    external = 3000
  }
}
