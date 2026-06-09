variable "project_name" { type = string  default = "telescope" }
variable "environment"  { type = string  default = "dev" }
variable "aws_region"   { type = string  default = "ap-south-1" }
variable "alert_email"  { type = string  description = "Email for billing alerts" }
variable "db_password"  {
  type        = string
  sensitive   = true
  description = "RDS PostgreSQL master password"
}
