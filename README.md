# AWS S3-SQS-Lambda Image Processor

A serverless image processing pipeline that automatically compresses and resizes images uploaded to an S3 bucket using AWS Lambda, SQS, and CloudWatch.

## Architecture

```plaintext
S3 Source Bucket → Event Notification → SQS Queue → Lambda Processor → S3 Destination Bucket
                                                      ↓                    ↓
                                                 SQS DLQ (on failure)  DynamoDB (tracking)
                                                      ↓
                                                 Web UI (download links)
```

## Features

- **Web UI**: Beautiful, responsive web interface for easy image upload and download
- **One-Time Download Links**: Secure, time-limited download links for processed images
- **Automatic Processing**: Images are processed automatically when uploaded to the source bucket
- **Format Support**: Supports JPG, JPEG, PNG, GIF, and WebP images
- **Configurable**: Adjustable image dimensions, quality, and processing parameters
- **Reliable**: Uses SQS for message queuing with dead letter queue for failed messages
- **Secure**: All buckets require TLS, block public access, and use server-side encryption
- **Monitored**: CloudWatch alarms for errors, duration, and queue depth
- **Cost-Optimized**: Configurable lifecycle policies and efficient resource usage
- **Lambda Layers**: Uses pre-built Pillow layer for fast image processing
- **Tracking**: DynamoDB table for tracking processing status and generating secure download links

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- Python 3.11+ (for local testing)

## Lambda Layer Configuration

This project uses a pre-built Pillow layer for fast image processing. The layer is automatically downloaded from a public repository during deployment:

- **Default Layer**: `https://github.com/serverlessia/lambda-pillow-layer/releases/download/python3.13-v4/pillow-layer.zip`
- **Runtime**: Python 3.13
- **Architecture**: x86_64
- **Custom Layer**: You can specify a different layer URL using the `layer_zip_url` variable

The layer includes optimized Pillow libraries for efficient image processing in AWS Lambda.

## Deployment

1. **Clone and navigate to the repository**:

   ```bash
   git clone <repository-url>
   cd tf-aws-s3-sqs-lambda-image-processor
   ```

2. **Initialize Terraform**:

   ```bash
   terraform init
   ```

3. **Review and customize variables** (optional):

   ```bash
   # Edit terraform.tfvars or set environment variables
   export TF_VAR_alarm_email="your-email@example.com"
   export TF_VAR_max_width=1920
   export TF_VAR_max_height=1080
   export TF_VAR_image_quality=85
   export TF_VAR_layer_zip_url="https://github.com/serverlessia/lambda-pillow-layer/releases/download/python3.13-v4/pillow-layer.zip"
   ```

4. **Plan the deployment**:

   ```bash
   terraform plan
   ```

5. **Deploy the infrastructure**:

   ```bash
   terraform apply
   ```

6. **Note the outputs** for testing:

   ```bash
   terraform output
   ```

## Configuration Variables

| Variable | Description | Default | Type |
|----------|-------------|---------|------|
| `project_name` | Name of the project | `image-processor` | string |
| `environment` | Environment name | `dev` | string |
| `region` | AWS region | `ap-southeast-2` | string |
| `max_width` | Maximum width for processed images | `1920` | number |
| `max_height` | Maximum height for processed images | `1080` | number |
| `image_quality` | JPEG quality (1-100) | `85` | number |
| `lambda_memory_size` | Lambda memory size in MB | `512` | number |
| `lambda_timeout` | Lambda timeout in seconds | `300` | number |
| `sqs_batch_size` | SQS batch size for Lambda | `1` | number |
| `sqs_visibility_timeout` | SQS visibility timeout | `300` | number |
| `sqs_max_receives` | Max receives before DLQ | `3` | number |
| `alarm_email` | Email for CloudWatch alarms | `""` | string |
| `layer_zip_url` | URL to Pillow layer ZIP file | `https://github.com/serverlessia/lambda-pillow-layer/releases/download/python3.13-v4/pillow-layer.zip` | string |

## Testing

### 1. Web UI (Recommended)

The easiest way to test the image processor is through the web interface:

1. **Get the Web UI URL**:

   ```bash
   terraform output web_ui_url
   ```

2. **Open the URL in your browser** and upload an image using the drag-and-drop interface

3. **Wait for processing** - the UI will show real-time status updates

4. **Download the processed image** using the one-time download link

### 2. Command Line Testing

Upload images directly to the source bucket:

```bash
# Get the source bucket name from Terraform output
SOURCE_BUCKET=$(terraform output -raw source_bucket_name)

# Upload test images
aws s3 cp test-image.jpg s3://$SOURCE_BUCKET/images/
aws s3 cp test-image.png s3://$SOURCE_BUCKET/images/
aws s3 cp test-image.gif s3://$SOURCE_BUCKET/images/
aws s3 cp test-image.webp s3://$SOURCE_BUCKET/images/
```

