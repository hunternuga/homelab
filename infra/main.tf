resource "aws_lightsail_key_pair" "homelab" {
  name = "homelab"
}

resource "aws_lightsail_instance" "node1" {
  name              = "homelab-node-1"
  availability_zone = "us-west-2a"
  blueprint_id      = "ubuntu_24_04"
  bundle_id         = "small_3_0"
  key_pair_name     = aws_lightsail_key_pair.homelab.name

  tags = {
    role = "control-plane"
  }
}

resource "aws_lightsail_instance" "node2" {
  name              = "homelab-node-2"
  availability_zone = "us-west-2a"
  blueprint_id      = "ubuntu_24_04"
  bundle_id         = "small_3_0"
  key_pair_name     = aws_lightsail_key_pair.homelab.name

  tags = {
    role = "agent"
  }
}

# Static IPs are free while attached to a running instance — used for both
# nodes so a stop/start never changes the address kubeconfig, SSH, or the
# k3s server URL depend on.

resource "aws_lightsail_static_ip" "node1" {
  name = "homelab-node-1-ip"
}

resource "aws_lightsail_static_ip_attachment" "node1" {
  static_ip_name = aws_lightsail_static_ip.node1.name
  instance_name  = aws_lightsail_instance.node1.name
}

resource "aws_lightsail_static_ip" "node2" {
  name = "homelab-node-2-ip"
}

resource "aws_lightsail_static_ip_attachment" "node2" {
  static_ip_name = aws_lightsail_static_ip.node2.name
  instance_name  = aws_lightsail_instance.node2.name
}

# Lightsail's public-ports firewall only governs public traffic — instances
# in the same account/region already reach each other over private IP for
# free, so node-2 can join node-1's k3s API on :6443 without opening it here.

resource "aws_lightsail_instance_public_ports" "node1" {
  instance_name = aws_lightsail_instance.node1.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidrs     = ["0.0.0.0/0"]
  }
}

resource "aws_lightsail_instance_public_ports" "node2" {
  instance_name = aws_lightsail_instance.node2.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidrs     = ["0.0.0.0/0"]
  }
}
