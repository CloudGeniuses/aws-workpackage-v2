############################################
# app_gwlbe_routes.tf
# Creates per-AZ route tables for App VPC
# Associates app subnets to AZ-local RTs
# Routes traffic to PAN FW via GWLBE
############################################

# --- CONFIG VALUES (Pre-Filled with Your Real IDs) ---

variable "vpc_app_id" {
  type        = string
  default     = "vpc-0d9793d0c3a15b56c"
}

variable "mgmt_cidr" {
  type        = string
  default     = "10.20.0.0/16"
}

variable "app_subnet_ids" {
  type = map(string)
  default = {
    az1 = "subnet-0713a498610ac9ddd" # app-az1 (10.30.11.0/24)
    az2 = "subnet-006ecb6b54880690d" # app-az2 (10.30.12.0/24)
  }
}

variable "gwlbe_endpoint_ids" {
  type = map(string)
  default = {
    az1 = "vpce-08635367177785ff0"   # gwlbe-ins-az1
    az2 = "vpce-0aeef965581da3518"   # gwlbe-ins-az2
  }
}

# --- CREATE PER-AZ ROUTE TABLES ---

resource "aws_route_table" "app" {
  for_each = var.app_subnet_ids

  vpc_id = var.vpc_app_id

  tags = {
    Name = "rt-app-${each.key}"
  }
}

# --- ROUTES TO FIREWALL (GWLBE -> PAN) ---

resource "aws_route" "app_default_via_gwlbe" {
  for_each = var.app_subnet_ids

  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = var.gwlbe_endpoint_ids[each.key]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route" "app_to_mgmt_via_gwlbe" {
  for_each = var.app_subnet_ids

  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = var.mgmt_cidr
  vpc_endpoint_id        = var.gwlbe_endpoint_ids[each.key]

  lifecycle {
    create_before_destroy = true
  }
}

# --- ASSOCIATE SUBNETS TO ROUTE TABLES (AZ-Local Flow Required) ---

resource "aws_route_table_association" "app" {
  for_each = var.app_subnet_ids

  subnet_id      = each.value
  route_table_id = aws_route_table.app[each.key].id
}

# --- OUTPUTS FOR VERIFICATION ---

output "app_route_table_ids" {
  value = { for k, rt in aws_route_table.app : k => rt.id }
}

output "app_route_subnet_associations" {
  value = {
    for k, assoc in aws_route_table_association.app :
    k => assoc.subnet_id
  }
}
