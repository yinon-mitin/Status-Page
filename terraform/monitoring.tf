data "aws_caller_identity" "current" {}

locals {
  alert_topic_name          = "${var.project}-${var.environment}-alerts"
  effective_alert_topic_arn = var.create_alert_topic ? aws_sns_topic.alerts[0].arn : var.external_alert_topic_arn
  monitored_ecs_services = var.create_services ? {
    web = {
      name          = aws_ecs_service.web[0].name
      desired_count = var.web_desired_count
    }
    worker = {
      name          = aws_ecs_service.worker[0].name
      desired_count = var.worker_desired_count
    }
    scheduler = {
      name          = aws_ecs_service.scheduler[0].name
      desired_count = var.scheduler_desired_count
    }
  } : {}
  alarm_actions = var.enable_monitoring && local.effective_alert_topic_arn != null ? [local.effective_alert_topic_arn] : []
}

resource "aws_sns_topic" "alerts" {
  count = var.enable_monitoring && var.create_alert_topic ? 1 : 0
  name  = local.alert_topic_name
  tags  = local.resource_tags
}

resource "aws_sns_topic_policy" "alerts" {
  count = var.enable_monitoring && var.create_alert_topic ? 1 : 0
  arn   = aws_sns_topic.alerts[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "SNS:*"
        Resource  = aws_sns_topic.alerts[0].arn
      },
      {
        Sid       = "CloudWatchAlarmPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.alerts[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${var.project}-${var.environment}-*"
          }
        }
      },
      {
        Sid       = "AwsBudgetsPublish"
        Effect    = "Allow"
        Principal = { Service = "budgets.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.alerts[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:budgets::${data.aws_caller_identity.current.account_id}:budget/${var.project}-${var.environment}-monthly"
          }
        }
      },
    ]
  })
}

resource "aws_sns_topic_subscription" "https_alerts" {
  for_each = var.enable_monitoring && local.effective_alert_topic_arn != null ? toset(var.alert_https_endpoints) : toset([])

  topic_arn = local.effective_alert_topic_arn
  protocol  = "https"
  endpoint  = each.value
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  count = local.data_plane_enabled && var.create_services && var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project}-${var.environment}-alb-unhealthy-hosts"
  alarm_description   = "One or more Status-Page ALB targets are unhealthy."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  dimensions = {
    LoadBalancer = aws_lb.web[0].arn_suffix
    TargetGroup  = aws_lb_target_group.web[0].arn_suffix
  }
  tags = local.resource_tags
}

resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  count = local.data_plane_enabled && var.create_services && var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project}-${var.environment}-alb-target-5xx"
  alarm_description   = "Application targets emitted at least five 5xx responses in five minutes."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  dimensions = {
    LoadBalancer = aws_lb.web[0].arn_suffix
    TargetGroup  = aws_lb_target_group.web[0].arn_suffix
  }
  tags = local.resource_tags
}

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  count = local.data_plane_enabled && var.create_services && var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project}-${var.environment}-alb-p95-latency"
  alarm_description   = "ALB target p95 response time exceeded two seconds."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 2
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  dimensions = {
    LoadBalancer = aws_lb.web[0].arn_suffix
  }
  tags = local.resource_tags
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  for_each = var.enable_monitoring ? local.monitored_ecs_services : {}

  alarm_name          = "${var.project}-${var.environment}-ecs-${each.key}-cpu"
  alarm_description   = "ECS ${each.key} CPU utilization exceeded 80 percent."
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = each.value.name
  }
  tags = local.resource_tags
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory" {
  for_each = var.enable_monitoring ? local.monitored_ecs_services : {}

  alarm_name          = "${var.project}-${var.environment}-ecs-${each.key}-memory"
  alarm_description   = "ECS ${each.key} memory utilization exceeded 80 percent."
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = each.value.name
  }
  tags = local.resource_tags
}

resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks" {
  for_each = var.enable_monitoring ? local.monitored_ecs_services : {}

  alarm_name          = "${var.project}-${var.environment}-ecs-${each.key}-running-tasks"
  alarm_description   = "ECS ${each.key} has fewer running tasks than its declared desired count."
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = each.value.desired_count
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = each.value.name
  }
  tags = local.resource_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  count = local.data_plane_enabled && var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project}-${var.environment}-rds-cpu"
  alarm_description   = "RDS CPU utilization exceeded 80 percent."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres[0].identifier
  }
  tags = local.resource_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  count = local.data_plane_enabled && var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project}-${var.environment}-rds-free-storage"
  alarm_description   = "RDS free storage dropped below 4 GiB."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 4294967296
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres[0].identifier
  }
  tags = local.resource_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  count = local.data_plane_enabled && var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project}-${var.environment}-rds-connections"
  alarm_description   = "RDS concurrent connections exceeded the demo capacity threshold."
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 60
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres[0].identifier
  }
  tags = local.resource_tags
}

resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  count = local.data_plane_enabled && var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project}-${var.environment}-redis-cpu"
  alarm_description   = "Redis engine CPU utilization exceeded 80 percent."
  namespace           = "AWS/ElastiCache"
  metric_name         = "EngineCPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  dimensions = {
    CacheClusterId = one(aws_elasticache_replication_group.redis[0].member_clusters)
    CacheNodeId    = "0001"
  }
  tags = local.resource_tags
}

resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  count = local.data_plane_enabled && var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project}-${var.environment}-redis-memory"
  alarm_description   = "Redis database memory usage exceeded 80 percent."
  namespace           = "AWS/ElastiCache"
  metric_name         = "DatabaseMemoryUsagePercentage"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  dimensions = {
    CacheClusterId = one(aws_elasticache_replication_group.redis[0].member_clusters)
    CacheNodeId    = "0001"
  }
  tags = local.resource_tags
}

resource "aws_cloudwatch_metric_alarm" "redis_evictions" {
  count = local.data_plane_enabled && var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project}-${var.environment}-redis-evictions"
  alarm_description   = "Redis evicted one or more keys."
  namespace           = "AWS/ElastiCache"
  metric_name         = "Evictions"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  dimensions = {
    CacheClusterId = one(aws_elasticache_replication_group.redis[0].member_clusters)
    CacheNodeId    = "0001"
  }
  tags = local.resource_tags
}

resource "aws_cloudwatch_dashboard" "production" {
  count          = local.data_plane_enabled && var.enable_monitoring ? 1 : 0
  dashboard_name = "${var.project}-${var.environment}"
  dashboard_body = jsonencode({
    start          = "-PT6H"
    periodOverride = "inherit"
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# Status-Page production\nHTTP-only demo. Alarm actions: `${coalesce(local.effective_alert_topic_arn, "disabled by the training-account SNS permission boundary")}`."
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 12
        height = 6
        properties = {
          title  = "ALB request health"
          region = var.aws_region
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.web[0].arn_suffix],
            [".", "HTTPCode_Target_5XX_Count", ".", "."],
            [".", "HTTPCode_ELB_5XX_Count", ".", "."],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 2
        width  = 12
        height = 6
        properties = {
          title  = "ALB targets and latency"
          region = var.aws_region
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.web[0].arn_suffix, "LoadBalancer", aws_lb.web[0].arn_suffix, { stat = "Minimum" }],
            [".", "UnHealthyHostCount", ".", ".", ".", ".", { stat = "Maximum" }],
            [".", "TargetResponseTime", "LoadBalancer", aws_lb.web[0].arn_suffix, { stat = "p95", yAxis = "right" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "ECS utilization"
          region = var.aws_region
          metrics = [
            for pair in setproduct(sort(keys(local.monitored_ecs_services)), ["CPUUtilization", "MemoryUtilization"]) :
            ["AWS/ECS", pair[1], "ClusterName", aws_ecs_cluster.this.name, "ServiceName", local.monitored_ecs_services[pair[0]].name, { label = "${pair[0]} ${lower(replace(pair[1], "Utilization", ""))}" }]
          ]
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "RDS health"
          region = var.aws_region
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.postgres[0].identifier],
            [".", "DatabaseConnections", ".", "."],
            [".", "FreeStorageSpace", ".", ".", { yAxis = "right" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 12
        height = 6
        properties = {
          title  = "Redis health"
          region = var.aws_region
          metrics = [
            ["AWS/ElastiCache", "EngineCPUUtilization", "CacheClusterId", one(aws_elasticache_replication_group.redis[0].member_clusters), "CacheNodeId", "0001"],
            [".", "DatabaseMemoryUsagePercentage", ".", "."],
            [".", "Evictions", ".", ".", { yAxis = "right" }],
          ]
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 14
        width  = 12
        height = 6
        properties = {
          title  = "Recent application errors"
          region = var.aws_region
          view   = "table"
          query  = "SOURCE '${aws_cloudwatch_log_group.web.name}' | fields @timestamp, @message | filter @message like /ERROR|CRITICAL|Traceback/ | sort @timestamp desc | limit 50"
        }
      },
    ]
  })
}

resource "aws_budgets_budget" "project" {
  count = var.enable_monitoring && var.enable_aws_budget ? 1 : 0

  name         = "${var.project}-${var.environment}-monthly"
  budget_type  = "COST"
  limit_amount = "300"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Project$${var.project}"]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 50
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [local.effective_alert_topic_arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [local.effective_alert_topic_arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [local.effective_alert_topic_arn]
  }

  tags = local.resource_tags

  depends_on = [aws_sns_topic_policy.alerts]

  lifecycle {
    precondition {
      condition     = local.effective_alert_topic_arn != null
      error_message = "enable_aws_budget requires either create_alert_topic or external_alert_topic_arn."
    }
  }
}
