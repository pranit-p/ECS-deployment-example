resource "aws_vpc" "ecs_deployment_vpc" {
  cidr_block           = "192.168.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "ecs-deployment-vpc"
  }
}

locals {
  public_subnet = [
    {
      ip_range= "192.168.1.0/24"
      availability_zone = "us-east-1a"
    },
    {
      ip_range= "192.168.3.0/24"
      availability_zone = "us-east-1b"
    },
    {
      ip_range= "192.168.5.0/24"
      availability_zone = "us-east-1c"
    }
  ]
  private_subnet = [
    {
      ip_range= "192.168.7.0/24"
      availability_zone = "us-east-1a"
    },
    {
      ip_range= "192.168.9.0/24"
      availability_zone = "us-east-1b"
    },
    {
      ip_range= "192.168.11.0/24"
      availability_zone = "us-east-1c"
    }
  ]
}

resource "aws_subnet" "ecs_deployment_public_subnet" {
  for_each =  { for subnet in local.public_subnet : subnet.availability_zone => subnet }
  vpc_id                  = aws_vpc.ecs_deployment_vpc.id
  cidr_block              = each.value.ip_range
  availability_zone       = each.value.availability_zone
  tags = {
    Name = "ecs-deployment-public-subnet",
  }
}

resource "aws_subnet" "ecs_deployment_private_subnet" {
  for_each =  { for subnet in local.private_subnet : subnet.availability_zone => subnet }
  vpc_id                  = aws_vpc.ecs_deployment_vpc.id
  cidr_block              = each.value.ip_range
  availability_zone       = each.value.availability_zone
  tags = {
    Name = "ecs-deployment-private-subnet",
  }
}

resource "aws_internet_gateway" "ecs_deployment_internet_gateway" {
  vpc_id = aws_vpc.ecs_deployment_vpc.id
  tags = {
    Name = "ecs_deployment_internet_gateway"
  }
}

resource "aws_route_table" "ecs_deployment_public_subnet_route_table" {
  vpc_id = aws_vpc.ecs_deployment_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ecs_deployment_internet_gateway.id
  }
}

resource "aws_route_table_association" "ecs_deployment_public_subnet_route_table" {
  for_each =  { for subnet in local.public_subnet : subnet.availability_zone => subnet }
  subnet_id      = aws_subnet.ecs_deployment_public_subnet[each.value.availability_zone].id
  route_table_id = aws_route_table.ecs_deployment_public_subnet_route_table.id
}

resource "aws_security_group" "ecs_deployment_security_group" {
  name   = "ecs-deployment-security-group"
  vpc_id = aws_vpc.ecs_deployment_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    self        = "false"
    cidr_blocks = ["0.0.0.0/0"]
    description = "allow http traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "allow internet access"
  }
}

resource "aws_ecs_cluster" "ecs_deployment_cluster" {
  name = "ecs-deployment-cluster"
}

resource "aws_ecs_cluster_capacity_providers" "ecs_deployment_cluster_capacity_providers" {
  cluster_name = aws_ecs_cluster.ecs_deployment_cluster.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 0
    weight            = 1
    capacity_provider = "FARGATE"
  }
}

resource "aws_ecs_task_definition" "ecs_deployment_task_definition" {
  family             = "ecs-deployment-task-definition"
  network_mode       = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([
    {
      name      = "frontend_UI"
      image     = "public.ecr.aws/nginx/nginx:stable-perl"
      cpu       = 1024
      memory    = 2048
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "ecs_service" {
  name            = "my-ecs-service"
  cluster         = aws_ecs_cluster.ecs_deployment_cluster.id
  task_definition = aws_ecs_task_definition.ecs_deployment_task_definition.arn
  desired_count   = 2

  launch_type = "FARGATE"

  network_configuration {
    subnets         = [for subnet in local.public_subnet : aws_subnet.ecs_deployment_public_subnet[subnet.availability_zone].id]
    security_groups = [aws_security_group.ecs_deployment_security_group.id]
    assign_public_ip = true
  }

  force_new_deployment = true

}

