##################################
# Useful Outputs After Deployment
##################################

output "ecs_cluster_id" {
  description = "The ID of the ECS Fargate cluster"
  value       = aws_ecs_cluster.karuna_cluster.id
}

output "ecs_service_name" {
  description = "The name of the ECS service running the Strapi app"
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

output "public_subnet_id" {
  description = "The ID of the public subnet for ECS Fargate tasks"
  value       = aws_subnet.karuna_public_subnet.id
}

output "private_subnet_id" {
  description = "The ID of the private subnet for the RDS database"
  value       = aws_subnet.karuna_private_subnet.id
}
