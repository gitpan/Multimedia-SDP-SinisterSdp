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

package Multimedia::SDP::SinisterSdp;

=head1 NAME

Multimedia::SDP::SinisterSdp - The Perl interface to the SinisterSdp C library

=head1 SYNOPSIS

 use Multimedia::SDP;
 ...

=head1 DESCRIPTION

Do not use this module directly. It contains only wrapper routines around the
XSubs that link to the corresponding C routines. The routines here work to make
the C interface much more Perl-ish.

=cut

use 5.005;
use strict;
use warnings;

BEGIN {

	use vars qw($VERSION @ISA @EXPORT);
	use Carp;

	use Exporter;
	use DynaLoader;

	$VERSION = '0.45';

	push(@ISA, qw(Exporter DynaLoader));

	@EXPORT = qw(
		NO_ERROR
		ERR_GENERIC
		ERR_OUT_OF_MEMORY
		ERR_FILE_OPEN_FAILED
		ERR_MALFORMED_FIELD
		ERR_EMPTY_FIELD
		ERR_INVALID_TYPE_CHARACTER
		ERR_MULTIPLE_UNIQUE_FIELDS
		ERR_FEILDS_OUT_OF_SEQUENCE
	);

	bootstrap Multimedia::SDP::SinisterSdp $VERSION;
}

# set default error handlers:
set_fatal_error_handler(sub { croak shift });
set_non_fatal_error_handler(
	sub {
		carp shift;
		return 1;
	}
);







################################################################################
#
# The subroutines for the Parser class:
#
################################################################################

package Multimedia::SDP::Parser;

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	return $class->new_parser;
}





sub start_handler
{
	my $self = shift;

	if (@_)
	{
		$self->set_start_handler(shift);
	}
	else
	{
		return $self->get_start_handler;
	}
}





sub start_description_handler
{
	my $self = shift;

	if (@_)
	{
		$self->set_start_description_handler(shift);
	}
	else
	{
		return $self->get_start_description_handler;
	}
}





sub field_handler
{
	my $self = shift;

	if (@_)
	{
		$self->set_field_handler(shift);
	}
	else
	{
		return $self->get_field_handler;
	}
}





sub end_description_handler
{
	my $self = shift;

	if (@_)
	{
		$self->set_end_description_handler(shift);
	}
	else
	{
		return $self->get_end_description_handler;
	}
}





sub end_handler
{
	my $self = shift;

	if (@_)
	{
		$self->set_end_handler(shift);
	}
	else
	{
		return $self->get_end_handler;
	}
}





sub user_data
{
	my $self = shift;

	if (@_)
	{
		$self->set_user_data(shift);
	}
	else
	{
		return $self->get_user_data;
	}
}





sub current_line_number { return shift->get_current_line_number }





sub current_description_number { return shift->get_current_description_number }





sub current_field_type { return shift->get_current_field_type }





sub current_field { return shift->get_current_field }







################################################################################
#
# The subroutines for the Generator class:
#
################################################################################

package Multimedia::SDP::Generator;

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	return $class->new_generator;
}





sub v_field
{
	my ($self, $protocol_version) = @_;

	$self->gen_protocol_version_field($protocol_version);
}





sub o_field
{
	my $self = shift;
	
	if (@_ == 1 and UNIVERSAL::isa($_[0], 'Multimedia::SDP::Owner'))
	{
		my $owner_object = shift;

		$self->gen_from_owner_object($owner_object);
	}
	else
	{
		my ($username, $session_id, $session_version,
		    $network_type, $address_type, $address) = @_;

		$self->gen_owner_field(
			$username,
			$session_id,
			$session_version,
			$network_type,
			$address_type,
			$address
		);
	}
}





sub s_field
{
	my ($self, $session_name) = @_;

	$self->gen_session_name_field($session_name);
}





sub i_field
{
	my ($self, $information) = @_;

	$self->gen_information_field($information);
}





sub u_field
{
	my ($self, $uri) = @_;

	$self->gen_uri_field($uri);
}





sub e_field
{
	my $self = shift;
	
	if (@_ == 1 and UNIVERSAL::isa($_[0], 'Multimedia::SDP::EmailContact'))
	{
		my $email_contact_object = shift;

		$self->gen_from_email_contact_object($email_contact_object);
	}
	else
	{
		my ($address, $name) = @_;

		$self->gen_email_contact_field(
			$address,
			$name
		);
	}
}





