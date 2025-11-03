variable "config_dir" {
  description = "Relative directory containing YAML files for this region (e.g., vpc-use1)"
  type        = string
}

variable "tgw_id" {
  description = "Transit Gateway ID for this region"
  type        = string
}

