##################################
# Useful Outputs After Deployment
##################################

output "ecs_cluster_id" {
  description = "The ID of the ECS Fargate cluster"
  value       = aws_ecs_cluster.karuna_cluster.id
}

output "ecs_service_name" {
  description = "The name of the ECS service running Strapi"
  value       = aws_ecs_service.karuna_service.name
}

output "rds_endpoint" {
  description = "The endpoint (hostname) of the PostgreSQL RDS instance"
  value       = aws_db_instance.karuna_postgres.address
}

output "rds_port" {
  description = "The port number for the RDS PostgreSQL database"
  value       = aws_db_instance.karuna_postgres.port
}

output "public_subnet_ids" {
  description = "The IDs of the public subnets for ECS"
  value = [
    aws_subnet.karuna_public_subnet_1.id,
    aws_subnet.karuna_public_subnet_2.id,
  ]
}

output "private_subnet_ids" {
  description = "The IDs of the private subnets for RDS"
  value = [
    aws_subnet.karuna_private_subnet_1.id,
    aws_subnet.karuna_private_subnet_2.id,
  ]
}

output "nat_gateway_id" {
  description = "The NAT Gateway ID"
  value       = aws_nat_gateway.karuna_nat.id
}
