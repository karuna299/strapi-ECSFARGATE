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
# Public Subnets (2 AZs)
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
# Private Subnets (2 AZs) for RDS
##############################################
resource "aws_subnet" "karuna_private_subnet_1" {
  vpc_id            = data.aws_vpc.default.id
  cidr_block        = "172.31.200.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = { Name = "karuna-private-subnet-1" }
}

resource "aws_subnet" "karuna_private_subnet_2" {
  vpc_id            = data.aws_vpc.default.id
  cidr_block        = "172.31.201.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags = { Name = "karuna-private-subnet-2" }
}

##############################################
# Default Internet Gateway
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
# NAT + Private Routing
##############################################
resource "aws_eip" "karuna_nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "karuna_nat" {
  subnet_id     = aws_subnet.karuna_public_subnet_1.id
  allocation_id = aws_eip.karuna_nat_eip.id
  tags = { Name = "karuna-nat-gateway" }
}

resource "aws_route_table" "karuna_private_rt" {
  vpc_id = data.aws_vpc.default.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.karuna_nat.id
  }
}

resource "aws_route_table_association" "karuna_private_rta_1" {
  subnet_id      = aws_subnet.karuna_private_subnet_1.id
  route_table_id = aws_route_table.karuna_private_rt.id
}

resource "aws_route_table_association" "karuna_private_rta_2" {
  subnet_id      = aws_subnet.karuna_private_subnet_2.id
  route_table_id = aws_route_table.karuna_private_rt.id
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

##############################################
# ECS Cluster
##############################################
resource "aws_ecs_cluster" "karuna_cluster" {
  name = "karuna-ecs-cluster"
}

##############################################
# ECR Repo
##############################################
data "aws_ecr_repository" "karuna_repo" {
  name = var.ecr_repository_name
}

##############################################
# ECS Task Execution Role
##############################################
resource "aws_iam_role" "karuna_ecs_task_execution_role" {
  name = "karuna-ecs-task-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "karuna_ecs_task_execution_role_attach" {
  role       = aws_iam_role.karuna_ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

##############################################
# RDS Subnet Group & PostgreSQL
##############################################
resource "aws_db_subnet_group" "karuna_db_subnet" {
  name       = "karuna-db-subnet"
  subnet_ids = [
    aws_subnet.karuna_private_subnet_1.id,
    aws_subnet.karuna_private_subnet_2.id
  ]
  tags = { Name = "karuna-db-subnet" }
}

resource "aws_db_instance" "karuna_postgres" {
  identifier             = "karuna-rds-postgres"
  engine                 = "postgres"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.karuna_db_subnet.id
  vpc_security_group_ids = [aws_security_group.karuna_sg_db.id]

  skip_final_snapshot   = true
  publicly_accessible   = false
}

##############################################
# ECS Task Definition (PostgreSQL + Logging)
##############################################
resource "aws_ecs_task_definition" "karuna_task" {
  family                   = "karuna-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.karuna_ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "karuna-strapi"
      image = "${data.aws_ecr_repository.karuna_repo.repository_url}:latest"

      portMappings = [
        { containerPort = 1337, hostPort = 1337 }
      ]

      environment = [
        # PostgreSQL connection settings
        { name = "DATABASE_CLIENT",     value = "postgres" },
        { name = "DATABASE_HOST",       value = aws_db_instance.karuna_postgres.address },
        { name = "DATABASE_PORT",       value = "5432" },
        { name = "DATABASE_NAME",       value = var.db_name },
        { name = "DATABASE_USERNAME",   value = var.db_username },
        { name = "DATABASE_PASSWORD",   value = var.db_password },
        { name = "DATABASE_SSL",        value = "true" },
        { name = "PGSSLMODE",         value = "no-verify" },

        # Strapi secrets
        { name = "APP_KEYS",           value = var.strapi_app_keys },
        { name = "API_TOKEN_SALT",     value = var.strapi_api_token_salt },
        { name = "ADMIN_JWT_SECRET",   value = var.strapi_admin_jwt_secret },
        { name = "JWT_SECRET",         value = var.strapi_admin_jwt_secret }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/karuna-strapi"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

##############################################
# ECS Service
##############################################
resource "aws_ecs_service" "karuna_service" {
  name            = "karuna-service"
  cluster         = aws_ecs_cluster.karuna_cluster.id
  task_definition = aws_ecs_task_definition.karuna_task.arn
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [
      aws_subnet.karuna_public_subnet_1.id,
      aws_subnet.karuna_public_subnet_2.id
    ]
    security_groups = [aws_security_group.karuna_sg_public.id]
    assign_public_ip = true
  }

  desired_count = 1
}
