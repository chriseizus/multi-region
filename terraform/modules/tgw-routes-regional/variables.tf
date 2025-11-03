variable "tgw_route_table_id" {
  description = "Regional TGW 的 Route Table ID（本模块只写这张表）"
  type        = string
}

variable "config_dir" {
  description = "相对调用目录的 VPC YAML 目录（与 VPC 模块一致）"
  type        = string
  default     = "vpc"
}

variable "tgw_vpc_attachments" {
  description = "映射 { vpc_name = tgw_vpc_attachment_id }，仅对存在映射的 VPC 写路由"
  type        = map(string)
}

variable "associate_attachments" {
  description = "是否把以上 attachments 关联到该 RT（一个 attachment 只能关联一张 RT）"
  type        = bool
  default     = false
}

variable "enable_propagation" {
  description = "是否开启 VPC attachment → 此 RT 的路由传播（一般不需要；我们写静态路由即可）"
  type        = bool
  default     = false
}
