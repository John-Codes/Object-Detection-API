#!/usr/bin/perl

use strict;
use warnings;
use lib '.';
use FileStore;
use VisionClient;
use Repository;

# Simple HTTP server using built-in modules
use HTTP::Daemon;
use HTTP::Status;
use URI::Escape;

# Configuration
my $PORT = 8080;
my $STORAGE_DIR = './storage';
my $OPENROUTER_API_KEY = $ENV{OPENROUTER_API_KEY} || die "OPENROUTER_API_KEY environment variable required";
my $DB_URL = $ENV{DB_URL} || 'postgresql://user:password@localhost:5432/vision_db';

# Initialize components
my $file_store = FileStore->new($STORAGE_DIR);
my $vision_client = VisionClient->new(api_key => $OPENROUTER_API_KEY);
my $repository = Repository->new(db_url => $DB_URL);

# Start HTTP server
my $server = HTTP::Daemon->new(LocalPort => $PORT, Reuse => 1) or die "Cannot start server: $!";

print "Server started on port $PORT\n";
print "Access at http://localhost:$PORT\n";

while (my $client = $server->accept()) {
    eval {
        while (my $request = $client->get_request) {
            handle_request($client, $request);
        }
    };
    if ($@) {
        print "Error: $@\n";
    }
    $client->close;
    undef($client);
}

sub handle_request {
    my ($client, $request) = @_;
    
    # Set CORS headers
    $client->send_header('Access-Control-Allow-Origin', '*');
    $client->send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    $client->send_header('Access-Control-Allow-Headers', 'Content-Type');
    
    if ($request->method eq 'OPTIONS') {
        $client->send_status_line(200);
        return;
    }
    
    my $path = $request->uri->path;
    
    if ($request->method eq 'POST' && $path eq '/detect') {
        handle_detection($client, $request);
    } elsif ($request->method eq 'GET' && $path eq '/detections') {
        handle_get_detections($client);
    } else {
        $client->send_error_status_line(404);
        $client->send_header('Content-Type', 'application/json');
        $client->send_body({ error => "Not found" });
    }
}

sub handle_detection {
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
        
        my $image_path = $file_store->save_image($temp_file, $extension);
        unlink $temp_file;
        
        # Ask the AI
        my $ai_result = $vision_client->analyze_image($image_data, $extension);
        
        # Record to database
        $repository->insert_detection(
            $ai_result->{object_name},
            $ai_result->{description},
            $image_path
        );
        
        # Return success response
        $client->send_status_line(200);
        $client->send_header('Content-Type', 'application/json');
        $client->send_body({
            object_name => $ai_result->{object_name},
            description => $ai_result->{description},
            image_path => $image_path
        });
        
    };
    
    if ($@) {
        $client->send_status_line(500);
        $client->send_header('Content-Type', 'application/json');
        $client->send_body({ error => $@ });
    }
}

sub handle_get_detections {
    my ($client) = @_;
    
    eval {
        my $detections = $repository->get_all_detections();
        
        $client->send_status_line(200);
        $client->send_header('Content-Type', 'application/json');
        $client->send_body($detections);
    };
    
    if ($@) {
        $client->send_status_line(500);
        $client->send_header('Content-Type', 'application/json');
        $client->send_body({ error => $@ });
    }
}