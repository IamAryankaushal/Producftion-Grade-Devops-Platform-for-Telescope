output "alb_sg_id"      { value = aws_security_group.alb.id }
output "eks_pods_sg_id" { value = aws_security_group.eks_pods.id }
