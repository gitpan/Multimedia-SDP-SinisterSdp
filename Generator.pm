################################################################################
#
# Copyright 2004 by William G. Davis.
#
# This library is free software released under the terms of the GNU Lesser
# General Public License (LGPL), the full terms of which can be found in the
# "COPYING" file that comes with the distribution.
#
# This library is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.
#
################################################################################

package Multimedia::SDP::Generator;

=head1 NAME

Multimedia::SDP::Generator - The SDP generator class

=head1 SYNOPSIS

 use Multimedia::SDP::Generator;

 my $generator = new Multimedia::SDP::Generator;

 $generator->v_field(0);
 $generator->o_field(
 	'username', 'session_id', 'session.version', 'IN', 'IP4', '127.0.0.1'
 );
 $generator->s_field('The name of my session');
 $generator->i_field('A short descrition of my session');
 $generator->u_field('http://url.to.my.session');
 $generator->e_field('someone@somewhere', 'Some One');
 $generator->c_field('IN', 'IP4', '127.0.0.1');
 $generator->t_field(time + (60 * 60 * 2)); # in two hours
 $generator->a_field('recvonly');
 $generator->m_field('audio', '49170', 'RTP/AVP', "0");

 print $generator->output;

=head1 DESCRIPTION

This class contains routines to enable you to generate an SDP description
programmatically.

=head1 METHODS

The following methods are available:

=cut

use 5.005;
use strict;
use warnings;
use vars qw(@EXPORT @EXPORT_OK %EXPORT_TAGS);
use base 'Exporter';
use Multimedia::SDP::SinisterSdp;

@EXPORT      = @Multimedia::SDP::SinisterSdp::EXPORT;
@EXPORT_OK   = @Multimedia::SDP::SinisterSdp::EXPORT_OK;
%EXPORT_TAGS = %Multimedia::SDP::SinisterSdp::EXPORT_TAGS;

1;

__END__

=head2 new()

This is the constructor method; it creates a new B<Multimedia::SDP::Generator>
object and returns a reference to it.

=head2 v_field(VERSION)

This method generates a protocol version ("v") field. It takes a version number
as its only argument.

=head2 o_field(OWNER_OBJECT | USERNAME, SESSION_ID, SESSION_VERSION, NETWORK_TYPE, ADDRESS_TYPE, ADDRESS)

This function generates a session owner ("o") field, optionally from a
B<Multimedia::SDP::Owner> object.

If you don't supply a B<Multimedia::SDP::Owner> object, then this method takes the
following arguments:

=over 4

=item USERNAME

(Optional.) The username of the originator of the session (defaults to "-").

=item SESSION_ID

A string containing the session ID.

=item SESSION_VERSION

A string containing the session version number (e.g., "v1.50").

=item NETWORK_TYPE

A string containing the type of network (e.g., "IN" for Internet).

=item ADDRESS_TYPE

A string containing the type of address (e.g., "IP4" for IPv4).

=item ADDRESS

A string containing the IP address (e.g., "127.0.0.1").

=back

=head2 s_field(SESSION_NAME)

This method generates a session name ("s") field.

It takes the session name as its only argument

=head2 i_field(INFORMATION)

This function generates either a session information or media information ("s")
field.

It takes a short description of the session or media as its only argument.

=head2 u_field(URI)

This method generates a URI ("u") field containing the URI of the session
description.

It takes a URI as its only argument.

=head2 e_field(EMAIL_CONTACT_OBJECT | EMAIL_ADDRESS, NAME)

This method generates an email contact information ("e") field, optionally from
a B<Multimedia::SDP::EmailContact> object.

If you don't supply a B<Multimedia::SDP::EmailContact> object, then this method
takes the following arguments:

=over 4

=item EMAIL_ADDRESS

A string containing an email address of someone.

=item NAME

(Optional.) A string containing the name of the person who can be reached at
that address.

=back

=head2 p_field(PHONE_CONTACT_OBJECT | PHONE_NUMBER, NAME)

This method generates a telephone contact information ("p") field, optionally
from a B<Multimedia::SDP::PhoneContact> object.

If you don't supply a B<Multimedia::SDP::PhoneContact> object, then this method
takes the following arguments:

=over 4

=item PHONE_NUMBER

A string containing a phone number.

=item NAME

(Optional.) The name of the person who can be reached at that number.

=back

=head2 c_field(CONNECTION_OBJECT | NETWORK_TYPE, ADDRESS_TYPE, ADDRESS, TTL, TOTAL_ADDRESSES)

This method generates a connection information ("c") field for the session or
an individual media, optionally from a B<Multimedia::SDP::Connection> object.

If you don't supply a B<Multimedia::SDP::Connection>, then this method takes the
following parameters:

=over 4

=item NETWORK_TYPE

A string containing the network type (e.g., "IN" for Internet).

=item ADDRESS_TYPE

A string containing the address type (e.g., "IP4" for IPv4).

