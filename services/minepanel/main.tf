data "docker_network" "homelab" {
  name = "homelab"
}

resource "docker_image" "minepanel" {
  name         = "ketbom/minepanel:latest"
  keep_locally = true
}

resource "docker_volume" "minepanel_data" {
  name = "minepanel_data"
}

resource "docker_container" "minepanel" {
  name  = "minepanel"
  image = docker_image.minepanel.image_id

  env = [
    "JWT_SECRET=${var.jwt_secret}",
    "JWT_EXPIRES_IN=2d",
    "CLIENT_USERNAME=${var.admin_username}",
    "CLIENT_PASSWORD=${var.admin_password}",
    "FRONTEND_URL=https://minepanel.nuga.dev",
    "NEXT_PUBLIC_BACKEND_URL=https://minepanel-api.nuga.dev",
    "BASE_DIR=/Users/hunternuga/homelab/services/minepanel/data",
    "NEXT_PUBLIC_DEFAULT_LANGUAGE=en"
  ]

  volumes {
    host_path      = "/Users/hunternuga/homelab/services/minepanel/data"
    container_path = "/app/data"
  }

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }

  networks_advanced {
    name = data.docker_network.homelab.name
  }

  restart = "unless-stopped"
}
