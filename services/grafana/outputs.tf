output "grafana_ip" {
  value = docker_container.grafana.network_data[0].ip_address
}
