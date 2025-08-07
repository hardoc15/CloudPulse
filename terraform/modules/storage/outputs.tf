output "table_names" {
  description = "Names of DynamoDB tables"
  value = {
    metadata = aws_dynamodb_table.metadata.name
    sensors  = aws_dynamodb_table.sensors.name
    metrics  = aws_dynamodb_table.metrics.name
  }
}

output "table_arns" {
  description = "ARNs of DynamoDB tables"
  value = {
    metadata = aws_dynamodb_table.metadata.arn
    sensors  = aws_dynamodb_table.sensors.arn
    metrics  = aws_dynamodb_table.metrics.arn
  }
}
