terraform {
  backend "s3" {
    encrypt = true
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  default_tags {
    tags = local.default_tags
  }
  ignore_tags {
    key_prefixes = ["gsfc-ngap"]
  }
  region  = var.aws_region
}

# Data sources
data "aws_caller_identity" "current" {}

data "aws_kms_key" "ssm_key" {
  key_id = "alias/aws/ssm"
}

data "aws_sns_topic" "batch_failure_topic" {
  name = "${var.prefix}-batch-job-failure"
}

data "aws_ssm_parameter" "edl_token" {
  name = "${var.prefix}-edl-token"
}

data "aws_ssm_parameter" "edl_username" {
  name = "generate-edl-username"
}

data "aws_ssm_parameter" "edl_password" {
  name = "generate-edl-password"
}

# Local variables
locals {
  account_id = data.aws_caller_identity.current.account_id
  default_tags = length(var.default_tags) == 0 ? {
    application : var.app_name,
    environment : var.environment,
    version : var.app_version
  } : var.default_tags
}