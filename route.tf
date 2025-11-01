############################################
# Management RTB (existing) routes
#  - Reuse the *existing* main RTB: rtb-06f69c9d737746730
#  - Add routes to Inspection (10.10.0.0/16) and App (10.30.0.0/16) via TGW
############################################

locals {
  # Existing main Route Table in vpc-mgmt (do not create a new one)
  mgmt_main_rtb_id = "rtb-06f69c9d737746730"
}

# Bastion -> Palo Alto (Inspection VPC)
resource "aws_route" "mgmt_to_inspection" {
  route_table_id         = local.mgmt_main_rtb_id
  destination_cidr_block = "10.10.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.att_mgmt]
}

# Bastion -> App VPC (optional but recommended for symmetry)
resource "aws_route" "mgmt_to_app" {
  route_table_id         = local.mgmt_main_rtb_id
  destination_cidr_block = "10.30.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.att_mgmt]
}
