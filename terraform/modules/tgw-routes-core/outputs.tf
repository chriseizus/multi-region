output "programmed_routes" {
  value = {
    for k, r in aws_ec2_transit_gateway_route.mesh_to_regions :
    k => {
      cidr           = r.destination_cidr_block
      attachment_id  = r.transit_gateway_attachment_id
      route_table_id = r.transit_gateway_route_table_id
    }
  }
}
