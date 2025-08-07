data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# Data Processor Lambda Function
resource "aws_lambda_function" "data_processor" {
  filename         = data.archive_file.data_processor.output_path
  function_name    = "${var.project_name}-data-processor-${var.name_suffix}"
  role            = aws_iam_role.data_processor.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.data_processor.output_base64sha256
  runtime         = "python3.9"
  timeout         = 30
  memory_size     = 256

  environment {
    variables = {
      S3_BUCKET = var.s3_bucket
      LOG_LEVEL = "INFO"
    }
  }

  tags = var.tags
}

# Data Transformer Lambda Function
resource "aws_lambda_function" "data_transformer" {
  filename         = data.archive_file.data_transformer.output_path
  function_name    = "${var.project_name}-data-transformer-${var.name_suffix}"
  role            = aws_iam_role.data_transformer.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.data_transformer.output_base64sha256
  runtime         = "python3.9"
  timeout         = 30
  memory_size     = 256

  environment {
    variables = {
      S3_BUCKET = var.s3_bucket
      LOG_LEVEL = "INFO"
    }
  }

  tags = var.tags
}

# Event Source Mapping for Kinesis Stream
resource "aws_lambda_event_source_mapping" "kinesis_processor" {
  event_source_arn  = var.kinesis_stream_arn
  function_name     = aws_lambda_function.data_processor.arn
  starting_position = "LATEST"
  batch_size        = 100
  parallelization_factor = 10

  depends_on = [aws_iam_role_policy.data_processor_kinesis]
}

# IAM Roles
resource "aws_iam_role" "data_processor" {
  name               = "${var.project_name}-data-processor-role-${var.name_suffix}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role" "data_transformer" {
  name               = "${var.project_name}-data-transformer-role-${var.name_suffix}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

# IAM Policy Attachments
resource "aws_iam_role_policy_attachment" "data_processor_basic" {
  role       = aws_iam_role.data_processor.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "data_transformer_basic" {
  role       = aws_iam_role.data_transformer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Kinesis access policy
resource "aws_iam_role_policy" "data_processor_kinesis" {
  name = "kinesis-access"
  role = aws_iam_role.data_processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListStreams"
        ]
        Resource = var.kinesis_stream_arn
      }
    ]
  })
}

# Kinesis policy is attached directly as inline policy
# No separate attachment needed

# S3 access policy
resource "aws_iam_role_policy" "s3_access" {
  name = "s3-access"
  role = aws_iam_role.data_processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${var.s3_bucket}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::${var.s3_bucket}"
      }
    ]
  })
}

# Lambda Function Archives
data "archive_file" "data_processor" {
  type        = "zip"
  output_path = "/tmp/data_processor.zip"
  source {
    content = file("${path.module}/../../../src/lambda-functions/data-processor/lambda_function.py")
    filename = "lambda_function.py"
  }
}

data "archive_file" "data_transformer" {
  type        = "zip"
  output_path = "/tmp/data_transformer.zip"
  source {
    content = file("${path.module}/../../../src/lambda-functions/data-transformer/lambda_function.py")
    filename = "lambda_function.py"
  }
}
