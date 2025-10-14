"""
Image Processor Lambda Function with Layer Support

This Lambda function processes images uploaded to the S3 source bucket.
It automatically compresses and resizes images according to the configured parameters.
Uses Pillow from a Lambda layer instead of bundled dependencies.
"""

import json
import boto3
import os
import time
import io
from urllib.parse import unquote_plus
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def handler(event, context):
    """
    Lambda function to process images from S3 and store them in destination bucket.

    Args:
        event: SQS event containing S3 object information
        context: Lambda context object

    Returns:
        dict: Response with status code and message
    """
    try:
        logger.info(f"Processing SQS event: {json.dumps(event, default=str)}")

        # Process each record in the SQS batch
        for record in event['Records']:
            try:
                # Parse SQS message body (which contains S3 event)
                message_body = json.loads(record['body'])
                logger.info(f"Processing message: {message_body}")

                # Handle S3 event notification
                if 'Records' in message_body:
                    for s3_record in message_body['Records']:
                        process_s3_object(s3_record)
                else:
                    # Direct S3 event (if not wrapped in SQS)
                    process_s3_object(message_body)

            except Exception as e:
                logger.error(f"Error processing record: {str(e)}")
                # Continue processing other records
                continue

        return {
            'statusCode': 200,
            'body': json.dumps('Images processed successfully')
        }

    except Exception as e:
        logger.error(f"Error processing images: {str(e)}")
        raise e

def process_s3_object(s3_record):
    """
    Process a single S3 object from the event record.

    Args:
        s3_record: S3 event record containing object information
    """
    object_key = None  # Initialize object_key for error handling
    try:
        # Check if this is a test event
        if s3_record.get('Event') == 's3:TestEvent':
            logger.info("Skipping S3 test event")
            return

        # Extract S3 object information
        bucket_name = s3_record['s3']['bucket']['name']
        object_key = unquote_plus(s3_record['s3']['object']['key'])

        logger.info(f"Processing image: s3://{bucket_name}/{object_key}")

        # Get environment variables
        destination_bucket = os.environ['DESTINATION_BUCKET']
        tracking_table = os.environ['TRACKING_TABLE']
        max_width = int(os.environ.get('MAX_WIDTH', '1920'))
        max_height = int(os.environ.get('MAX_HEIGHT', '1080'))
        image_quality = int(os.environ.get('IMAGE_QUALITY', '85'))
        max_file_size = int(os.environ.get('MAX_FILE_SIZE', '10485760'))  # 10MB in bytes

        # Download image from source bucket
        response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
        image_data = response['Body'].read()

        logger.info(f"Downloaded image, size: {len(image_data)} bytes")

        # Check file size limit
        if len(image_data) > max_file_size:
            error_msg = f"File size {len(image_data)} bytes exceeds maximum allowed size of {max_file_size} bytes (10MB)"
            logger.error(error_msg)
            update_processing_status(tracking_table, object_key, 'error', error_msg)
            return

        # Process the image
        processed_image_data, original_format = process_image(
            image_data,
            max_width,
            max_height,
            image_quality
        )

        # Upload processed image to destination bucket
        upload_processed_image(
            processed_image_data,
            destination_bucket,
            object_key,
            original_format
        )

        # Update DynamoDB status
        update_processing_status(tracking_table, object_key, 'processed')

        logger.info(f"Successfully processed: {object_key}")

    except Exception as e:
        object_info = f"object {object_key}" if object_key else "S3 object"
        logger.error(f"Error processing {object_info}: {str(e)}")
        # Update status to error in DynamoDB (only if we have object_key)
        if object_key:
            try:
                update_processing_status(os.environ['TRACKING_TABLE'], object_key, 'error', str(e))
            except:
                pass  # Don't fail if we can't update status
        raise e

