locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Lambda environment variables
  lambda_env_vars = {
    DESTINATION_BUCKET = aws_s3_bucket.destination.bucket
    TRACKING_TABLE     = aws_dynamodb_table.tracking.name
    MAX_WIDTH          = var.max_width
    MAX_HEIGHT         = var.max_height
    IMAGE_QUALITY      = var.image_quality
  }
}

# Random string for unique bucket names
resource "random_string" "bucket_suffix" {
  length  = 4
  special = false
  upper   = false
}

# Random string for unique log group names
resource "random_string" "log_suffix" {
  length  = 4
  special = false
  upper   = false
}
