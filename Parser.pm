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

package Multimedia::SDP::Parser;

=head1 NAME

Multimedia::SDP::Parser - The SDP parser class

=head1 SYNOPSIS

 use Multimedia::SDP::Parser;
 
 my $parser = new Multimedia::SDP::Parser;
 
 my $description = $parser->parse($string);
 
 # or:
 
 my $description = $parser->parse_file($filename);

 # or:

 $parser->start_handler(sub {...});
 $parser->field_handler(sub {...});
 $parser->end_handler(sub {...});

 $parser->event_stream_parse($string);

=head1 DESCRIPTION

This class contains methods to parse SDP session descriptions.

=head1 METHODS

The following methods are available:

=cut

use 5.005;
use strict;
use warnings;
use vars qw(@EXPORT @EXPORT_OK %EXPORT_TAGS);
use base 'Exporter'
use Multimedia::SDP::SinisterSdp;

@EXPORT      = @Multimedia::SDP::SinisterSdp::EXPORT;
@EXPORT_OK   = @Multimedia::SDP::SinisterSdp::EXPORT_OK;
%EXPORT_TAGS = %Multimedia::SDP::SinisterSdp::EXPORT_TAGS;

1;

__END__

=head2 new()

The constructor method. Creates a new Multimedia::SDP::Parser object and
returns a reference to it.

=head2 parse(STRING)

This function parses one or more SDP session descriptions from a string into
B<Multimedia::SDP::Description> objects. If there are multiple descriptions,
then it returns an array of B<Multimedia::SDP::Description> objects in list
context, and just the first description in scalar context.

It returns undef if an error occurred and it had to stop parsing.

You can retrieve and modify the various parts of the descriptions encapsulated
by B<Multimedia::SDP::Description> objects with the methods outlined in
L<Multimedia::SDP::Description|Multimedia::SDP::Description>.

=head2 parse_file(FILENAME)

This function parses one or more SDP session descriptions from the specified
file into B<Multimedia::SDP::Description> objects. If there are multiple
descriptions in the file, then it returns an array of
B<Multimedia::SDP::Description> objects in list context, and just the first
description in scalar context.

It returns undef if an error occurred and it couldn't open the file or parse
the descriptions inside.

You can retrieve and modify the various parts of the descriptions encapsulated
by B<Multimedia::SDP::Description> objects with the methods outlined in
L<Multimedia::SDP::Description|Multimedia::SDP::Description>.

=head2 event_stream_parse(STRING)

This method provides access to the lower-level event stream parser. It parses
the string as an event stream and calls various event handlers as it goes, and
returns true if it successfully parses the stream, flase otherwise. It also
passes on to each handler a reference to some piece of data if you specify one.

The handlers you can register are:

 1) a start handler to be invoked before the parser starts parsing;

 2) a start-of-description handler to be invoked when the current field
    denotes the start of an SDP description (a "v" field);

 3) a field handler to be invoked for each field;

 4) an end-of-description handler to be invoked when the current field
    denotes the end of a description (a subsequint "v" field or the end
    of the stream);

 5) and then an end handler to be invoked when it stops parsing.

The end handler (if registered) will be invoked when parsing stops regardless
of whether or not it stops after successfully parsing the stream or stops
because of an error (this is to enable you to do any neccessary cleanup). As
a convience, the return value detailed below will also be passed on to the
end handler.

You can register a non-fatal error handler to catch parser errors and decide
dynamically whether or not you want it to keep parsing. See
L<Multimedia::SDP|Multimedia::SDP> for more information on this.

=head2 event_stream_parse_file(FILENAME)

This method works just like C<event_stream_parse()> except instead of a
string to parse, it takes the name of a file, opens it, and then parses the
file as an event stream.

=head2 start_handler([HANDLER])

This is a get/set method that enables you to register a start handler to be
called when parsing starts. Any suboutine reference you supply will be invoked
with the parser object as the first argument and a reference to the user
data as the second argument.

=head2 start_description_handler([HANDLER])

This is a get/set method that enables you to register a start-of-description
handler to be called when the parser encounters the start of a new session
description. Any subroutine reference you supply will be invoked with the
parser object as the first argument, the number of this description (1 for the
first description encountered, 2 for second, etc.) as the second argument, and
a reference to the user data as the third argument.

=head2 field_handler([HANDLER])

This is a get/set method that enables you to register a field handler to be
invoked for each and every SDP field encountered. Any subroutine reference you
supply will be invoked with the parser object as the first argument, a string
containing the field type (e.g., "v", "o", "c") as the second argument, a
string containing the field value as the third argument, and a reference to the
user data as the fourth argument.

=head2 end_description_handler([HANDLER])

This is a get/set method that enables you to register an end-of-description
handler to be called when the parser encounters a description-terminating "v"
field while parsing a description or the end of the stream. Any subroutine
reference you supply will be invoked with the parser object as the first
argument, the number of this description (1 for the first description ending, 2
for second, etc.) as the second argument, and a reference to the user data as
the third argument.

=head2 end_handler([HANDLER])

This is a get/set method that enables you to register an end handler to be
called when parsering terminates. Any subroutine reference you supply will be
invoked with the parser object as the first argument, the result of parsing
(true or false for success or failure) as the second argument, and a reference
to the user data as the third argument.

=head2 user_data([REFERENCE])

This is a get/set method that lets you specify a piece of data to be passed by
reference to each handler the parser invokes. It can be a reference to a hash,
array, whatever.

=head2 current_line_number()

This method returns the current line number of the line being parsed in the
stream.

=head2 current_description_number()

This method returns the number of the current description being parsed (e.g.,
1 for the first description, 2 for the second, etc.).

=head2 current_field_type()

This method returns the type character of the current SDP field being parsed.

=head2 current_field()

This method returns a string containing the value of the current SDP field
being parsed.

=head2 field_encountered(TYPE)

This method returns the number of times a certain type of field has been
encountered for the description being parsed.

=head1 BUGS

Bugs in this package can be reported and monitored using CPAN's request tracker.

You can also email me directly via
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
