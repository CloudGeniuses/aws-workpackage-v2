############################################
# app_gwlbe_routes.tf (per-AZ GWLBE endpoints)
############################################

locals {
  # VPCs
  vpc_app_id  = "vpc-0d9793d0c3a15b56c"     # App VPC (10.30.0.0/16)
  vpc_mgmt_id = "vpc-05ba9445813b0d56a"     # Mgmt VPC (10.20.0.0/16)

  # CIDRs
  app_cidr  = "10.30.0.0/16"
  mgmt_cidr = "10.20.0.0/16"

  # App subnets (must be in vpc_app_id)
  app_subnet_ids = {
    az1 = "subnet-0713a498610ac9ddd"       # app-az1  (10.30.11.0/24)
    az2 = "subnet-006ecb6b54880690d"       # app-az2  (10.30.12.0/24)
  }

  # Mgmt subnets (must be in vpc_mgmt_id)
  mgmt_subnet_ids = {
    az1 = "subnet-0df91eca84831dcf7"       # mgmt-az1 (10.20.11.0/24)
    az2 = "subnet-000d1270d3c8e2c7"        # mgmt-az2 (10.20.12.0/24)  <-- verify exists in this account/region
  }

  # Your GWLB Endpoint Service (from inspection VPC)
  gwlb_service_name = "com.amazonaws.vpce.us-west-2.vpce-svc-0a4f6952bc2855d2f"
}

############################################
# APP VPC — one GWLBE per AZ (zonal), RTs and routes
############################################

# Per-AZ GWLBE in APP VPC (each endpoint can have only ONE subnet)
resource "aws_vpc_endpoint" "app_gwlbe" {
  for_each          = local.app_subnet_ids
  vpc_id            = local.vpc_app_id
  service_name      = local.gwlb_service_name
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [each.value]   # exactly one subnet per endpoint

  tags = { Name = "gwlbe-app-${each.key}" }
}

# Per-AZ route table in APP VPC
resource "aws_route_table" "app" {
  for_each = local.app_subnet_ids
  vpc_id   = local.vpc_app_id
  tags     = { Name = "rt-app-${each.key}" }
}

# N-S: App → Internet via PAN (through APP GWLBE in same AZ)
resource "aws_route" "app_default_via_gwlbe" {
  for_each               = local.app_subnet_ids
  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = aws_vpc_endpoint.app_gwlbe[each.key].id
  lifecycle { create_before_destroy = true }
}

# E-W: App → Mgmt via PAN (through APP GWLBE in same AZ)
resource "aws_route" "app_to_mgmt_via_gwlbe" {
  for_each               = local.app_subnet_ids
  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = local.mgmt_cidr
  vpc_endpoint_id        = aws_vpc_endpoint.app_gwlbe[each.key].id
  lifecycle { create_before_destroy = true }
}

# Associate each App subnet with its AZ-local route table
resource "aws_route_table_association" "app" {
  for_each      = local.app_subnet_ids
  subnet_id     = each.value
  route_table_id = aws_route_table.app[each.key].id
}

############################################
# MGMT VPC — one GWLBE per AZ (zonal), RTs and routes
############################################

# Per-AZ GWLBE in MGMT VPC
resource "aws_vpc_endpoint" "mgmt_gwlbe" {
  for_each          = local.mgmt_subnet_ids
  vpc_id            = local.vpc_mgmt_id
  service_name      = local.gwlb_service_name
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [each.value]   # exactly one subnet per endpoint

  tags = { Name = "gwlbe-mgmt-${each.key}" }
}

# Per-AZ route table in MGMT VPC
resource "aws_route_table" "mgmt" {
  for_each = local.mgmt_subnet_ids
  vpc_id   = local.vpc_mgmt_id
  tags     = { Name = "rt-mgmt-${each.key}" }
}

# E-W: Mgmt → App via PAN (through MGMT GWLBE in same AZ)
resource "aws_route" "mgmt_to_app_via_gwlbe" {
  for_each               = local.mgmt_subnet_ids
  route_table_id         = aws_route_table.mgmt[each.key].id
  destination_cidr_block = local.app_cidr
  vpc_endpoint_id        = aws_vpc_endpoint.mgmt_gwlbe[each.key].id
  lifecycle { create_before_destroy = true }
}

# N-S: Mgmt → Internet via PAN (optional; enabled)
resource "aws_route" "mgmt_default_via_gwlbe" {
  for_each               = local.mgmt_subnet_ids
  route_table_id         = aws_route_table.mgmt[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = aws_vpc_endpoint.mgmt_gwlbe[each.key].id
  lifecycle { create_before_destroy = true }
}

# Associate each Mgmt subnet with its AZ-local route table
resource "aws_route_table_association" "mgmt" {
  for_each      = local.mgmt_subnet_ids
  subnet_id     = each.value
  route_table_id = aws_route_table.mgmt[each.key].id
}

############################################
# OUTPUTS
############################################

output "app_gwlbe_ids" {
  value       = { for k, v in aws_vpc_endpoint.app_gwlbe : k => v.id }
  description = "App GWLBE endpoint IDs per AZ"
}

output "mgmt_gwlbe_ids" {
  value       = { for k, v in aws_vpc_endpoint.mgmt_gwlbe : k => v.id }
  description = "Mgmt GWLBE endpoint IDs per AZ"
}

output "app_route_table_ids" {
  value = { for k, rt in aws_route_table.app : k => rt.id }
}

output "mgmt_route_table_ids" {
  value = { for k, rt in aws_route_table.mgmt : k => rt.id }
}
