variable "aws_region" {
  description = "AWS Region for the ECR/ECS environment."
  type        = string
  default     = "il-central-1"
}

variable "project" {
  description = "Short project identifier used in AWS resource names and tags."
  type        = string
  default     = "yinon-status-page"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.project))
    error_message = "project must be 3-32 characters, use lowercase letters, numbers, and hyphens, and start/end with a letter or number."
  }
}

variable "environment" {
  description = "Deployment environment, for example dev or prod."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be exactly dev or prod so resource and state isolation remains explicit."
  }
}

variable "owner" {
  description = "Owner value required by the AWS account's resource-creation guardrail."
  type        = string
  default     = "yinon"
}

variable "image_tag" {
  description = "Immutable application image tag, normally the Git commit SHA published by GitHub Actions."
  type        = string
  default     = "bootstrap"
}

variable "app_image_uri" {
  description = "Optional full application image URI. When null, Terraform uses the managed ECR application repository and image_tag."
  type        = string
  default     = null
  nullable    = true
}

variable "nginx_image_uri" {
  description = "Optional full NGINX image URI. When null, Terraform uses the managed ECR NGINX repository and image_tag."
  type        = string
  default     = null
  nullable    = true
}

variable "app_private_subnet_ids" {
  description = "Private application-subnet IDs for ECS tasks. Required only when create_services is true."
  type        = list(string)
  default     = []
}

variable "ecs_security_group_id" {
  description = "Security group ID attached to ECS tasks. It must allow port 80 only from the ALB security group. Required only when create_services is true."
  type        = string
  default     = null
  nullable    = true
}

variable "web_target_group_arn" {
  description = "ALB target group ARN for the NGINX container on port 80. Required only when create_services is true."
  type        = string
  default     = null
  nullable    = true
}

variable "create_services" {
  description = "Set true only after the VPC, private application subnets, ECS security group, ALB target group, RDS, Redis, and Secrets Manager inputs exist."
  type        = bool
  default     = false
}

variable "web_desired_count" {
  description = "Initial web service task count. Two tasks are placed across the internal application subnets."
  type        = number
  default     = 2
}

variable "worker_desired_count" {
  description = "Initial RQ worker task count."
  type        = number
  default     = 1
}

variable "scheduler_desired_count" {
  description = "Initial RQ scheduler task count."
  type        = number
  default     = 1
}

variable "runtime_environment" {
  description = "Non-secret environment values passed to all application containers, such as RDS endpoint, Redis endpoint, allowed hosts, and site URL."
  type        = map(string)
  default = {
    POSTGRES_HOST             = "REPLACE_WITH_RDS_ENDPOINT"
    POSTGRES_PORT             = "5432"
    POSTGRES_DB               = "statuspage"
    POSTGRES_USER             = "statuspage"
    REDIS_HOST                = "REPLACE_WITH_REDIS_ENDPOINT"
    REDIS_PORT                = "6379"
    STATUS_PAGE_ALLOWED_HOSTS = "REPLACE_WITH_ALB_DNS_OR_DOMAIN"
    STATUS_PAGE_SITE_URL      = "https://REPLACE_WITH_DOMAIN"
    STATUS_PAGE_TIME_ZONE     = "Asia/Jerusalem"
  }
}

variable "runtime_secret_arns" {
  description = "Map of externally managed environment-variable names to Secrets Manager secret ARNs. With the managed data plane, Terraform derives POSTGRES_PASSWORD from the RDS-managed secret."
  type        = map(string)
  default     = {}
}

variable "teardown_mode" {
  description = "Temporarily disable deletion protection and allow ECR image deletion during the reviewed automated destroy workflow."
  type        = bool
  default     = false
}

variable "enable_monitoring" {
  description = "Create the production CloudWatch dashboard and alarms. Notification transport and Budget remain separately permission-gated."
  type        = bool
  default     = true
}

variable "create_alert_topic" {
  description = "Create the production SNS topic and policy. Keep false when the operator lacks SNS administration permissions."
  type        = bool
  default     = false
}

variable "external_alert_topic_arn" {
  description = "Optional manually bootstrapped SNS topic ARN used when create_alert_topic is false. Its policy must allow the exact project alarms and Budget."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.external_alert_topic_arn == null || var.external_alert_topic_arn == "arn:aws:sns:il-central-1:992382545251:yinon-status-page-prod-alerts"
    error_message = "external_alert_topic_arn must be the exact il-central-1 production alert topic ARN."
  }
}

variable "enable_aws_budget" {
  description = "Create the project-scoped 300 USD AWS Budget. Requires Budget permissions and an effective alert topic."
  type        = bool
  default     = false
}

variable "alert_https_endpoints" {
  description = "HTTPS receivers for the production SNS alert topic, normally the verified Cloudflare Telegram relay endpoint."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for endpoint in var.alert_https_endpoints : can(regex("^https://[^[:space:]]+$", endpoint))])
    error_message = "Every alert endpoint must be an HTTPS URL."
  }
}

variable "final_snapshot_identifier" {
  description = "Unique RDS final snapshot identifier supplied by the automated destroy workflow."
  type        = string
  default     = null
  nullable    = true
}

variable "ecs_execution_role_arn" {
  description = "ARN of the manually managed ECS task execution role. Terraform must not manage this role."
  type        = string
  default     = null
  nullable    = true
}

variable "ecs_task_role_arn" {
  description = "ARN of the manually managed ECS task role. Terraform must not manage this role."
  type        = string
  default     = null
  nullable    = true
}

variable "create_network" {
  description = "Set true only after reviewing the VPC CIDR and the cost/security implications of the network layer."
  type        = bool
  default     = false
}

variable "create_data_plane" {
  description = "Set true only after reviewing the VPC, ALB, RDS, ElastiCache, VPC endpoint, and recurring-cost plan. Requires create_network."
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Production hostname served by the public ALB after ACM DNS validation."
  type        = string
  default     = "status.yifilter.uk"
}

variable "request_acm_certificate" {
  description = "Set true only when the approved identity has ACM RequestCertificate permission."
  type        = bool
  default     = false
}

variable "acm_certificate_arn" {
  description = "Issued ACM certificate ARN used for the ALB HTTPS listener. Can be supplied after manual ACM issuance."
  type        = string
  default     = null
  nullable    = true
}

variable "vpc_cidr" {
  description = "CIDR for the Status-Page VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "availability_zones" {
  description = "Two AZs for the public ALB subnets and internal ECS application subnets."
  type        = map(string)
  default = {
    a = "il-central-1a"
    b = "il-central-1b"
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs for the internet-facing ALB."
  type        = map(string)
  default = {
    a = "10.42.0.0/24"
    b = "10.42.1.0/24"
  }
}

variable "app_subnet_cidrs" {
  description = "Internal application subnet CIDRs for ECS tasks."
  type        = map(string)
  default = {
    a = "10.42.10.0/24"
    b = "10.42.11.0/24"
  }
}

variable "data_subnet_cidrs" {
  description = "Private data-subnet CIDRs for RDS and ElastiCache across the two active AZs."
  type        = map(string)
  default = {
    a = "10.42.20.0/24"
    b = "10.42.21.0/24"
  }
}
