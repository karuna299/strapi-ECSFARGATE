##################################
# Useful Outputs After Deployment
##################################

output "ecs_cluster_id" {
  description = "The ID of the ECS Fargate cluster"
  value       = aws_ecs_cluster.karuna_cluster.id
}


output "rds_endpoint" {
  description = "The endpoint (hostname) of the PostgreSQL RDS instance"
  value       = aws_db_instance.karuna_postgres.address
}

output "rds_port" {
  description = "The port number for the RDS PostgreSQL database"
  value       = aws_db_instance.karuna_postgres.port
}



