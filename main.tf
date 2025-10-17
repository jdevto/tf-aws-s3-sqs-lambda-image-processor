# =============================================================================
# DATA SOURCES
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# LAMBDA DEPLOYMENT PACKAGES
# =============================================================================

data "archive_file" "image_processor_zip" {
  type        = "zip"
  source_dir  = "lambda/image-processor"
  output_path = "lambda/image-processor/handler.zip"
}

# =============================================================================
# LAMBDA LAYERS
# =============================================================================

# Download layer ZIP from URL
data "http" "layer_zip" {
  url = var.layer_zip_url
  request_headers = {
    Accept = "application/octet-stream"
  }
}

# Save downloaded ZIP to local file
resource "local_file" "downloaded_zip" {
  filename       = "${path.module}/lambda/pillow_layer.zip"
  content_base64 = data.http.layer_zip.response_body_base64
}

resource "aws_lambda_layer_version" "pillow_simd" {
  layer_name               = "${local.name_prefix}-pillow-simd-${random_string.log_suffix.result}"
  compatible_runtimes      = ["python3.13"]
  compatible_architectures = ["x86_64"]
  description              = "Pillow layer for image processing"
  filename                 = local_file.downloaded_zip.filename
  source_code_hash         = base64sha256(data.http.layer_zip.response_body)
}

data "archive_file" "webui_lambda_zip" {
  type        = "zip"
  source_dir  = "lambda/webui"
  output_path = "lambda/webui/handler.zip"
}

# =============================================================================
# S3 BUCKETS
# =============================================================================

# Source Bucket (for uploads)
resource "aws_s3_bucket" "source" {
  bucket        = "${local.name_prefix}-source-${random_string.bucket_suffix.result}"
  force_destroy = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-source"
  })
}

resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_cors_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "source" {
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "source" {
  bucket = aws_s3_bucket.source.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.source.arn,
          "${aws_s3_bucket.source.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.source]
}

# Destination Bucket (for processed images)
resource "aws_s3_bucket" "destination" {
  bucket        = "${local.name_prefix}-destination-${random_string.bucket_suffix.result}"
  force_destroy = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-destination"
  })
}

resource "aws_s3_bucket_versioning" "destination" {
  bucket = aws_s3_bucket.destination.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "destination" {
  bucket = aws_s3_bucket.destination.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "destination" {
  bucket = aws_s3_bucket.destination.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "destination" {
  bucket = aws_s3_bucket.destination.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.destination.arn,
          "${aws_s3_bucket.destination.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.destination]
}

# Assets Bucket (for static files like favicon)
resource "aws_s3_bucket" "assets" {
  bucket        = "${local.name_prefix}-assets-${random_string.bucket_suffix.result}"
  force_destroy = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-assets"
  })
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "assets" {
  bucket = aws_s3_bucket.assets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.assets.arn,
          "${aws_s3_bucket.assets.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid       = "AllowPublicReadAssets"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.assets.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.assets]
}

# S3 Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    id     = "delete_old_objects"
    status = "Enabled"

    expiration {
      days = 1 # Delete source files after 1 day
    }
  }

  rule {
    id     = "abort_incomplete_multipart_uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "destination" {
  bucket = aws_s3_bucket.destination.id

  rule {
    id     = "delete_old_objects"
    status = "Enabled"

    expiration {
      days = 7 # Delete processed files after 7 days
    }
  }

  rule {
    id     = "abort_incomplete_multipart_uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# =============================================================================
# SQS QUEUES
# =============================================================================

resource "aws_sqs_queue" "dlq" {
  name                      = "${local.name_prefix}-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-dlq"
  })
}

resource "aws_sqs_queue" "main" {
  name                       = "${local.name_prefix}-queue"
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = 1209600 # 14 days

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.sqs_max_receives
  })

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-queue"
  })
}

resource "aws_sqs_queue_policy" "s3_to_sqs" {
  queue_url = aws_sqs_queue.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.main.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.source.arn
          }
        }
      }
    ]
  })
}

# =============================================================================
# DYNAMODB
# =============================================================================

resource "aws_dynamodb_table" "tracking" {
  name         = "${local.name_prefix}-tracking"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  lifecycle {
    prevent_destroy = false
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-tracking"
  })
}

# =============================================================================
# IAM ROLES AND POLICIES
# =============================================================================

# Image Processor Lambda Role
resource "aws_iam_role" "lambda_role" {
  name = "${local.name_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-lambda-role"
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.name_prefix}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.source.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.destination.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.tracking.arn
      }
    ]
  })
}

