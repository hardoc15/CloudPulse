variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "name_suffix" {
  description = "Suffix for resource names"
  type        = string
}

variable "kinesis_stream_arn" {
  description = "ARN of the Kinesis data stream"
  type        = string
}

variable "s3_bucket" {
  description = "S3 bucket for data storage"
  type        = string
}

variable "memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
