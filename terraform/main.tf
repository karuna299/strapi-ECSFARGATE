##############################################
# Provider
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
# Default VPC & AZ Data
##############################################

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get availability zones to distribute subnets
data "aws_availability_zones" "available" {}

##############################################
# Subnets inside default VPC
##############################################

# Public subnet for ECS (first AZ)
resource "aws_subnet" "karuna_public_subnet" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = cidrsubnet(data.aws_vpc.default.cidr_block, 8, 1)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "karuna-public-subnet"
  }
}

# Private subnet for RDS (first AZ)
resource "aws_subnet" "karuna_private_subnet" {
  vpc_id            = data.aws_vpc.default.id
  cidr_block        = cidrsubnet(data.aws_vpc.default.cidr_block, 8, 2)
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "karuna-private-subnet"
  }
}

##############################################
# Internet Gateway + Route for Public
##############################################

resource "aws_internet_gateway" "karuna_igw" {
  vpc_id = data.aws_vpc.default.id
  tags = {
    Name = "karuna-igw"
  }
}

resource "aws_route_table" "karuna_public_rt" {
  vpc_id = data.aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.karuna_igw.id
  }
}

resource "aws_route_table_association" "karuna_public_rta" {
  subnet_id      = aws_subnet.karuna_public_subnet.id
  route_table_id = aws_route_table.karuna_public_rt.id
}

##############################################
# NAT Gateway for Private Subnet Egress
##############################################

resource "aws_eip" "karuna_nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "karuna_nat" {
  allocation_id = aws_eip.karuna_nat_eip.id
  subnet_id     = aws_subnet.karuna_public_subnet.id

  tags = {
    Name = "karuna-nat-gateway"
  }
}

resource "aws_route_table" "karuna_private_rt" {
  vpc_id = data.aws_vpc.default.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.karuna_nat.id
  }
}

resource "aws_route_table_association" "karuna_private_rta" {
  subnet_id      = aws_subnet.karuna_private_subnet.id
  route_table_id = aws_route_table.karuna_private_rt.id
}

##############################################
# Security Groups for ECS & RDS
##############################################

resource "aws_security_group" "karuna_sg_public" {
  name   = "karuna-sg-public"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
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

  # Allow only ECS SG to access DB on port 5432
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
# Reference ECR Repository
##############################################

data "aws_ecr_repository" "karuna_repo" {
  name = var.ecr_repository_name
}

##############################################
# RDS PostgreSQL in Private Subnet
##############################################

resource "aws_db_subnet_group" "karuna_db_subnet" {
  name       = "karuna-db-subnet"
  subnet_ids = [aws_subnet.karuna_private_subnet.id]

  tags = {
    Name = "karuna-db-subnet"
  }
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

  skip_final_snapshot     = true
  publicly_accessible     = false
}

##############################################
# ECS Task Definition (Fargate)
##############################################

resource "aws_ecs_task_definition" "karuna_task" {
  family                   = "karuna-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"

  container_definitions = jsonencode([
    {
      name      = "karuna-strapi"
      image     = data.aws_ecr_repository.karuna_repo.repository_url
      portMappings = [
        {
          containerPort = 1337
          hostPort      = 1337
        }
      ]
      environment = [
        {
          name  = "DATABASE_HOST"
          value = aws_db_instance.karuna_postgres.address
        },
        {
          name  = "DATABASE_PORT"
          value = "5432"
        },
        {
          name  = "DATABASE_NAME"
          value = var.db_name
        },
        {
          name  = "DATABASE_USERNAME"
          value = var.db_username
        },
        {
          name  = "DATABASE_PASSWORD"
          value = var.db_password
        }
      ]
    }
  ])
}

##############################################
# ECS Service (Fargate)
##############################################

resource "aws_ecs_service" "karuna_service" {
  name            = "karuna-service"
  cluster         = aws_ecs_cluster.karuna_cluster.id
  task_definition = aws_ecs_task_definition.karuna_task.arn
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.karuna_public_subnet.id]
    security_groups = [aws_security_group.karuna_sg_public.id]
    assign_public_ip = true
  }

  desired_count = 1
}
