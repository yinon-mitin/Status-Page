resource "aws_ecr_repository" "app" {
  name                 = "${var.project}-${var.environment}-app"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.resource_tags
}

resource "aws_ecr_repository" "nginx" {
  name                 = "${var.project}-${var.environment}-nginx"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.resource_tags
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the most recent 30 application images."
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = ["sha-"]
        countType     = "imageCountMoreThan"
        countNumber   = 30
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "nginx" {
  repository = aws_ecr_repository.nginx.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the most recent 30 NGINX images."
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = ["sha-"]
        countType     = "imageCountMoreThan"
        countNumber   = 30
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/${var.project}/${var.environment}/web"
  retention_in_days = 30
  tags              = local.resource_tags
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/${var.project}/${var.environment}/worker"
  retention_in_days = 30
  tags              = local.resource_tags
}

resource "aws_cloudwatch_log_group" "scheduler" {
  name              = "/ecs/${var.project}/${var.environment}/scheduler"
  retention_in_days = 30
  tags              = local.resource_tags
}

resource "aws_ecs_cluster" "this" {
  name = "${var.project}-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.resource_tags
}

locals {
  resource_tags = {
    ManagedBy   = "Terraform"
    Owner       = var.owner
    Project     = var.project
    Environment = var.environment
    Repository  = "yinon-mitin/Status-Page"
  }

  app_image   = coalesce(var.app_image_uri, "${aws_ecr_repository.app.repository_url}:${var.image_tag}")
  nginx_image = coalesce(var.nginx_image_uri, "${aws_ecr_repository.nginx.repository_url}:${var.image_tag}")

  environment = [for name, value in var.runtime_environment : { name = name, value = value }]
  secrets     = [for name, value_from in var.runtime_secret_arns : { name = name, valueFrom = value_from }]

  service_subnet_ids        = var.create_data_plane ? values(aws_subnet.app)[*].id : var.app_private_subnet_ids
  service_security_group_id = var.create_data_plane ? aws_security_group.ecs[0].id : var.ecs_security_group_id
  service_target_group_arn  = var.create_data_plane ? aws_lb_target_group.web[0].arn : var.web_target_group_arn

  app_container = {
    name        = "app"
    image       = local.app_image
    essential   = true
    environment = local.environment
    secrets     = local.secrets
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.web.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "app"
      }
    }
  }
}

resource "aws_ecs_task_definition" "web" {
  family                   = "${var.project}-${var.environment}-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn
  tags                     = local.resource_tags

  container_definitions = jsonencode([
    merge(local.app_container, {
      healthCheck = {
        command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:8001/healthz', timeout=3)\""]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 45
      }
    }),
    {
      name      = "nginx"
      image     = local.nginx_image
      essential = true
      portMappings = [{
        containerPort = 80
        protocol      = "tcp"
      }]
      dependsOn = [{ containerName = "app", condition = "HEALTHY" }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.web.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "nginx"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://127.0.0.1/healthz || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 45
      }
    }
  ])
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.project}-${var.environment}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn
  tags                     = local.resource_tags

  container_definitions = jsonencode([merge(local.app_container, {
    name    = "worker"
    command = ["python", "manage.py", "rqworker", "high", "default", "low"]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.worker.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "worker"
      }
    }
  })])
}

resource "aws_ecs_task_definition" "scheduler" {
  family                   = "${var.project}-${var.environment}-scheduler"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn
  tags                     = local.resource_tags

  container_definitions = jsonencode([merge(local.app_container, {
    name    = "scheduler"
    command = ["python", "manage.py", "rqscheduler"]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.scheduler.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "scheduler"
      }
    }
  })])
}

resource "aws_ecs_service" "web" {
  count           = var.create_services ? 1 : 0
  name            = "web"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = var.web_desired_count
  launch_type     = "FARGATE"
  tags            = local.resource_tags

  network_configuration {
    subnets          = local.service_subnet_ids
    security_groups  = [local.service_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = local.service_target_group_arn
    container_name   = "nginx"
    container_port   = 80
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    precondition {
      condition     = length(local.service_subnet_ids) > 0 && local.service_security_group_id != null && local.service_target_group_arn != null
      error_message = "Web service requires private application subnets, the ECS security group, and the ALB target group."
    }

    precondition {
      condition     = contains(keys(var.runtime_secret_arns), "STATUS_PAGE_SECRET_KEY") && contains(keys(var.runtime_secret_arns), "POSTGRES_PASSWORD")
      error_message = "Web service requires STATUS_PAGE_SECRET_KEY and POSTGRES_PASSWORD from Secrets Manager."
    }
  }
}

resource "aws_ecs_service" "worker" {
  count           = var.create_services ? 1 : 0
  name            = "worker"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.worker_desired_count
  launch_type     = "FARGATE"
  tags            = local.resource_tags

  network_configuration {
    subnets          = local.service_subnet_ids
    security_groups  = [local.service_security_group_id]
    assign_public_ip = false
  }
}

resource "aws_ecs_service" "scheduler" {
  count           = var.create_services ? 1 : 0
  name            = "scheduler"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.scheduler.arn
  desired_count   = var.scheduler_desired_count
  launch_type     = "FARGATE"
  tags            = local.resource_tags

  network_configuration {
    subnets          = local.service_subnet_ids
    security_groups  = [local.service_security_group_id]
    assign_public_ip = false
  }
}
