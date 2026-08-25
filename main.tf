terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {}

locals {
  name   = "blog-lambda-crud"
  region = "us-east-1"

  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.0"

  name = local.name
  cidr = "10.0.0.0/16"

  azs             = local.azs
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway = false
}

resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${local.name}-vpce-"
  description = "VPC endpoint interfaces"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }
}

resource "aws_vpc_endpoint" "eks" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${local.region}.eks"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "sts" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${local.region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.25.0"

  name               = local.name
  kubernetes_version = "1.36"

  endpoint_public_access  = false
  endpoint_private_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  create_kms_key                           = false
  encryption_config                        = null
  enable_cluster_creator_admin_permissions = true
}

module "kube_crud" {
  source = "./kube_crud"

  name                      = local.name
  cluster_name              = module.eks.cluster_name
  cluster_security_group_id = module.eks.cluster_primary_security_group_id
  subnet_ids                = module.vpc.private_subnets
  vpc_id                    = module.vpc.vpc_id
  kubectl_version           = "1.36.2"
  helm_version              = "4.2.4"
}

module "invoke_demo_namespace" {
  source = "./kube_crud/modules/invoke"

  function_name = module.kube_crud.function_name
  type          = "manifest"
  name          = "demo-namespace"
  manifest = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = "demo"
      labels = {
        managed-by = "kube-crud-lambda"
      }
    }
  })
}

module "invoke_demo_configmap" {
  source = "./kube_crud/modules/invoke"

  function_name = module.kube_crud.function_name
  type          = "manifest"
  name          = "demo-configmap"
  manifest = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "demo-config"
      namespace = "demo"
    }
    data = {
      environment = "blog-demo"
      managed_by  = "kube-crud-lambda"
    }
  })

  depends_on = [module.invoke_demo_namespace]
}

module "invoke_demo_helm" {
  source = "./kube_crud/modules/invoke"

  function_name    = module.kube_crud.function_name
  type             = "helm"
  name             = "demo-helm"
  release          = "demo-helm"
  chart            = "demo"
  chart_dir        = "${path.module}/charts/demo"
  namespace        = "demo-helm"
  create_namespace = true
  values = yamlencode({
    namespace = "demo-helm"
    configMap = {
      environment = "blog-demo"
      managed_by  = "kube-crud-lambda-helm"
    }
  })

  depends_on = [module.invoke_demo_namespace]
}
