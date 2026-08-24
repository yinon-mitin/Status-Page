data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

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

resource "aws_iam_role" "task_execution" {
  name               = "${var.project}-${var.environment}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "task_execution_secrets" {
  dynamic "statement" {
    for_each = length(var.runtime_secret_arns) == 0 ? [] : [1]

    content {
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = values(var.runtime_secret_arns)
    }
  }
}

resource "aws_iam_role_policy" "task_execution_secrets" {
  count  = length(var.runtime_secret_arns) == 0 ? 0 : 1
  name   = "read-runtime-secrets"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_secrets.json
}

resource "aws_iam_role" "task" {
  name               = "${var.project}-${var.environment}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

data "aws_iam_policy_document" "github_actions_ecr_assume_role" {
  count = var.github_oidc_provider_arn == null ? 0 : 1

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions_ecr_publish" {
  count              = var.github_oidc_provider_arn == null ? 0 : 1
  name               = "${var.project}-${var.environment}-github-ecr-publish"
  assume_role_policy = data.aws_iam_policy_document.github_actions_ecr_assume_role[0].json
}

data "aws_iam_policy_document" "github_actions_ecr_publish" {
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [
      aws_ecr_repository.app.arn,
      aws_ecr_repository.nginx.arn,
    ]
  }
}

resource "aws_iam_role_policy" "github_actions_ecr_publish" {
  count  = var.github_oidc_provider_arn == null ? 0 : 1
  name   = "push-only-ecr-images"
  role   = aws_iam_role.github_actions_ecr_publish[0].id
  policy = data.aws_iam_policy_document.github_actions_ecr_publish.json
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
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn
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
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn
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
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn
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
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.app_private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.web_target_group_arn
    container_name   = "nginx"
    container_port   = 80
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    precondition {
      condition     = length(var.app_private_subnet_ids) > 0 && var.ecs_security_group_id != null && var.web_target_group_arn != null
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
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.app_private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }
}

resource "aws_ecs_service" "scheduler" {
  count           = var.create_services ? 1 : 0
  name            = "scheduler"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.scheduler.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.app_private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }
}
