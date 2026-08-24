output "ecr_app_repository_url" {
  description = "Application ECR repository URL used by GitHub Actions."
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_nginx_repository_url" {
  description = "NGINX ECR repository URL used by GitHub Actions."
  value       = aws_ecr_repository.nginx.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "task_execution_role_arn" {
  description = "Task execution role ARN; it reads ECR images, writes logs, and reads explicitly supplied runtime secrets."
  value       = aws_iam_role.task_execution.arn
}

output "github_actions_ecr_publish_role_arn" {
  description = "Set this value as the AWS_ROLE_TO_ASSUME GitHub repository variable after creating the account-level GitHub OIDC provider."
  value       = try(aws_iam_role.github_actions_ecr_publish[0].arn, null)
}

output "network" {
  description = "Network IDs for the next ALB, ECS service, RDS, and Redis stages. Null until create_network is enabled."
  value = var.create_network ? {
    vpc_id             = aws_vpc.main[0].id
    public_subnet_ids  = values(aws_subnet.public)[*].id
    app_subnet_ids     = values(aws_subnet.app)[*].id
    alb_security_group = aws_security_group.alb[0].id
    ecs_security_group = aws_security_group.ecs[0].id
  } : null
}
