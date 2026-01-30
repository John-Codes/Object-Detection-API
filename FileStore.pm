package FileStore;

use strict;
use warnings;
use File::Basename;
use File::Path qw(make_path);
use File::Copy;
use Time::HiRes qw(time);

sub new {
    my ($class, $storage_dir) = @_;
    my $self = {
        storage_dir => $storage_dir || './storage'
    };
    
    # Create storage directory if it doesn't exist
    make_path($self->{storage_dir}) unless -d $self->{storage_dir};
    
    return bless $self, $class;
}

sub save_image {
    my ($self, $temp_file, $extension) = @_;
    
    # Generate unique filename using timestamp
    my $timestamp = time();
    my $microseconds = sprintf("%06d", ($timestamp - int($timestamp)) * 1000000);
    my $filename = "image_${timestamp}_${microseconds}.${extension}";
    my $filepath = $self->{storage_dir} . "/$filename";
    
    # Copy file to storage
    copy($temp_file, $filepath) or die "Failed to save image: $!";
    
    return $filepath;
}

sub get_image_path {
    my ($self, $filename) = @_;
    return $self->{storage_dir} . "/$filename";
}

1;