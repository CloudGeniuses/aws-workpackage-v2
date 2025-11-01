############################################
# Variables (set your PAN instance ID)
############################################
variable "pan_instance_id" {
  description = "Existing Palo Alto EC2 instance ID"
  type        = string
  default     = "i-09ea669dc07701d14" # <-- change if different
}

############################################
# Untrust ENI (ethernet1/1) in ins-untrust-az1 (10.10.11.0/24)
############################################
resource "aws_network_interface" "pan_untrust_eni" {
  subnet_id         = aws_subnet.ins_untrust_az1.id
  security_groups   = [aws_security_group.pan_untrust_sg.id]
  description       = "pan-untrust-az1 (ethernet1/1)"
  source_dest_check = false  # disable for firewall dataplane

  tags = {
    Name = "pan-untrust-az1"
    Role = "untrust"
  }
}

resource "aws_network_interface_attachment" "pan_untrust_attach" {
  instance_id          = var.pan_instance_id
  network_interface_id = aws_network_interface.pan_untrust_eni.id
  device_index         = 1 # maps to ethernet1/1
}

############################################
# Trust ENI (ethernet1/2) in ins-trust-az1 (10.10.21.0/24)
############################################
resource "aws_network_interface" "pan_trust_eni" {
  subnet_id         = aws_subnet.ins_trust_az1.id
  security_groups   = [aws_security_group.pan_dataplane_sg.id]
  description       = "pan-trust-az1 (ethernet1/2)"
  source_dest_check = false  # disable for firewall dataplane

  tags = {
    Name = "pan-trust-az1"
    Role = "trust"
  }
}

resource "aws_network_interface_attachment" "pan_trust_attach" {
  instance_id          = var.pan_instance_id
  network_interface_id = aws_network_interface.pan_trust_eni.id
  device_index         = 2 # maps to ethernet1/2
}

############################################
# (Optional) Outputs: show the assigned private IPs
############################################
output "pan_untrust_private_ip" {
  value = aws_network_interface.pan_untrust_eni.private_ip
}

output "pan_trust_private_ip" {
  value = aws_network_interface.pan_trust_eni.private_ip
}
