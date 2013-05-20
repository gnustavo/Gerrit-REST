use 5.010;
use utf8;
use strict;
use warnings;

package Gerrit::REST;
# ABSTRACT: A thin wrapper around Gerrit's REST API

use Carp;
use URI;
use JSON;
use Data::Util qw/:check/;
use REST::Client;

sub new {
    my ($class, $URL, $username, $password, $rest_client_config) = @_;

    $URL = URI->new($URL) if is_string($URL);
    is_instance($URL, 'URI')
        or croak __PACKAGE__ . "::new: URL argument must be a string or a URI object.\n";

    is_string($username)
        or croak __PACKAGE__ . "::new: USERNAME argument must be a string.\n";

    is_string($password)
        or croak __PACKAGE__ . "::new: PASSWORD argument must be a string.\n";

    $rest_client_config = {} unless defined $rest_client_config;
    is_hash_ref($rest_client_config)
        or croak __PACKAGE__ . "::new: REST_CLIENT_CONFIG argument must be a hash-ref.\n";

    $rest_client_config->{host} = $URL;

    my $rest = REST::Client->new($rest_client_config);

    # Request compact JSON by default
    $rest->addHeader('Accept' => 'application/json');

    # Configure password authentication
    $rest->getUseragent()->credentials($URL->host_port, 'Gerrit Code Review', $username, $password);

    return bless {
        rest => $rest,
        json => JSON->new->utf8->allow_nonref,
    } => $class;
}

sub _content {
    my ($self) = @_;

    my $rest    = $self->{rest};
    my $code    = $rest->responseCode();
    my $type    = $rest->responseHeader('Content-Type');
    my $content = $rest->responseContent();

    unless ($code =~ /^2/) {
        require HTTP::Status;
        my $message = HTTP::Status::status_message($code) || '(unknown)';
        croak "ERROR: $code - $message\n$type\n$content\n";
    }

    if (! defined $type) {
        return undef;
    } elsif ($type =~ m:^application/json:i) {
        if (substr($content, 0, 4) eq ")]}'") {
            return $self->{json}->decode(substr($content, 5));
        } else {
            croak "Missing \")]}'\" prefix for JSON content:\n$content\n";
        }
    } elsif ($type =~ m:^text/plain:i) {
        return $content;
    } else {
        croak "I don't understand content with Content-Type '$type'.\n";
    }
}

sub GET {
    my ($self, $resource) = @_;

    $self->{rest}->GET("/a$resource");

    return $self->_content();
}

sub DELETE {
    my ($self, $resource) = @_;

    $self->{rest}->DELETE("/a$resource");

    return $self->_content();
}

sub PUT {
    my ($self, $resource, $value) = @_;

    $self->{rest}->PUT(
        "/a$resource",
        $self->{json}->encode($value),
        {'Content-Type' => 'application/json;charset=UTF-8'},
    );

    return $self->_content();
}

sub POST {
    my ($self, $resource, $value) = @_;

    $self->{rest}->POST(
        "/a$resource",
        $self->{json}->encode($value),
        {'Content-Type' => 'application/json;charset=UTF-8'},
    );

    return $self->_content();
}

1;
