############################################
# 1) 创建 EKS 集群（只启用 Auto Mode，不建内置池）
############################################
module "eks_auto_use1" {
  source    = "./modules/eks-auto"
  providers = { aws = aws.use1 }

  # 👇 来自你的 VPC 模块输出
  vpcs = module.vpcs_use1.vpcs

  # （可选）端点可见性按 VPC 覆盖
  # endpoint_public_map  = { "vpc-a" = false }
  # endpoint_private_map = { "vpc-a" = true  }

  # 这个变量在 modules/eks-auto/variables.tf 里要声明（见下文）
  tags = { Environment = "shared", Region = "us-east-1" }
}

############################################
# 2) 生成 NodeClass / NodePool 的 YAML
############################################
module "eks_autopools_yaml_use1" {
  source = "./modules/eks-autopools-yaml"

  # 👇 同样来自 VPC 输出
  vpcs = module.vpcs_use1.vpcs

  # 👇 从上面创建好的集群里取名字，做个映射（供记录/输出）
  cluster_names = {
    for k, v in module.eks_auto_use1.eks : k => v.cluster_name
  }
  mesh_sg_ids = module.eks_auto_use1.mesh_sg_ids

  # 👇 在调用处传“输出目录”（用 path.module 拼绝对路径）
  out_dir = "${path.module}/rendered/eks-autopools"
}
