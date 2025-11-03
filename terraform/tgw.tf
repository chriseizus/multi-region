############################
# variables
############################
variable "use1_region" {
  type    = string
  default = "us-east-1"
}
variable "usw2_region" {
  type    = string
  default = "us-west-2"
}
variable "use1_asn" {
  type    = number
  default = 64513
}
variable "usw2_asn" {
  type    = number
  default = 64514
}
variable "tags" {
  type    = map(string)
  default = { Environment = "prod" }
}

############################
# TGW in us-east-1
############################
resource "aws_ec2_transit_gateway" "use1" {
  provider                        = aws.use1
  description                     = "Regional TGW (us-east-1)"
  amazon_side_asn                 = var.use1_asn
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  tags                            = merge(var.tags, { Name = "use1-tgw", Role = "regional", Region = var.use1_region })
}

############################
# TGW in us-west-2
############################
resource "aws_ec2_transit_gateway" "usw2" {
  provider                        = aws.usw2
  description                     = "Regional TGW (us-west-2)"
  amazon_side_asn                 = var.usw2_asn
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  tags                            = merge(var.tags, { Name = "usw2-tgw", Role = "regional", Region = var.usw2_region })
}

############################
# Peering: use1 -> usw2
############################
resource "aws_ec2_transit_gateway_peering_attachment" "use1_to_usw2" {
  provider                = aws.use1
  transit_gateway_id      = aws_ec2_transit_gateway.use1.id
  peer_transit_gateway_id = aws_ec2_transit_gateway.usw2.id
  peer_region             = var.usw2_region
  tags                    = merge(var.tags, { Name = "use1-to-usw2" })
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "usw2_accept" {
  provider                      = aws.usw2
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.use1_to_usw2.id
  depends_on                    = [aws_ec2_transit_gateway_peering_attachment.use1_to_usw2]
  tags                          = merge(var.tags, { Name = "usw2-accept-use1" })
}

############################
# Outputs
############################
# TGW IDs
output "tgw_id_use1" { value = aws_ec2_transit_gateway.use1.id }
output "tgw_id_usw2" { value = aws_ec2_transit_gateway.usw2.id }

# 默认关联路由表（默认 RT）ID——供路由模块直接引用
output "tgw_default_rt_id_use1" { value = aws_ec2_transit_gateway.use1.association_default_route_table_id }
output "tgw_default_rt_id_usw2" { value = aws_ec2_transit_gateway.usw2.association_default_route_table_id }

# Peering IDs
output "peering_id_use1_to_usw2" { value = aws_ec2_transit_gateway_peering_attachment.use1_to_usw2.id }
output "peering_accepter_id_usw2" { value = aws_ec2_transit_gateway_peering_attachment_accepter.usw2_accept.id }
