use strict;
use warnings;
use diagnostics;
use Test;

BEGIN {
	plan(tests => 24);

	eval {
		require Multimedia::SDP::Parser;
		Multimedia::SDP::Parser->import;
	};
	ok(!$@);

	eval {
		require Multimedia::SDP::Generator;
		Multimedia::SDP::Generator->import;
	};
	ok(!$@);
}

my $parser = new Multimedia::SDP::Parser;
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

my $generator = new Multimedia::SDP::Generator;

$generator->v(0);
$generator->o(
	'username', 'session_id', 'session.version', 'IN', 'IP4', '127.0.0.1'
);
$generator->s('The name of my session');
$generator->i('A short descrition of my session');
$generator->u('http://url.to.my.session');
$generator->e('someone@somewhere', 'Some One');
$generator->c('IN', 'IP4', '127.0.0.1');
my $time = time + (60 * 60 * 2); # in two hours
$generator->t($time);
$generator->a('recvonly');

my $network_time = $time + 2208988800;
ok($generator->output, <<END_OF_OUTPUT);
v=0
o=username session_id session.version IN IP4 127.0.0.1
s=The name of my session
i=A short descrition of my session
u=http://url.to.my.session
e=Some One <someone\@somewhere>
c=IN IP4 127.0.0.1
t=$network_time 0
a=recvonly
END_OF_OUTPUT
