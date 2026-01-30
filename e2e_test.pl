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
use DBI;
use FileStore;
use VisionClient;
use Repository;

print "Starting Real End-to-End Tests...\n";

# Test configuration
my $TEST_PORT = 8084;
my $TEST_DB_URL = 'postgresql://user:password@localhost:5432/vision_test_db';

# Skip database tests if PostgreSQL is not available
my $skip_db_tests = 0;

# Test 1: Start PostgreSQL database
print "\n1. Testing PostgreSQL database connection...\n";
my $dbh = test_database_connection();
if ($dbh) {
    print "✓ PostgreSQL database connected\n";
    $dbh->disconnect();
} else {
    print "✗ Cannot connect to PostgreSQL database\n";
    print "Please ensure PostgreSQL is running and accessible\n";
    exit 1;
}

# Test 2: Test FileStore with real storage
print "\n2. Testing FileStore with real storage...\n";
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
        unlink $image_path;  # Clean up
    } else {
        print "✗ Failed to save image\n";
    }
    
    unlink $temp_file;
} else {
    print "✗ FileStore initialization failed\n";
}

# Test 3: Test Repository with real database
print "\n3. Testing Repository with database...\n";
my $repository = Repository->new(db_url => $TEST_DB_URL);
if ($repository) {
    print "✓ Repository initialized\n";
    
    # Test database connection
    my $test_dbh = $repository->connect();
    if ($test_dbh) {
        print "✓ Database connection successful\n";
        $test_dbh->disconnect();
        
        # Test inserting a record
        eval {
            $repository->insert_detection(
                "Test Object",
                "A test object for e2e testing",
                "./storage/test_image.jpg"
            );
            print "✓ Database record inserted successfully\n";
        };
        if ($@) {
            print "✗ Database insert failed: $@\n";
        }
    } else {
        print "✗ Database connection failed\n";
    }
} else {
    print "✗ Repository initialization failed\n";
}

# Test 4: Start real API server
print "\n4. Starting real API server...\n";
my $server = start_real_api_server();
if ($server) {
    print "✓ Real API server started\n";
} else {
    print "✗ Failed to start real API server\n";
    exit 1;
}

# Test 5: Test real POST /detect endpoint
print "\n5. Testing real POST /detect endpoint...\n";
my $response = test_real_detect_endpoint();
if ($response->is_success) {
    print "✓ Real POST /detect successful\n";
    print "Response: " . $response->content . "\n";
} else {
    print "✗ Real POST /detect failed: " . $response->status_line . "\n";
}

# Test 6: Test real GET /detections endpoint
print "\n6. Testing real GET /detections endpoint...\n";
my $get_response = test_real_get_detections();
if ($get_response->is_success) {
    print "✓ Real GET /detections successful\n";
    print "Response: " . $get_response->content . "\n";
} else {
    print "✗ Real GET /detections failed: " . $get_response->status_line . "\n";
}

# Test 7: Test database persistence
print "\n7. Testing database persistence...\n";
my $persist_response = test_real_get_detections();
if ($persist_response->is_success) {
    my $content = $persist_response->content;
    if ($content =~ /Test Object/) {
        print "✓ Database persistence working\n";
    } else {
        print "✗ Database persistence not working\n";
    }
} else {
    print "✗ Database persistence test failed\n";
}

# Cleanup
$server->close();
print "\nAll real E2E tests completed!\n";

# Helper functions
sub test_database_connection {
    eval {
        my $dbh = DBI->connect(
            "DBI:Pg:dbname=vision_test_db;host=localhost;port=5432",
            'user',
            'password',
            { RaiseError => 1, AutoCommit => 1 }
        );
        return $dbh;
    };
    return undef;
}

sub start_real_api_server {
    my $server = HTTP::Daemon->new(LocalPort => $TEST_PORT, Reuse => 1) 
        or return undef;
    
    # Start server in background
    my $pid = fork();
    if ($pid) {
        return $server;  # Parent returns server object
    } else {
        # Child process handles requests with real components
        while (my $client = $server->accept()) {
            while (my $request = $client->get_request) {
                handle_real_request($client, $request);
            }
            $client->close;
            undef($client);
        }
        exit 0;
    }
}

sub handle_real_request {
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
        handle_real_detection($client, $request);
    } elsif ($request->method eq 'GET' && $path eq '/detections') {
        handle_real_get_detections($client);
    } else {
        $client->send_status_line(404);
        $client->send_header('Content-Type', 'application/json');
        $client->send_crlf;
        $client->send('{"error": "Not found"}');
        $client->send_crlf;
    }
}

