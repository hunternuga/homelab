data "docker_network" "homelab" {
  name = "homelab"
}

resource "docker_image" "it_tools" {
  name         = "corentinth/it-tools:latest"
  keep_locally = true
}

resource "docker_container" "it_tools" {
  name  = "it-tools"
  image = docker_image.it_tools.image_id

  networks_advanced {
    name = data.docker_network.homelab.name
  }

  restart = "unless-stopped"
}
