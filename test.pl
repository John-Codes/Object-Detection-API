#!/usr/bin/perl

use strict;
use warnings;
use Test::Simple tests => 9;
use lib '.';
use FileStore;
use VisionClient;
use Repository;
use HTTP::Daemon;
use HTTP::Request;
use HTTP::Response;
use LWP::UserAgent;
use File::Temp;
use MIME::Base64;

# Test 1: FileStore functionality
print "Testing FileStore...\n";
my $file_store = FileStore->new('./test_storage');
ok($file_store, "FileStore object created");

# Create a test image file
my $test_image = create_test_image();
my $temp_file = File::Temp->new(SUFFIX => '.jpg');
print $temp_file $test_image;
close $temp_file;

# Test saving image
my $image_path = $file_store->save_image($temp_file->filename, 'jpg');
ok(-f $image_path, "Image saved successfully");
unlink $temp_file;

# Test 2: VisionClient functionality (mock test)
print "\nTesting VisionClient...\n";
my $vision_client = VisionClient->new(api_key => 'test_key');
ok($vision_client, "VisionClient object created");

# Test 3: Repository functionality (mock test)
print "\nTesting Repository...\n";
my $repository = Repository->new(db_url => 'postgresql://test:test@localhost:5432/test_db');
ok($repository, "Repository object created");

# Test 4: HTTP Server functionality
print "\nTesting HTTP Server...\n";
my $server = HTTP::Daemon->new(LocalPort => 8081, Reuse => 1);
ok($server, "HTTP server created");

# Test 5: Test image creation
print "\nTesting image creation...\n";
my $test_image_data = create_test_image();
ok(length($test_image_data) > 0, "Test image created");

# Test 6: Test JSON encoding/decoding
print "\nTesting JSON functionality...\n";
my $test_data = { test => "value", number => 42 };
my $json_string = '{"test": "value", "number": 42}';
my $decoded_data = simple_json_decode($json_string);
ok($decoded_data->{test} eq "value", "JSON decode works");

# Test 7: Test file operations
print "\nTesting file operations...\n";
my $test_file = File::Temp->new();
print $test_file "test content";
close $test_file;
open my $fh, '<', $test_file->filename or die "Can't read test file: $!";
my $content = do { local $/; <$fh> };
close $fh;
ok($content eq "test content", "File read/write works");
unlink $test_file;

# Test 8: Test multipart form data parsing
print "\nTesting multipart parsing...\n";
my $multipart_data = create_multipart_test();
my ($extracted_data, $extracted_filename) = parse_multipart($multipart_data);
ok($extracted_filename eq "test.jpg", "Multipart parsing works");

print "\nAll basic tests completed!\n";

# Helper functions
sub create_test_image {
    # Create a simple 1x1 pixel JPEG
    return "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01\x01\x00H\x00H\x00\x00\xFF\xDB\x00C\x00\x08\x06\x06\x07\x06\x05\x08\x07\x07\x07\t\t\x08\n\x0C\x14\r\x0C\x0B\x0B\x0C\x19\x12\x13\x0F\x14\x1D\x1A\x1F\x1E\x1D\x1A\x1C\x1C $.' \",#\x1C(7),01444\x1F'9=82<.342\xFF\xC0\x00\x01\x00\x01\x01\x01\x11\x00\x02\x11\x00\x03\x11\x00\x00\xFF\xC4\x00\x14\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x08\xFF\xC4\x00\x14\x10\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xFF\xDA\x00\x0C\x03\x01\x00\x02\x11\x03\x11\x00\x3F\x00\xAA\xFF\xD9";
}

sub simple_json_decode {
    my ($json) = @_;
    my $result = {};
    if ($json =~ /"([^"]+)"\s*:\s*"([^"]+)"/) {
        $result->{$1} = $2;
    }
    return $result;
}

sub create_multipart_test {
    my $boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW";
    my $content = "--$boundary\r\n";
    $content .= "Content-Disposition: form-data; name=\"image\"; filename=\"test.jpg\"\r\n";
    $content .= "Content-Type: image/jpeg\r\n\r\n";
    $content .= create_test_image();
    $content .= "\r\n--$boundary--\r\n";
    return $content;
}

sub parse_multipart {
    my ($content) = @_;
    my $boundary = $content =~ /----(.+?)\r\n/ ? $1 : '';
    my $filename = '';
    my $data = '';
    
    if ($content =~ /filename="([^"]+)"/) {
        $filename = $1;
    }
    
    if ($content =~ /\r\n\r\n(.+)\r\n--$boundary--/) {
        $data = $1;
    }
    
    return ($data, $filename);
}