package Gerrit::REST;
# ABSTRACT: A thin wrapper around Gerrit's REST API

use 5.010;
use utf8;
use strict;
use warnings;

use Carp;
use URI;
use JSON;
use Data::Util qw/:check/;
use REST::Client;
use Gerrit::REST::Exception;

sub new {
    my ($class, $URL, $username, $password, $rest_client_config) = @_;

    $URL = URI->new($URL) if is_string($URL);
    is_instance($URL, 'URI')
        or croak __PACKAGE__ . "::new: URL argument must be a string or a URI object.\n";

    # If no password is set we try to lookup the credentials in the .netrc file
    if (! defined $password) {
        eval {require Net::Netrc}
            or croak "Can't require Net::Netrc module. Please, specify the USERNAME and PASSWORD.\n";
        if (my $machine = Net::Netrc->lookup($URL->host, $username)) { # $username may be undef
            $username = $machine->login;
            $password = $machine->password;
        } else {
            croak "No credentials found in the .netrc file.\n";
        }
    }

    is_string($username)
        or croak __PACKAGE__ . "::new: USERNAME argument must be a string.\n";

    is_string($password)
        or croak __PACKAGE__ . "::new: PASSWORD argument must be a string.\n";

    $rest_client_config = {} unless defined $rest_client_config;
    is_hash_ref($rest_client_config)
        or croak __PACKAGE__ . "::new: REST_CLIENT_CONFIG argument must be a hash-ref.\n";

    my $rest = REST::Client->new($rest_client_config);

    # Set default base URL
    $rest->setHost($URL);

    # Follow redirects/authentication by default
    $rest->setFollow(1);

    # Request compact JSON by default
    $rest->addHeader('Accept' => 'application/json');

    # Configure UserAgent name and password authentication
    for my $ua ($rest->getUseragent) {
        $ua->agent(__PACKAGE__);
        $ua->credentials($URL->host_port, 'Gerrit Code Review', $username, $password);
    }

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

    ## no critic (ErrorHandling::RequireCarping)

    $code =~ /^2/
        or die Gerrit::REST::Exception->new($code, $type, $content);

    if (! defined $type) {
        return;
    } elsif ($type =~ m:^application/json:i) {
        if (substr($content, 0, 4) eq ")]}'") {
            return $self->{json}->decode(substr($content, 5));
        } else {
            die Gerrit::REST::Exception->new(
                '500', 'text/plain',
                "Missing \")]}'\" prefix for JSON content:\n$content\n",
            );
        }
    } elsif ($type =~ m:^text/plain:i) {
        return $content;
    } else {
        die Gerrit::REST::Exception->new(
            '500', 'text/plain',
            "I don't understand content with Content-Type '$type'.\n",
        );
    }

    ## use critic
}

sub GET {
    my ($self, $resource) = @_;

    eval { $self->{rest}->GET("/a$resource") };
    die Gerrit::REST::Exception->new($@) if $@;

    return $self->_content();
}

sub DELETE {
    my ($self, $resource) = @_;

    eval { $self->{rest}->DELETE("/a$resource") };
    die Gerrit::REST::Exception->new($@) if $@;

    return $self->_content();
}

sub PUT {
    my ($self, $resource, $value) = @_;

    eval { $self->{rest}->PUT(
        "/a$resource",
        $self->{json}->encode($value),
        {'Content-Type' => 'application/json;charset=UTF-8'},
    ) };
    die Gerrit::REST::Exception->new($@) if $@;

    return $self->_content();
}

sub POST {
    my ($self, $resource, $value) = @_;

    eval { $self->{rest}->POST(
        "/a$resource",
        $self->{json}->encode($value),
        {'Content-Type' => 'application/json;charset=UTF-8'},
    ) };
    die Gerrit::REST::Exception->new($@) if $@;

    return $self->_content();
}

1;


__END__

