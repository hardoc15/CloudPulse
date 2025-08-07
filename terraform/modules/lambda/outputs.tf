output "function_names" {
  description = "Names of the Lambda functions"
  value = {
    data_processor    = aws_lambda_function.data_processor.function_name
    data_transformer  = aws_lambda_function.data_transformer.function_name
  }
}

output "function_arns" {
  description = "ARNs of the Lambda functions"
  value = {
    data_processor    = aws_lambda_function.data_processor.arn
    data_transformer  = aws_lambda_function.data_transformer.arn
  }
}
