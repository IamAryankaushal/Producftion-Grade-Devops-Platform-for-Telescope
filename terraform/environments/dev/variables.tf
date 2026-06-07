variable "project_name" {
  type    = string
  default = "telescope"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "alert_email" {
  type        = string
  description = "Email address for billing alerts"
}