# Web UI Lambda Role
resource "aws_iam_role" "webui_lambda_role" {
  name = "${local.name_prefix}-webui-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-webui-lambda-role"
  })
}

resource "aws_iam_role_policy" "webui_lambda_policy" {
  name = "${local.name_prefix}-webui-lambda-policy"
  role = aws_iam_role.webui_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid    = "AllowS3ReadAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:HeadObject"
        ]
        Resource = [
          "${aws_s3_bucket.source.arn}/*",
          "${aws_s3_bucket.destination.arn}/*",
          "${aws_s3_bucket.assets.arn}/*"
        ]
      },
      {
        Sid    = "AllowS3WriteAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.source.arn}/*",
          "${aws_s3_bucket.destination.arn}/*",
          "${aws_s3_bucket.assets.arn}/*"
        ]
      },
      {
        Sid    = "AllowDynamoDBReadAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.tracking.arn
      },
      {
        Sid    = "AllowDynamoDBWriteAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.tracking.arn
      }
    ]
  })
}

# API Gateway CloudWatch Logs Role
resource "aws_iam_role" "api_gateway_logs_role" {
  name = "${local.name_prefix}-api-gateway-logs-role"

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

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-api-gateway-logs-role"
  })
}

resource "aws_iam_role_policy" "api_gateway_logs_policy" {
  name = "${local.name_prefix}-api-gateway-logs-policy"
  role = aws_iam_role.api_gateway_logs_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowWriteToCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          aws_cloudwatch_log_group.api_gateway_access_logs.arn,
          aws_cloudwatch_log_group.api_gateway_execution_logs.arn,
          "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/apigateway/*",
          "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:API-Gateway-Execution-Logs_*"
        ]
      },
      {
        Sid    = "AllowDescribeLogGroups"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:*"
      }
    ]
  })
}

# =============================================================================
# LAMBDA FUNCTIONS
# =============================================================================

resource "aws_lambda_function" "image_processor" {
  filename         = "lambda/image-processor/handler.zip"
  function_name    = "${local.name_prefix}-image-processor-${random_string.log_suffix.result}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.handler"
  runtime          = "python3.13"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  source_code_hash = data.archive_file.image_processor_zip.output_base64sha256

  layers = [aws_lambda_layer_version.pillow_simd.arn]

  environment {
    variables = local.lambda_env_vars
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-image-processor-${random_string.log_suffix.result}"
  })

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs,
    aws_lambda_layer_version.pillow_simd
  ]
}

resource "aws_lambda_function" "webui" {
  filename         = "lambda/webui/handler.zip"
  function_name    = "${local.name_prefix}-webui-${random_string.log_suffix.result}"
  role             = aws_iam_role.webui_lambda_role.arn
  handler          = "handler.handler"
  runtime          = "python3.13"
  timeout          = 30
  memory_size      = 256
  source_code_hash = data.archive_file.webui_lambda_zip.output_base64sha256

  environment {
    variables = {
      SOURCE_BUCKET      = aws_s3_bucket.source.bucket
      DESTINATION_BUCKET = aws_s3_bucket.destination.bucket
      ASSETS_BUCKET      = aws_s3_bucket.assets.bucket
      TRACKING_TABLE     = aws_dynamodb_table.tracking.name
      REGION             = data.aws_region.current.region
    }
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-webui-${random_string.log_suffix.result}"
  })

  depends_on = [
    aws_iam_role_policy.webui_lambda_policy,
    aws_cloudwatch_log_group.webui_logs
  ]
}

# Lambda Event Source Mapping
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.main.arn
  function_name    = aws_lambda_function.image_processor.arn
  batch_size       = var.sqs_batch_size
}

