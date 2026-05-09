output "cadvisor_ip" {
  value = docker_container.cadvisor.network_data[0].ip_address
}
