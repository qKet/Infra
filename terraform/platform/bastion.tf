module "bastion" {
  source = "../modules/bastion"

  project_name          = var.project_name
  vpc_id                = module.network.vpc_id
  subnet_id             = module.network.private_general_subnet_ids[0]
  bastion_instance_type = var.bastion_instance_type
}
