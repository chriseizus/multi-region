locals {
  vpc_dirs = { for name, _ in var.vpcs : name => "${var.out_dir}/${name}" }
}

# NodeClass (app) —— app 通常不绑 SG，明确传空数组
resource "local_file" "nodeclass_app" {
  for_each = var.vpcs
  filename = "${local.vpc_dirs[each.key]}/nodeclass-${each.key}-app.yaml"
  content = templatefile("${path.module}/templates/nodeclass.yaml.tmpl", {
    name                = "${each.key}-app"
    subnet_ids          = each.value.private_app_subnet_ids
    include_pod_subnets = false
    pod_subnet_ids      = []
    sg_ids              = [] # ✅ 新增：即使不用也要传，模板才不会找不到
  })
}

# NodeClass (mesh) —— 这里把每个 VPC 对应的 SG ID 传给模板
resource "local_file" "nodeclass_mesh" {
  for_each = var.vpcs
  filename = "${local.vpc_dirs[each.key]}/nodeclass-${each.key}-mesh.yaml"
  content = templatefile("${path.module}/templates/nodeclass.yaml.tmpl", {
    name                = "${each.key}-mesh"
    subnet_ids          = each.value.mesh_ew_subnet_ids
    include_pod_subnets = false
    pod_subnet_ids      = []
    # ✅ 新增：存在则传 [sg-id]，不存在则传 []
    sg_ids = contains(keys(var.mesh_sg_ids), each.key) ? [var.mesh_sg_ids[each.key]] : []
  })
}

# NodePool (app)
resource "local_file" "nodepool_app" {
  for_each = var.vpcs
  filename = "${local.vpc_dirs[each.key]}/nodepool-${each.key}-app.yaml"
  content = templatefile("${path.module}/templates/nodepool.yaml.tmpl", {
    name             = "${each.key}-app"
    nodeclass_ref    = "${each.key}-app"
    pool_label_key   = "pool"
    pool_label_value = "app"
    add_taint        = false
    taint_key        = ""
    taint_value      = ""
    taint_effect     = ""
  })
}

# NodePool (mesh)
resource "local_file" "nodepool_mesh" {
  for_each = var.vpcs
  filename = "${local.vpc_dirs[each.key]}/nodepool-${each.key}-mesh.yaml"
  content = templatefile("${path.module}/templates/nodepool.yaml.tmpl", {
    name             = "${each.key}-mesh"
    nodeclass_ref    = "${each.key}-mesh"
    pool_label_key   = "pool"
    pool_label_value = "mesh"
    add_taint        = true
    taint_key        = "mesh"
    taint_value      = "true"
    taint_effect     = "NoSchedule"
  })
}

output "rendered_dirs" {
  value = local.vpc_dirs
}
