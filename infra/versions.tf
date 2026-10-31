terraform {
  required_version = ">= 1.10"
  cloud {
    organization = "ooad-andriidv"
    workspaces {
      name = "new-project-dev"
    }
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      PROJECT_NAME = var.project_name
    }
  }
}
