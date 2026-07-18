output "node1_public_ip" {
  value = aws_lightsail_static_ip.node1.ip_address
}

output "node1_private_ip" {
  value = aws_lightsail_instance.node1.private_ip_address
}

output "node2_public_ip" {
  value = aws_lightsail_static_ip.node2.ip_address
}

output "node2_private_ip" {
  value = aws_lightsail_instance.node2.private_ip_address
}

output "ssh_private_key" {
  value     = aws_lightsail_key_pair.homelab.private_key
  sensitive = true
}
