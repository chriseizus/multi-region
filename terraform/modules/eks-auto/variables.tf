variable "vpcs" { /* 略：map(object{ vpc_id, subnets ... }) */ }
variable "kubernetes_version" {
  type    = string
  default = "1.33"
}
variable "endpoint_public_map" {
  type    = map(bool)
  default = {}
}
variable "endpoint_private_map" {
  type    = map(bool)
  default = {}
}
variable "tags" {
  type    = map(string)
  default = {}
} # ✅确保存在
