"""
Image Processor Web UI Lambda Handler

This Lambda function provides a web interface for the image processing service.
It handles file uploads, processing status checks, and download link generation.
"""

import json
import boto3
import os
import uuid
import time
import logging
from datetime import datetime, timedelta
from urllib.parse import unquote_plus

# =============================================================================
# CONFIGURATION
# =============================================================================

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

# =============================================================================
# MAIN HANDLER
# =============================================================================

def handler(event, context):
    """
    Main Lambda handler for web UI and download link generation.

    Handles:
    - Serving the web UI
    - Generating presigned upload URLs
    - Creating one-time download links
    - Checking processing status
    - Favicon redirects

    Args:
        event: Lambda event object
        context: Lambda context object

    Returns:
        dict: HTTP response
    """
    try:
        # Debug logging at the start
        logger.info(f"Handler called with event: {json.dumps(event)}")

        # Get HTTP method and path
        http_method = event.get('httpMethod', 'GET')
        path = event.get('path', '/')

        logger.info(f"Processing request: {http_method} {path}")

        # Route requests
        if http_method in ['GET', 'HEAD']:
            return handle_get_request(event, path)
        elif http_method == 'POST':
            return handle_post_request(event, path)
        else:
            return create_response(405, {'error': 'Method not allowed'})

    except Exception as e:
        logger.error(f"Error in web UI Lambda: {str(e)}")
        return create_response(500, {'error': 'Internal server error'})

# =============================================================================
# REQUEST ROUTING
# =============================================================================

def handle_get_request(event, path):
    """Handle GET and HEAD requests."""
    if path == '/' or path == '/index.html':
        logger.info("Routing to serve_web_ui()")
        return serve_web_ui()
    elif path in ['/favicon.ico', '/favicon.png', '/prod/favicon.ico', '/prod/favicon.png']:
        logger.info(f"Redirecting favicon request to S3: {path}")
        return redirect_to_s3_favicon(path)
    elif path.startswith('/download/'):
        logger.info("Routing to handle_download()")
        return handle_download(event)
    elif path == '/status':
        logger.info("Routing to handle_status_check()")
        return handle_status_check(event)
    elif 'proxy' in event.get('pathParameters', {}):
        # Handle proxy requests (for favicon files)
        proxy_path = event['pathParameters']['proxy']
        if proxy_path in ['favicon.ico', 'favicon.png']:
            logger.info(f"Redirecting favicon proxy request to S3: {proxy_path}")
            return redirect_to_s3_favicon(f"/{proxy_path}")
        else:
            logger.info(f"404 for proxy path: {proxy_path}")
            return create_response(404, {'error': 'Not found'})
    else:
        logger.info(f"404 for path: {path}")
        return create_response(404, {'error': 'Not found'})

def handle_post_request(event, path):
    """Handle POST requests."""
    if path == '/upload-url':
        return generate_upload_url(event)
    elif path == '/check-status':
        return check_processing_status(event)
    else:
        return create_response(404, {'error': 'Not found'})

# =============================================================================
# WEB UI FUNCTIONS
# =============================================================================

def serve_web_ui():
    """Serve the web UI HTML page."""
    html_content = get_web_ui_html()
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'text/html',
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Pragma': 'no-cache',
            'Expires': '0',
            'Last-Modified': str(int(time.time()))
        },
        'body': html_content
    }

