resource "aws_lightsail_key_pair" "homelab" {
  name = "homelab"
}

resource "aws_lightsail_instance" "node1" {
  name              = "homelab-node-1"
  availability_zone = "us-west-2a"
  blueprint_id      = "ubuntu_24_04"
  bundle_id         = "medium_3_0"
  key_pair_name     = aws_lightsail_key_pair.homelab.name
}

# Static IP is free while attached to a running instance — used so a
# stop/start never changes the address kubeconfig, SSH, or the k3s server
# URL depend on.

resource "aws_lightsail_static_ip" "node1" {
  name = "homelab-node-1-ip"
}

resource "aws_lightsail_static_ip_attachment" "node1" {
  static_ip_name = aws_lightsail_static_ip.node1.name
  instance_name  = aws_lightsail_instance.node1.name
}

resource "aws_lightsail_instance_public_ports" "node1" {
  instance_name = aws_lightsail_instance.node1.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidrs     = ["0.0.0.0/0"]
  }
}
