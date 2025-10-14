# Image Processor Lambda Function

This Lambda function processes images uploaded to the S3 source bucket. It automatically compresses and resizes images according to the configured parameters.

## Functionality

- Downloads images from the S3 source bucket
- Resizes images while maintaining aspect ratio (max 1920x1080)
- Compresses images with 85% JPEG quality
- Uploads processed images to the S3 destination bucket
- Updates processing status in DynamoDB
- Handles errors gracefully and updates status accordingly

## Dependencies

- **boto3**: AWS SDK for Python
- **Pillow (PIL)**: Image processing library for Python

## Environment Variables

- `DESTINATION_BUCKET`: Name of the destination S3 bucket
- `TRACKING_TABLE`: Name of the DynamoDB table for tracking processing status

## Function Details

- **File**: `handler.py`
- **Function**: `handler(event, context)`
- **Handler**: `handler.handler`
- **Runtime**: Python 3.13

## Input

The function is triggered by SQS events containing S3 object information. It processes images with the following extensions:

- `.jpg`
- `.jpeg`
- `.png`

## Output

Processed images are stored in the destination bucket with:

- Same filename and path structure as the original
- Resized dimensions (max 1920x1080, maintaining aspect ratio)
- Compressed with 85% JPEG quality
- Metadata: `processed=true`, `processor=lambda-image-processor`, `processed_at=timestamp`

## DynamoDB Integration

The function updates the tracking table with:

- `status`: 'processed' or 'error'
- `processed_at`: Unix timestamp
- `error_message`: Error details (if status is 'error')

## Error Handling

- Logs all errors to CloudWatch
- Updates DynamoDB status to 'error' on failure
- Continues processing other records in batch
- Idempotent processing for safe replays

## File ID Extraction

The function extracts the file ID from the S3 object key:

- Expected format: `images/{file_id}_{filename}`
- Falls back to using the full object key if format doesn't match
