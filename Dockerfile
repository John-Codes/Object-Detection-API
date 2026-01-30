FROM perl:5.38-slim

WORKDIR /app

# Install dependencies
RUN apt-get update && apt-get install -y \
    libdbi-perl \
    libdbd-pg-perl \
    libmime-base64-perl \
    libwww-perl \
    && rm -rf /var/lib/apt/lists/*

# Copy application files
COPY *.pm app.pl ./

# Create storage directory
RUN mkdir -p storage

# Set permissions
RUN chmod +x app.pl

# Expose port
EXPOSE 8080

# Run the application
CMD ["perl", "app.pl"]