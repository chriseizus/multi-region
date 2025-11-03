variable "tgw_route_table_id" {
  description = "Core TGW 的 Route Table ID（本模块只写这张表）"
  type        = string
}

variable "config_dirs_by_region" {
  description = <<EOT
按 Region 提供 YAML 目录映射，例如：
{
  "us-east-1" = "vpc-dev-use1",
  "us-west-2" = "vpc-dev-usw2"
}
EOT
  type        = map(string)
}

variable "peering_attachments_by_region" {
  description = <<EOT
Core 侧的 TGW Peering Attachment 映射：{ region = core_side_peering_attachment_id }
Core 要把该 region 的所有 mesh /24 指向这里
EOT
  type        = map(string)
}

# 可选：是否把 peering attachments 关联到此 Core RT
variable "associate_peerings" {
  type    = bool
  default = false
}
