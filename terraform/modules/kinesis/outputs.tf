output "stream_name" {
  description = "Name of the Kinesis data stream"
  value       = aws_kinesis_stream.main.name
}

output "stream_arn" {
  description = "ARN of the Kinesis data stream"
  value       = aws_kinesis_stream.main.arn
}

output "analytics_application_name" {
  description = "Name of the Kinesis Analytics application"
  value       = aws_kinesisanalyticsv2_application.analytics.name
}