=head1 SYNOPSIS

    use Gerrit::REST;

    my $gerrit = Gerrit::REST->new('https://review.example.net', 'myuser', 'mypass');

    # Get a specific project description
    my $project = $gerrit->GET('/projects/myproject');
    print "Name: $project->{name}\n";
    print "Description: $project->{description}\n";

    # Create a new group belonging to the Administrators group
    my $admin_group = $gerrit->GET('/groups/Administrators');
    my $newgroup = $gerrit->PUT('/groups/newgroup', {
        description    => 'New group description.',
        visible_to_all => 'true',
        owner          => $admin_group->{name},
        owner_id       => $admin_group->{group_id},
    });

    # Add an account to the new group
    my $account = $gerrit->GET('/accounts/someuser');
    $gerrit->PUT("/groups/$newgroup->{id}/members/$account->{name}");

    # Review change-id #100, patch-set 3
    $gerrit->POST("/changes/100/revisions/3/review", {
        message => 'Some nits need to be fixed.',
        labels  => {'Code-Review' => -1},
    });

    # How to deal with errors easily
    my $project = eval { $gerrit->GET('/projects/myproject') };
    die $@->as_text if $@;

    # How to deal with errors thoroughly
    my $project = eval { $gerrit->GET('/projects/myproject') };
    if ($@) {
        my ($code, $type, $content) = @{$@}{qw/code type content/};
        # ...
    }

=head1 DESCRIPTION

"L<Gerrit|https://code.google.com/p/gerrit/> is a web based code
review system, facilitating online code reviews for projects using the
Git version control system."

This module is a thin wrapper around L<Gerrit's REST
API|http://gerrit-documentation.googlecode.com/svn/Documentation/2.6/rest-api.html>,
which is superseding it's old L<SSH
API|http://gerrit-documentation.googlecode.com/svn/Documentation/2.6/cmd-index.html>,
for which there is another Perl module called
L<Gerrit::Client|http://search.cpan.org/dist/Gerrit-Client/>.

=head1 CONSTRUCTOR

=head2 new URL, USERNAME, PASSWORD [, REST_CLIENT_CONFIG]

The constructor needs up to four arguments:

=over

=item * URL

A string or a URI object denoting the base URL of the Gerrit
server. This is a required argument.

=item * USERNAME

The username of a Gerrit user.

It can be undefined if PASSWORD is also undefined. In such a case the
user credentials are looked up in the C<.netrc> file.

=item * PASSWORD

The HTTP password of the user. (This is the password the user uses to
log in to Gerrit's web interface.)

It can be undefined, in which case the user credentials are looked up
in the C<.netrc> file.

=item * REST_CLIENT_CONFIG

A Gerrit::REST object uses a REST::Client object to make the REST
invocations. This optional argument must be a hash-ref that can be fed
to the REST::Client constructor. Note that the C<URL> argument
overwrites any value associated with the C<host> key in this hash.

=back

=head1 METHODS

Gerrit's REST API documentation lists dozens of "endpoints" which can
be operated via the standard HTTP requests: GET, DELETE, PUT, and
POST. Gerrit::REST objects implement four methods called GET, DELETE,
PUT, and POST to make it easier to invoke and get results from
Gerrit's REST endpoints.

All four methods need a RESOURCE argument which is simply a string
denoting the endpoint URL's path, as indicated in the documentation.

PUT and POST need a second argument which is the VALUE that's a Perl
data structure (usually a hash-ref, but sometimes a simple string)
which is encoded using the C<encode> method of a C<JSON> object and
passed as contents of the underlying associated HTTP method.

All four methods return the value returned by the associated
endpoint's method, as specified in the documentation, decoded
according to its content type as follows:

=over

=item * application/json

The majority of the API's endpoints return JSON values. Those are
decoded using the C<decode> method of a C<JSON> object. Most of the
endpoints return hashes, which are returned as a Perl hash-ref.

=item * text/plain

Those values are returned as simple strings.

=back

Some endpoints don't return anything. In those cases, the methods
return C<undef>. The methods croak if they get any other type of
values in return.

In case of errors (i.e., if the underlying HTTP method return an error
code different from 2xx) the method dies throwing a
C<Gerrit::REST::Exception> object. These objects are simple hash-refs
containing the C<code>, the C<type>, and the C<content> of the HTTP
error response. So, in order to treat errors you must invoke the
methods in an eval block and test C<$@> or use any of the exception
handling Perl modules, such as C<Try::Tiny> and C<Try::Catch>. The
L</SYNOPSIS> section above shows some examples.

=head2 GET RESOURCE

Returns the RESOURCE as a Perl data structure.

=head2 DELETE RESOURCE

Deletes the RESOURCE.

=head2 PUT RESOURCE, VALUE

Creates RESOURCE based on VALUE.

=head2 POST RESOURCE, VALUE

Updates RESOURCE based on VALUE.

=head1 SEE ALSO

=over

=item * C<REST::Client>

Gerrit::REST uses a REST::Client object to perform the low-level interactions.

=item * C<Gerrit::Client>

Gerrit::Client is another Perl module implementing the other Gerrit
API based on SSH.

=back