def get_web_ui_html():
    """Return the HTML content for the web UI."""
    return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Image Processor</title>
    <link rel="icon" type="image/png" href="/prod/favicon.png">
    <link rel="shortcut icon" href="/prod/favicon.ico">
    <link rel="icon" href="/prod/favicon.ico">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }

        .container {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            padding: 40px;
            max-width: 600px;
            width: 100%;
        }

        .header {
            text-align: center;
            margin-bottom: 40px;
        }

        .header h1 {
            color: #333;
            font-size: 2.5rem;
            margin-bottom: 10px;
        }

        .header p {
            color: #666;
            font-size: 1.1rem;
        }

        .upload-area {
            border: 3px dashed #ddd;
            border-radius: 15px;
            padding: 60px 20px;
            text-align: center;
            margin-bottom: 30px;
            transition: all 0.3s ease;
            cursor: pointer;
        }

        .upload-area:hover {
            border-color: #667eea;
            background-color: #f8f9ff;
        }

        .upload-area.dragover {
            border-color: #667eea;
            background-color: #f0f2ff;
        }

        .upload-icon {
            font-size: 3rem;
            color: #ddd;
            margin-bottom: 20px;
        }

        .upload-text {
            font-size: 1.2rem;
            color: #666;
            margin-bottom: 10px;
        }

        .upload-subtext {
            color: #999;
            font-size: 0.9rem;
        }

        .file-input {
            display: none;
        }

        .btn {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 15px 30px;
            border-radius: 10px;
            font-size: 1.1rem;
            cursor: pointer;
            transition: transform 0.2s ease;
            width: 100%;
            margin-bottom: 20px;
        }

        .btn:hover {
            transform: translateY(-2px);
        }

        .btn:disabled {
            opacity: 0.6;
            cursor: not-allowed;
            transform: none;
        }

        .status {
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
            display: none;
        }

        .status.processing {
            background-color: #fff3cd;
            border: 1px solid #ffeaa7;
            color: #856404;
        }

        .status.success {
            background-color: #d4edda;
            border: 1px solid #c3e6cb;
            color: #155724;
        }

        .status.error {
            background-color: #f8d7da;
            border: 1px solid #f5c6cb;
            color: #721c24;
        }

        .download-link {
            display: inline-block;
            background: #28a745;
            color: white;
            text-decoration: none;
            padding: 12px 24px;
            border-radius: 8px;
            font-weight: 500;
            transition: background-color 0.2s ease;
        }

        .download-link:hover {
            background: #218838;
        }

        .file-info {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 8px;
            margin-bottom: 20px;
            display: none;
        }

        .spinner {
            display: inline-block;
            width: 20px;
            height: 20px;
            border: 3px solid #f3f3f3;
            border-top: 3px solid #667eea;
            border-radius: 50%;
            animation: spin 1s linear infinite;
            margin-right: 10px;
        }

        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }

        .progress-bar {
            width: 100%;
            height: 6px;
            background-color: #e9ecef;
            border-radius: 3px;
            overflow: hidden;
            margin-top: 10px;
        }

        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #667eea, #764ba2);
            width: 0%;
            transition: width 0.3s ease;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🖼️ Image Processor</h1>
            <p>Upload your images and get them automatically compressed and resized</p>
        </div>

        <div class="upload-area" id="uploadArea">
            <div class="upload-icon">📁</div>
            <div class="upload-text">Click to select or drag & drop your image</div>
            <div class="upload-subtext">Supports JPG, JPEG, PNG, GIF, and WEBP files (max 10MB)</div>
            <input type="file" id="fileInput" class="file-input" accept=".jpg,.jpeg,.png,.gif,.webp">
        </div>

        <button id="uploadBtn" class="btn" disabled>Select a file to upload</button>

        <div id="fileInfo" class="file-info">
            <strong>Selected file:</strong> <span id="fileName"></span><br>
            <strong>Size:</strong> <span id="fileSize"></span>
        </div>

        <div id="status" class="status">
            <div id="statusMessage"></div>
            <div class="progress-bar" id="progressBar" style="display: none;">
                <div class="progress-fill" id="progressFill"></div>
            </div>
        </div>
    </div>

    <script>
        const uploadArea = document.getElementById('uploadArea');
        const fileInput = document.getElementById('fileInput');
        const uploadBtn = document.getElementById('uploadBtn');
        const fileInfo = document.getElementById('fileInfo');
        const status = document.getElementById('status');
        const statusMessage = document.getElementById('statusMessage');
        const progressBar = document.getElementById('progressBar');
        const progressFill = document.getElementById('progressFill');

        let currentFileId = null;
        let checkInterval = null;

        // File selection handlers
        uploadArea.addEventListener('click', () => fileInput.click());
        fileInput.addEventListener('change', handleFileSelect);

        // Drag and drop handlers
        uploadArea.addEventListener('dragover', (e) => {
            e.preventDefault();
            uploadArea.classList.add('dragover');
        });

        uploadArea.addEventListener('dragleave', () => {
            uploadArea.classList.remove('dragover');
        });

        uploadArea.addEventListener('drop', (e) => {
            e.preventDefault();
            uploadArea.classList.remove('dragover');
            const files = e.dataTransfer.files;
            if (files.length > 0) {
                fileInput.files = files;
                handleFileSelect();
            }
        });

        function handleFileSelect() {
            const file = fileInput.files[0];
            if (file) {
                // Validate file type
                const allowedTypes = ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp'];
                if (!allowedTypes.includes(file.type)) {
                    showStatus('error', 'Please select a JPG, JPEG, PNG, GIF, or WEBP file.');
                    return;
                }

                // Validate file size (10MB limit)
                const maxSize = 10 * 1024 * 1024; // 10MB in bytes
                if (file.size > maxSize) {
                    showStatus('error', `File size ${formatFileSize(file.size)} exceeds the maximum allowed size of 10MB.`);
                    return;
                }

                // Show file info
                document.getElementById('fileName').textContent = file.name;
                document.getElementById('fileSize').textContent = formatFileSize(file.size);
                fileInfo.style.display = 'block';

                uploadBtn.textContent = 'Upload Image';
                uploadBtn.disabled = false;
                uploadBtn.onclick = uploadFile;

                hideStatus();
            }
        }

        function uploadFile() {
            const file = fileInput.files[0];
            if (!file) return;

            uploadBtn.disabled = true;
            uploadBtn.textContent = 'Uploading...';
            showStatus('processing', 'Preparing upload...');

            // Get upload URL
            fetch('/prod/upload-url', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    filename: file.name
                })
            })
            .then(response => response.json())
            .then(data => {
                if (data.error) {
                    throw new Error(data.error);
                }

                currentFileId = data.file_id;
                showStatus('processing', 'Uploading image...');
                progressBar.style.display = 'block';

                // Upload file to S3
                return fetch(data.upload_url, {
                    method: 'PUT',
                    body: file,
                    headers: {
                        'Content-Type': file.type
                    }
                });
            })
            .then(() => {
                showStatus('processing', 'Image uploaded! Processing...');
                progressFill.style.width = '50%';

                // Start checking processing status
                checkProcessingStatus();
            })
            .catch(error => {
                console.error('Upload error:', error);
                showStatus('error', 'Upload failed: ' + error.message);
                resetUpload();
            });
        }

        function checkProcessingStatus() {
            if (!currentFileId) return;

            checkInterval = setInterval(() => {
                fetch('/prod/check-status', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        file_id: currentFileId
                    })
                })
                .then(response => response.json())
                .then(data => {
                    if (data.error) {
                        throw new Error(data.error);
                    }

                    if (data.status === 'processed') {
                        clearInterval(checkInterval);
                        progressFill.style.width = '100%';
                        showStatus('success',
                            `Image processed successfully! ` +
                            `<a href="/prod/download/${data.download_token}" class="download-link" target="_blank">Download Processed Image</a>`
                        );
                        resetUpload();
                    } else if (data.status === 'processing') {
                        progressFill.style.width = '75%';
                        showStatus('processing', 'Processing image...');
                    }
                })
                .catch(error => {
                    console.error('Status check error:', error);
                    clearInterval(checkInterval);
                    showStatus('error', 'Failed to check processing status: ' + error.message);
                    resetUpload();
                });
            }, 2000); // Check every 2 seconds
        }

        function showStatus(type, message) {
            status.className = `status ${type}`;
            statusMessage.innerHTML = message;
            status.style.display = 'block';
        }

        function hideStatus() {
            status.style.display = 'none';
        }

        function resetUpload() {
            uploadBtn.disabled = false;
            uploadBtn.textContent = 'Select a file to upload';
            uploadBtn.onclick = null;
            fileInput.value = '';
            fileInfo.style.display = 'none';
            progressBar.style.display = 'none';
            progressFill.style.width = '0%';
            currentFileId = null;
        }

        function formatFileSize(bytes) {
            if (bytes === 0) return '0 Bytes';
            const k = 1024;
            const sizes = ['Bytes', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        }
    </script>
</body>
</html>
    """

# =============================================================================
# UPLOAD FUNCTIONS
# =============================================================================

def generate_upload_url(event):
    """Generate a presigned URL for direct S3 upload."""
    try:
        body = json.loads(event.get('body', '{}'))
        filename = body.get('filename', '')

        if not filename:
            return create_response(400, {'error': 'Filename is required'})

        # Validate file extension
        allowed_extensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp']
        file_ext = os.path.splitext(filename.lower())[1]
        if file_ext not in allowed_extensions:
            return create_response(400, {'error': 'Only JPG, JPEG, PNG, GIF, and WEBP files are allowed'})

        # Generate unique key
        unique_id = str(uuid.uuid4())
        s3_key = f"images/{unique_id}_{filename}"

        # Get source bucket from environment
        source_bucket = os.environ['SOURCE_BUCKET']

        # Generate presigned URL for upload
        # Map file extensions to proper MIME types
        content_type_map = {
            '.jpg': 'image/jpeg',
            '.jpeg': 'image/jpeg',
            '.png': 'image/png',
            '.gif': 'image/gif',
            '.webp': 'image/webp'
        }
        content_type = content_type_map.get(file_ext, 'image/jpeg')

        # Use regional endpoint to avoid redirect issues
        region = os.environ.get('REGION', 'ap-southeast-2')
        s3_client_regional = boto3.client(
            's3',
            region_name=region,
            endpoint_url=f"https://s3.{region}.amazonaws.com"
        )

        presigned_url = s3_client_regional.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': source_bucket,
                'Key': s3_key,
                'ContentType': content_type
            },
            ExpiresIn=3600  # 1 hour
        )

        # Store upload info in DynamoDB for tracking
        table = dynamodb.Table(os.environ['TRACKING_TABLE'])
        table.put_item(Item={
            'id': unique_id,
            'filename': filename,
            's3_key': s3_key,
            'status': 'uploaded',
            'created_at': int(time.time()),
            'expires_at': int(time.time()) + 86400  # 24 hours
        })

        return create_response(200, {
            'upload_url': presigned_url,
            'file_id': unique_id,
            'filename': filename
        })

    except Exception as e:
        logger.error(f"Error generating upload URL: {str(e)}")
        return create_response(500, {'error': 'Failed to generate upload URL'})

# =============================================================================
# PROCESSING STATUS FUNCTIONS
# =============================================================================

def check_processing_status(event):
    """Check if an image has been processed."""
    try:
        body = json.loads(event.get('body', '{}'))
        file_id = body.get('file_id', '')

        if not file_id:
            return create_response(400, {'error': 'File ID is required'})

        table = dynamodb.Table(os.environ['TRACKING_TABLE'])
        response = table.get_item(Key={'id': file_id})

        if 'Item' not in response:
            return create_response(404, {'error': 'File not found'})

        item = response['Item']

        # First check if the source file exists
        source_bucket = os.environ['SOURCE_BUCKET']
        source_key = item['s3_key']

        try:
            s3_client.head_object(Bucket=source_bucket, Key=source_key)
        except s3_client.exceptions.NoSuchKey:
            return create_response(404, {'error': 'Source file not found'})
        except Exception as e:
            logger.error(f"Error checking source file: {str(e)}")
            return create_response(500, {'error': 'Failed to check source file'})

        # Check if the processed file exists in destination bucket
        destination_bucket = os.environ['DESTINATION_BUCKET']
        destination_key = item['s3_key']

        try:
            # File exists, check if it's actually processed
            response = s3_client.head_object(
                Bucket=destination_bucket,
                Key=destination_key
            )
            metadata = response.get('Metadata', {})

            if metadata.get('processed') == 'true':
                # Generate secure download token instead of presigned URL
                import secrets
                download_token = secrets.token_urlsafe(32)
                download_expires = int(time.time()) + 3600  # 1 hour

                # Store download token in DynamoDB
                table.update_item(
                    Key={'id': file_id},
                    UpdateExpression='SET download_token = :token, download_expires = :expires',
                    ExpressionAttributeValues={
                        ':token': download_token,
                        ':expires': download_expires
                    }
                )

                return create_response(200, {
                    'status': 'processed',
                    'download_token': download_token,
                    'message': 'Image processed successfully'
                })
            else:
                return create_response(200, {
                    'status': 'processing',
                    'message': 'Image is still being processed'
                })

        except s3_client.exceptions.NoSuchKey:
            return create_response(200, {
                'status': 'processing',
                'message': 'Image is still being processed'
            })
        except Exception as e:
            logger.error(f"Error checking processed file: {str(e)}")
            return create_response(200, {
                'status': 'processing',
                'message': 'Image is still being processed'
            })

    except Exception as e:
        logger.error(f"Error checking processing status: {str(e)}")
        return create_response(500, {'error': 'Failed to check status'})

# =============================================================================
# DOWNLOAD FUNCTIONS
# =============================================================================

def handle_download(event):
    """Handle download requests with one-time tokens."""
    try:
        # Extract token from path
        path_parts = event.get('path', '').split('/')
        if len(path_parts) < 3:
            return create_response(400, {'error': 'Invalid download URL'})

        download_token = path_parts[2]

        # Look up token in DynamoDB
        table = dynamodb.Table(os.environ['TRACKING_TABLE'])
        response = table.scan(
            FilterExpression='download_token = :token AND download_expires > :now',
            ExpressionAttributeValues={
                ':token': download_token,
                ':now': int(time.time())
            }
        )

        if not response['Items']:
            return create_response(404, {'error': 'Download link not found or expired'})

        item = response['Items'][0]

        # Generate presigned URL for download
        destination_bucket = os.environ['DESTINATION_BUCKET']
        presigned_url = s3_client.generate_presigned_url(
            'get_object',
            Params={
                'Bucket': destination_bucket,
                'Key': item['s3_key']
            },
            ExpiresIn=300  # 5 minutes
        )

        # Invalidate the download token (one-time use)
        table.update_item(
            Key={'id': item['id']},
            UpdateExpression='REMOVE download_token, download_expires'
        )

        # Redirect to the presigned URL
        return {
            'statusCode': 302,
            'headers': {
                'Location': presigned_url
            }
        }

    except Exception as e:
        logger.error(f"Error handling download: {str(e)}")
        return create_response(500, {'error': 'Download failed'})

# =============================================================================
# FAVICON FUNCTIONS
# =============================================================================

def redirect_to_s3_favicon(path):
    """Redirect favicon requests to S3 with direct URL."""
    try:
        # Determine which favicon file based on the path
        if path.endswith('.png'):
            key = 'assets/favicon.png'
        else:
            key = 'assets/favicon.ico'

        # Generate direct S3 URL for the favicon from assets bucket
        assets_bucket = os.environ['ASSETS_BUCKET']
        region = os.environ.get('AWS_REGION', 'ap-southeast-2')
        s3_url = f"https://{assets_bucket}.s3-{region}.amazonaws.com/{key}?v={int(time.time())}"

        logger.info(f"Redirecting to S3 direct URL: {s3_url}")

        return {
            'statusCode': 302,
            'headers': {
                'Location': s3_url,
                'Cache-Control': 'public, max-age=86400'  # Cache for 24 hours
            }
        }
    except Exception as e:
        logger.error(f"Error redirecting favicon: {str(e)}")
        return {
            'statusCode': 404,
            'headers': {'Content-Type': 'text/plain'},
            'body': 'Favicon not found'
        }

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

def handle_status_check(event):
    """Simple health check endpoint."""
    return create_response(200, {'status': 'healthy'})

def create_response(status_code, body, content_type='application/json'):
    """Create HTTP response with proper headers."""
    if content_type == 'application/json':
        body = json.dumps(body)

    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': content_type,
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type'
        },
        'body': body
    }
