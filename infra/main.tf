# Ambleroot (a fictional startup that sells guided city tours): AWS infrastructure
# for the booking app, as delivered by the vendor.
#
# DEMO CODE, FLAWED ON PURPOSE. Never run `terraform apply` on this version.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.name
      ManagedBy = "terraform"
    }
  }
}

variable "region" {
  description = "AWS region for every resource."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Prefix for resource names."
  type        = string
  default     = "ambleroot"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.name}-app"
  }
}

output "app_public_ip" {
  description = "Public address of the app server."
  value       = aws_instance.app.public_ip
}

output "uploads_bucket" {
  description = "Bucket for tour photos and the documents customers upload."
  value       = aws_s3_bucket.uploads.bucket
}

output "image_repository_url" {
  description = "Where CI pushes the app image."
  value       = aws_ecr_repository.app.repository_url
}

output "ci_role_arn" {
  description = "Role that GitHub Actions assumes."
  value       = aws_iam_role.ci.arn
}

output "database_endpoint" {
  description = "PostgreSQL host and port."
  value       = aws_db_instance.main.endpoint
}

output "database_password_secret_arn" {
  description = "Secrets Manager secret where RDS keeps the database password."
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}