=item ADDRESS

A string containing the IP address to connect to (e.g., "127.0.0.1").

=item TTL

(Optional.) For UDP multicast, the Time To Live.

=item TOTAL_ADDRESSES

(Optional.) For UDP multicast, counting up from the final IP block in
I<ADDRESS>, how many addresses are available?

=back

=head2 b_field(BANDWIDTH_OBJECT | BANDWIDTH_MODIFIER, BANDWIDTH_VALUE)

This method generates a bandwidth information ("b") field, optionally from a
B<Multimedia::SDP::Bandwidth> object.

If you don't supply a B<Multimedia::SDP::Bandwidth> object, then this method takes
the following arguments:

=over 4

=item BANDWIDTH_MODIFIER

A string containing what I<BANDWIDTH_VALUE> applies to (e.g., "CT" for the
conference total).

=item BANDWIDTH_VALUE

A number that's the available bandwidth in kilobits per second.

=back

=head2 t_field(SESSION_PLAY_TIME_OBJECT | START_TIME, STOP_TIME)

This method generates a session time ("t") field, optionally from a
B<Multimedia::SDP::SessionPlayTime> object.

If you don't supply a B<Multimedia::SDP::SessionPlayTime> object, then this method
takes the following arguments:

=over 4

=item START_TIME

The start time of the session as a Perl C<time()> value (the number of seconds
since epoch). This will be converted to an NTP timestamp.

=item END_TIME

The end time of the session as a Perl C<time()> value (the number of seconds
since epoch). This will be converted to an NTP timestamp.

=back

=head2 r_field(REPEAT_TIME_OBJECT | REPEAT_INTERVAL, ACTIVE_DURATION, REPEAT_OFFSETS)

This method generates a repeat times ("r") field, optionally from a
B<Multimedia::SDP::RepeatTime> object.

If you don't supply a B<Multimedia::SDP::RepeatTime> object, then this method takes the
following arguments:

=over 4

=item REPEAT_INTERVAL

The repeat interval.

=item ACTIVE_DURATION

The active duration of the session.

=item REPEAT_OFFSETS

The repeat offsets, either as a reference to an array containing each offset as elements, or one big string containing all of the offsets separated by spaces.

=back

=head2 z_field(ZONE_ADJUSTMENT_OBJECTS | TIME, OFFSET, ...)

This method generates a time zone adjustment ("z") field.

You can supply either an array of C<Multimedia::SDP::ZoneAdjusment> objects or an
array containing pairs of the following:

=over 4

=item TIME

A Perl C<time()> value of when some type of zone adjustment is to occur.

=item OFFSET

The adjustment to make (e.g., "+1h" for add an hour or "-1h" for subtract an
hour).

=back

=head2 k_field(ENCRYPTION_OBJECT | METHOD, KEY)

This method generates an encryption information ("k") field, optionally from a
B<Multimedia::SDP::Encryption> object.

If you don't supply a B<Multimedia::SDP::Encryption> object, then this method
takes the following arguments:

=over 4

=item METHOD

The encryption method (e.g., "PGP").

=item KEY

(Optional.) The encryption key.

=back

=head2 a_field(ATTRIBUTE_OBJECT | NAME, VALUE)

This method generates a session attribute or media attribute ("a") field,
optionally from a B<Multimedia::SDP::Attribute> object.

If you don't supply a B<Multimedia::SDP::Attribute> object, then this method takes
the following arguments:

=over 4

=item NAME

The attribute name.

=item VALUE

(Optional.) The attribute value.

=back

=head2 m_field(MEDIA_DESCRIPTION_OBJECT | MEDIA_TYPE, PORT, TOTAL_PORTS, TRANSPORT_PROTOCOL, FORMATS)

This method generates a media description ("m") field, and if you supply a
B<Multimedia::SDP::MediaDescription> object, all other fields that go with it.

If you don't supply a B<Multimedia::SDP::MediaDescription> object, then this method
takes the following arguments:

=over 4

=item MEDIA_TYPE

A string containing the media type.

=item PORT

The port number.

=item TOTAL_PORTS

The number of ports available, counting up from I<PORT>.

=item TRANSPORT_PROTOCOL

A string containing the transport protocol.

=item FORMATS

The media formats, either as a reference to an array containing the formats as
elements, or one big string containing the media formats separated by spaces.

=back

=head2 output()

This method returns a string containing the generated SDP description(s).

=head2 save_output(FILENAME)

This method saves the generates SDP description(s) to the specified file.

=head1 BUGS

Bugs in this package can be reported and monitored using CPAN's request
tracker: http://rt.cpan.org.

You can also email me directly:
<william_g_davis at users dot sourceforge dot net>.

=head1 COPYRIGHT

Copyright 2004 by William G. Davis.

This library is free software released under the terms of the GNU Lesser
General Public License (LGPL), the full terms of which can be found in the
"COPYING" file that comes with the distribution.

This library is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.

=cut
