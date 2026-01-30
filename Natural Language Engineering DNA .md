# Solo Dev Survival Guide: AI Vision API

## The Simple Version (Layman's Terms)

**The Trigger**: You send an image to your API.

**The Brain**: Your API sends that image to OpenRouter (the AI). The AI tells you what it sees.

**The Filing Cabinet**: Your API saves the actual picture in a folder on your computer.

**The Logbook**: Your API writes down the "Who, What, and When" in a database list.

---

## Part 1: The Database (The Storage Room)

We use Docker to spin up a PostgreSQL database instantly. We'll use a `docker-compose.yml` file and an `init.sql` script to make sure the table exists the moment the database starts.

### `init.sql` (The Table Setup)

```sql
CREATE TABLE IF NOT EXISTS detected_objects (
    id SERIAL PRIMARY KEY,
    object_name TEXT,
    description TEXT,
    image_path TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### `docker-compose.db.yml`

```yaml
services:
  db:
    image: postgres:15
    restart: always
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
      POSTGRES_DB: vision_db
    ports:
      - "5432:5432"
    volumes:
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
```

---

## Part 2: The Logic (Language Agnostic Guide)

Follow these exact steps in your code.

### Step 1: Accept the Image
Create a POST endpoint `/detect`.
Receive the image file from the request.

### Step 2: Ask the AI (OpenRouter)
Send a request to `https://openrouter.ai/api/v1/chat/completions`.
The Prompt: `"Identify the main object in this image and give a brief description."`
The Model: Use a VLM like `google/gemini-pro-vision` or `openai/gpt-4o`.

### Step 3: Save the File Locally
Generate a unique name (e.g., `image_123.jpg`).
Move the image from the request to a local folder called `/storage`.

### Step 4: Record to Database
Connect to the Postgres DB.
Run: `INSERT INTO detected_objects (object_name, description, image_path) VALUES (?, ?, ?)` using the data from the AI and the file path.

---

## Part 3: The API Container (The Shipping Box)

This turns your code into a portable unit.

### `Dockerfile`

```dockerfile
# Use a slim version of your language (e.g., python:3.11-slim)
FROM python:3.11-slim 
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
CMD ["python", "main.py"]
```

### `docker-compose.api.yml`

```yaml
services:
  api:
    build: .
    ports:
      - "8080:8080"
    volumes:
      - ./storage:/app/storage
    environment:
      - OPENROUTER_API_KEY=your_key_here
      - DB_URL=postgresql://user:password@db:5432/vision_db
```

---

## Technical Summary (The Single Responsibility Rule)

To keep this "clean enough to survive," ensure your code follows this structure:

- **FileStore class**: Only handles saving/loading bytes to the disk.
- **VisionClient class**: Only handles the HTTP call to OpenRouter.
- **Repository class**: Only handles the SQL INSERT statement.
- **Handler function**: The "boss" that calls the three classes above in order.