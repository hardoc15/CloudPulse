data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-api-${var.name_suffix}"
  description = "CloudPulse Data Ingestion API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.tags
}

# API Gateway Resource
resource "aws_api_gateway_resource" "data_ingestion" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "ingest"
}

# API Gateway Method
resource "aws_api_gateway_method" "post_data" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.data_ingestion.id
  http_method   = "POST"
  authorization = "NONE"

  request_validator_id = aws_api_gateway_request_validator.main.id
  
  request_models = {
    "application/json" = aws_api_gateway_model.sensor_data.name
  }
}

# Request Validator
resource "aws_api_gateway_request_validator" "main" {
  name                        = "validator"
  rest_api_id                = aws_api_gateway_rest_api.main.id
  validate_request_body      = true
  validate_request_parameters = true
}

# API Gateway Model for request validation
resource "aws_api_gateway_model" "sensor_data" {
  rest_api_id  = aws_api_gateway_rest_api.main.id
  name         = "SensorData"
  content_type = "application/json"

  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    title     = "Sensor Data Schema"
    type      = "object"
    required  = ["sensor_id", "temperature", "humidity"]
    properties = {
      sensor_id = {
        type = "string"
        minLength = 1
        maxLength = 50
      }
      temperature = {
        type = "number"
        minimum = -100
        maximum = 100
      }
      humidity = {
        type = "number"
        minimum = 0
        maximum = 100
      }
      timestamp = {
        type = "string"
        format = "date-time"
      }
      location = {
        type = "string"
        maxLength = 100
      }
    }
  })
}

# API Gateway Integration with Kinesis
resource "aws_api_gateway_integration" "kinesis" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.data_ingestion.id
  http_method = aws_api_gateway_method.post_data.http_method

  integration_http_method = "POST"
  type                   = "AWS"
  uri                    = "arn:aws:apigateway:${data.aws_region.current.name}:kinesis:action/PutRecord"
  credentials            = aws_iam_role.api_gateway_kinesis.arn

  request_templates = {
    "application/json" = jsonencode({
      "StreamName": var.kinesis_stream_name,
      "Data": "$util.base64Encode($input.json('$'))",
      "PartitionKey": "$input.path('$.sensor_id')"
    })
  }
}

# Method Response
resource "aws_api_gateway_method_response" "success" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.data_ingestion.id
  http_method = aws_api_gateway_method.post_data.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_method_response" "error" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.data_ingestion.id
  http_method = aws_api_gateway_method.post_data.http_method
  status_code = "400"

  response_models = {
    "application/json" = "Error"
  }
}

# Integration Response
resource "aws_api_gateway_integration_response" "success" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.data_ingestion.id
  http_method = aws_api_gateway_method.post_data.http_method
  status_code = aws_api_gateway_method_response.success.status_code

  response_templates = {
    "application/json" = jsonencode({
      "message": "Data ingested successfully",
      "timestamp": "$context.requestTime"
    })
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [aws_api_gateway_integration.kinesis]
}

resource "aws_api_gateway_integration_response" "error" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.data_ingestion.id
  http_method = aws_api_gateway_method.post_data.http_method
  status_code = aws_api_gateway_method_response.error.status_code

  selection_pattern = "4\\d{2}"

  response_templates = {
    "application/json" = jsonencode({
      "error": "Bad Request",
      "message": "$context.error.message"
    })
  }

  depends_on = [aws_api_gateway_integration.kinesis]
}

# CORS Support
resource "aws_api_gateway_method" "options" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.data_ingestion.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.data_ingestion.id
  http_method = aws_api_gateway_method.options.http_method

  type = "MOCK"
  
  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

resource "aws_api_gateway_method_response" "options" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.data_ingestion.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.data_ingestion.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = aws_api_gateway_method_response.options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_integration.options]
}

# IAM Role for API Gateway to access Kinesis
resource "aws_iam_role" "api_gateway_kinesis" {
  name = "${var.project_name}-api-gateway-kinesis-${var.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "api_gateway_kinesis" {
  name = "kinesis-put-record"
  role = aws_iam_role.api_gateway_kinesis.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecords"
        ]
        Resource = "arn:aws:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/${var.kinesis_stream_name}"
      }
    ]
  })
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "main" {
  depends_on = [
    aws_api_gateway_integration.kinesis,
    aws_api_gateway_integration.options,
  ]

  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.data_ingestion.id,
      aws_api_gateway_method.post_data.id,
      aws_api_gateway_integration.kinesis.id,
      aws_api_gateway_method.options.id,
      aws_api_gateway_integration.options.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Stage
resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "v1"

  xray_tracing_enabled = true

  tags = var.tags
}


