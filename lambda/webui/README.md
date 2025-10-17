# Web UI Lambda Function

This Lambda function provides a web interface for the image processor, including file upload, processing status checking, and secure download link generation.

## Functionality

- Serves a responsive web UI for image upload
- Generates presigned URLs for direct S3 upload
- Tracks upload and processing status in DynamoDB
- Creates one-time download links for processed images
- Provides real-time status updates

## Dependencies

- **boto3**: AWS SDK for Python

## Environment Variables

- `SOURCE_BUCKET`: Name of the source S3 bucket
- `DESTINATION_BUCKET`: Name of the destination S3 bucket
- `TRACKING_TABLE`: Name of the DynamoDB table for tracking

## Function Details

- **File**: `handler.py`
- **Function**: `handler(event, context)`
- **Handler**: `handler.handler`
- **Runtime**: Python 3.13

## API Endpoints

### GET /

Serves the main web UI HTML page.

### POST /upload-url

Generates a presigned URL for direct S3 upload.
**Request Body:**

```json
{
  "filename": "image.jpg"
}
```

**Response:**

```json
{
  "upload_url": "https://...",
  "file_id": "uuid",
  "filename": "image.jpg"
}
```

### POST /check-status

Checks if an image has been processed.
**Request Body:**

```json
{
  "file_id": "uuid"
}
```

**Response:**

```json
{
  "status": "processed|processing",
  "download_url": "/download/token",
  "filename": "image.jpg"
}
```

### GET /download/{token}

Redirects to a presigned URL for downloading the processed image.

- One-time use token
- 1-hour expiration
- Automatically invalidates after use

## Security Features

- File type validation (JPG, JPEG, PNG only)
- One-time download links with expiration
- Automatic token invalidation after use
- CORS headers for web browser compatibility

## DynamoDB Schema

The function uses a DynamoDB table with the following schema:

- `id` (String): Unique file identifier
- `filename` (String): Original filename
- `s3_key` (String): S3 object key
- `status` (String): Processing status
- `created_at` (Number): Unix timestamp
- `expires_at` (Number): TTL timestamp
- `download_token` (String): One-time download token
- `download_expires` (Number): Download token expiration
