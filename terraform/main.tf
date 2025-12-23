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
# Public Subnets (ONLY)
##############################################
resource "aws_subnet" "karuna_public_subnet_1" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = "172.31.128.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = { Name = "karuna-public-subnet-1" }
}

resource "aws_subnet" "karuna_public_subnet_2" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = "172.31.129.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags = { Name = "karuna-public-subnet-2" }
}

##############################################
# Internet Gateway
##############################################
data "aws_internet_gateway" "default" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

##############################################
# Public Routing
##############################################
resource "aws_route_table" "karuna_public_rt" {
  vpc_id = data.aws_vpc.default.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.aws_internet_gateway.default.id
  }
}

resource "aws_route_table_association" "karuna_public_rta_1" {
  subnet_id      = aws_subnet.karuna_public_subnet_1.id
  route_table_id = aws_route_table.karuna_public_rt.id
}

resource "aws_route_table_association" "karuna_public_rta_2" {
  subnet_id      = aws_subnet.karuna_public_subnet_2.id
  route_table_id = aws_route_table.karuna_public_rt.id
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
# ECS Cluster (Container Insights enabled)
##############################################
resource "aws_ecs_cluster" "karuna_cluster" {
  name = "karuna-ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

##############################################
# ECR Repo
##############################################
data "aws_ecr_repository" "karuna_repo" {
  name = var.ecr_repository_name
}

##############################################
# IAM Role
##############################################
resource "aws_iam_role" "karuna_ecs_task_execution_role" {
  name = "karuna-ecs-task-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "karuna_ecs_task_execution_role_attach" {
  role       = aws_iam_role.karuna_ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

##############################################
# RDS (PUBLIC)
##############################################
resource "aws_db_instance" "karuna_postgres" {
  identifier             = "karuna-rds-postgres"
  engine                 = "postgres"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  publicly_accessible    = true
  vpc_security_group_ids = [aws_security_group.karuna_sg_db.id]
  skip_final_snapshot    = true
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
    image = "${data.aws_ecr_repository.karuna_repo.repository_url}:latest"

    portMappings = [{ containerPort = 1337, hostPort = 1337 }]

    environment = [
      { name = "DATABASE_CLIENT", value = "postgres" },
      { name = "DATABASE_HOST", value = aws_db_instance.karuna_postgres.address },
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
        awslogs-group         = "/ecs/karuna-strapi"
        awslogs-region        = var.region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

##############################################
# ECS Service + ALB
##############################################
resource "aws_ecs_service" "karuna_service" {
  name            = "karuna-service"
  cluster         = aws_ecs_cluster.karuna_cluster.id
  task_definition = aws_ecs_task_definition.karuna_task.arn

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  network_configuration {
    subnets         = [aws_subnet.karuna_public_subnet_1.id, aws_subnet.karuna_public_subnet_2.id]
    security_groups = [aws_security_group.karuna_sg_public.id]
    assign_public_ip = false
  }

  desired_count = 1

  load_balancer {
    target_group_arn = aws_lb_target_group.karuna_tg.arn
    container_name   = "karuna-strapi"
    container_port   = 1337
  }
}

##############################################
# ALB Security Group
##############################################
resource "aws_security_group" "karuna_sg_alb" {
  name   = "karuna-sg-alb"
  vpc_id = data.aws_vpc.default.id

  ingress { from_port = 80 to_port = 80 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
  ingress { from_port = 443 to_port = 443 protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }

  egress { from_port = 0 to_port = 0 protocol = "-1" cidr_blocks = ["0.0.0.0/0"] }
}

##############################################
# Application Load Balancer
##############################################
resource "aws_lb" "karuna_alb" {
  name               = "karuna-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.karuna_public_subnet_1.id, aws_subnet.karuna_public_subnet_2.id]
  security_groups    = [aws_security_group.karuna_sg_alb.id]
}

##############################################
# Target Groups (Blue / Green)
##############################################
resource "aws_lb_target_group" "karuna_tg" {
  name = "karuna-tg"
  port = 1337
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path = "/admin"
    matcher = "200-399"
  }
}

resource "aws_lb_target_group" "karuna_tg_green" {
  name = "karuna-tg-green"
  port = 1337
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path = "/admin"
    matcher = "200-399"
  }
}

##############################################
# ALB Listener
##############################################
resource "aws_lb_listener" "karuna_listener" {
  load_balancer_arn = aws_lb.karuna_alb.arn
  port = 80
  protocol = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.karuna_tg.arn
  }
}

##############################################
# CodeDeploy Application
##############################################
resource "aws_codedeploy_app" "karuna_codedeploy_app" {
  name             = "karuna-strapi-codedeploy-app"
  compute_platform = "ECS"
}

##############################################
# IAM Role for CodeDeploy (FIXED)
##############################################
resource "aws_iam_role" "karuna_codedeploy_role" {
  name = "karuna-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "karuna_codedeploy_role_attach" {
  role       = aws_iam_role.karuna_codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForECS"
}

##############################################
# Extra permissions for CodeDeploy
##############################################
resource "aws_iam_role_policy" "karuna_codedeploy_ecs_permissions" {
  name = "karuna-codedeploy-ecs-extra"
  role = aws_iam_role.karuna_codedeploy_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:UpdateService",
          "ecs:RegisterTaskDefinition",
          "ecs:CreateTaskSet",
          "ecs:DeleteTaskSet",
          "ecs:DescribeTaskSets",
          "ecs:UpdateServicePrimaryTaskSet"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "elasticloadbalancing:*"
        ],
        Resource = "*"
      }
    ]
  })
}

##############################################
# CodeDeploy Deployment Group
##############################################
resource "aws_codedeploy_deployment_group" "karuna_codedeploy_dg" {
  app_name              = aws_codedeploy_app.karuna_codedeploy_app.name
  deployment_group_name = "karuna-strapi-deployment-group"
  service_role_arn      = aws_iam_role.karuna_codedeploy_role.arn

  deployment_config_name = "CodeDeployDefault.ECSCanary10Percent5Minutes"

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

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

      target_group { name = aws_lb_target_group.karuna_tg.name }
      target_group { name = aws_lb_target_group.karuna_tg_green.name }
    }
  }

  blue_green_deployment_config {
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }

    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
  }
}

##############################################
# CloudWatch Dashboard
##############################################
resource "aws_cloudwatch_dashboard" "karuna_ecs_dashboard" {
  dashboard_name = "karuna-ecs-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric",
        width  = 24,
        height = 6,
        properties = {
          metrics = [
            ["AWS/ECS","CPUUtilization","ClusterName",aws_ecs_cluster.karuna_cluster.name,"ServiceName",aws_ecs_service.karuna_service.name],
            ["AWS/ECS","MemoryUtilization","ClusterName",aws_ecs_cluster.karuna_cluster.name,"ServiceName",aws_ecs_service.karuna_service.name]
          ],
          view   = "timeSeries",
          stat   = "Average",
          period = 300,
          region = var.region,
          title  = "ECS CPU & Memory Utilization"
        }
      }
    ]
  })
}
