locals {
  cfg_dir_abs = "${path.root}/${var.config_dir}"
  files       = fileset(local.cfg_dir_abs, "*.yaml")

  vpcs = {
    for f in local.files :
    yamldecode(file("${local.cfg_dir_abs}/${f}")).name
    => yamldecode(file("${local.cfg_dir_abs}/${f}"))
  }

  # vpc -> distinct(mesh /24)
  mesh_ew_per_vpc = {
    for vpc_name, v in local.vpcs :
    vpc_name => distinct([for x in try(v.mesh_ew.per_az, []) : x.cidr])
  }

  # ⚠️ for_each 键只基于 YAML（plan 可知），不依赖 attachment
  # key = "vpc|cidr"
  route_keys = flatten([
    for vpc_name, cidrs in local.mesh_ew_per_vpc :
    [for cidr in cidrs : "${vpc_name}|${cidr}"]
  ])

  # 展开为 map，值里包含 vpc_name/cidr；attachment 在资源里再 lookup
  routes_map = {
    for k in local.route_keys :
    k => {
      vpc_name = split("|", k)[0]
      cidr     = split("|", k)[1]
    }
  }
}

# 静态路由：mesh /24 -> 该 VPC 的 TGW Attachment
resource "aws_ec2_transit_gateway_route" "mesh" {
  for_each = local.routes_map

  destination_cidr_block         = each.value.cidr
  transit_gateway_route_table_id = var.tgw_route_table_id

  # attachment id 可能在 plan 阶段 unknown（同一次 apply 创建），这里允许 unknown
  transit_gateway_attachment_id = lookup(var.tgw_vpc_attachments, each.value.vpc_name, null)

  # 运行时做显式校验：保证 map 里真有该 vpc 的 attachment
  lifecycle {
    precondition {
      condition     = lookup(var.tgw_vpc_attachments, each.value.vpc_name, null) != null
      error_message = "Missing TGW VPC attachment for VPC '${each.value.vpc_name}'. Ensure VPC module outputs include this VPC, or apply VPC stack first."
    }
  }
}

# # 可选：把 attachments 关联到此 RT（这里 keys 就来自传入 map，通常是 plan 可知；如果同 apply 创建也 OK）
# resource "aws_ec2_transit_gateway_route_table_association" "assoc" {
#   for_each                       = var.associate_attachments ? var.tgw_vpc_attachments : {}
#   transit_gateway_attachment_id  = each.value
#   transit_gateway_route_table_id = var.tgw_route_table_id
# }

# resource "aws_ec2_transit_gateway_route_table_propagation" "prop" {
#   for_each                       = var.enable_propagation ? var.tgw_vpc_attachments : {}
#   transit_gateway_attachment_id  = each.value
#   transit_gateway_route_table_id = var.tgw_route_table_id
# }
