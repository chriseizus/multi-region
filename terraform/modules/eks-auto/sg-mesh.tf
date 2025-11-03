# Mesh 专用 SG
resource "aws_security_group" "mesh_ew" {
  for_each = var.vpcs

  name        = "${each.key}-mesh-ew"
  description = "Mesh east-west workload security group (allow 100.64.0.0/16)"
  vpc_id      = each.value.vpc_id

  # 你可以统一加 tags 来标记
  tags = merge({
    Name = "${each.key}-mesh-ew"
    Role = "mesh-ew"
  }, var.tags)
}

# ingress：允许 100.64.0.0/16 全流量
resource "aws_security_group_rule" "mesh_ingress_any" {
  for_each          = var.vpcs
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["100.64.0.0/16"]
  security_group_id = aws_security_group.mesh_ew[each.key].id
}

# egress：放通所有（默认出站全通）
resource "aws_security_group_rule" "mesh_egress_any" {
  for_each          = var.vpcs
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.mesh_ew[each.key].id
}