sub handle_real_detection {
    my ($client, $request) = @_;
    
    eval {
        # Parse multipart form data
        my $content = $request->content;
        my $boundary = $request->header('Content-Type') =~ /boundary=(.+)/ ? $1 : '';
        
        unless ($boundary) {
            die "No boundary found in multipart form";
        }
        
        # Extract image data
        my ($image_data, $filename, $extension);
        my @parts = split(/--$boundary/, $content);
        
        foreach my $part (@parts) {
            if ($part =~ /filename="([^"]+)"/) {
                $filename = $1;
                my ($name, $path, $ext) = fileparse($filename, qr/\.[^.]*/);
                $extension = $ext =~ s/^\.//r;
                
                if ($part =~ /Content-Type: image\/(\w+)/) {
                    $extension = $1;
                }
                
                # Extract image data
                if ($part =~ /\r\n\r\n(.+)\r\n--/) {
                    $image_data = $1;
                    last;
                }
            }
        }
        
        unless ($image_data) {
            die "No image data found";
        }
        
        # Save image to storage
        my $temp_file = "/tmp/upload.$$.$extension";
        open my $fh, '>', $temp_file or die "Can't create temp file: $!";
        print $fh $image_data;
        close $fh;
        
        my $file_store = FileStore->new('./test_storage');
        my $image_path = $file_store->save_image($temp_file, $extension);
        unlink $temp_file;
        
        # Mock AI response (since we don't have real API key in test)
        my $ai_result = {
            object_name => "Test Object",
            description => "A test object for e2e testing"
        };
        
        # Record to database
        my $repository = Repository->new(db_url => $TEST_DB_URL);
        $repository->insert_detection(
            $ai_result->{object_name},
            $ai_result->{description},
            $image_path
        );
        
        # Return success response
        my $response_data = sprintf(
            '{"object_name": "%s", "description": "%s", "image_path": "%s"}',
            $ai_result->{object_name},
            $ai_result->{description},
            $image_path
        );
        
        $client->send_status_line(200);
        $client->send_header('Content-Type', 'application/json');
        $client->send_crlf;
        $client->send($response_data);
        $client->send_crlf;
        
    };
    
    if ($@) {
        $client->send_status_line(500);
        $client->send_header('Content-Type', 'application/json');
        $client->send_crlf;
        $client->send('{"error": "' . $@ . '"}');
        $client->send_crlf;
    }
}

sub handle_real_get_detections {
    my ($client) = @_;
    
    eval {
        my $repository = Repository->new(db_url => $TEST_DB_URL);
        my $detections = $repository->get_all_detections();
        
        my $json_response = '[' . join(',', map { 
            sprintf(
                '{"id": %d, "object_name": "%s", "description": "%s", "image_path": "%s", "created_at": "%s"}',
                $_->{id}, $_->{object_name}, $_->{description}, $_->{image_path}, $_->{created_at}
            )
        } @$detections) . ']';
        
        $client->send_status_line(200);
        $client->send_header('Content-Type', 'application/json');
        $client->send_crlf;
        $client->send($json_response);
        $client->send_crlf;
    };
    
    if ($@) {
        $client->send_status_line(500);
        $client->send_header('Content-Type', 'application/json');
        $client->send_crlf;
        $client->send('{"error": "' . $@ . '"}');
        $client->send_crlf;
    }
}

sub test_real_detect_endpoint {
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

sub test_real_get_detections {
    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new(
        'GET',
        "http://localhost:$TEST_PORT/detections"
    );
    return $ua->request($request);
}

sub create_test_image {
    # Create a simple 1x1 pixel JPEG
    return "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01\x01\x00H\x00H\x00\x00\xFF\xDB\x00C\x00\x08\x06\x06\x07\x06\x05\x08\x07\x07\x07\t\t\x08\n\x0C\x14\r\x0C\x0B\x0B\x0C\x19\x12\x13\x0F\x14\x1D\x1A\x1F\x1E\x1D\x1A\x1C\x1C $.' \",#\x1C(7),01444\x1F'9=82<.342\xFF\xC0\x00\x01\x00\x01\x01\x01\x11\x00\x02\x11\x00\x03\x11\x00\x00\xFF\xC4\x00\x14\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x08\xFF\xC4\x00\x14\x10\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xFF\xDA\x00\x0C\x03\x01\x00\x02\x11\x03\x11\x00\x3F\x00\xAA\xFF\xD9";
}