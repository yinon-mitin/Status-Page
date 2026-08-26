provider "aws" {
  region = var.aws_region
}

locals {
  name_prefix = "yinon-status-page-smoke"
  common_tags = {
    Owner       = "yinon"
    Project     = "yinon-status-page"
    Environment = "smoke"
    ManagedBy   = "Terraform"
    Repository  = "yinon-mitin/Status-Page"
    Purpose     = "temporary-idempotency-test"
  }
}

resource "aws_ecr_repository" "app" {
  name                 = "${local.name_prefix}-app"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

resource "aws_ecr_repository" "nginx" {
  name                 = "${local.name_prefix}-nginx"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

resource "aws_ecs_cluster" "this" {
  name = local.name_prefix

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "image_reference" {
  count                    = var.execution_role_arn == null ? 0 : 1
  family                   = "${local.name_prefix}-image-reference"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.execution_role_arn

  container_definitions = jsonencode([
    {
      name      = "statuspage-app"
      image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
      essential = true
      cpu       = 256
      memory    = 512
    }
  ])

  tags = local.common_tags
}
