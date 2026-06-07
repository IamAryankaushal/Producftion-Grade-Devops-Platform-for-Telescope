variable "project_name"                   { type = string }
variable "environment"                    { type = string }
variable "eks_cluster_role_arn"           { type = string }
variable "fargate_pod_execution_role_arn" { type = string }
variable "public_subnet_ids"              { type = list(string) }
variable "private_subnet_ids"             { type = list(string) }
variable "vpc_id"                         { type = string }
