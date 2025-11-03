##################################
# 读取 YAML（批量 VPC）
##################################

locals {
  cfg_dir_abs = "${path.root}/${var.config_dir}"
  files       = fileset(local.cfg_dir_abs, "*.yaml")

  # 统一把每个 YAML 解析为 map，key = vpc name
  vpcs = {
    for f in local.files :
    yamldecode(file("${local.cfg_dir_abs}/${f}")).name
    => yamldecode(file("${local.cfg_dir_abs}/${f}"))
  }
}

##################################
# Region/AZ 元数据
##################################
data "aws_region" "current" {}
data "aws_availability_zones" "this" { state = "available" }

##################################
# mesh-ew（方式B：per_az /24）
# - 支持 az 或 az_index（二选一）
# - 先把 per_az 标准化为 {vpc_name, az, cidr}
##################################
locals {
  mesh_ew_plan = {
    for vpc_name, v in local.vpcs :
    vpc_name => (
      length(try(v.mesh_ew.per_az, [])) > 0
      ? [
        for x in v.mesh_ew.per_az : {
          vpc_name = vpc_name
          az       = try(x.az, data.aws_availability_zones.this.names[try(x.az_index, 0)])
          cidr     = x.cidr
        }
      ]
      : []
    )
  }

  # 需要关联为 VPC 附加 CIDR 的集合（去重）
  mesh_ew_cidr_pairs = distinct(flatten([
    for vpc_name, arr in local.mesh_ew_plan : [
      for e in arr : {
        key      = "${vpc_name}|${e.cidr}"
        vpc_name = vpc_name
        cidr     = e.cidr
      }
    ]
  ]))
}


##################################
# VPC
##################################
resource "aws_vpc" "this" {
  for_each = local.vpcs

  cidr_block           = try(each.value.primary_cidr, "10.0.0.0/16")
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(try(each.value.tags, {}), {
    Name   = each.key
    Region = data.aws_region.current.id
  })
}

# 先关联副 CIDR（避免 InvalidSubnet.Range）
resource "aws_vpc_ipv4_cidr_block_association" "mesh_ew" {
  for_each   = { for p in local.mesh_ew_cidr_pairs : p.key => p }
  vpc_id     = aws_vpc.this[each.value.vpc_name].id
  cidr_block = each.value.cidr
}

##################################
# 固定分配：10.0.0.0/16（2 AZ）
# - private_app: /18 + /18（等价 /17 总容量）
# - private_data: /20 + /20
# - public: /22 + /22
# YAML 若显式给出 subnets.* 则优先用 YAML
##################################
locals {
  # 默认计划（按两 AZ）
  _defaults_two_az = {
    public       = ["10.0.160.0/22", "10.0.164.0/22"]
    private_app  = ["10.0.0.0/18", "10.0.64.0/18"]
    private_data = ["10.0.128.0/20", "10.0.144.0/20"]
  }

  # 生成每个 VPC 的最终子网计划：YAML 优先，否则用固定默认
  vpc_subnet_plan = {
    for vpc_name, v in local.vpcs :
    vpc_name => {
      public       = coalesce(try(v.subnets.public, null), local._defaults_two_az.public)
      private_app  = coalesce(try(v.subnets.private_app, null), local._defaults_two_az.private_app)
      private_data = coalesce(try(v.subnets.private_data, null), local._defaults_two_az.private_data)
    }
  }

  # 保障 AZ 与数组长度一致（两 AZ 场景）
  _validate = {
    for vpc_name, v in local.vpcs :
    vpc_name => length(v.az_names) == 2 ? true : false
  }
}

# 如果不是两 AZ，直接在 plan 阶段报错（避免静默错配）
resource "null_resource" "assert_two_az" {
  for_each = local.vpcs
  triggers = {
    ok = local._validate[each.key] ? "true" : "false"
  }

  lifecycle {
    precondition {
      condition     = length(try(local.vpc_subnet_plan[each.key].public, [])) == length(local.vpcs[each.key].az_names)
      error_message = "VPC ${each.key} 的 subnets.public 数量必须等于 az_names 数量。"
    }
    precondition {
      condition     = length(try(local.vpc_subnet_plan[each.key].private_app, [])) == length(local.vpcs[each.key].az_names)
      error_message = "VPC ${each.key} 的 subnets.private_app 数量必须等于 az_names 数量（我们按两块 /18）。"
    }
    precondition {
      condition     = length(try(local.vpc_subnet_plan[each.key].private_data, [])) == length(local.vpcs[each.key].az_names)
      error_message = "VPC ${each.key} 的 subnets.private_data 数量必须等于 az_names 数量。"
    }
  }

}

