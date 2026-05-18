output "minepanel_ip" {
  value = docker_container.minepanel.network_data[0].ip_address
}
