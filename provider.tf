terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  env_name          = "sandbox"
  provisioner       = "terraform"
  github_repository = "ecs_deployment"
  project           = "ecs_deployment"
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      env               = local.env_name
      provisioner       = local.provisioner
      github-repository = local.github_repository
      project           = local.project
    }
  }
}