# 展开为具体子网条目（YAML 显式 > 默认）
locals {
  public_subnets = flatten([
    for vpc_name, v in local.vpcs : [
      for idx, az in v.az_names : {
        key      = "${vpc_name}|public|${az}"
        vpc_name = vpc_name
        az       = az
        cidr     = local.vpc_subnet_plan[vpc_name].public[idx]
      }
    ]
  ])

  private_app_subnets = flatten([
    for vpc_name, v in local.vpcs : [
      for idx, az in v.az_names : {
        key      = "${vpc_name}|private-app|${az}"
        vpc_name = vpc_name
        az       = az
        cidr     = local.vpc_subnet_plan[vpc_name].private_app[idx]
      }
    ]
  ])

  private_data_subnets = flatten([
    for vpc_name, v in local.vpcs : [
      for idx, az in v.az_names : {
        key      = "${vpc_name}|private-data|${az}"
        vpc_name = vpc_name
        az       = az
        cidr     = local.vpc_subnet_plan[vpc_name].private_data[idx]
      }
    ]
  ])

  # mesh-ew 子网
  mesh_ew_subnets = flatten([
    for vpc_name, arr in local.mesh_ew_plan : [
      for e in arr : {
        key      = "${vpc_name}|mesh-ew|${e.az}"
        vpc_name = vpc_name
        az       = e.az
        cidr     = e.cidr
      }
    ]
  ])
}

#############
# Subnets
#############
resource "aws_subnet" "public" {
  for_each                = { for s in local.public_subnets : s.key => s if s.cidr != null }
  vpc_id                  = aws_vpc.this[each.value.vpc_name].id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true
  tags                    = { Name = "${each.value.vpc_name}-public-${each.value.az}", Tier = "public" }
}

resource "aws_subnet" "private_app" {
  for_each          = { for s in local.private_app_subnets : s.key => s if s.cidr != null }
  vpc_id            = aws_vpc.this[each.value.vpc_name].id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  tags              = { Name = "${each.value.vpc_name}-private-app-${each.value.az}", Tier = "private-app", Role = "eks" }
}

resource "aws_subnet" "private_data" {
  for_each          = { for s in local.private_data_subnets : s.key => s if s.cidr != null }
  vpc_id            = aws_vpc.this[each.value.vpc_name].id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  tags              = { Name = "${each.value.vpc_name}-private-data-${each.value.az}", Tier = "private-data" }
}

resource "aws_subnet" "mesh_ew" {
  for_each          = { for s in local.mesh_ew_subnets : s.key => s }
  vpc_id            = aws_vpc.this[each.value.vpc_name].id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az
  tags              = { Name = "${each.value.vpc_name}-mesh-ew-${each.value.az}", Tier = "mesh-ew" }

  depends_on = [aws_vpc_ipv4_cidr_block_association.mesh_ew]
}

#####################
# IGW / EIP / NATGW
#####################
resource "aws_internet_gateway" "igw" {
  for_each = local.vpcs
  vpc_id   = aws_vpc.this[each.key].id
  tags     = { Name = "${each.key}-igw" }
}

locals {
  nat_plan = {
    for vpc_name, v in local.vpcs :
    vpc_name => {
      single     = try(v.single_nat_gateway, true)
      azs        = v.az_names
      primary_az = v.az_names[0]
    }
  }

  nat_targets = flatten([
    for vpc_name, np in local.nat_plan :
    (np.single
      ? [{ vpc_name = vpc_name, az = np.primary_az }]
      : [for az in np.azs : { vpc_name = vpc_name, az = az }]
    )
  ])
}

resource "aws_eip" "nat" {
  for_each = { for t in local.nat_targets : "${t.vpc_name}|${t.az}" => t }
  domain   = "vpc"
  tags     = { Name = "eip-nat-${each.value.vpc_name}-${each.value.az}" }
}

# 找到同 AZ 的 public 子网
locals {
  nat_public_subnet_id = {
    for k, t in aws_eip.nat :
    k => one([
      for sk, s in aws_subnet.public :
      s.id if(s.vpc_id == aws_vpc.this[split("|", k)[0]].id && s.availability_zone == split("|", k)[1])
    ])
  }
}

resource "aws_nat_gateway" "ngw" {
  for_each      = aws_eip.nat
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = local.nat_public_subnet_id[each.key]
  tags          = { Name = "nat-${each.key}" }
  depends_on    = [aws_internet_gateway.igw]
}

###############################
# Route Tables: public / private / mesh-ew
###############################
# Public RT
resource "aws_route_table" "rt_public" {
  for_each = local.vpcs
  vpc_id   = aws_vpc.this[each.key].id
  tags     = { Name = "${each.key}-rt-public" }
}

