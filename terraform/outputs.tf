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
