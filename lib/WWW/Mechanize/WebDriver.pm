package WWW::Mechanize::WebDriver;
use strict;
use Selenium::Remote::Driver;
use WWW::Mechanize::Plugin::Selector;
use HTTP::Response;
use HTTP::Headers;

sub new {
    my ($class, %options) = @_;
    
    $options{ port } ||= 4446;
    
    # XXX Need autodie
    
    # Launch PhantomJs
    $options{ launch_exe } ||= 'phantomjs';
    $options{ launch_arg } ||= [ "--webdriver=$options{ port }", #"--webdriver-loglevel=ERROR",
                               ];
    my $cmd= "| $options{ launch_exe } @{ $options{ launch_arg } }";
    $options{ pid } ||= open my $fh, $cmd
        or die "Couldn't launch [$cmd]: $! / $?";
    $options{ fh } = $fh;
    
    # Connect to it
    $options{ driver } ||= Selenium::Remote::Driver->new(
        'port' => $options{ port },
        auto_close => 1,
     );
     
     bless \%options => $class;
};

sub driver {
    $_[0]->{driver}
};

sub DESTROY {
    kill 9 => $_[0]->{ pid }
}

=head1 NAVIGATION METHODS

=head2 C<< $mech->get( $url, %options ) >>

  $mech->get( $url, ':content_file' => $tempfile );

Retrieves the URL C<URL>.

It returns a faked L<HTTP::Response> object for interface compatibility
with L<WWW::Mechanize>. It seems that Selenium and thus L<Selenium::Remote::Driver>
have no concept of HTTP status code and thus no way of returning the
HTTP status code.

Recognized options:

=over 4

=item *

C<< :content_file >> - filename to store the data in

=item *

C<< no_cache >> - if true, bypass the browser cache

=back

=cut

sub update_response {
    my( $self, $phantom_res ) = @_;

    my @headers= map {;%$_} @{ $phantom_res->{headers} };
    my $res= HTTP::Response->new( $phantom_res->{status}, $phantom_res->{statusText}, \@headers );

    # XXX should we fetch the response body?!

    $self->{response} = $res
};

sub get {
    my ($self, $url, %options ) = @_;
    # We need to stringify $url so it can pass through JSON
    my $phantom_res= $self->driver->get( "$url" );

    $self->update_response( $phantom_res );
};

sub decoded_content {
    $_[0]->driver->get_page_source
};

sub content {
    $_[0]->driver->get_page_source
};

sub title {
    $_[0]->driver->get_title;
};

sub response { $_[0]->{response} };
*res = \&response;

=head2 C<< $mech->success() >>

    $mech->get('http://google.com');
    print "Yay"
        if $mech->success();

Returns a boolean telling whether the last request was successful.
If there hasn't been an operation yet, returns false.

This is a convenience function that wraps C<< $mech->res->is_success >>.

=cut

sub success {
    my $res = $_[0]->response( headers => 0 );
    $res and $res->is_success
}

=head2 C<< $mech->selector( $css_selector, %options ) >>

  my @text = $mech->selector('p.content');

Returns all nodes matching the given CSS selector. If
C<$css_selector> is an array reference, it returns
all nodes matched by any of the CSS selectors in the array.

This takes the same options that C<< ->xpath >> does.

This method is implemented via L<WWW::Mechanize::Plugin::Selector>.

=cut

*selector = \&WWW::Mechanize::Plugin::Selector::selector;

sub xpath {
    my( $self, $query, %options) = @_;
    
    if ('ARRAY' ne (ref $query||'')) {
        $query = [$query];
    };

    # XXX I fear we can only search within The One Document, and not
    #     conveniently within IFRAMEs etc.
    if ($options{ node }) {
        $options{ document } ||= $options{ node }->{ownerDocument};
    } else {
        $options{ document } ||= $self->document;
    };

    # XXX Determine if we want only one element
    #     or a list, like WWW::Mechanize::Firefox

    # Now find the elements
    my @elements;
    if( $options{ node }) {
        @elements= map { $self->driver->find_child_elements( $options{ node }, $_ => 'xpath' ) } @$query;
    } else {
        @elements= map { $self->driver->find_elements( $_ => 'xpath' ) } @$query;
    };

    @elements
}

1;
