module "eks" {
  source = "../modules/eks"

  project_name = var.project_name
  eks_version  = var.eks_version

  cluster_subnet_ids = concat(module.network.public_subnet_ids, module.network.private_general_subnet_ids)
  node_subnet_ids    = module.network.private_general_subnet_ids

  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
}
