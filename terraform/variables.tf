##################################
# AWS Region
##################################

variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "ap-south-1"
}

##################################
# ECR Repository
##################################

variable "ecr_repository_name" {
  description = "Name of the existing ECR repository to use for the Strapi image"
  type        = string
}

##################################
# RDS PostgreSQL Database
##################################

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
}

variable "db_username" {
  description = "PostgreSQL database username"
  type        = string
}

variable "db_password" {
  description = "PostgreSQL database password"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class (size) for PostgreSQL"
  type        = string
  default     = "db.t3.micro"
}

##################################
# Strapi App Environment Variables
##################################

variable "strapi_admin_jwt_secret" {
  description = "JWT secret for Strapi admin"
  type        = string
  sensitive   = true
}

variable "strapi_api_token_salt" {
  description = "API token salt for Strapi"
  type        = string
  sensitive   = true
}

variable "strapi_app_keys" {
  description = "Comma-separated app keys for Strapi"
  type        = string
  sensitive   = true
}
