output "app_repository_url" {
  description = "Temporary ECR destination for the locally built Status-Page image."
  value       = aws_ecr_repository.app.repository_url
}

output "nginx_repository_url" {
  description = "Temporary ECR destination for the locally built NGINX image."
  value       = aws_ecr_repository.nginx.repository_url
}

output "cluster_arn" {
  description = "Temporary ECS cluster used for Terraform idempotency validation."
  value       = aws_ecs_cluster.this.arn
}

output "task_definition_arn" {
  description = "Temporary Fargate task definition referencing the pushed Status-Page image."
  value       = try(aws_ecs_task_definition.image_reference[0].arn, null)
}
