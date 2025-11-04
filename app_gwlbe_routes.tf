############################################
# app_gwlbe_routes.tf
# App & Mgmt VPC per-AZ routing via GWLB/GWLBE -> PAN
# - App: rt-app-az1/az2 + routes 0.0.0.0/0 and 10.20.0.0/16 -> local GWLBE
# - Mgmt: creates GWLBE from endpoint service, builds rt-mgmt-az1/az2,
#         and routes 10.30.0.0/16 and 0.0.0.0/0 -> mgmt GWLBE
############################################

locals {
  vpc_app_id  = "vpc-0d9793d0c3a15b56c"     # App VPC (10.30.0.0/16)
  vpc_mgmt_id = "vpc-05ba9445813b0d56a"     # Mgmt VPC (10.20.0.0/16)

  app_cidr    = "10.30.0.0/16"
  mgmt_cidr   = "10.20.0.0/16"

  # App subnets (per AZ)
  app_subnet_ids = {
    az1 = "subnet-0713a498610ac9ddd"       # app-az1 (10.30.11.0/24)
    az2 = "subnet-006ecb6b54880690d"       # app-az2 (10.30.12.0/24)
  }

  # Existing App-side GWLBE endpoint IDs (per AZ)
  gwlbe_app = {
    az1 = "vpce-08635367177785ff0"         # gwlbe-ins-az1
    az2 = "vpce-0aeef965581da3518"         # gwlbe-ins-az2
  }

  # Mgmt subnets (per AZ)
  mgmt_subnet_ids = {
    az1 = "subnet-0df91eca84831dcf7"       # mgmt-az1 (10.20.11.0/24)
    az2 = "subnet-000d1270d3c8e2c7"        # mgmt-az2 (10.20.12.0/24)
  }

  # GWLB Endpoint Service name (from inspection VPC)
  gwlb_service_name = "com.amazonaws.vpce.us-west-2.vpce-svc-0a4f6952bc2855d2f"
}

############################################
# APP VPC — per-AZ Route Tables → local GWLBE
############################################

resource "aws_route_table" "app" {
  for_each = local.app_subnet_ids

  vpc_id = local.vpc_app_id

  tags = {
    Name = "rt-app-${each.key}"
  }
}

# N-S: App → Internet via PAN (through local GWLBE)
resource "aws_route" "app_default_via_gwlbe" {
  for_each = local.app_subnet_ids

  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.gwlbe_app[each.key]

  lifecycle {
    create_before_destroy = true
  }
}

# E-W: App → Mgmt via PAN (through local GWLBE)
resource "aws_route" "app_to_mgmt_via_gwlbe" {
  for_each = local.app_subnet_ids

  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = local.mgmt_cidr
  vpc_endpoint_id        = local.gwlbe_app[each.key]

  lifecycle {
    create_before_destroy = true
  }
}

# Associate each App subnet to its AZ-local route table
resource "aws_route_table_association" "app" {
  for_each = local.app_subnet_ids

  subnet_id      = each.value
  route_table_id = aws_route_table.app[each.key].id
}

############################################
# MGMT VPC — create GWLBE + per-AZ RTs + routes
############################################

# One GWLB Endpoint across both Mgmt subnets (AWS creates zonal ENIs)
resource "aws_vpc_endpoint" "mgmt_gwlbe" {
  vpc_id            = local.vpc_mgmt_id
  service_name      = local.gwlb_service_name
  vpc_endpoint_type = "GatewayLoadBalancer"

  subnet_ids = [
    local.mgmt_subnet_ids.az1,
    local.mgmt_subnet_ids.az2
  ]

  tags = {
    Name = "gwlbe-mgmt"
  }
}

# Per-AZ Mgmt route tables
resource "aws_route_table" "mgmt" {
  for_each = local.mgmt_subnet_ids

  vpc_id = local.vpc_mgmt_id

  tags = {
    Name = "rt-mgmt-${each.key}"
  }
}

# E-W: Mgmt → App via PAN (target the created mgmt GWLBE)
resource "aws_route" "mgmt_to_app_via_gwlbe" {
  for_each = local.mgmt_subnet_ids

  route_table_id         = aws_route_table.mgmt[each.key].id
  destination_cidr_block = local.app_cidr
  vpc_endpoint_id        = aws_vpc_endpoint.mgmt_gwlbe.id

  lifecycle {
    create_before_destroy = true
  }
}

# N-S: Mgmt → Internet via PAN (enabled to fully satisfy & polish)
resource "aws_route" "mgmt_default_via_gwlbe" {
  for_each = local.mgmt_subnet_ids

  route_table_id         = aws_route_table.mgmt[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = aws_vpc_endpoint.mgmt_gwlbe.id

  lifecycle {
    create_before_destroy = true
  }
}

# Associate each Mgmt subnet to its AZ-local route table
resource "aws_route_table_association" "mgmt" {
  for_each = local.mgmt_subnet_ids

  subnet_id      = each.value
  route_table_id = aws_route_table.mgmt[each.key].id
}

############################################
# OUTPUTS
############################################

output "app_route_table_ids" {
  value = { for k, rt in aws_route_table.app : k => rt.id }
}

output "app_route_table_associations" {
  value = { for k, a in aws_route_table_association.app : k => a.subnet_id }
}

output "mgmt_gwlbe_id" {
  value       = aws_vpc_endpoint.mgmt_gwlbe.id
  description = "Mgmt VPC GWLBE endpoint ID"
}

output "mgmt_route_table_ids" {
  value = { for k, rt in aws_route_table.mgmt : k => rt.id }
}

output "mgmt_route_table_associations" {
  value = { for k, a in aws_route_table_association.mgmt : k => a.subnet_id }
}
