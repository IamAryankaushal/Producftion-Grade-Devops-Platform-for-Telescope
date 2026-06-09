terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "telescope-tfstate-808683200925"
    key            = "telescope/dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "telescope-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "telescope-devops"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = {
      Project     = "telescope-devops"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

module "vpc" {
  source       = "../../modules/vpc"
  project_name = var.project_name
  environment  = var.environment
}

module "security_groups" {
  source       = "../../modules/security-groups"
  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr
}

module "iam" {
  source        = "../../modules/iam"
  project_name  = var.project_name
  environment   = var.environment
  account_id    = data.aws_caller_identity.current.account_id
  oidc_provider = module.eks.oidc_provider
  alert_email   = var.alert_email

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

module "eks" {
  source                         = "../../modules/eks"
  project_name                   = var.project_name
  environment                    = var.environment
  eks_cluster_role_arn           = module.iam.eks_cluster_role_arn
  fargate_pod_execution_role_arn = module.iam.fargate_pod_execution_role_arn
  vpc_id                         = module.vpc.vpc_id
  public_subnet_ids              = module.vpc.public_subnet_ids
  private_subnet_ids             = module.vpc.private_subnet_ids

  depends_on = [module.iam]
}

module "ecr" {
  source       = "../../modules/ecr"
  project_name = var.project_name
  environment  = var.environment
}

module "rds" {
  source             = "../../modules/rds"
  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = module.vpc.vpc_cidr
  private_subnet_ids = module.vpc.private_subnet_ids
  db_password        = var.db_password
}

# ============================================================================
# REFERENCE ONLY — Route 53 + ACM
# Uncomment to activate. Requires a registered domain.
# ============================================================================
# module "route53" {
#   source       = "../../modules/route53"
#   project_name = var.project_name
#   environment  = var.environment
#   domain_name  = "telescope.yourdomain.com"
#   alb_dns_name = "<value from: kubectl get ingress -n telescope>"
#   alb_zone_id  = "ZP97RAFLXTNZK"  # ap-south-1 ALB zone ID
# }
