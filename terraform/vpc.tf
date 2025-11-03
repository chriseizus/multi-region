module "vpcs_use1" {
  source    = "./modules/vpc"
  providers = { aws = aws.use1 }

  tgw_id     = aws_ec2_transit_gateway.use1.id
  config_dir = "vpc-use1"
}

module "vpcs_usw2" {
  source    = "./modules/vpc"
  providers = { aws = aws.usw2 }

  tgw_id     = aws_ec2_transit_gateway.usw2.id
  config_dir = "vpc-usw2"
}