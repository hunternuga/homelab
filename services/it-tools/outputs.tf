output "it_tools_container_ip" {
  value = docker_container.it_tools.network_data[0].ip_address
}
