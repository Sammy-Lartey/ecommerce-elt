terraform {
  required_version = ">= 1.11"

  backend "s3" {
    bucket       = "sammy-ecom-elt-tfstate"
    key          = "main/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

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
      project    = var.project
      env        = var.env
      owner      = "sammy"
      managed_by = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}