sub p_field
{
	my $self = shift;
	
	if (@_ == 1 and UNIVERSAL::isa($_[0], 'Multimedia::SDP::PhoneContact'))
	{
		my $phone_contact_object = shift;

		$self->gen_from_phone_contact_object($phone_contact_object);
	}
	else
	{
		my ($number, $name) = @_;

		$self->gen_phone_contact_field(
			$number,
			$name
		);
	}
}





sub c_field
{
	my $self = shift;
	
	if (@_ == 1 and UNIVERSAL::isa($_[0], 'Multimedia::SDP::Connection'))
	{
		my $connection_object = shift;

		$self->gen_from_connection_object($connection_object);
	}
	else
	{
		my ($network_type, $address_type, $address, $ttl,
		    $total_addresses) = @_;

		$self->gen_connection_field(
			$network_type,
			$address_type,
			$address,
			$ttl,
			$total_addresses
		);
	}
}





sub b_field
{
	my $self = shift;
	
	if (@_ == 1 and UNIVERSAL::isa($_[0], 'Multimedia::SDP::Bandwidth'))
	{
		my $bandwidth_object = shift;

		$self->gen_from_bandwidth_object($bandwidth_object);
	}
	else
	{
		my ($modifier, $value) = @_;

		$self->gen_bandwidth_field($modifier, $value);
	}
}





sub t_field
{
	my $self = shift;

	if (@_ == 1
		and UNIVERSAL::isa($_[0], 'Multimedia::SDP::SessionPlayTime'))
	{
		my $session_play_time_object = shift;

		$self->gen_from_session_play_time_object(
			$session_play_time_object
		);
	}
	else
	{
		my ($start_time, $end_time) = @_;

		$self->gen_session_play_time_field($start_time, $end_time);
	}
}





sub r_field
{
	my $self = shift;

	if (@_ == 1 and UNIVERSAL::isa($_[0], 'Multimedia::SDP::RepeatTime'))
	{
		my $repeat_time_object = shift;

		$self->gen_from_repeat_time_object($repeat_time_object);
	}
	else
	{
		my ($repeat_interval, $active_duration, $repeat_offsets) = @_;

		
		$repeat_offsets = join(' ', @$repeat_offsets)
			if (ref $repeat_offsets eq 'ARRAY');

		$self->gen_repeat_time_field(
			$repeat_interval, $active_duration, $repeat_offsets
		);
	}
}





sub z_field
{
	my $self = shift;

	if (UNIVERSAL::isa($_[0], 'Multimedia::SDP::ZoneAdjustment'))
	{
		$self->gen_from_zone_adjustment_objects(@_);
	}
	else
	{
		my @adjustment_objects;
		while (my ($time, $offset) = (shift, shift))
		{
			my $adjustment = new Multimedia::SDP::ZoneAdjustment;

			$adjustment->time($time);
			$adjustment->offset($offset);

			push(@adjustment_objects, $adjustment);
		}

		$self->gen_from_zone_adjustment_objects(@adjustment_objects);
	}
}





sub k_field
{
	my $self = shift;

	if (@_ == 1 and UNIVERSAL::isa($_[0], 'Multimedia::SDP::Encryption'))
	{
		my $encryption_object = shift;

		$self->gen_from_encryption_object($encryption_object);
	}
	else
	{
		my ($method, $key) = @_;

		$self->gen_encryption_field($method, $key);
	}
}





sub a_field
{
	my $self = shift;

	if (@_ == 1 and UNIVERSAL::isa($_[0], 'Multimedia::SDP::Attribute'))
	{
		my $attribute_object = shift;

		$self->gen_from_attribute_object($attribute_object);
	}
	else
	{
		my ($name, $value) = @_;

		$self->gen_attribute_field($name, $value);
	}
}





sub m_field
{
	my $self = shift;

	if (@_ == 1
		and UNIVERSAL::isa($_[0], 'Multimedia::SDP::MediaDescription'))
	
	{
		my $media_description_object = shift;

		$self->gen_from_media_description_object(
			$media_description_object
		);
	}
	else
	{
		my ($media_type, $port, $total_ports, $transport_protocol,
		    $formats) = @_;

		$formats = join(' ', @$formats) if (ref $formats eq 'ARRAY');

		$self->gen_media_description_field(
			$media_type,
			$port,
			$total_ports,
			$transport_protocol,
			$formats
		);
	}
}





sub output { return shift->get_generated_output }





sub save_output { return shift->save_generated_output(@_) }







################################################################################
#
# The subroutines for the Description class:
#
################################################################################

package Multimedia::SDP::Description;

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	return $class->new_description;
}





sub protocol_version
{
	my $self = shift;

	if (@_)
	{
		$self->set_protocol_version(shift);
	}
	else
	{
		return $self->get_protocol_version;
	}
}





