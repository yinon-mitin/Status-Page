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
