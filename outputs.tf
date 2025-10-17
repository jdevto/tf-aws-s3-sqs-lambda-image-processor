output "source_bucket_name" {
  description = "Name of the source S3 bucket"
  value       = aws_s3_bucket.source.bucket
}

output "destination_bucket_name" {
  description = "Name of the destination S3 bucket"
  value       = aws_s3_bucket.destination.bucket
}

output "source_bucket_arn" {
  description = "ARN of the source S3 bucket"
  value       = aws_s3_bucket.source.arn
}

output "destination_bucket_arn" {
  description = "ARN of the destination S3 bucket"
  value       = aws_s3_bucket.destination.arn
}

output "sqs_queue_url" {
  description = "URL of the main SQS queue"
  value       = aws_sqs_queue.main.url
}

output "sqs_queue_arn" {
  description = "ARN of the main SQS queue"
  value       = aws_sqs_queue.main.arn
}

output "dlq_url" {
  description = "URL of the dead letter queue"
  value       = aws_sqs_queue.dlq.url
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.image_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.image_processor.arn
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = var.alarm_email != "" ? aws_sns_topic.alerts[0].arn : null
}

output "web_ui_url" {
  description = "URL of the web UI for image upload and download"
  value       = "https://${aws_api_gateway_rest_api.webui_api.id}.execute-api.${var.region}.amazonaws.com/prod/"
}

output "api_gateway_id" {
  description = "ID of the API Gateway"
  value       = aws_api_gateway_rest_api.webui_api.id
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB tracking table"
  value       = aws_dynamodb_table.tracking.name
}

output "deployment_instructions" {
  description = "Instructions for testing the deployment"
  value       = <<-EOT
    To test the image processor:

    WEB UI (Recommended):
    1. Open the web UI in your browser:
       https://${aws_api_gateway_rest_api.webui_api.id}.execute-api.${var.region}.amazonaws.com/prod/

    2. Upload an image using the web interface
    3. Wait for processing and download the processed image

    COMMAND LINE TESTING:
    1. Upload an image to the source bucket:
       aws s3 cp your-image.jpg s3://${aws_s3_bucket.source.bucket}/images/

    2. Check the destination bucket for processed image:
       aws s3 ls s3://${aws_s3_bucket.destination.bucket}/images/

    3. Monitor Lambda logs:
       aws logs tail /aws/lambda/${aws_lambda_function.image_processor.function_name} --follow

    4. Check SQS queue status:
       aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.main.url} --attribute-names All
  EOT
}
