# Solo Dev Vision API

A minimal Perl implementation of an AI Vision API following the solo dev survival guide.

## Features

- **FileStore**: Handles saving/loading images to `/storage`
- **VisionClient**: Manages OpenRouter API communication
- **Repository**: Handles PostgreSQL database operations
- **Simple HTTP Server**: Built-in Perl HTTP server with CORS support

## Quick Start

1. Set up environment variables:
   ```bash
   export OPENROUTER_API_KEY="your_openrouter_api_key_here"
   ```

2. Start the services:
   ```bash
   docker-compose up -d
   ```

3. Test the API:
   ```bash
   curl -X POST -F "image=@test.jpg" http://localhost:8080/detect
   ```

## API Endpoints

### POST /detect
Analyze an image and return detected objects.

**Request:**
```bash
curl -X POST -F "image=@your_image.jpg" http://localhost:8080/detect
```

**Response:**
```json
{
  "object_name": "Cat",
  "description": "A black cat sitting on a windowsill",
  "image_path": "./storage/image_1234567890.jpg"
}
```

### GET /detections
Get all detected objects from the database.

**Request:**
```bash
curl http://localhost:8080/detections
```

**Response:**
```json
[
  {
    "id": 1,
    "object_name": "Cat",
    "description": "A black cat sitting on a windowsill",
    "image_path": "./storage/image_1234567890.jpg",
    "created_at": "2024-01-01T12:00:00Z"
  }
]
```

## Architecture

The system follows the single responsibility principle:

- **FileStore**: Only handles saving/loading bytes to disk
- **VisionClient**: Only handles HTTP calls to OpenRouter
- **Repository**: Only handles SQL INSERT statements
- **Main API**: Coordinates the three classes above

## Environment Variables

- `OPENROUTER_API_KEY`: Your OpenRouter API key (required)
- `DB_URL`: PostgreSQL connection string (optional, defaults to local PostgreSQL)

## Development

Run locally without Docker:
```bash
# Install dependencies
sudo apt-get install libdbi-perl libdbd-pg-perl libmime-base64-perl libwww-perl

# Start PostgreSQL manually
sudo service postgresql start

# Run the app
perl app.pl
```

## License

MIT - Simple and clean for solo dev survival.