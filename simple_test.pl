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

print "Starting Simple API Integration Tests...\n";

# Test 1: Start mock API server
print "\n1. Testing API server startup...\n";
my $server = start_mock_api_server();
if ($server) {
    print "✓ Mock API server started\n";
} else {
    print "✗ Failed to start mock API server\n";
    exit 1;
}

# Test 2: Test POST /detect endpoint
print "\n2. Testing POST /detect endpoint...\n";
my $response = test_detect_endpoint();
if ($response->is_success) {
    print "✓ POST /detect successful\n";
    print "Response: " . $response->content . "\n";
} else {
    print "✗ POST /detect failed: " . $response->status_line . "\n";
}

# Test 3: Test GET /detections endpoint
print "\n3. Testing GET /detections endpoint...\n";
my $get_response = test_get_detections();
if ($get_response->is_success) {
    print "✓ GET /detections successful\n";
    print "Response: " . $get_response->content . "\n";
} else {
    print "✗ GET /detections failed: " . $get_response->status_line . "\n";
}

# Test 4: Test invalid endpoint
print "\n4. Testing invalid endpoint...\n";
my $invalid_response = test_invalid_endpoint();
if (!$invalid_response->is_success) {
    print "✓ Invalid endpoint correctly returns " . $invalid_response->code . "\n";
} else {
    print "✗ Invalid endpoint should return error\n";
}

# Test 5: Test malformed request
print "\n5. Testing malformed request...\n";
my $malformed_response = test_malformed_request();
if (!$malformed_response->is_success) {
    print "✓ Malformed request correctly returns " . $malformed_response->code . "\n";
} else {
    print "✗ Malformed request should return error\n";
}

# Cleanup
$server->close();

print "\nAll API integration tests completed!\n";

# Helper functions
sub start_mock_api_server {
    my $server = HTTP::Daemon->new(LocalPort => 8083, Reuse => 1) 
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
        my $response_data = '{"object_name": "Test Object", "description": "A test object for integration testing", "image_path": "./storage/test_image.jpg"}';
        
        $client->send_status_line(200);
        $client->send_header('Content-Type', 'application/json');
        $client->send_crlf;
        $client->send($response_data);
        $client->send_crlf;
        
    } elsif ($request->method eq 'GET' && $path eq '/detections') {
        # Mock detections list
        my $response_data = '[{"id": 1, "object_name": "Test Object", "description": "A test object for integration testing", "image_path": "./storage/test_image.jpg", "created_at": "2024-01-01T12:00:00Z"}]';
        
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
        "http://localhost:8083/detect",
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
        "http://localhost:8083/detections"
    );
    return $ua->request($request);
}

sub test_invalid_endpoint {
    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new(
        'GET',
        "http://localhost:8083/invalid"
    );
    return $ua->request($request);
}

sub test_malformed_request {
    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new(
        'POST',
        "http://localhost:8083/detect",
        ['Content-Type' => 'application/json'],
        'malformed json'
    );
    return $ua->request($request);
}

sub create_test_image {
    # Create a simple 1x1 pixel JPEG
    return "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01\x01\x00H\x00H\x00\x00\xFF\xDB\x00C\x00\x08\x06\x06\x07\x06\x05\x08\x07\x07\x07\t\t\x08\n\x0C\x14\r\x0C\x0B\x0B\x0C\x19\x12\x13\x0F\x14\x1D\x1A\x1F\x1E\x1D\x1A\x1C\x1C $.' \",#\x1C(7),01444\x1F'9=82<.342\xFF\xC0\x00\x01\x00\x01\x01\x01\x11\x00\x02\x11\x00\x03\x11\x00\x00\xFF\xC4\x00\x14\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x08\xFF\xC4\x00\x14\x10\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xFF\xDA\x00\x0C\x03\x01\x00\x02\x11\x03\x11\x00\x3F\x00\xAA\xFF\xD9";
}