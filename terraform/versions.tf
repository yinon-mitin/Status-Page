terraform {
  required_version = ">= 1.6.0"

  # Credentials and the bucket/key are supplied at init time; do not commit
  # backend access details or environment-specific state locations.
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
