# 常用输出：按 VPC 聚合
output "vpcs" {
  value = {
    for vpc_name, v in local.vpcs :
    vpc_name => {
      vpc_id                  = aws_vpc.this[vpc_name].id
      public_subnet_ids       = [for k, s in aws_subnet.public : s.id if s.vpc_id == aws_vpc.this[vpc_name].id]
      private_app_subnet_ids  = [for k, s in aws_subnet.private_app : s.id if s.vpc_id == aws_vpc.this[vpc_name].id]
      private_data_subnet_ids = [for k, s in aws_subnet.private_data : s.id if s.vpc_id == aws_vpc.this[vpc_name].id]
      mesh_ew_subnet_ids      = [for k, s in aws_subnet.mesh_ew : s.id if s.vpc_id == aws_vpc.this[vpc_name].id]
    }
  }
}

# 给 TGW 路由模块用：{ vpc_name => attachment_id }
output "tgw_vpc_attachment_ids" {
  value = {
    for vpc_name, _ in local.vpcs :
    vpc_name => aws_ec2_transit_gateway_vpc_attachment.this[vpc_name].id
  }
}
