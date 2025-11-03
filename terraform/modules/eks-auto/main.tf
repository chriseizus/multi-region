module "eks_auto_per_vpc" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.8"

  for_each = var.vpcs

  name               = "${each.key}-eks"
  kubernetes_version = var.kubernetes_version

  vpc_id     = each.value.vpc_id
  subnet_ids = concat(each.value.private_app_subnet_ids, each.value.mesh_ew_subnet_ids)

  control_plane_subnet_ids = each.value.private_app_subnet_ids

  endpoint_public_access  = lookup(var.endpoint_public_map, each.key, false)
  endpoint_private_access = lookup(var.endpoint_private_map, each.key, true)

  # 关键：启用 Auto Mode + 只建 IAM（不创建内置 node pools）
  compute_config                 = { enabled = true }
  create_auto_mode_iam_resources = true

  addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
  }

  enable_cluster_creator_admin_permissions = true
  tags                                     = merge({ ManagedBy = "Terraform" }, var.tags)
}
