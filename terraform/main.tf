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
# Default VPC & AZs
##############################################
data "aws_vpc" "default" {
  default = true
}

data "aws_availability_zones" "available" {}

##############################################
# CloudWatch Log Group
##############################################
resource "aws_cloudwatch_log_group" "karuna_strapi" {
  name              = "/ecs/karuna-strapi"
  retention_in_days = 7
}

##############################################
# Public Subnets
##############################################
resource "aws_subnet" "karuna_public_subnet_1" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = "172.31.128.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
}

resource "aws_subnet" "karuna_public_subnet_2" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = "172.31.129.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
}

##############################################
# Security Groups
##############################################
resource "aws_security_group" "karuna_sg_public" {
  name   = "karuna-sg-public"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 1337
    to_port     = 1337
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

resource "aws_security_group" "karuna_sg_db" {
  name   = "karuna-sg-db"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.karuna_sg_public.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "karuna_sg_alb" {
  name   = "karuna-sg-alb"
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

resource "aws_security_group" "karuna_sg_ecs" {
  name   = "karuna-sg-ecs"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port       = 1337
    to_port         = 1337
    protocol        = "tcp"
    security_groups = [aws_security_group.karuna_sg_alb.id]
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
resource "aws_ecs_cluster" "karuna_cluster" {
  name = "karuna-ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

##############################################
# IAM Roles
##############################################
resource "aws_iam_role" "karuna_ecs_task_execution_role" {
  name = "karuna-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Action    = "sts:AssumeRole",
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec_attach" {
  role       = aws_iam_role.karuna_ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

##############################################
# ECS Task Definition
##############################################
resource "aws_ecs_task_definition" "karuna_task" {
  family                   = "karuna-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.karuna_ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name  = "karuna-strapi"
    image = "${var.ecr_repository_url}:latest"

    portMappings = [{
      containerPort = 1337
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/karuna-strapi"
        awslogs-region        = var.region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

##############################################
# ALB + Target Groups
##############################################
resource "aws_lb" "karuna_alb" {
  name               = "karuna-alb"
  load_balancer_type = "application"
  subnets            = [aws_subnet.karuna_public_subnet_1.id, aws_subnet.karuna_public_subnet_2.id]
  security_groups    = [aws_security_group.karuna_sg_alb.id]
}

resource "aws_lb_target_group" "karuna_tg_blue" {
  name        = "karuna-tg-blue"
  port        = 1337
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path    = "/admin"
    matcher = "200-399"
  }
}

resource "aws_lb_target_group" "karuna_tg_green" {
  name        = "karuna-tg-green"
  port        = 1337
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path    = "/admin"
    matcher = "200-399"
  }
}

resource "aws_lb_listener" "karuna_listener" {
  load_balancer_arn = aws_lb.karuna_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.karuna_tg_blue.arn
  }
}

##############################################
# ECS Service (CodeDeploy managed)
##############################################
resource "aws_ecs_service" "karuna_service" {
  name    = "karuna-service"
  cluster = aws_ecs_cluster.karuna_cluster.id

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  network_configuration {
    subnets         = [aws_subnet.karuna_public_subnet_1.id, aws_subnet.karuna_public_subnet_2.id]
    security_groups = [aws_security_group.karuna_sg_ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.karuna_tg_blue.arn
    container_name   = "karuna-strapi"
    container_port   = 1337
  }

  desired_count = 1
}

##############################################
# CodeDeploy
##############################################
resource "aws_codedeploy_app" "karuna_codedeploy_app" {
  name             = "karuna-strapi-codedeploy-app"
  compute_platform = "ECS"
}

resource "aws_iam_role" "karuna_codedeploy_role" {
  name = "karuna-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Action    = "sts:AssumeRole",
      Principal = { Service = "codedeploy.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_attach" {
  role       = aws_iam_role.karuna_codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForECS"
}

resource "aws_codedeploy_deployment_group" "karuna_codedeploy_dg" {
  app_name              = aws_codedeploy_app.karuna_codedeploy_app.name
  deployment_group_name = "karuna-strapi-deployment-group"
  service_role_arn      = aws_iam_role.karuna_codedeploy_role.arn
  deployment_config_name = "CodeDeployDefault.ECSCanary10Percent5Minutes"

  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.karuna_cluster.name
    service_name = aws_ecs_service.karuna_service.name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.karuna_listener.arn]
      }

      target_group { name = aws_lb_target_group.karuna_tg_blue.name }
      target_group { name = aws_lb_target_group.karuna_tg_green.name }
    }
  }
}

##############################################
# CloudWatch Dashboard
##############################################
resource "aws_cloudwatch_dashboard" "karuna_ecs_dashboard" {
  dashboard_name = "karuna-ecs-dashboard"

  dashboard_body = jsonencode({
    widgets = [{
      type = "metric",
      width = 24,
      height = 6,
      properties = {
        metrics = [
          ["AWS/ECS","CPUUtilization","ClusterName",aws_ecs_cluster.karuna_cluster.name,"ServiceName",aws_ecs_service.karuna_service.name],
          ["AWS/ECS","MemoryUtilization","ClusterName",aws_ecs_cluster.karuna_cluster.name,"ServiceName",aws_ecs_service.karuna_service.name]
        ],
        view = "timeSeries",
        period = 300,
        stat = "Average",
        region = var.region,
        title = "ECS CPU & Memory Utilization"
      }
    }]
  })
}
