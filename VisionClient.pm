package VisionClient;

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request::Common;
use MIME::Base64;

sub new {
    my ($class, %args) = @_;
    my $self = {
        api_key => $args{api_key},
        model => $args{model} || 'nvidia/nemotron-nano-12b-v2-vl:free',
        timeout => $args{timeout} || 30
    };
    
    die "API key required" unless $self->{api_key};
    
    return bless $self, $class;
}

sub analyze_image {
    my ($self, $image_data, $image_type) = @_;
    
    # Create base64 encoded image data
    my $encoded_image = encode_base64($image_data, '');
    
    # Prepare the request
    my $prompt = "Identify the main object in this image and give a brief description.";
    
    my $request_data = {
        model => $self->{model},
        messages => [
            {
                role => 'user',
                content => [
                    { type => 'text', text => $prompt },
                    {
                        type => 'image_url',
                        image_url => {
                            url => "data:image/$image_type;base64,$encoded_image"
                        }
                    }
                ]
            }
        ]
    };
    
    # Make HTTP request
    my $ua = LWP::UserAgent->new;
    $ua->timeout($self->{timeout});
    $ua->default_header('Authorization' => "Bearer $self->{api_key}");
    $ua->default_header('Content-Type' => 'application/json');
    $ua->default_header('HTTP-Referer' => 'http://localhost:8080');
    $ua->default_header('X-Title' => 'Solo Dev Vision API');
    
    my $response = $ua->post(
        'https://openrouter.ai/api/v1/chat/completions',
        Content => $self->encode_json($request_data)
    );
    
    if (!$response->is_success) {
        die "OpenRouter API error: " . $response->status_line;
    }
    
    my $response_data = $self->decode_json($response->content);
    
    # Extract the response text
    my $response_text = $response_data->{choices}[0]{message}{content} || '';
    
    # Simple parsing to extract object name and description
    my ($object_name, $description);
    if ($response_text =~ /^(.+?):\s*(.+)$/) {
        $object_name = $1;
        $description = $2;
    } else {
        $object_name = "Unknown Object";
        $description = $response_text;
    }
    
    return {
        object_name => $object_name,
        description => $description
    };
}

sub encode_json {
    my ($self, $data) = @_;
    # Simple JSON encoder for basic data structures
    my $json = '{';
    my $first = 1;
    
    foreach my $key (keys %$data) {
        unless ($first) {
            $json .= ',';
        }
        $first = 0;
        
        $json .= '"' . $key . '":';
        
        if (ref $data->{$key} eq 'HASH') {
            $json .= $self->encode_json($data->{$key});
        } elsif (ref $data->{$key} eq 'ARRAY') {
            $json .= '[' . join(',', map { '"' . $_ . '"' } @{$data->{$key}}) . ']';
        } else {
            $json .= '"' . $data->{$key} . '"';
        }
    }
    
    $json .= '}';
    return $json;
}

sub decode_json {
    my ($self, $json) = @_;
    # Simple JSON decoder for basic response structure
    my $data = {};
    
    if ($json =~ /"model"\s*:\s*"([^"]+)"/) {
        $data->{model} = $1;
    }
    
    if ($json =~ /"choices"\s*:\s*\[\s*\{\s*"message"\s*:\s*\{\s*"content"\s*:\s*"([^"]+)"/) {
        $data->{choices} = [{ message => { content => $1 } }];
    }
    
    return $data;
}

1;