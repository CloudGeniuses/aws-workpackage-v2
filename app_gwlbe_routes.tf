############################################
# app_gwlbe_routes.tf  (tag-based lookups, per-AZ endpoints)
############################################

# Which AWS account am I using?
data "aws_caller_identity" "current" {}

output "aws_account_in_use" {
  value       = data.aws_caller_identity.current.account_id
  description = "AWS account ID used by this workspace/run"
}

############################################################
# DATA LOOKUPS — avoid brittle hard-coded IDs
############################################################

# VPCs by Name tag
data "aws_vpc" "app" {
  filter {
    name   = "tag:Name"
    values = ["vpc-app"]
  }
}

data "aws_vpc" "mgmt" {
  filter {
    name   = "tag:Name"
    values = ["vpc-mgmt"]
  }
}

# App subnets (in vpc-app)
data "aws_subnet" "app_az1" {
  filter {
    name   = "tag:Name"
    values = ["app-az1"]
  }
  vpc_id = data.aws_vpc.app.id
}

data "aws_subnet" "app_az2" {
  filter {
    name   = "tag:Name"
    values = ["app-az2"]
  }
  vpc_id = data.aws_vpc.app.id
}

# Mgmt subnets (in vpc-mgmt)
data "aws_subnet" "mgmt_az1" {
  filter {
    name   = "tag:Name"
    values = ["mgmt-az1"]
  }
  vpc_id = data.aws_vpc.mgmt.id
}

data "aws_subnet" "mgmt_az2" {
  filter {
    name   = "tag:Name"
    values = ["mgmt-az2"]
  }
  vpc_id = data.aws_vpc.mgmt.id
}

locals {
  # CIDRs
  app_cidr     = "10.30.0.0/16"
  mgmt_cidr    = "10.20.0.0/16"
  fw_mgmt_cidr = "10.10.1.0/24"   # PAN Mgmt subnet (inspection VPC)
  tgw_id       = "tgw-0428e79b5f0d6fec0"  # << your TGW

  # GWLB endpoint service (from inspection VPC)
  gwlb_service_name = "com.amazonaws.vpce.us-west-2.vpce-svc-0a4f6952bc2855d2f"

  # Per-AZ subnet maps
  app_subnets = {
    az1 = data.aws_subnet.app_az1.id
    az2 = data.aws_subnet.app_az2.id
  }

  mgmt_subnets = {
    az1 = data.aws_subnet.mgmt_az1.id
    az2 = data.aws_subnet.mgmt_az2.id
  }
}

############################################################
# APP VPC — one GWLBE per AZ (zonal), RTs and routes
############################################################

resource "aws_vpc_endpoint" "app_gwlbe" {
  for_each          = local.app_subnets
  vpc_id            = data.aws_vpc.app.id
  service_name      = local.gwlb_service_name
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [each.value]

  tags = {
    Name = "gwlbe-app-${each.key}"
  }
}

resource "aws_route_table" "app" {
  for_each = local.app_subnets
  vpc_id   = data.aws_vpc.app.id

  tags = {
    Name = "rt-app-${each.key}"
  }
}

resource "aws_route" "app_default_via_gwlbe" {
  for_each               = local.app_subnets
  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = aws_vpc_endpoint.app_gwlbe[each.key].id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route" "app_to_mgmt_via_gwlbe" {
  for_each               = local.app_subnets
  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = local.mgmt_cidr
  vpc_endpoint_id        = aws_vpc_endpoint.app_gwlbe[each.key].id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route_table_association" "app" {
  for_each       = local.app_subnets
  subnet_id      = each.value
  route_table_id = aws_route_table.app[each.key].id
}

############################################################
# MGMT VPC — one GWLBE per AZ (zonal), RTs and routes
############################################################

resource "aws_vpc_endpoint" "mgmt_gwlbe" {
  for_each          = local.mgmt_subnets
  vpc_id            = data.aws_vpc.mgmt.id
  service_name      = local.gwlb_service_name
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [each.value]

  tags = {
    Name = "gwlbe-mgmt-${each.key}"
  }
}

resource "aws_route_table" "mgmt" {
  for_each = local.mgmt_subnets
  vpc_id   = data.aws_vpc.mgmt.id

  tags = {
    Name = "rt-mgmt-${each.key}"
  }
}

# NEW: MGMT → PAN mgmt subnet via TGW (uninspected path for SSM/SSH/UI)
resource "aws_route" "mgmt_to_fwmgmt_via_tgw" {
  for_each               = local.mgmt_subnets
  route_table_id         = aws_route_table.mgmt[each.key].id
  destination_cidr_block = local.fw_mgmt_cidr
  transit_gateway_id     = local.tgw_id

  lifecycle {
    create_before_destroy = true
  }
}

# MGMT → APP via firewall (inspected)
resource "aws_route" "mgmt_to_app_via_gwlbe" {
  for_each               = local.mgmt_subnets
  route_table_id         = aws_route_table.mgmt[each.key].id
  destination_cidr_block = local.app_cidr
  vpc_endpoint_id        = aws_vpc_endpoint.mgmt_gwlbe[each.key].id

  lifecycle {
    create_before_destroy = true
  }
}

# MGMT → Internet via firewall (inspected)
resource "aws_route" "mgmt_default_via_gwlbe" {
  for_each               = local.mgmt_subnets
  route_table_id         = aws_route_table.mgmt[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = aws_vpc_endpoint.mgmt_gwlbe[each.key].id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route_table_association" "mgmt" {
  for_each       = local.mgmt_subnets
  subnet_id      = each.value
  route_table_id = aws_route_table.mgmt[each.key].id
}

############################################################
# Outputs
############################################################

output "app_gwlbe_ids" {
  value       = { for k, v in aws_vpc_endpoint.app_gwlbe : k => v.id }
  description = "App GWLBE endpoint IDs per AZ"
}

output "mgmt_gwlbe_ids" {
  value       = { for k, v in aws_vpc_endpoint.mgmt_gwlbe : k => v.id }
  description = "Mgmt GWLBE endpoint IDs per AZ"
}

output "app_route_table_ids" {
  value       = { for k, rt in aws_route_table.app : k => rt.id }
  description = "App Route Table IDs per AZ"
}

output "mgmt_route_table_ids" {
  value       = { for k, rt in aws_route_table.mgmt : k => rt.id }
  description = "Mgmt Route Table IDs per AZ"
}
