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

package Multimedia::SDP;

=head1 NAME

Multimedia::SDP - The Session Description Protocol parser and generator classes

=head1 SYNOPSIS

 use Multimedia::SDP::Parser;
 use Multimedia::SDP::Generator;

=head1 DESCRIPTION

This library provides classes for parsing and generating Session Description
Protocol session descriptions.

It links to a C library called SinisterSdp that you must have installed.

To get started, see L<Multimedia::SDP::Parser|Multimedia::SDP::Parser> and
L<Multimedia::SDP::Generator|Multimedia::SDP::Generator> for usage of each.

=cut

use 5.005;
use strict;
use warnings;
use vars qw($VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS);
use base 'Exporter';
use Multimedia::SDP::Parser;
use Multimedia::SDP::Generator;

$VERSION = '0.40';

@EXPORT = (
	@Multimedia::SDP::Parser::EXPORT
	@Multimedia::SDP::Generator::EXPORT
);
@EXPORT_OK = (
	@Multimedia::SDP::Parser::EXPORT_OK
	@Multimedia::SDP::Generator::EXPORT_OK
);
%EXPORT_TAGS = (
	%Multimedia::SDP::Parser::EXPORT_TAGS
	%Multimedia::SDP::Generator::EXPORT_TAGS
);

1;

__END__

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
