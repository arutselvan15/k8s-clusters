terraform {
  required_version = ">= 1.5.0"

  backend "local" {}

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
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

# Auth is clouds.yaml (OS_CLIENT_CONFIG_FILE + OS_CLOUD), not keys in this file.
provider "openstack" {
  cloud = var.cloud
}
