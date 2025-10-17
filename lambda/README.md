# Lambda Functions

This directory contains all Lambda functions for the image processing pipeline. Each function has its own subdirectory with its code, dependencies, and documentation.

## Structure

```plaintext
lambda/
├── image-processor/          # Image processing Lambda
│   ├── lambda_function.py    # Main function code
│   ├── requirements.txt      # Python dependencies
│   └── README.md            # Function documentation
├── webui/                   # Web UI Lambda
│   ├── webui_lambda.py      # Main function code
│   ├── requirements.txt     # Python dependencies
│   └── README.md           # Function documentation
└── README.md               # This file
```

## Functions

### Image Processor (`image-processor/`)

Processes images uploaded to S3 by resizing and compressing them according to configuration parameters.

**Key Features:**

- Automatic image resizing while maintaining aspect ratio
- Configurable compression quality
- Support for JPG, JPEG, and PNG formats
- Metadata tagging for processed images

### Web UI (`webui/`)

Provides a web interface for uploading images and downloading processed results.

**Key Features:**

- Responsive web interface
- Direct S3 upload via presigned URLs
- Real-time processing status updates
- One-time download links for security

## Development

### Local Testing

To test Lambda functions locally:

1. **Install dependencies:**

   ```bash
   cd lambda/image-processor
   pip install -r requirements.txt
   ```

2. **Set environment variables:**

   ```bash
   export DESTINATION_BUCKET="your-bucket"
   export MAX_WIDTH=1920
   export MAX_HEIGHT=1080
   export IMAGE_QUALITY=85
   ```

3. **Test the function:**

   ```bash
   python lambda_function.py
   ```

### Adding New Functions

1. Create a new subdirectory: `lambda/your-function-name/`
2. Add your function code and `requirements.txt`
3. Create a `README.md` documenting the function
4. Update the main Terraform configuration to include the new function

### Dependencies

Each Lambda function manages its own dependencies in its `requirements.txt` file. When deploying, Terraform will package the entire directory (including dependencies) into a zip file.

**Note:** For production deployments, consider using Lambda Layers for common dependencies to reduce package size and improve cold start times.
