output "prometheus_ip" {
  value = docker_container.prometheus.network_data[0].ip_address
}
