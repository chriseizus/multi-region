# 读取每个 region 的 YAML 目录
locals {
  region_cfg = {
    for region, dir in var.config_dirs_by_region :
    region => {
      dir   = dir
      files = fileset("${path.root}/${dir}", "*.yaml")
    }
  }

  # region -> vpc map
  region_vpcs = {
    for region, cfg in local.region_cfg :
    region => {
      for f in cfg.files :
      yamldecode(file("${path.root}/${cfg.dir}/${f}")).name
      => yamldecode(file("${path.root}/${cfg.dir}/${f}"))
    }
  }

  # region -> distinct(mesh /24)
  region_mesh_cidrs = {
    for region, vpcs in local.region_vpcs :
    region => distinct(flatten([
      for vpc_name, v in vpcs :
      [for x in try(v.mesh_ew.per_az, []) : x.cidr]
    ]))
  }

  # 需要写入 Core 的条目（仅对提供了 peering attachment 的 region 生效）
  entries = {
    for e in flatten([
      for region, cidrs in local.region_mesh_cidrs :
      (contains(keys(var.peering_attachments_by_region), region)
        ? [for cidr in cidrs : {
          key           = "${region}|${cidr}"
          region        = region
          cidr          = cidr
          attachment_id = var.peering_attachments_by_region[region]
        }]
        : []
      )
    ]) : e.key => e
  }
}

# 静态路由：该 region 的每个 mesh /24 -> Core 侧 peering attachment（通往该 region 的 TGW）
resource "aws_ec2_transit_gateway_route" "mesh_to_regions" {
  for_each = local.entries

  destination_cidr_block         = each.value.cidr
  transit_gateway_attachment_id  = each.value.attachment_id
  transit_gateway_route_table_id = var.tgw_route_table_id
  blackhole                      = false
}

# 可选：把 peering attachments 关联到 Core RT
resource "aws_ec2_transit_gateway_route_table_association" "assoc_peering" {
  for_each = var.associate_peerings ? var.peering_attachments_by_region : {}

  transit_gateway_attachment_id  = each.value
  transit_gateway_route_table_id = var.tgw_route_table_id
}