resource "aws_route" "rt_public_igw" {
  for_each               = local.vpcs
  route_table_id         = aws_route_table.rt_public[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw[each.key].id
}

resource "aws_route_table_association" "assoc_public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.rt_public[split("|", each.key)[0]].id
}

# Private-app RT
resource "aws_route_table" "rt_private_app" {
  for_each = local.vpcs
  vpc_id   = aws_vpc.this[each.key].id
  tags     = { Name = "${each.key}-rt-private-app" }
}

# Private-data RT
resource "aws_route_table" "rt_private_data" {
  for_each = local.vpcs
  vpc_id   = aws_vpc.this[each.key].id
  tags     = { Name = "${each.key}-rt-private-data" }
}

# 默认路由去重：每个 VPC 只在“首个 AZ”创建一次 0/0 → NAT
locals {
  first_az_by_vpc = { for vpc_name, v in local.vpcs : vpc_name => v.az_names[0] }
}

resource "aws_route" "rt_private_app_nat" {
  for_each               = local.first_az_by_vpc
  route_table_id         = aws_route_table.rt_private_app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.ngw["${each.key}|${each.value}"].id
}

resource "aws_route" "rt_private_data_nat" {
  for_each               = local.first_az_by_vpc
  route_table_id         = aws_route_table.rt_private_data[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.ngw["${each.key}|${each.value}"].id
}

resource "aws_route_table_association" "assoc_private_app" {
  for_each       = aws_subnet.private_app
  subnet_id      = each.value.id
  route_table_id = aws_route_table.rt_private_app[split("|", each.key)[0]].id
}

resource "aws_route_table_association" "assoc_private_data" {
  for_each       = aws_subnet.private_data
  subnet_id      = each.value.id
  route_table_id = aws_route_table.rt_private_data[split("|", each.key)[0]].id
}

# mesh-ew：每个 mesh 子网独立 RT（方便叠加跨区路由）
resource "aws_route_table" "rt_mesh_ew" {
  for_each = aws_subnet.mesh_ew
  vpc_id   = each.value.vpc_id
  tags     = { Name = "${split("|", each.key)[0]}-rt-mesh-ew-${each.value.availability_zone}" }
}

resource "aws_route" "rt_mesh_ew_nat" {
  for_each               = aws_subnet.mesh_ew
  route_table_id         = aws_route_table.rt_mesh_ew[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = try(
    aws_nat_gateway.ngw["${split("|", each.key)[0]}|${each.value.availability_zone}"].id,
    aws_nat_gateway.ngw["${split("|", each.key)[0]}|${local.first_az_by_vpc[split("|", each.key)[0]]}"].id
  )
}

# 对端 mesh 段 -> TGW（复制到每张 mesh-ew RT）
locals {
  mesh_peer_routes = flatten([
    for vpc_name, v in local.vpcs : [
      for cidr in try(v.mesh_peer_cidrs, []) : {
        vpc_name = vpc_name
        cidr     = cidr
      }
    ]
  ])

  mesh_ew_rt_entries_list = flatten([
    for rt_key, rt in aws_route_table.rt_mesh_ew : [
      for r in local.mesh_peer_routes : {
        key      = "${rt_key}|${r.cidr}"
        rt_key   = rt_key
        vpc_name = split("|", rt_key)[0]
        cidr     = r.cidr
      } if startswith(rt_key, "${r.vpc_name}|")
    ]
  ])

  mesh_ew_rt_entries = { for e in local.mesh_ew_rt_entries_list : e.key => e }
}

resource "aws_route" "rt_mesh_ew_to_tgw" {
  for_each               = local.mesh_ew_rt_entries
  route_table_id         = aws_route_table.rt_mesh_ew[each.value.rt_key].id
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = var.tgw_id
}

############################################
# VPC -> TGW Attachment（按 VPC 一条；使用全部 mesh-ew 子网）
############################################
locals {
  mesh_ew_subnet_ids_by_vpc = {
    for vpc_name, _ in local.vpcs :
    vpc_name => [
      for k, s in aws_subnet.mesh_ew :
      s.id if s.vpc_id == aws_vpc.this[vpc_name].id
    ]
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = local.vpcs

  vpc_id             = aws_vpc.this[each.key].id
  transit_gateway_id = var.tgw_id
  subnet_ids         = local.mesh_ew_subnet_ids_by_vpc[each.key]

  dns_support            = "enable"
  ipv6_support           = "disable"
  appliance_mode_support = "disable"

  tags = merge(try(each.value.tags, {}), {
    Name  = "${each.key}-tgw-attachment"
    Scope = "mesh-ew"
  })

  lifecycle { ignore_changes = [subnet_ids] }
}
