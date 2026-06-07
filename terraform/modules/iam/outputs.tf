output "eks_cluster_role_arn"           { value = aws_iam_role.eks_cluster.arn }
output "fargate_pod_execution_role_arn" { value = aws_iam_role.fargate_pod_execution.arn }
output "alb_controller_role_arn"        { value = aws_iam_role.alb_controller.arn }
output "billing_sns_topic_arn"          { value = aws_sns_topic.billing_alert.arn }
