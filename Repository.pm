package Repository;

use strict;
use warnings;
use DBI;

sub new {
    my ($class, %args) = @_;
    my $self = {
        db_url => $args{db_url} || 'postgresql://user:password@localhost:5432/vision_db'
    };
    
    return bless $self, $class;
}

sub connect {
    my ($self) = @_;
    
    # Parse database URL
    my ($user, $password, $host, $port, $database);
    if ($self->{db_url} =~ /postgresql:\/\/([^:]+):([^@]+)@([^:]+):(\d+)\/(.+)/) {
        $user = $1;
        $password = $2;
        $host = $3;
        $port = $4;
        $database = $5;
    } else {
        die "Invalid database URL format";
    }
    
    # Connect to database
    my $dbh = DBI->connect(
        "DBI:Pg:dbname=$database;host=$host;port=$port",
        $user,
        $password,
        { RaiseError => 1, AutoCommit => 1 }
    );
    
    return $dbh;
}

sub insert_detection {
    my ($self, $object_name, $description, $image_path) = @_;
    
    my $dbh = $self->connect();
    
    my $sth = $dbh->prepare(
        "INSERT INTO detected_objects (object_name, description, image_path) VALUES (?, ?, ?)"
    );
    
    $sth->execute($object_name, $description, $image_path);
    
    $sth->finish();
    $dbh->disconnect();
    
    return 1;
}

sub get_all_detections {
    my ($self) = @_;
    
    my $dbh = $self->connect();
    
    my $sth = $dbh->prepare(
        "SELECT id, object_name, description, image_path, created_at FROM detected_objects ORDER BY created_at DESC"
    );
    
    $sth->execute();
    
    my @detections;
    while (my $row = $sth->fetchrow_hashref()) {
        push @detections, $row;
    }
    
    $sth->finish();
    $dbh->disconnect();
    
    return \@detections;
}

1;