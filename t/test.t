use strict;
use warnings;
use Test;
use Devel::Peek;

use lib qw(.. ../blib);

BEGIN { plan tests => 22 }

use Multimedia::SDP::SinisterSdp;
ok(1);

my $parser = Multimedia::SDP::Parser->new_parser();
ok(UNIVERSAL::isa($parser, 'Multimedia::SDP::Parser'));

my $description = $parser->parse_file('./t/test.sdp');
ok($description->protocol_version, 7);

{
	my $owner = $description->get_owner;
	ok(UNIVERSAL::isa($owner, 'Multimedia::SDP::Owner'));

	ok($owner->username, 'wgdavis');
	ok($owner->session_id, '2890844526');
	ok($owner->session_version, 'v1.001');
	ok($owner->network_type, 'IN');
	ok($owner->address_type, 'IP4');
	ok($owner->address, '127.0.0.1');
}

ok($description->session_name, 'Test SDP Description');
ok($description->session_information,
	'A simple SDP description to test the SinisterSdp Perl module.');
ok($description->uri, 'http://search.cpan.org/dist/Multimedia-SDP');

{
	my $email_contact = $description->get_email_contacts;
	ok(UNIVERSAL::isa($email_contact, 'Multimedia::SDP::EmailContact'));

	ok($email_contact->address, 'william_g_davis@users.sourceforge.net');
	ok($email_contact->name, 'William G. Davis');
}

{
	my $connection = $description->get_connection;
	ok(UNIVERSAL::isa($connection, 'Multimedia::SDP::Connection'));

	ok($connection->network_type, 'IN');
	ok($connection->address_type, 'IP4');
	ok($connection->address, '127.0.0.1');
	ok($connection->ttl, 120);
}

my $start_handler = sub { };

$parser->set_start_handler($start_handler);

ok($parser->get_start_handler == $start_handler);
