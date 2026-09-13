terraform {
  required_version = ">= 1.5.0"

  backend "local" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# Project credentials in k8s-clusters/sensitive/aws (not ~/.aws). kubeadm on EC2 (not EKS).
provider "aws" {
  region                   = var.aws_region
  profile                  = var.aws_profile
  shared_credentials_files = [abspath("${path.root}/../../../../sensitive/aws/credentials")]
  shared_config_files      = [abspath("${path.root}/../../../../sensitive/aws/cli.conf")]
}