# Lambda Permission for API Gateway
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webui.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.webui_api.execution_arn}/*/*"
}

# =============================================================================
# API GATEWAY
# =============================================================================

resource "aws_api_gateway_rest_api" "webui_api" {
  name        = "${local.name_prefix}-webui-api"
  description = "API Gateway for Image Processor Web UI"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-webui-api"
  })
}

# API Gateway Resources
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.webui_api.id
  parent_id   = aws_api_gateway_rest_api.webui_api.root_resource_id
  path_part   = "{proxy+}"
}


# API Gateway Methods
resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = aws_api_gateway_rest_api.webui_api.id
  resource_id   = aws_api_gateway_rest_api.webui_api.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.webui_api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

# CORS Methods
resource "aws_api_gateway_method" "options_root" {
  rest_api_id   = aws_api_gateway_rest_api.webui_api.id
  resource_id   = aws_api_gateway_rest_api.webui_api.root_resource_id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "options_proxy" {
  rest_api_id   = aws_api_gateway_rest_api.webui_api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}


# API Gateway Integrations
resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = aws_api_gateway_rest_api.webui_api.id
  resource_id = aws_api_gateway_rest_api.webui_api.root_resource_id
  http_method = aws_api_gateway_method.proxy_root.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.webui.invoke_arn
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.webui_api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.webui.invoke_arn
}

resource "aws_api_gateway_integration" "options_root" {
  rest_api_id = aws_api_gateway_rest_api.webui_api.id
  resource_id = aws_api_gateway_rest_api.webui_api.root_resource_id
  http_method = aws_api_gateway_method.options_root.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_integration" "options_proxy" {
  rest_api_id = aws_api_gateway_rest_api.webui_api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.options_proxy.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# API Gateway Method Responses
resource "aws_api_gateway_method_response" "options_root" {
  rest_api_id = aws_api_gateway_rest_api.webui_api.id
  resource_id = aws_api_gateway_rest_api.webui_api.root_resource_id
  http_method = aws_api_gateway_method.options_root.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_method_response" "options_proxy" {
  rest_api_id = aws_api_gateway_rest_api.webui_api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.options_proxy.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# API Gateway Integration Responses
resource "aws_api_gateway_integration_response" "options_root" {
  rest_api_id = aws_api_gateway_rest_api.webui_api.id
  resource_id = aws_api_gateway_rest_api.webui_api.root_resource_id
  http_method = aws_api_gateway_method.options_root.http_method
  status_code = aws_api_gateway_method_response.options_root.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_integration_response" "options_proxy" {
  rest_api_id = aws_api_gateway_rest_api.webui_api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.options_proxy.http_method
  status_code = aws_api_gateway_method_response.options_proxy.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "webui_deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_root,
    aws_api_gateway_integration.lambda,
    aws_api_gateway_integration.options_root,
    aws_api_gateway_integration.options_proxy,
    aws_api_gateway_integration_response.options_root,
    aws_api_gateway_integration_response.options_proxy,
    aws_lambda_permission.api_gw
  ]

  rest_api_id = aws_api_gateway_rest_api.webui_api.id


  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Account (required for execution logging)
resource "aws_api_gateway_account" "webui_account" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_logs_role.arn

  depends_on = [aws_cloudwatch_log_group.api_gateway_execution_logs]
}

# API Gateway Stage
resource "aws_api_gateway_stage" "webui_stage" {
  deployment_id = aws_api_gateway_deployment.webui_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.webui_api.id
  stage_name    = "prod"

  # Enable CloudWatch logging
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_access_logs.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      ip                 = "$context.identity.sourceIp"
      caller             = "$context.identity.caller"
      user               = "$context.identity.user"
      requestTime        = "$context.requestTime"
      httpMethod         = "$context.httpMethod"
      resourcePath       = "$context.resourcePath"
      status             = "$context.status"
      protocol           = "$context.protocol"
      responseLength     = "$context.responseLength"
      userAgent          = "$context.identity.userAgent"
      requestTimeEpoch   = "$context.requestTimeEpoch"
      integrationLatency = "$context.integration.latency"
      responseLatency    = "$context.responseLatency"
      errorMessage       = "$context.error.message"
      errorMessageString = "$context.error.messageString"
      requestHeaders     = "$context.request.headers"
      responseHeaders    = "$context.response.headers"
    })
  }

  # Enable X-Ray tracing
  xray_tracing_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-webui-stage"
  })

  depends_on = [
    aws_cloudwatch_log_group.api_gateway_access_logs,
    aws_cloudwatch_log_group.api_gateway_execution_logs,
    aws_iam_role.api_gateway_logs_role,
    aws_api_gateway_account.webui_account
  ]
}

# API Gateway Method Settings
resource "aws_api_gateway_method_settings" "webui_logging" {
  rest_api_id = aws_api_gateway_rest_api.webui_api.id
  stage_name  = aws_api_gateway_stage.webui_stage.stage_name
  method_path = "*/*"

  settings {
    logging_level      = "INFO"
    data_trace_enabled = true
    metrics_enabled    = true
  }
}

# =============================================================================
# CLOUDWATCH LOG GROUPS
# =============================================================================

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-image-processor-${random_string.log_suffix.result}"
  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-lambda-logs"
  })
}

