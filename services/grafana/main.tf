data "docker_network" "homelab" {
  name = "homelab"
}

data "external" "prometheus_ip" {
  program = ["${path.module}/../../scripts/get_prometheus_ip.sh"]
}

resource "docker_image" "grafana" {
  name         = "grafana/grafana:latest"
  keep_locally = true
}

resource "docker_volume" "grafana_data" {
  name = "grafana_data"
}

resource "null_resource" "grafana_datasource" {
  depends_on = [docker_volume.grafana_data]

  triggers = {
    prometheus_ip = data.external.prometheus_ip.result.ip
  }

  provisioner "local-exec" {
    command = "sed 's|http://localhost:9090|http://${data.external.prometheus_ip.result.ip}:9090|g' ${path.module}/provisioning/datasources/prometheus.yaml > /tmp/prometheus_ds.yaml && podman run --rm -v grafana_data:/var/lib/grafana alpine sh -c 'mkdir -p /var/lib/grafana/provisioning/datasources && cat > /var/lib/grafana/provisioning/datasources/prometheus.yaml' < /tmp/prometheus_ds.yaml"
  }
}

resource "docker_container" "grafana" {
  depends_on = [null_resource.grafana_datasource]

  name  = "grafana"
  image = docker_image.grafana.image_id

  env = [
    "GF_SERVER_ROOT_URL=https://grafana.nuga.dev",
    "GF_AUTH_DISABLE_LOGIN_FORM=false",
    "GF_SECURITY_ADMIN_USER=admin",
    "GF_SECURITY_ADMIN_PASSWORD=changeme",
    "GF_PATHS_PROVISIONING=/var/lib/grafana/provisioning"
  ]

  volumes {
    volume_name    = docker_volume.grafana_data.name
    container_path = "/var/lib/grafana"
  }

  volumes {
    host_path      = abspath("${path.module}/provisioning/dashboards")
    container_path = "/var/lib/grafana/provisioning/dashboards"
    read_only      = true
  }

  networks_advanced {
    name = data.docker_network.homelab.name
  }

  restart = "unless-stopped"
}