sub session_name
{
	my $self = shift;

	if (@_)
	{
		$self->set_session_name(shift);
	}
	else
	{
		return $self->get_session_name;
	}
}





sub session_information
{
	my $self = shift;

	if (@_)
	{
		$self->set_session_information(shift);
	}
	else
	{
		return $self->get_session_information;
	}
}





sub uri
{
	my $self = shift;

	if (@_)
	{
		$self->set_uri(shift);
	}
	else
	{
		return $self->get_uri;
	}
}





sub output_to_string { return shift->output_description_to_string }




sub output_to_file
{
	my ($self, $filename) = @_;

	$self->output_description_to_file($filename)
}







################################################################################
#
# The subroutines for the Owner class:
#
################################################################################

package Multimedia::SDP::Owner;

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	return $class->new_owner;
}





sub username
{
	my $self = shift;

	if (@_)
	{
		$self->set_username(shift);
	}
	else
	{
		return $self->get_username;
	}
}





sub session_id
{
	my $self = shift;

	if (@_)
	{
		$self->set_session_id(shift);
	}
	else
	{
		return $self->get_session_id;
	}
}





sub session_version
{
	my $self = shift;

	if (@_)
	{
		$self->set_session_version(shift);
	}
	else
	{
		return $self->get_session_version;
	}
}





sub network_type
{
	my $self = shift;

	if (@_)
	{
		$self->set_owner_network_type(shift);
	}
	else
	{
		return $self->get_owner_network_type;
	}
}





sub address
{
	my $self = shift;

	if (@_)
	{
		$self->set_owner_address(shift);
	}
	else
	{
		return $self->get_owner_address;
	}
}





sub address_type
{
	my $self = shift;

	if (@_)
	{
		$self->set_owner_address_type(shift);
	}
	else
	{
		return $self->get_owner_address_type;
	}
}







################################################################################
#
# The subroutines for the EmailContact class:
#
################################################################################

package Multimedia::SDP::EmailContact;

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	return $class->new_email_contact;
}





sub address
{
	my $self = shift;

	if (@_)
	{
		$self->set_email_address(shift);
	}
	else
	{
		return $self->get_email_address;
	}
}





sub name
{
	my $self = shift;

	if (@_)
	{
		$self->set_email_name(shift);
	}
	else
	{
		return $self->get_email_name;
	}
}







################################################################################
#
# The subroutines for the PhoneContact class:
#
################################################################################

package Multimedia::SDP::PhoneContact;

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	return $class->new_phone_contact;
}





sub number
{
	my $self = shift;

	if (@_)
	{
		$self->set_phone_number(shift);
	}
	else
	{
		return $self->get_phone_number;
	}
}





sub name
{
	my $self = shift;

	if (@_)
	{
		$self->set_phone_name(shift);
	}
	else
	{
		return $self->get_phone_name;
	}
}







################################################################################
#
# The subroutines for the Connection class:
#
################################################################################

package Multimedia::SDP::Connection;

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	return $class->new_connection;
}





sub network_type
{
	my $self = shift;

	if (@_)
	{
		$self->set_connection_network_type(shift);
	}
	else
	{
		return $self->get_connection_network_type;
	}
}





sub ttl
{
	my $self = shift;

	if (@_)
	{
		$self->set_connection_ttl(shift);
	}
	else
	{
		return $self->get_connection_ttl;
	}
}





sub address
{
	my $self = shift;

	if (@_)
	{
		$self->set_connection_address(shift);
	}
	else
	{
		return $self->get_connection_address;
	}
}





sub address_type
{
	my $self = shift;

	if (@_)
	{
		$self->set_connection_address_type(shift);
	}
	else
	{
		return $self->get_connection_address_type;
	}
}





sub total_addresses
{
	my $self = shift;

	if (@_)
	{
		$self->set_total_connection_addresses(shift);
	}
	else
	{
		return $self->get_total_connection_addresses;
	}
}







################################################################################
#
# The subroutines for the Bandwidth class:
#
################################################################################

package Multimedia::SDP::Bandwidth;

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	return $class->new_bandwidth;
}





sub modifier
{
	my $self = shift;

	if (@_)
	{
		$self->set_bandwidth_modifier(shift);
	}
	else
	{
		return $self->get_bandwidth_modifier;
	}
}





sub value
{
	my $self = shift;

	if (@_)
	{
		$self->set_bandwidth_value(shift);
	}
	else
	{
		return $self->get_bandwidth_value;
	}
}







################################################################################
#
# The subroutines for the SessionPlayTime class:
#
################################################################################

