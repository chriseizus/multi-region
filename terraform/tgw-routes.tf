############################################
# A) use1 TGW：本地 + 指向远端
############################################

# 1) use1 本地 mesh → 本区 VPC attachments
module "use1_local_mesh" {
  source    = "./modules/tgw-routes-regional"
  providers = { aws = aws.use1 }

  tgw_route_table_id  = aws_ec2_transit_gateway.use1.association_default_route_table_id
  config_dir          = "vpc-use1" # 与 use1 的 VPC 模块一致
  tgw_vpc_attachments = module.vpcs_use1.tgw_vpc_attachment_ids

  associate_attachments = true
  enable_propagation    = false

  depends_on = [module.vpcs_use1]
}

# 2) use1 指向“远端（usw2）”的 mesh → peering
module "use1_to_usw2_peer_mesh" {
  # 复用“core”模块作为“对端聚合”模块
  source    = "./modules/tgw-routes-core"
  providers = { aws = aws.use1 }

  tgw_route_table_id = aws_ec2_transit_gateway.use1.association_default_route_table_id

  # 仅传一个对端 region 的目录
  config_dirs_by_region = {
    (var.usw2_region) = "vpc-usw2"
  }

  # use1 → usw2 的 peering attachment（use1侧）
  peering_attachments_by_region = {
    (var.usw2_region) = aws_ec2_transit_gateway_peering_attachment.use1_to_usw2.id
  }

  associate_peerings = false
  depends_on         = [aws_ec2_transit_gateway_peering_attachment_accepter.usw2_accept]
}

############################################
# B) usw2 TGW：本地 + 指向远端
############################################

# 1) usw2 本地 mesh → 本区 VPC attachments
module "usw2_local_mesh" {
  source    = "./modules/tgw-routes-regional"
  providers = { aws = aws.usw2 }

  tgw_route_table_id  = aws_ec2_transit_gateway.usw2.association_default_route_table_id
  config_dir          = "vpc-usw2"
  tgw_vpc_attachments = module.vpcs_usw2.tgw_vpc_attachment_ids

  associate_attachments = true
  enable_propagation    = false

  depends_on = [module.vpcs_usw2]
}

# 2) usw2 指向“远端（use1）”的 mesh → peering
module "usw2_to_use1_peer_mesh" {
  source    = "./modules/tgw-routes-core"
  providers = { aws = aws.usw2 }

  tgw_route_table_id = aws_ec2_transit_gateway.usw2.association_default_route_table_id

  config_dirs_by_region = {
    (var.use1_region) = "vpc-use1"
  }

  # 这里要用“usw2 侧”对同一条 peering 的 attachment
  # 注意：对于一条 peering，双方各有一个 attachment ID。上面用的是 use1 侧，
  # 这里必须用 usw2 侧的那个（即 accepter 资源暴露的 ID）。
  peering_attachments_by_region = {
    (var.use1_region) = aws_ec2_transit_gateway_peering_attachment_accepter.usw2_accept.id
  }

  associate_peerings = false
  depends_on         = [aws_ec2_transit_gateway_peering_attachment_accepter.usw2_accept]
}
