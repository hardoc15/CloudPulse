terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "CloudPulse"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  project_name = "cloudpulse"
  name_suffix  = "${var.environment}-${random_id.suffix.hex}"
  
  common_tags = {
    Project     = "CloudPulse"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# S3 bucket for data storage
resource "aws_s3_bucket" "data_lake" {
  bucket = "${local.project_name}-data-lake-${local.name_suffix}"
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Kinesis Data Stream
module "kinesis" {
  source = "./modules/kinesis"
  
  stream_name     = "${local.project_name}-stream-${local.name_suffix}"
  shard_count     = var.kinesis_shard_count
  retention_period = var.kinesis_retention_period
  
  tags = local.common_tags
}

# Lambda functions
module "lambda" {
  source = "./modules/lambda"
  
  project_name    = local.project_name
  name_suffix     = local.name_suffix
  kinesis_stream_arn = module.kinesis.stream_arn
  s3_bucket       = aws_s3_bucket.data_lake.bucket
  
  tags = local.common_tags
}

# API Gateway
module "api_gateway" {
  source = "./modules/api-gateway"
  
  project_name        = local.project_name
  name_suffix         = local.name_suffix
  kinesis_stream_name = module.kinesis.stream_name
  
  tags = local.common_tags
}

# DynamoDB for metadata
module "storage" {
  source = "./modules/storage"
  
  project_name = local.project_name
  name_suffix  = local.name_suffix
  
  tags = local.common_tags
}

# Monitoring and alerting
module "monitoring" {
  source = "./modules/monitoring"
  
  project_name           = local.project_name
  name_suffix            = local.name_suffix
  kinesis_stream_name    = module.kinesis.stream_name
  lambda_function_names  = module.lambda.function_names
  api_gateway_id         = module.api_gateway.api_id
  
  alert_email = var.alert_email
  
  tags = local.common_tags
}
