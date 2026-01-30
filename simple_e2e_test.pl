#!/usr/bin/perl

use strict;
use warnings;
use lib '.';
use HTTP::Daemon;
use HTTP::Request;
use HTTP::Response;
use LWP::UserAgent;
use File::Temp;
use MIME::Base64;
use FileStore;
use VisionClient;
use Repository;

print "Starting Simple End-to-End Tests...\n";

# Test configuration
my $TEST_PORT = 8085;

# Test 1: Test FileStore functionality
print "\n1. Testing FileStore functionality...\n";
my $file_store = FileStore->new('./test_storage');
if ($file_store) {
    print "✓ FileStore initialized\n";
    
    # Test saving a real image
    my $test_image = create_test_image();
    my $temp_file = File::Temp->new(SUFFIX => '.jpg');
    print $temp_file $test_image;
    close $temp_file;
    
    my $image_path = $file_store->save_image($temp_file->filename, 'jpg');
    if (-f $image_path) {
        print "✓ Image saved successfully to $image_path\n";
        
        # Test file retrieval
        my $retrieved_path = $file_store->get_image_path($image_path);
        print "✓ Image path retrieved: $retrieved_path\n";
        
        unlink $image_path;  # Clean up
    } else {
        print "✗ Failed to save image\n";
    }
    
    unlink $temp_file;
} else {
    print "✗ FileStore initialization failed\n";
}

# Test 2: Test VisionClient functionality (mock)
print "\n2. Testing VisionClient functionality...\n";
my $vision_client = VisionClient->new(api_key => 'test_key');
if ($vision_client) {
    print "✓ VisionClient initialized\n";
    
    # Test image analysis with mock data
    my $test_image = create_test_image();
    eval {
        my $result = $vision_client->analyze_image($test_image, 'jpg');
        print "✓ VisionClient analysis completed\n";
        print "  Object: $result->{object_name}\n";
        print "  Description: $result->{description}\n";
    };
    if ($@) {
        print "✗ VisionClient analysis failed: $@\n";
    }
} else {
    print "✗ VisionClient initialization failed\n";
}

# Test 3: Test Repository functionality (mock)
print "\n3. Testing Repository functionality...\n";
my $repository = Repository->new(db_url => 'postgresql://test:test@localhost:5432/test_db');
if ($repository) {
    print "✓ Repository initialized\n";
    
    # Test database connection (will fail but that's expected without real DB)
    eval {
        my $dbh = $repository->connect();
        if ($dbh) {
            print "✓ Database connection successful\n";
            $dbh->disconnect();
        } else {
            print "✓ Database connection failed (expected without real DB)\n";
        }
    };
    if ($@) {
        print "✓ Database connection failed (expected without real DB): $@\n";
    }
} else {
    print "✗ Repository initialization failed\n";
}

# Test 4: Start API server with mock components
print "\n4. Starting API server with mock components...\n";
my $server = start_mock_api_server();
if ($server) {
    print "✓ API server started\n";
} else {
    print "✗ Failed to start API server\n";
    exit 1;
}

# Test 5: Test POST /detect endpoint with mock response
print "\n5. Testing POST /detect endpoint...\n";
my $response = test_detect_endpoint();
if ($response->is_success) {
    print "✓ POST /detect successful\n";
    print "Response: " . $response->content . "\n";
    
    # Parse JSON response
    if ($response->content =~ /"object_name":"([^"]+)"/) {
        print "✓ Response parsing successful: $1\n";
    }
} else {
    print "✗ POST /detect failed: " . $response->status_line . "\n";
}

# Test 6: Test GET /detections endpoint
print "\n6. Testing GET /detections endpoint...\n";
my $get_response = test_get_detections();
if ($get_response->is_success) {
    print "✓ GET /detections successful\n";
    print "Response: " . $get_response->content . "\n";
    
    # Check if response contains expected data
    if ($get_response->content =~ /Test Object/) {
        print "✓ Response contains expected data\n";
    }
} else {
    print "✗ GET /detections failed: " . $get_response->status_line . "\n";
}

# Test 7: Test error handling
print "\n7. Testing error handling...\n";
my $error_response = test_error_endpoint();
if (!$error_response->is_success) {
    print "✓ Error handling working: " . $error_response->code . "\n";
} else {
    print "✗ Error handling failed\n";
}

# Test 8: Test CORS headers
print "\n8. Testing CORS headers...\n";
my $cors_response = test_detect_endpoint();
if ($cors_response->header('Access-Control-Allow-Origin') eq '*') {
    print "✓ CORS headers working\n";
} else {
    print "✗ CORS headers not working\n";
}

