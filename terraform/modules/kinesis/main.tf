resource "aws_kinesis_stream" "main" {
  name             = var.stream_name
  shard_count      = var.shard_count
  retention_period = var.retention_period

  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords",
  ]

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = var.tags
}

# Aggregated data stream for analytics output
resource "aws_kinesis_stream" "aggregated" {
  name             = "${var.stream_name}-aggregated"
  shard_count      = 1
  retention_period = 24

  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords",
  ]

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = var.tags
}

# S3 bucket for Kinesis Analytics code
resource "aws_s3_bucket" "analytics_code" {
  bucket = "${var.stream_name}-analytics-code"
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "analytics_code" {
  bucket = aws_s3_bucket.analytics_code.id
  versioning_configuration {
    status = "Enabled"
  }
}



# Kinesis Analytics Application for real-time processing
resource "aws_kinesisanalyticsv2_application" "analytics" {
  name                   = "${var.stream_name}-analytics"
  runtime_environment    = "SQL-1_0"
  service_execution_role = aws_iam_role.analytics.arn

  application_configuration {
    application_code_configuration {
      code_content {
        text_content = local.flink_sql_code
      }
      code_content_type = "PLAINTEXT"
    }

    sql_application_configuration {
      input {
        name_prefix = "SOURCE_SQL_STREAM"
        input_schema {
          record_format {
            record_format_type = "JSON"
            mapping_parameters {
              json_mapping_parameters {
                record_row_path = "$"
              }
            }
          }
          record_column {
            mapping  = "$.timestamp"
            name     = "event_timestamp"
            sql_type = "TIMESTAMP"
          }
          record_column {
            mapping  = "$.sensor_id"
            name     = "sensor_id"
            sql_type = "VARCHAR(50)"
          }
          record_column {
            mapping  = "$.temperature"
            name     = "temperature"
            sql_type = "DOUBLE"
          }
          record_column {
            mapping  = "$.humidity"
            name     = "humidity"
            sql_type = "DOUBLE"
          }
          record_column {
            mapping  = "$.location"
            name     = "location"
            sql_type = "VARCHAR(100)"
          }
        }
        kinesis_streams_input {
          resource_arn = aws_kinesis_stream.main.arn
        }
      }

      output {
        name = "DESTINATION_SQL_STREAM"
        destination_schema {
          record_format_type = "JSON"
        }
        kinesis_streams_output {
          resource_arn = aws_kinesis_stream.aggregated.arn
        }
      }


    }
  }

  tags = var.tags
}

# IAM role for Kinesis Analytics
resource "aws_iam_role" "analytics" {
  name = "${var.stream_name}-analytics-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "kinesisanalytics.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "analytics" {
  name = "${var.stream_name}-analytics-policy"
  role = aws_iam_role.analytics.id

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
        Resource = aws_kinesis_stream.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecords"
        ]
        Resource = aws_kinesis_stream.aggregated.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "${aws_s3_bucket.analytics_code.arn}/*"
      }
    ]
  })
}







locals {
  flink_sql_code = <<-EOT
    CREATE OR REPLACE STREAM "SENSOR_DATA_STREAM" (
      "event_timestamp" TIMESTAMP,
      "sensor_id" VARCHAR(50),
      "temperature" DOUBLE,
      "humidity" DOUBLE,
      "location" VARCHAR(100)
    );

    CREATE OR REPLACE STREAM "AGGREGATED_DATA_STREAM" (
      "window_start" TIMESTAMP,
      "window_end" TIMESTAMP,
      "sensor_id" VARCHAR(50),
      "avg_temperature" DOUBLE,
      "avg_humidity" DOUBLE,
      "record_count" INTEGER
    );

    INSERT INTO "AGGREGATED_DATA_STREAM"
    SELECT 
      STEP("SENSOR_DATA_STREAM"."ROWTIME" BY INTERVAL '1' MINUTE) as "window_start",
      STEP("SENSOR_DATA_STREAM"."ROWTIME" BY INTERVAL '1' MINUTE) + INTERVAL '1' MINUTE as "window_end",
      "SENSOR_DATA_STREAM"."sensor_id",
      AVG("SENSOR_DATA_STREAM"."temperature") as "avg_temperature",
      AVG("SENSOR_DATA_STREAM"."humidity") as "avg_humidity",
      COUNT(*) as "record_count"
    FROM "SENSOR_DATA_STREAM"
    GROUP BY 
      "SENSOR_DATA_STREAM"."sensor_id",
      STEP("SENSOR_DATA_STREAM"."ROWTIME" BY INTERVAL '1' MINUTE);
  EOT
}

data "aws_region" "current" {}