package Multimedia::SDP::SessionPlayTime;

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	return $class->new_session_play_time;
}





sub start_time
{
	my $self = shift;

	if (@_)
	{
		$self->set_start_time(shift);
	}
	else
	{
		return $self->get_start_time;
	}
}





sub end_time
{
	my $self = shift;

	if (@_)
	{
		$self->set_end_time(shift);
	}
	else
	{
		return $self->get_end_time;
	}
}







################################################################################
#
# The subroutines for the RepeatTime class:
#
################################################################################

package Multimedia::SDP::RepeatTime;

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	return $class->new_repeat_time;
}





sub repeat_interval
{
	my $self = shift;

	if (@_)
	{
		$self->set_repeat_interval(shift);
	}
	else
	{
		return $self->get_repeat_interval;
	}
}





sub active_duration
{
	my $self = shift;

	if (@_)
	{
		$self->set_active_duration(shift);
	}
	else
	{
		return $self->get_active_duration;
	}
}





sub repeat_offsets
{
	my $self = shift;

	if (@_)
	{
		$self->set_repeat_offsets(@_, scalar @_);
	}
	else
	{
		return $self->get_repeat_offsets;
	}
}







################################################################################
#
# The subroutines for the ZoneAdjustment class:
#
################################################################################

package Multimedia::SDP::ZoneAdjustment;

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	return $class->new_zone_adjustment;
}





sub time
{
	my $self = shift;

	if (@_)
	{
		$self->set_zone_adjustment_time(shift);
	}
	else
	{
		return $self->get_zone_adjustment_time;
	}
}





sub offset
{
	my $self = shift;

	if (@_)
	{
		$self->set_zone_adjustment_offset(shift);
	}
	else
	{
		return $self->get_zone_adjustment_offset;
	}
}







################################################################################
#
# The subroutines for the Encryption class:
#
################################################################################

package Multimedia::SDP::Encryption;

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	return $class->new_encryption;
}





sub method
{
	my $self = shift;

	if (@_)
	{
		$self->set_encryption_method(shift);
	}
	else
	{
		return $self->get_encryption_method;
	}
}





sub key
{
	my $self = shift;

	if (@_)
	{
		$self->set_encryption_key(shift);
	}
	else
	{
		return $self->get_encryption_key;
	}
}







################################################################################
#
# The subroutines for the Attribute class:
#
################################################################################

package Multimedia::SDP::Attribute;

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	return $class->new_attribute;
}





sub name
{
	my $self = shift;

	if (@_)
	{
		$self->set_attribute_name(shift);
	}
	else
	{
		return $self->get_attribute_name;
	}
}





sub value
{
	my $self = shift;

	if (@_)
	{
		$self->set_attribute_value(shift);
	}
	else
	{
		return $self->get_attribute_value;
	}
}







################################################################################
#
# The subroutines for the MediaDescription class:
#
################################################################################

package Multimedia::SDP::MediaDescription;

@Multimedia::SDP::MediaBandwidth::ISA  = 'Multimedia::SDP::MediaDescription';
@Multimedia::SDP::MediaConnection::ISA = 'Multimedia::SDP::MediaDescription';
@Multimedia::SDP::MediaEncryption::ISA = 'Multimedia::SDP::MediaDescription';
@Multimedia::SDP::MediaAttribute::ISA  = 'Multimedia::SDP::MediaDescription';

sub new
{
	my $invo  = shift;
	my $class = ref $invo || $invo;

	return $class->new_media_description;
}





sub media_type
{
	my $self = shift;

	if (@_)
	{
		$self->set_media_type(shift);
	}
	else
	{
		return $self->get_media_type;
	}
}





sub port
{
	my $self = shift;

	if (@_)
	{
		$self->set_media_port(shift);
	}
	else
	{
		return $self->get_media_port;
	}
}





sub total_ports
{
	my $self = shift;

	if (@_)
	{
		$self->set_total_media_ports(shift);
	}
	else
	{
		return $self->get_total_media_ports;
	}
}





sub transport_protocol
{
	my $self = shift;

	if (@_)
	{
		$self->set_media_transport_protocol(shift);
	}
	else
	{
		return $self->get_media_transport_protocol;
	}
}





sub media_formats
{
	my $self = shift;

	if (@_)
	{
		$self->set_media_formats(shift);
	}
	else
	{
		return $self->get_media_formats;
	}
}





sub media_information
{
	my $self = shift;

	if (@_)
	{
		$self->set_media_information(shift);
	}
	else
	{
		return $self->get_media_information;
	}
}

1;

__END__

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