### 2. Monitor Processing

**Check Lambda logs**:

```bash
LAMBDA_FUNCTION=$(terraform output -raw lambda_function_name)
aws logs tail /aws/lambda/$LAMBDA_FUNCTION --follow
```

**Check SQS queue status**:

```bash
QUEUE_URL=$(terraform output -raw sqs_queue_url)
aws sqs get-queue-attributes --queue-url $QUEUE_URL --attribute-names All
```

**Check destination bucket**:

```bash
DEST_BUCKET=$(terraform output -raw destination_bucket_name)
aws s3 ls s3://$DEST_BUCKET/images/
```

### 3. Verify Processing

Check that processed images:

- Are stored in the destination bucket
- Have `processed=true` metadata
- Are resized according to configuration
- Maintain aspect ratio

```bash
# List objects with metadata
aws s3api list-objects-v2 --bucket $DEST_BUCKET --prefix images/

# Get object metadata
aws s3api head-object --bucket $DEST_BUCKET --key images/test-image.jpg
```

## Monitoring

### CloudWatch Alarms

The following alarms are created (if `alarm_email` is provided):

- **Lambda Errors**: Triggers when Lambda function encounters errors
- **Lambda Duration**: Triggers when function takes longer than 4 minutes
- **SQS Queue Depth**: Triggers when queue has more than 10 messages
- **DLQ Messages**: Triggers when any messages are in the dead letter queue

### Logs

- Lambda logs: `/aws/lambda/{function-name}`
- API Gateway logs: `/aws/apigateway/{api-name}/`
- Retention: 1 day (configurable)
- Log level: INFO and above

## Security

- **S3 Buckets**: Block all public access, require TLS
- **Encryption**: Server-side encryption (SSE-S3) for all objects
- **IAM**: Least-privilege access for Lambda function
- **VPC**: Not required (Lambda runs in AWS managed VPC)

## Cost Optimization

- **Lifecycle Policies**: Optional automatic deletion of old objects
- **Lambda Memory**: Configurable based on image processing needs
- **SQS Visibility Timeout**: Tuned to processing time
- **Log Retention**: 1 day (configurable)

## Troubleshooting

### Common Issues

1. **Images not processing**:
   - Check S3 event notifications are enabled
   - Verify SQS queue permissions
   - Check Lambda function logs

2. **Lambda timeouts**:
   - Increase `lambda_timeout` variable
   - Increase `lambda_memory_size` for faster processing

3. **Permission errors**:
   - Verify IAM role has required S3 and SQS permissions
   - Check bucket policies

4. **Images in DLQ**:
   - Check Lambda logs for processing errors
   - Verify image format is supported (JPG, JPEG, PNG, GIF, WebP)

### Debug Commands

```bash
# Check Lambda function status
aws lambda get-function --function-name $(terraform output -raw lambda_function_name)

# Check SQS queue metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS \
  --metric-name ApproximateNumberOfVisibleMessages \
  --dimensions Name=QueueName,Value=$(terraform output -raw sqs_queue_url | cut -d'/' -f4) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Note**: This will delete all data in the S3 buckets. Ensure you have backups if needed.

## Development

### Project Structure

```plaintext
tf-aws-s3-sqs-lambda-image-processor/
├── lambda/                          # Lambda functions
│   ├── image-processor/             # Image processing Lambda
│   │   ├── lambda_function.py       # Main function code
│   │   ├── requirements.txt         # Dependencies
│   │   └── README.md               # Function docs
│   ├── webui/                      # Web UI Lambda
│   │   ├── webui_lambda.py         # Main function code
│   │   ├── requirements.txt        # Dependencies
│   │   ├── assets/                 # Static assets (favicon, etc.)
│   │   └── README.md              # Function docs
│   └── README.md                   # Lambda functions overview
├── layers/                         # Lambda layers (legacy)
│   └── pillow-simd/               # Local Pillow layer build
├── main.tf                         # Main Terraform configuration
├── variables.tf                    # Terraform variables
├── outputs.tf                      # Terraform outputs
├── locals.tf                       # Terraform locals
├── versions.tf                     # Provider versions
├── .gitignore                      # Git ignore rules
├── LAYER_BUILD_PLAN.md            # Layer build documentation
└── README.md                       # This file
```

### Local Testing

For local development and testing:

```bash
# Test image processor Lambda
cd lambda/image-processor
pip install -r requirements.txt
python lambda_function.py

# Test web UI Lambda
cd lambda/webui
pip install -r requirements.txt
python webui_lambda.py
```

### Adding New Image Formats

To support additional image formats:

1. Update the S3 event notification filters in `main.tf` (lines 1024-1063)
2. Modify the image processing logic in `lambda/image-processor/lambda_function.py`
3. Update the PIL image conversion logic as needed
4. Test with the new format using the web UI or command line

## License

This project is licensed under the MIT License - see the LICENSE file for details.
