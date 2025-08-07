variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "name_suffix" {
  description = "Suffix for resource names"
  type        = string
}

variable "kinesis_stream_name" {
  description = "Name of the Kinesis data stream"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
