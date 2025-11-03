output "eks" {
  description = "每个 VPC 的 EKS 关键信息"
  value = {
    for k, m in module.eks_auto_per_vpc :
    k => {
      cluster_name  = m.cluster_name
      cluster_arn   = m.cluster_arn
      endpoint      = m.cluster_endpoint
      oidc_provider = m.oidc_provider
      cluster_sg_id = m.cluster_security_group_id
    }
  }
}

output "mesh_sg_ids" {
  value = { for k, sg in aws_security_group.mesh_ew : k => sg.id }
}
