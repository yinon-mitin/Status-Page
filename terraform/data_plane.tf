locals {
  data_plane_enabled = var.create_network && var.create_data_plane

  interface_endpoint_services = toset([
    "ecr.api",
    "ecr.dkr",
    "logs",
    "secretsmanager",
  ])
}

resource "aws_security_group" "endpoints" {
  count       = local.data_plane_enabled ? 1 : 0
  name        = "${var.project}-${var.environment}-endpoints"
  description = "PrivateLink endpoint ingress from ECS tasks only."
  vpc_id      = aws_vpc.main[0].id
  tags        = merge(local.resource_tags, { Name = "${var.project}-${var.environment}-endpoints" })
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_ecs" {
  count                        = local.data_plane_enabled ? 1 : 0
  security_group_id            = aws_security_group.endpoints[0].id
  referenced_security_group_id = aws_security_group.ecs[0].id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = local.data_plane_enabled ? local.interface_endpoint_services : toset([])
  vpc_id              = aws_vpc.main[0].id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = values(aws_subnet.app)[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  tags                = merge(local.resource_tags, { Name = "${var.project}-${var.environment}-${replace(each.value, ".", "-")}-endpoint" })
}

resource "aws_vpc_endpoint" "s3" {
  count             = local.data_plane_enabled ? 1 : 0
  vpc_id            = aws_vpc.main[0].id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.app[0].id]
  tags              = merge(local.resource_tags, { Name = "${var.project}-${var.environment}-s3-endpoint" })
}

resource "aws_security_group" "rds" {
  count       = local.data_plane_enabled ? 1 : 0
  name        = "${var.project}-${var.environment}-rds"
  description = "PostgreSQL ingress from ECS tasks only."
  vpc_id      = aws_vpc.main[0].id
  tags        = merge(local.resource_tags, { Name = "${var.project}-${var.environment}-rds" })
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_ecs" {
  count                        = local.data_plane_enabled ? 1 : 0
  security_group_id            = aws_security_group.rds[0].id
  referenced_security_group_id = aws_security_group.ecs[0].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_db_subnet_group" "postgres" {
  count      = local.data_plane_enabled ? 1 : 0
  name       = "${var.project}-${var.environment}-postgres"
  subnet_ids = values(aws_subnet.data)[*].id
  tags       = merge(local.resource_tags, { Name = "${var.project}-${var.environment}-postgres" })
}

resource "aws_db_instance" "postgres" {
  count                       = local.data_plane_enabled ? 1 : 0
  identifier                  = "${var.project}-${var.environment}-postgres"
  engine                      = "postgres"
  engine_version              = "16"
  instance_class              = "db.t4g.micro"
  allocated_storage           = 20
  max_allocated_storage       = 50
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = "statuspage"
  username                    = "statuspage"
  manage_master_user_password = true
  publicly_accessible         = false
  backup_retention_period     = 2
  deletion_protection         = true
  skip_final_snapshot         = false
  final_snapshot_identifier   = "${var.project}-${var.environment}-postgres-final"
  multi_az                    = false
  db_subnet_group_name        = aws_db_subnet_group.postgres[0].name
  vpc_security_group_ids      = [aws_security_group.rds[0].id]
  auto_minor_version_upgrade  = true
  copy_tags_to_snapshot       = true
  apply_immediately           = false
  tags                        = merge(local.resource_tags, { Name = "${var.project}-${var.environment}-postgres" })
}

resource "aws_security_group" "redis" {
  count       = local.data_plane_enabled ? 1 : 0
  name        = "${var.project}-${var.environment}-redis"
  description = "Redis ingress from ECS tasks only."
  vpc_id      = aws_vpc.main[0].id
  tags        = merge(local.resource_tags, { Name = "${var.project}-${var.environment}-redis" })
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_ecs" {
  count                        = local.data_plane_enabled ? 1 : 0
  security_group_id            = aws_security_group.redis[0].id
  referenced_security_group_id = aws_security_group.ecs[0].id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_elasticache_subnet_group" "redis" {
  count      = local.data_plane_enabled ? 1 : 0
  name       = "${var.project}-${var.environment}-redis"
  subnet_ids = values(aws_subnet.data)[*].id
}

resource "aws_elasticache_replication_group" "redis" {
  count                      = local.data_plane_enabled ? 1 : 0
  replication_group_id       = "${var.project}-${var.environment}-redis"
  description                = "Status-Page Redis queue and cache."
  engine                     = "redis"
  engine_version             = "7.1"
  node_type                  = "cache.t4g.micro"
  port                       = 6379
  num_cache_clusters         = 1
  automatic_failover_enabled = false
  multi_az_enabled           = false
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  subnet_group_name          = aws_elasticache_subnet_group.redis[0].name
  security_group_ids         = [aws_security_group.redis[0].id]
  snapshot_retention_limit   = 2
  apply_immediately          = false
  tags                       = merge(local.resource_tags, { Name = "${var.project}-${var.environment}-redis" })
}

resource "aws_lb" "web" {
  count                      = local.data_plane_enabled ? 1 : 0
  name                       = "${var.project}-${var.environment}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb[0].id]
  subnets                    = values(aws_subnet.public)[*].id
  enable_deletion_protection = true
  tags                       = merge(local.resource_tags, { Name = "${var.project}-${var.environment}-alb" })
}

resource "aws_lb_target_group" "web" {
  count       = local.data_plane_enabled ? 1 : 0
  name        = "${var.project}-${var.environment}-web"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main[0].id

  health_check {
    enabled  = true
    path     = "/healthz"
    matcher  = "200"
    protocol = "HTTP"
  }

  tags = merge(local.resource_tags, { Name = "${var.project}-${var.environment}-web" })
}

resource "aws_lb_listener" "http" {
  count             = local.data_plane_enabled ? 1 : 0
  load_balancer_arn = aws_lb.web[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web[0].arn
  }
}

resource "aws_acm_certificate" "web" {
  count             = local.data_plane_enabled && var.request_acm_certificate ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"
  tags              = merge(local.resource_tags, { Name = "${var.project}-${var.environment}-certificate" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "https" {
  count             = local.data_plane_enabled && var.acm_certificate_arn != null ? 1 : 0
  load_balancer_arn = aws_lb.web[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web[0].arn
  }
}