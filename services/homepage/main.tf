data "docker_network" "homelab" {
  name = "homelab"
}

resource "docker_image" "homepage" {
  name         = "ghcr.io/gethomepage/homepage:latest"
  keep_locally = true
}

resource "docker_container" "homepage" {
  name  = "homepage"
  image = docker_image.homepage.image_id

  env = [
    "HOMEPAGE_ALLOWED_HOSTS=homepage.nuga.dev"
  ]

  ports {
    internal = 3000
    external = 3000
  }

  volumes {
    host_path      = abspath("${path.module}/config")
    container_path = "/app/config"
  }

  networks_advanced {
    name = data.docker_network.homelab.name
  }

  restart = "unless-stopped"
}
