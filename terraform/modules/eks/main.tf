resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-${var.environment}-eks"
  role_arn = var.eks_cluster_role_arn
  version  = "1.28"

  vpc_config {
    subnet_ids              = concat(var.public_subnet_ids, var.private_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  enabled_cluster_log_types = []

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks"
    Project     = var.project_name
    Environment = var.environment
  }

  depends_on = [var.eks_cluster_role_arn]
}

resource "aws_eks_fargate_profile" "telescope" {
  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = "telescope-services"
  pod_execution_role_arn = var.fargate_pod_execution_role_arn
  subnet_ids             = var.private_subnet_ids
  selector { namespace = "telescope" }
  tags = { Name = "telescope-fargate-profile" }
}

resource "aws_eks_fargate_profile" "monitoring" {
  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = "monitoring-services"
  pod_execution_role_arn = var.fargate_pod_execution_role_arn
  subnet_ids             = var.private_subnet_ids
  selector { namespace = "monitoring" }
  tags = { Name = "monitoring-fargate-profile" }
}

resource "aws_eks_fargate_profile" "kube_system" {
  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = "kube-system"
  pod_execution_role_arn = var.fargate_pod_execution_role_arn
  subnet_ids             = var.private_subnet_ids
  selector { namespace = "kube-system" }
}

# OIDC provider for IRSA
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
