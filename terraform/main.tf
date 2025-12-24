##############################################
# Provider & Requirements
##############################################
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

##############################################
# Default VPC & Public Subnets
##############################################
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

##############################################
# CloudWatch Log Group
##############################################
resource "aws_cloudwatch_log_group" "karuna_strapi" {
  name              = "/ecs/karuna-strapi"
  retention_in_days = 7
}

##############################################
# Security Groups
##############################################
resource "aws_security_group" "alb_sg" {
  name   = "karuna-alb-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_sg" {
  name   = "karuna-ecs-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port       = 1337
    to_port         = 1337
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  name   = "karuna-db-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

##############################################
# ECS Cluster
##############################################
resource "aws_ecs_cluster" "cluster" {
  name = "karuna-ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

##############################################
# ECR Repo
##############################################
data "aws_ecr_repository" "repo" {
  name = var.ecr_repository_name
}

##############################################
# IAM Role - ECS Task Execution
##############################################
resource "aws_iam_role" "ecs_execution_role" {
  name = "karuna-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_attach" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

##############################################
# RDS - PostgreSQL
##############################################
resource "aws_db_instance" "postgres" {
  identifier             = "karuna-postgres"
  engine                 = "postgres"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot    = true
}

##############################################
# ECS Task Definition (Placeholder)
##############################################
resource "aws_ecs_task_definition" "task" {
  family                   = "karuna-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name  = "karuna-strapi"
    image = "${data.aws_ecr_repository.repo.repository_url}:latest"

    portMappings = [{
      containerPort = 1337
    }]

    environment = [
      { name = "HOST", value = "0.0.0.0" },
      { name = "PORT", value = "1337" },

      { name = "DATABASE_CLIENT", value = "postgres" },
      { name = "DATABASE_HOST", value = aws_db_instance.postgres.address },
      { name = "DATABASE_PORT", value = "5432" },
      { name = "DATABASE_NAME", value = var.db_name },
      { name = "DATABASE_USERNAME", value = var.db_username },
      { name = "DATABASE_PASSWORD", value = var.db_password },
      { name = "DATABASE_SSL", value = "true" },
      { name = "DATABASE_SSL_REJECT_UNAUTHORIZED", value = "false" },

      { name = "APP_KEYS", value = var.strapi_app_keys },
      { name = "API_TOKEN_SALT", value = var.strapi_api_token_salt },
      { name = "ADMIN_JWT_SECRET", value = var.strapi_admin_jwt_secret },
      { name = "JWT_SECRET", value = var.strapi_admin_jwt_secret }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.karuna_strapi.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

##############################################
# ALB & Target Groups
##############################################
resource "aws_lb" "alb" {
  name               = "karuna-alb"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.public.ids
  security_groups    = [aws_security_group.alb_sg.id]
}

resource "aws_lb_target_group" "blue" {
  name        = "karuna-tg-blue"
  port        = 1337
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
   path                = "/admin"
   matcher             = "200-399"
   interval            = 30
   timeout             = 5
   healthy_threshold   = 2
   unhealthy_threshold = 2
  }

}

resource "aws_lb_target_group" "green" {
  name        = "karuna-tg-green"
  port        = 1337
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
   path                = "/admin"
   matcher             = "200-399"
   interval            = 30
   timeout             = 5
   healthy_threshold   = 2
   unhealthy_threshold = 2
  }

}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

##############################################
# ECS Service (CodeDeploy Controlled)
##############################################
resource "aws_ecs_service" "service" {
  name            = "karuna-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.task.arn
  desired_count   = 0

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  network_configuration {
    subnets         = data.aws_subnets.public.ids
    security_groups = [aws_security_group.ecs_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = "karuna-strapi"
    container_port   = 1337
  }

  lifecycle {
    ignore_changes = [
      task_definition,
      desired_count,
      load_balancer
    ]
  }
}

##############################################
# CodeDeploy
##############################################
resource "aws_iam_role" "codedeploy_role" {
  name = "karuna-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "codedeploy.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_attach" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

resource "aws_codedeploy_app" "app" {
  name             = "karuna-strapi-codedeploy-app"
  compute_platform = "ECS"
}

resource "aws_codedeploy_deployment_group" "dg" {
  app_name              = aws_codedeploy_app.app.name
  deployment_group_name = "karuna-deployment-group"
  service_role_arn      = aws_iam_role.codedeploy_role.arn

  deployment_config_name = "CodeDeployDefault.ECSCanary10Percent5Minutes"

  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.cluster.name
    service_name = aws_ecs_service.service.name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.http.arn]
      }

      target_group { name = aws_lb_target_group.blue.name }
      target_group { name = aws_lb_target_group.green.name }
    }
  }

  blue_green_deployment_config {
    terminate_blue_instances_on_deployment_success {
      action = "TERMINATE"
    }
  }
}

##############################################
# CloudWatch Dashboard
##############################################
resource "aws_cloudwatch_dashboard" "dashboard" {
  dashboard_name = "karuna-ecs-dashboard"

  dashboard_body = jsonencode({
    widgets = [{
      type   = "metric"
      width  = 24
      height = 6
      properties = {
        metrics = [
          ["AWS/ECS","CPUUtilization","ClusterName",aws_ecs_cluster.cluster.name,"ServiceName",aws_ecs_service.service.name],
          ["AWS/ECS","MemoryUtilization","ClusterName",aws_ecs_cluster.cluster.name,"ServiceName",aws_ecs_service.service.name]
        ]
        region = var.region
        stat   = "Average"
        title  = "ECS CPU & Memory"
      }
    }]
  })
}