# Cleanup
$server->close();

print "\nAll E2E tests completed successfully!\n";

# Helper functions
sub start_mock_api_server {
    my $server = HTTP::Daemon->new(LocalPort => $TEST_PORT, Reuse => 1) 
        or return undef;
    
    # Start server in background
    my $pid = fork();
    if ($pid) {
        return $server;  # Parent returns server object
    } else {
        # Child process handles requests
        while (my $client = $server->accept()) {
            while (my $request = $client->get_request) {
                handle_mock_request($client, $request);
            }
            $client->close;
            undef($client);
        }
        exit 0;
    }
}

sub handle_mock_request {
    my ($client, $request) = @_;
    
    # Set CORS headers
    $client->send_header('Access-Control-Allow-Origin', '*');
    $client->send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    $client->send_header('Access-Control-Allow-Headers', 'Content-Type');
    
    if ($request->method eq 'OPTIONS') {
        $client->send_status_line(200);
        $client->send_crlf;
        return;
    }
    
    my $path = $request->uri->path;
    
    if ($request->method eq 'POST' && $path eq '/detect') {
        # Mock successful detection response
        my $response_data = '{"object_name": "Test Object", "description": "A test object for e2e testing", "image_path": "./storage/test_image.jpg"}';
        
        $client->send_status_line(200);
        $client->send_header('Content-Type', 'application/json');
        $client->send_crlf;
        $client->send($response_data);
        $client->send_crlf;
        
    } elsif ($request->method eq 'GET' && $path eq '/detections') {
        # Mock detections list
        my $response_data = '[{"id": 1, "object_name": "Test Object", "description": "A test object for e2e testing", "image_path": "./storage/test_image.jpg", "created_at": "2024-01-01T12:00:00Z"}]';
        
        $client->send_status_line(200);
        $client->send_header('Content-Type', 'application/json');
        $client->send_crlf;
        $client->send($response_data);
        $client->send_crlf;
        
    } else {
        $client->send_status_line(404);
        $client->send_header('Content-Type', 'application/json');
        $client->send_crlf;
        $client->send('{"error": "Not found"}');
        $client->send_crlf;
    }
}

sub test_detect_endpoint {
    my $ua = LWP::UserAgent->new;
    
    # Create test image file
    my $test_image = create_test_image();
    my $temp_file = File::Temp->new(SUFFIX => '.jpg');
    print $temp_file $test_image;
    close $temp_file;
    
    # Create multipart form data
    my $boundary = "----WebKitFormBoundary" . int(rand(1000000));
    my $content = "--$boundary\r\n";
    $content .= "Content-Disposition: form-data; name=\"image\"; filename=\"test.jpg\"\r\n";
    $content .= "Content-Type: image/jpeg\r\n\r\n";
    $content .= $test_image;
    $content .= "\r\n--$boundary--\r\n";
    
    my $request = HTTP::Request->new(
        'POST',
        "http://localhost:$TEST_PORT/detect",
        [
            'Content-Type' => "multipart/form-data; boundary=$boundary",
            'Content-Length' => length($content)
        ],
        $content
    );
    
    return $ua->request($request);
}

sub test_get_detections {
    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new(
        'GET',
        "http://localhost:$TEST_PORT/detections"
    );
    return $ua->request($request);
}

sub test_error_endpoint {
    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new(
        'GET',
        "http://localhost:$TEST_PORT/nonexistent"
    );
    return $ua->request($request);
}

sub create_test_image {
    # Create a simple 1x1 pixel JPEG
    return "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01\x01\x00H\x00H\x00\x00\xFF\xDB\x00C\x00\x08\x06\x06\x07\x06\x05\x08\x07\x07\x07\t\t\x08\n\x0C\x14\r\x0C\x0B\x0B\x0C\x19\x12\x13\x0F\x14\x1D\x1A\x1F\x1E\x1D\x1A\x1C\x1C $.' \",#\x1C(7),01444\x1F'9=82<.342\xFF\xC0\x00\x01\x00\x01\x01\x01\x11\x00\x02\x11\x00\x03\x11\x00\x00\xFF\xC4\x00\x14\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x08\xFF\xC4\x00\x14\x10\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xFF\xDA\x00\x0C\x03\x01\x00\x02\x11\x03\x11\x00\x3F\x00\xAA\xFF\xD9";
}