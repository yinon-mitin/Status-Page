variable "aws_region" {
  description = "AWS Region for the isolated ECR/ECS smoke stack."
  type        = string
  default     = "il-central-1"
}

variable "image_tag" {
  description = "Immutable tag applied to the locally built images after they are pushed to ECR."
  type        = string
}

variable "execution_role_arn" {
  description = "Optional project-scoped ECS execution role ARN. When unset, the smoke stack validates ECR and ECS cluster idempotency without registering a Fargate task definition."
  type        = string
  default     = null
  nullable    = true
}