resource "aws_cloudwatch_log_group" "webui_logs" {
  name              = "/aws/lambda/${local.name_prefix}-webui-${random_string.log_suffix.result}"
  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-webui-logs"
  })
}

resource "aws_cloudwatch_log_group" "api_gateway_access_logs" {
  name              = "/aws/apigateway/${local.name_prefix}-webui-api/access-${random_string.log_suffix.result}"
  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-api-gateway-access-logs"
  })
}

resource "aws_cloudwatch_log_group" "api_gateway_execution_logs" {
  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.webui_api.id}/prod"
  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-api-gateway-execution-logs"
  })

  depends_on = [aws_api_gateway_rest_api.webui_api]
}

# =============================================================================
# S3 ASSET UPLOADS
# =============================================================================

# Upload favicon.ico to assets bucket
resource "aws_s3_object" "favicon_ico" {
  bucket = aws_s3_bucket.assets.id
  key    = "assets/favicon.ico"
  source = "lambda/webui/assets/favicon.ico"

  content_type        = "image/x-icon"
  cache_control       = "public, max-age=86400"
  content_disposition = "inline"

  # Ensure the file exists before creating the resource
  depends_on = [aws_s3_bucket.assets]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-favicon-ico"
  })
}

# Upload favicon.png to assets bucket
resource "aws_s3_object" "favicon_png" {
  bucket = aws_s3_bucket.assets.id
  key    = "assets/favicon.png"
  source = "lambda/webui/assets/favicon.png"

  content_type        = "image/png"
  cache_control       = "public, max-age=86400"
  content_disposition = "inline"

  # Ensure the file exists before creating the resource
  depends_on = [aws_s3_bucket.assets]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-favicon-png"
  })
}

# =============================================================================
# S3 EVENT NOTIFICATIONS
# =============================================================================

resource "aws_s3_bucket_notification" "source_notification" {
  bucket = aws_s3_bucket.source.id

  queue {
    queue_arn     = aws_sqs_queue.main.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "images/"
    filter_suffix = ".jpg"
  }

  queue {
    queue_arn     = aws_sqs_queue.main.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "images/"
    filter_suffix = ".jpeg"
  }

  queue {
    queue_arn     = aws_sqs_queue.main.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "images/"
    filter_suffix = ".png"
  }

  queue {
    queue_arn     = aws_sqs_queue.main.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "images/"
    filter_suffix = ".gif"
  }

  queue {
    queue_arn     = aws_sqs_queue.main.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "images/"
    filter_suffix = ".webp"
  }

  depends_on = [aws_sqs_queue_policy.s3_to_sqs]
}

# =============================================================================
# CLOUDWATCH ALARMS
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = var.alarm_email != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]

  dimensions = {
    FunctionName = aws_lambda_function.image_processor.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  count               = var.alarm_email != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-lambda-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = "240000" # 4 minutes
  alarm_description   = "This metric monitors lambda duration"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]

  dimensions = {
    FunctionName = aws_lambda_function.image_processor.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "sqs_queue_depth" {
  count               = var.alarm_email != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-sqs-queue-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ApproximateNumberOfVisibleMessages"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = "10"
  alarm_description   = "This metric monitors SQS queue depth"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]

  dimensions = {
    QueueName = aws_sqs_queue.main.name
  }
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  count               = var.alarm_email != "" ? 1 : 0
  alarm_name          = "${local.name_prefix}-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfVisibleMessages"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "This metric monitors DLQ messages"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }
}

# =============================================================================
# SNS ALERTS
# =============================================================================

resource "aws_sns_topic" "alerts" {
  count = var.alarm_email != "" ? 1 : 0
  name  = "${local.name_prefix}-alerts"
  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alerts"
  })
}

resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "assets_bucket_name" {
  description = "Name of the S3 assets bucket"
  value       = aws_s3_bucket.assets.bucket
}

output "favicon_ico_url" {
  description = "URL of the favicon.ico file"
  value       = "https://${aws_s3_bucket.assets.bucket_domain_name}/assets/favicon.ico"
}

output "favicon_png_url" {
  description = "URL of the favicon.png file"
  value       = "https://${aws_s3_bucket.assets.bucket_domain_name}/assets/favicon.png"
}

output "api_gateway_access_log_group" {
  description = "CloudWatch log group for API Gateway access logs"
  value       = aws_cloudwatch_log_group.api_gateway_access_logs.name
}

output "api_gateway_execution_log_group" {
  description = "CloudWatch log group for API Gateway execution logs"
  value       = aws_cloudwatch_log_group.api_gateway_execution_logs.name
}