def process_image(image_data, max_width, max_height, quality):
    """
    Process image by resizing and compressing it while maintaining original format.

    Args:
        image_data: Raw image data
        max_width: Maximum width for the processed image
        max_height: Maximum height for the processed image
        quality: Image quality (1-100)

    Returns:
        bytes: Processed image data
    """
    try:
        import time
        start_time = time.time()
        # Import PIL from the layer
        from PIL import Image

        # Open image with PIL
        image = Image.open(io.BytesIO(image_data))
        original_size = image.size
        original_format = image.format
        original_mode = image.mode
        logger.info(f"Original image size: {original_size}, format: {original_format}, mode: {original_mode}")

        # Calculate new dimensions while maintaining aspect ratio
        original_width, original_height = image.size
        aspect_ratio = original_width / original_height

        if original_width > max_width or original_height > max_height:
            if aspect_ratio > 1:  # Landscape
                new_width = min(max_width, original_width)
                new_height = int(new_width / aspect_ratio)
            else:  # Portrait or square
                new_height = min(max_height, original_height)
                new_width = int(new_height * aspect_ratio)

            # Resize image
            image = image.resize((new_width, new_height), Image.Resampling.LANCZOS)
            logger.info(f"Resized image: {original_size} -> {image.size}")

        # Save processed image to bytes maintaining original format and mode
        output_buffer = io.BytesIO()

        # Determine save parameters based on format
        if original_format == 'JPEG':
            # For JPEG, convert to RGB if needed
            if image.mode in ('RGBA', 'LA', 'P'):
                # Create a white background for JPEG
                background = Image.new('RGB', image.size, (255, 255, 255))
                if image.mode == 'P':
                    image = image.convert('RGBA')
                background.paste(image, mask=image.split()[-1] if image.mode == 'RGBA' else None)
                image = background
            elif image.mode != 'RGB':
                image = image.convert('RGB')
            image.save(output_buffer, format='JPEG', quality=quality, optimize=True, progressive=True)
        elif original_format == 'PNG':
            # For PNG, preserve original mode (including RGBA for transparency)
            image.save(output_buffer, format='PNG', optimize=True)
        elif original_format == 'GIF':
            # For GIF, check if it's animated
            if hasattr(image, 'n_frames') and image.n_frames > 1:
                # Animated GIF - limit frames for performance
                max_frames = 50  # Limit to 50 frames to prevent timeout
                total_frames = min(image.n_frames, max_frames)

                logger.info(f"Processing animated GIF with {image.n_frames} frames (limiting to {total_frames})")

                frames = []
                durations = []

                for frame_num in range(total_frames):
                    image.seek(frame_num)
                    # Resize frame if needed
                    if original_width > max_width or original_height > max_height:
                        frame = image.resize((new_width, new_height), Image.Resampling.LANCZOS)
                    else:
                        frame = image.copy()
                    frames.append(frame)

                    # Preserve frame duration
                    if 'duration' in image.info:
                        durations.append(image.info['duration'])
                    else:
                        durations.append(100)  # Default 100ms

                # Save animated GIF with optimization
                if frames:
                    frames[0].save(
                        output_buffer,
                        format='GIF',
                        save_all=True,
                        append_images=frames[1:],
                        duration=durations,
                        loop=image.info.get('loop', 0),
                        optimize=True,
                        disposal=2  # Clear to background for better compression
                    )
                    logger.info(f"Saved animated GIF with {len(frames)} frames")
            else:
                # Static GIF - simple processing
                image.save(output_buffer, format='GIF', optimize=True)
        elif original_format == 'WEBP':
            # For WEBP, use aggressive compression settings
            image.save(output_buffer, format='WEBP',
                     quality=quality,
                     optimize=True,
                     method=6,  # Best compression method (0-6)
                     lossless=False)  # Use lossy compression for better size reduction
        else:
            # Fallback to original format with basic optimization
            image.save(output_buffer, format=original_format, optimize=True)

        processed_data = output_buffer.getvalue()
        processing_time = time.time() - start_time

        logger.info(f"Processed image size: {len(processed_data)} bytes (original: {len(image_data)} bytes) in {processing_time:.2f}s")

        return processed_data, original_format

    except Exception as e:
        logger.error(f"Error processing image: {str(e)}")
        raise e

def upload_processed_image(processed_data, destination_bucket, object_key, image_format):
    """
    Upload processed image to destination bucket with metadata.

    Args:
        processed_data: Processed image data
        destination_bucket: Destination S3 bucket name
        object_key: S3 object key for the processed image
        image_format: Original image format (JPEG, PNG, WEBP, etc.)
    """
    try:
        # Prepare metadata
        metadata = {
            'processed': 'true',
            'processor': 'lambda-image-processor',
            'processed_at': str(int(time.time())),
            'original_format': image_format
        }

        # Determine content type based on format
        content_type_map = {
            'JPEG': 'image/jpeg',
            'PNG': 'image/png',
            'GIF': 'image/gif',
            'WEBP': 'image/webp',
            'BMP': 'image/bmp',
            'TIFF': 'image/tiff'
        }
        content_type = content_type_map.get(image_format, 'image/jpeg')

        # Upload to destination bucket
        s3_client.put_object(
            Bucket=destination_bucket,
            Key=object_key,
            Body=processed_data,
            ContentType=content_type,
            Metadata=metadata,
            ServerSideEncryption='AES256'
        )

        logger.info(f"Uploaded processed image to: s3://{destination_bucket}/{object_key}")

    except Exception as e:
        logger.error(f"Error uploading processed image: {str(e)}")
        raise e

def update_processing_status(table_name, object_key, status='processed', error=None):
    """
    Update the processing status in DynamoDB.

    Args:
        table_name: DynamoDB table name
        object_key: S3 object key
        status: Processing status ('processed', 'error')
        error: Error message if status is 'error'
    """
    try:
        # Extract file ID from object key (format: images/{file_id}_{filename})
        # Remove 'images/' prefix and split by '_' to get file_id
        key_parts = object_key.split('/')
        if len(key_parts) >= 2:
            filename_part = key_parts[-1]  # Get the filename part
            # Split by '_' and take the first part as file_id
            file_id = filename_part.split('_')[0]
        else:
            # Fallback: use the object key as file_id
            file_id = object_key.replace('/', '_')

        logger.info(f"Updating status for file_id: {file_id}")

        table = dynamodb.Table(table_name)

        update_expression = 'SET #status = :status, processed_at = :processed_at'
        expression_attribute_names = {'#status': 'status'}
        expression_attribute_values = {
            ':status': status,
            ':processed_at': int(time.time())
        }

        if error:
            update_expression += ', error_message = :error_message'
            expression_attribute_values[':error_message'] = error

        table.update_item(
            Key={'id': file_id},
            UpdateExpression=update_expression,
            ExpressionAttributeNames=expression_attribute_names,
            ExpressionAttributeValues=expression_attribute_values
        )

        logger.info(f"Updated status for file {file_id}: {status}")

    except Exception as e:
        logger.error(f"Error updating processing status: {str(e)}")
        # Don't raise here as this is not critical for the main processing
