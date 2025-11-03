variable "vpcs" { /* 同上 */ }
variable "cluster_names" { type = map(string) }
variable "out_dir" { type = string } # ✅ 不要默认值里的 ${path.*}
variable "mesh_sg_ids" {
  type        = map(string)
  description = "每个 VPC 的 mesh SG ID，用于 NodeClass.securityGroupSelectorTerms"
  default     = {} # ✅ 加上默认值，避免未传时报错
}
