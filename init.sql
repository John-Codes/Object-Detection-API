CREATE TABLE IF NOT EXISTS detected_objects (
    id SERIAL PRIMARY KEY,
    object_name TEXT,
    description TEXT,
    image_path TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);