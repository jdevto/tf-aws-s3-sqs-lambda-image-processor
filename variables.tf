variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "image-processor"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2"
}

# Image processing configuration
variable "max_width" {
  description = "Maximum width for processed images"
  type        = number
  default     = 1920
}

variable "max_height" {
  description = "Maximum height for processed images"
  type        = number
  default     = 1080
}

variable "image_quality" {
  description = "JPEG quality for processed images (1-100)"
  type        = number
  default     = 85
  validation {
    condition     = var.image_quality >= 1 && var.image_quality <= 100
    error_message = "Image quality must be between 1 and 100."
  }
}

# Lambda configuration
variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
}

# SQS configuration
variable "sqs_batch_size" {
  description = "SQS batch size for Lambda processing"
  type        = number
  default     = 1
}

variable "sqs_visibility_timeout" {
  description = "SQS visibility timeout in seconds"
  type        = number
  default     = 300
}

variable "sqs_max_receives" {
  description = "Maximum number of receives before moving to DLQ"
  type        = number
  default     = 3
}

# Monitoring configuration
variable "alarm_email" {
  description = "Email address for CloudWatch alarms"
  type        = string
  default     = ""
}

# Layer configuration
variable "layer_zip_url" {
  description = "Direct URL to the ZIP. Example: https://github.com/serverlessia/lambda-pillow-layer/releases/download/python3.13-v4/pillow-layer.zip"
  type        = string
  default     = "https://github.com/serverlessia/lambda-pillow-layer/releases/download/python3.13-v4/pillow-layer.zip"
}
