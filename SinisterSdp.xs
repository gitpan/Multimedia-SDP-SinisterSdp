/*******************************************************************************
 * 
 * Copyright 2004 by William G. Davis.
 *
 * This library is free software released under the terms of the GNU Lesser
 * General Public License (LGPL), the full terms of which can be found in the
 * "COPYING" file that comes with the distribution.
 *
 * This library is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.
 *
 *-----------------------------------------------------------------------------
 *
 * This file contains the XS glue code the links the SinisterSdp routines to
 * Perl.
 * 
 ******************************************************************************/

#ifdef __cplusplus
extern "C" {
#endif

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "SDP/SDP_Parser.h"
#include "SDP/SDP_Generator.h"

/* For backwards compatibility with pre-5.6.1 versions of Perl: */
#include "ppport.h"

#ifdef __cplusplus
}
#endif

/*
 * This is used to set one of the handlers in either the SDP_ParserGlue
 * struct below or the golbal error handler variables after it:
 */
#define SDP_SET_SV_IN_GLUE(_sv_to_set_, _sv_) \
	if (_sv_to_set_ == NULL)              \
		_sv_to_set_ = newSVsv(_sv_);  \
        else                                  \
		SvSetSV(_sv_to_set_, _sv_);

/* This is used to retrieve those handlers from the struct or globals: */
#define SDP_GET_SV_FROM_GLUE(_sv_to_get_) \
	((_sv_to_get_) ? newSVsv(_sv_to_get_) : &PL_sv_undef)

/*
 * This macro takes an element from a SinisterSdp linked list and from it
 * returns either the first element (if the XSub is being called in scalar
 * context) or each element in the list (if the XSub is being called in list
 * context and there is more than one element in the list):
 */
#define SDP_RETURN_LINKED_LIST_AS_ARRAY(_item_, _class_) \
	while (_item_)                                   \
	{                                                \
		SV *sv;                                  \
                                                         \
		EXTEND(SP, 1);                           \
		sv = sv_newmortal();                     \
		sv_setref_pv(sv, _class_, _item_);       \
		PUSHs(sv);                               \
                                                         \
		if (GIMME == G_SCALAR)                   \
			break;                           \
		                                         \
		_item_ = SDP_GetNext(_item_);            \
	}

/*
 * This macro is used to copy each SV of the same type from the incoming @_
 * stack to a C array.
 */
#define SDP_COPY_ARRAY_FROM_STACK(_destination_, _type_, _svmac_, _total_)  \
	do {                                                                \
		_destination_ = NULL;                                       \
                                                                            \
		if (_total_)                                                \
		{                                                           \
			int i;                                              \
			int sp_i;                                           \
                                                                            \
			_destination_ = (_type_ *) SDP_Allocate(            \
				sizeof(_type_) * (_total_)                  \
			);                                                  \
			if (_destination_ == NULL)                          \
			{                                                   \
				SDP_RaiseFatalError(                        \
					SDP_ERR_OUT_OF_MEMORY,              \
					"Couldn't allocate memory to "      \
					"copy an array from @_: %s.",       \
					SDP_OS_ERROR_STRING                 \
				);                                          \
				XSRETURN_UNDEF;                             \
			}                                                   \
                                                                            \
			for (                                               \
				i = 0, sp_i = items - (_total_);            \
				i < (_total_);                              \
				++i, ++sp_i)                                \
					_destination_[i] =                  \
						(_type_) _svmac_(ST(sp_i)); \
		}                                                           \
	} while (0)

/*
 * This macro shifts objects off the stack and builds a doubly-linked list with
 * them:
 */
#define SDP_ARRAY_TO_LINKED_LIST(_destination_, _type_, _total_)    \
	do {                                                        \
		_type_ *current = NULL;                             \
		_type_ *next    = NULL;                             \
		int i;                                              \
                                                                    \
		_destination_ = NULL;                               \
		for (i = items - (_total_); i < items; ++i)         \
		{                                                   \
			next = (_type_ *) SvIV((SV *) SvRV(ST(i))); \
                                                                    \
			if (current)                                \
			{                                           \
				SDP_SetNext(current, next);         \
				SDP_SetPrevious(next, current);     \
                                                                    \
				current = next;                     \
			}                                           \
			else                                        \
			{                                           \
				current = next;                     \
                                                                    \
				_destination_ = current;            \
			}                                           \
		}                                                   \
	} while (0)



/*
 * This struct is used as a sort of go-between for Perl and SDP_Parser
 * structs. Obviously, we can't use the SinisterSdp SDP_Set*Handler routines
 * from Perl and supply them with subroutine references, because the C library
 * wont know how to call them. To call a Perl subroutine from C, you must jump
 * through a few hoops, all of which are described in "perlcall".
 *
 * As a result, each SDP_Parser struct gets one of these structs too. It's
 * stored as the user data for the SDP_Parser struct, and gets passed around.
 * All of the set_*_handler() XSubs store in this struct the SV's containing
 * subroutine refs that they take, and then we have C functions below
 * (invoke_*_handler()) that get them from this struct and invoke them
 * properly. It's these functions, that prepare the Perl stack and then call
 * the Perl subroutine, that get registered with SDP_Set*Handler() functions.
 *
 * We also store a copy of the parser reference to make it easier to pass
 * around, and since we're passing around this struct as the user data, we keep
 * the user's user data in here too.
 *
 * The "state" hack lets the user write handlers that don't need to return true
 * to keep going:
 */
typedef struct {
	/*
	 * This stores the blessed SV ref to an SDP_Parser struct. This struct
	 * is then registered as the user data for that struct and gets passed
	 * to the functins below:
	 */
	SV *parser;

	/* The *real* handlers; subroutine references to invoke: */
	SV *start_handler;
	SV *start_description_handler;
	SV *field_handler;
	SV *end_description_handler;
	SV *end_handler;

	/*
	 * The *real* user data; a reference to something to be passed to
	 * those subroutines above:
	 */
	SV *user_data;

	/* Used to control flow without return values from Perl: */
	int halt_parsing;
} SDP_ParserGlue;

/*
 * Same thing as above. We can't register Perl subroutines as the SinisterSdp 
 * error handlers, so instead we store them here and then register functions to
 * prepare the stack and invoke them properly:
 */
static SV *_fatal_error_handler;
static SV *_non_fatal_error_handler;







int invoke_start_handler(
	SDP_Parser *   parser,
	void *         user_data)
{
	dSP;
	SDP_ParserGlue *parser_glue = (SDP_ParserGlue *) user_data;

	ENTER;
	SAVETMPS;

	PUSHMARK(SP);
	XPUSHs(parser_glue->parser);
	XPUSHs(parser_glue->user_data);
	PUTBACK;

	perl_call_sv(parser_glue->start_handler, G_SCALAR);

	FREETMPS;
        LEAVE;

	if (parser_glue->halt_parsing)
	{
		parser_glue->halt_parsing = 0;
		return 0;
	}
	else
	{
		return 1;
	}
}





int invoke_start_description_handler(
	SDP_Parser *   parser,
	int            description_number,
	void *         user_data)
{
	dSP;
	SDP_ParserGlue *parser_glue = (SDP_ParserGlue *) user_data;

	ENTER;
	SAVETMPS;

	PUSHMARK(SP);
	XPUSHs(parser_glue->parser);
	XPUSHs(sv_2mortal(newSViv(description_number)));
	XPUSHs(parser_glue->user_data);
	PUTBACK;

	perl_call_sv(parser_glue->start_description_handler, G_SCALAR);

	FREETMPS;
        LEAVE;

	if (parser_glue->halt_parsing)
	{
		parser_glue->halt_parsing = 0;
		return 0;
	}
	else
	{
		return 1;
	}
}





int invoke_field_handler(
	SDP_Parser *   parser,
	char           field_type,
	const char *   field_value,
	void *         user_data)
{
	dSP;
	SDP_ParserGlue *parser_glue = (SDP_ParserGlue *) user_data;

	ENTER;
	SAVETMPS;

	PUSHMARK(SP);
	XPUSHs(parser_glue->parser);
	XPUSHs(sv_2mortal(newSVpvf("%c", field_type)));
	XPUSHs(sv_2mortal(newSVpv(field_value, 0)));
	XPUSHs(parser_glue->user_data);
	PUTBACK;

	perl_call_sv(parser_glue->field_handler, G_SCALAR);

	FREETMPS;
        LEAVE;

	if (parser_glue->halt_parsing)
	{
		parser_glue->halt_parsing = 0;
		return 0;
	}
	else
	{
		return 1;
	}
}





int invoke_end_description_handler(
	SDP_Parser *   parser,
	int            description_number,
	void *         user_data)
{
	dSP;
	SDP_ParserGlue *parser_glue = (SDP_ParserGlue *) user_data;

	ENTER;
	SAVETMPS;

	PUSHMARK(SP);
	XPUSHs(parser_glue->parser);
	XPUSHs(sv_2mortal(newSViv(description_number)));
	XPUSHs(parser_glue->user_data);
	PUTBACK;

	perl_call_sv(parser_glue->end_description_handler, G_SCALAR);

	FREETMPS;
        LEAVE;

	if (parser_glue->halt_parsing)
	{
		parser_glue->halt_parsing = 0;
		return 0;
	}
	else
	{
		return 1;
	}
}





void invoke_end_handler(
	SDP_Parser *   parser,
	int            parser_result,
	void *         user_data)
{
	dSP;
	SDP_ParserGlue *parser_glue = (SDP_ParserGlue *) user_data;

	ENTER;
	SAVETMPS;

	PUSHMARK(SP);
	XPUSHs(parser_glue->parser);
	XPUSHs(sv_2mortal(newSViv(parser_result)));
	XPUSHs(parser_glue->user_data);
	PUTBACK;

	perl_call_sv(parser_glue->start_handler, G_SCALAR);

	FREETMPS;
        LEAVE;

	parser_glue->halt_parsing = 0;
}





void invoke_fatal_error_handler(
	SDP_Error      error_code,
	const char *   error_string)
{
	dSP;

	ENTER;
	SAVETMPS;

	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(error_string, 0)));
	XPUSHs(sv_2mortal(newSViv(error_code)));
	PUTBACK;

	perl_call_sv(_fatal_error_handler, G_SCALAR|G_DISCARD);

	FREETMPS;
	LEAVE;
}





int invoke_non_fatal_error_handler(
	SDP_Error      error_code,
	const char *   error_string)
{
	dSP;
	int scalars_returned;
	int status;

	ENTER;
	SAVETMPS;

	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newSVpv(error_string, 0)));
	XPUSHs(sv_2mortal(newSViv(error_code)));
	PUTBACK;

	scalars_returned = perl_call_sv(_non_fatal_error_handler, G_SCALAR);

	SPAGAIN;

	status = scalars_returned ? POPi : 0;

	PUTBACK;
	FREETMPS;
	LEAVE;

	return status;
}







/*******************************************************************************
 *
 * The start of the XS code:
 *
 ******************************************************************************/

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::SinisterSdp

PROTOTYPES: ENABLE





# The XSubs that act as constants for the error codes in SDP_Error.h:

int
NO_ERROR()
	CODE:
		RETVAL = SDP_NO_ERROR;
	OUTPUT:
		RETVAL

int
ERR_GENERIC()
	CODE:
		RETVAL = SDP_ERR_GENERIC;
	OUTPUT:
		RETVAL

int
ERR_OUT_OF_MEMORY()
	CODE:
		RETVAL = SDP_ERR_OUT_OF_MEMORY;
	OUTPUT:
		RETVAL

int
ERR_FILE_OPEN_FAILED()
	CODE:
		RETVAL = SDP_ERR_FILE_OPEN_FAILED;
	OUTPUT:
		RETVAL

int
ERR_MALFORMED_FIELD()
	CODE:
		RETVAL = SDP_ERR_MALFORMED_FIELD;
	OUTPUT:
		RETVAL

int
ERR_EMPTY_FIELD()
	CODE:
		RETVAL = SDP_ERR_EMPTY_FIELD;
	OUTPUT:
		RETVAL

int
ERR_INVALID_TYPE_CHARACTER()
	CODE:
		RETVAL = SDP_ERR_INVALID_TYPE_CHARACTER;
	OUTPUT:
		RETVAL

int
ERR_MULTIPLE_UNIQUE_FIELDS()
	CODE:
		RETVAL = SDP_ERR_MULTIPLE_UNIQUE_FIELDS;
	OUTPUT:
		RETVAL

int
ERR_FEILDS_OUT_OF_SEQUENCE()
	CODE:
		RETVAL = SDP_ERR_FEILDS_OUT_OF_SEQUENCE;
	OUTPUT:
		RETVAL





################################################################################
#
# The XSubs for the SDP_Parser struct class:
#
################################################################################

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::Parser



SV *
new_parser(CLASS)
		char *CLASS
	PREINIT:
		SDP_Parser *parser;
		SDP_ParserGlue *parser_glue;
		SV *address;
	CODE:
	{
		parser = SDP_NewParser();
		if (parser == NULL)
			XSRETURN_UNDEF;

		parser_glue = (SDP_ParserGlue *) SDP_Allocate(
			sizeof(SDP_ParserGlue)
		);
		if (parser_glue == NULL)
		{
			SDP_DestroyParser(parser);
			XSRETURN_UNDEF;
		}

		SDP_SetUserData(parser, (void *) parser_glue);

		address = newSViv((int) parser);
		RETVAL  = newRV(address);
		sv_bless(RETVAL, gv_stashpv(CLASS, 1));

		parser_glue->parser = sv_2mortal(newSVsv(RETVAL));
	}
	OUTPUT:
		RETVAL



SV *
parse(parser, string)
		SDP_Parser *   parser
		const char *   string
	PREINIT:
		char CLASS[] = "Multimedia::SDP::Description";
		SDP_Description *description;
	PPCODE:
	{
		description = SDP_Parse(parser, string);

		SDP_RETURN_LINKED_LIST_AS_ARRAY(description, CLASS);
	}



SV *
parse_file(parser, filename)
		SDP_Parser *   parser
		const char *   filename
	PREINIT:
		char CLASS[] = "Multimedia::SDP::Description";
		SDP_Description *description;
	PPCODE:
	{
		description = SDP_ParseFile(parser, filename);

		SDP_RETURN_LINKED_LIST_AS_ARRAY(description, CLASS);
	}



int
event_stream_parse(parser, string)
		SDP_Parser *   parser
		const char *   string
	CODE:
		RETVAL = SDP_EventStreamParse(parser, string);
	OUTPUT:
		RETVAL



int
event_stream_parse_file(parser, filename)
		SDP_Parser *   parser
		const char *   filename
	CODE:
		RETVAL = SDP_EventStreamParseFile(parser, filename);
	OUTPUT:
		RETVAL



void halt(parser)
		SDP_Parser *parser
	PREINIT:
		SDP_ParserGlue *parser_glue;
	CODE:
		parser_glue = (SDP_ParserGlue *) SDP_GetUserData(parser);
		parser_glue->halt_parsing = 1;



void
set_start_handler(parser, handler)
		SDP_Parser *   parser
		SV *           handler
	PREINIT:
		SDP_ParserGlue *parser_glue;
	CODE:
	{
		parser_glue = (SDP_ParserGlue *) SDP_GetUserData(parser);

		SDP_SET_SV_IN_GLUE(parser_glue->start_handler, handler);

		SDP_SetStartHandler(parser, invoke_start_handler);
	}



void
set_start_description_handler(parser, handler)
		SDP_Parser *   parser
		SV *           handler
	PREINIT:
		SDP_ParserGlue *parser_glue;
	CODE:
	{
		parser_glue = (SDP_ParserGlue *) SDP_GetUserData(parser);

		SDP_SET_SV_IN_GLUE(
			parser_glue->start_description_handler, handler
		);

		SDP_SetStartDescriptionHandler(
			parser, invoke_start_description_handler
		);
	}



void
set_field_handler(parser, handler)
		SDP_Parser *   parser
		SV *           handler
	PREINIT:
		SDP_ParserGlue *parser_glue;
	CODE:
	{
		parser_glue = (SDP_ParserGlue *) SDP_GetUserData(parser);

		SDP_SET_SV_IN_GLUE(parser_glue->field_handler, handler);

		SDP_SetFieldHandler(parser, invoke_field_handler);
	}



void
set_end_description_handler(parser, handler)
		SDP_Parser *   parser
		SV *           handler
	PREINIT:
		SDP_ParserGlue *parser_glue;
	CODE:
	{
		parser_glue = (SDP_ParserGlue *) SDP_GetUserData(parser);

		SDP_SET_SV_IN_GLUE(
			parser_glue->end_description_handler, handler
		);

		SDP_SetEndDescriptionHandler(
			parser, invoke_end_description_handler
		);
	}



void
set_end_handler(parser, handler)
		SDP_Parser *   parser
		SV *           handler
	PREINIT:
		SDP_ParserGlue *parser_glue;
	CODE:
	{
		parser_glue = (SDP_ParserGlue *) SDP_GetUserData(parser);

		SDP_SET_SV_IN_GLUE(parser_glue->end_handler, handler);

		SDP_SetEndHandler(parser, invoke_end_handler);
	}



void
set_user_data(parser, user_data)
		SDP_Parser *   parser
		void *         user_data
	CODE:
		SDP_SetUserData(parser, user_data);



SV *
get_start_handler(parser)
		SDP_Parser *parser
	PREINIT:
		SDP_ParserGlue *parser_glue;
	CODE:
		parser_glue = (SDP_ParserGlue *) SDP_GetUserData(parser);
		RETVAL = SDP_GET_SV_FROM_GLUE(parser_glue->start_handler);
	OUTPUT:
		RETVAL



SV *
get_start_description_handler(parser)
		SDP_Parser *parser
	PREINIT:
		SDP_ParserGlue *parser_glue;
	CODE:
		parser_glue = (SDP_ParserGlue *) SDP_GetUserData(parser);
		RETVAL = SDP_GET_SV_FROM_GLUE(
			parser_glue->start_description_handler
		);
	OUTPUT:
		RETVAL



SV *
get_field_handler(parser)
		SDP_Parser *parser
	PREINIT:
		SDP_ParserGlue *parser_glue;
	CODE:
		parser_glue = (SDP_ParserGlue *) SDP_GetUserData(parser);
		RETVAL = SDP_GET_SV_FROM_GLUE(parser_glue->field_handler);
	OUTPUT:
		RETVAL



SV *
get_end_description_handler(parser)
		SDP_Parser *parser
	PREINIT:
		SDP_ParserGlue *parser_glue;
	CODE:
		parser_glue = (SDP_ParserGlue *) SDP_GetUserData(parser);
		RETVAL = SDP_GET_SV_FROM_GLUE(
			parser_glue->end_description_handler
		);
	OUTPUT:
		RETVAL



SV *
get_end_handler(parser)
		SDP_Parser *parser
	PREINIT:
		SDP_ParserGlue *parser_glue;
	CODE:
		parser_glue = (SDP_ParserGlue *) SDP_GetUserData(parser);
		RETVAL = SDP_GET_SV_FROM_GLUE(parser_glue->end_handler);
	OUTPUT:
		RETVAL



SV *
get_user_data(parser)
		SDP_Parser *parser
	PREINIT:
		SDP_ParserGlue *parser_glue;
	CODE:
		parser_glue = (SDP_ParserGlue *) SDP_GetUserData(parser);
		RETVAL = SDP_GET_SV_FROM_GLUE(parser_glue->user_data);
	OUTPUT:
		RETVAL



int
get_current_line_number(parser)
		SDP_Parser *parser
	CODE:
		RETVAL = SDP_GetCurrentLineNumber(parser);
	OUTPUT:
		RETVAL



int
get_current_description_number(parser)
		SDP_Parser *parser
	CODE:
		RETVAL = SDP_GetCurrentDescriptionNumber(parser);
	OUTPUT:
		RETVAL



char
get_current_field_type(parser)
		SDP_Parser *parser
	CODE:
		RETVAL = SDP_GetCurrentFieldType(parser);
	OUTPUT:
		RETVAL



char *
get_current_field(parser)
		SDP_Parser *parser
	CODE:
		RETVAL = SDP_GetCurrentField(parser);
	OUTPUT:
		RETVAL



int
field_encountered(parser, field_type)
		SDP_Parser *   parser
		char           field_type
	CODE:
		RETVAL = SDP_FieldEncountered(parser, field_type);
	OUTPUT:
		RETVAL



void
destroy_parser(parser)
		SDP_Parser *parser
	CODE:
	{
		SDP_ParserGlue *parser_glue =
			(SDP_ParserGlue *) SDP_GetUserData(parser);

		SDP_DestroyParser(parser);

		SDP_Destroy(parser_glue);
	}







################################################################################
#
# The XSubs for the SDP_Generator struct class:
#
################################################################################

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::Generator



SDP_Generator *
new_generator(CLASS)
		char *CLASS
	CODE:
		RETVAL = SDP_NewGenerator();
	OUTPUT:
		RETVAL



int
gen_protocol_version_field(generator, protocol_version)
		SDP_Generator *   generator
		int               protocol_version
	CODE:
		RETVAL = SDP_GenProtocolVersionField(
			generator, protocol_version
		);
	OUTPUT:
		RETVAL



int
gen_owner_field(generator, username, session_id, session_version, network_type, address_type, address)
		SDP_Generator *   generator
		const char *      username
		const char *      session_id
		const char *      session_version
		const char *      network_type
		const char *      address_type
		const char *      address
	CODE:
		RETVAL = SDP_GenOwnerField(
			generator,
			username,
			session_id,
			session_version,
			network_type,
			address_type,
			address
		);
	OUTPUT:
		RETVAL



int
gen_from_owner_object(generator, owner)
		SDP_Generator *   generator
		SDP_Owner *       owner
	CODE:
		RETVAL = SDP_GenFromOwner(generator, owner);
	OUTPUT:
		RETVAL



int
gen_session_name_field(generator, session_name)
		SDP_Generator *   generator
		const char *      session_name
	CODE:
		RETVAL = SDP_GenSessionNameField(generator, session_name);
	OUTPUT:
		RETVAL



int
gen_information_field(generator, information)
		SDP_Generator *   generator
		const char *      information
	CODE:
		RETVAL = SDP_GenInformationField(generator, information);
	OUTPUT:
		RETVAL



int
gen_uri_field(generator, uri)
		SDP_Generator *   generator
		const char *      uri
	CODE:
		RETVAL = SDP_GenURIField(generator, uri);
	OUTPUT:
		RETVAL



int
gen_email_contact_field(generator, address, name)
		SDP_Generator *   generator
		const char *      address
		const char *      name
	CODE:
		RETVAL = SDP_GenEmailContactField(generator, address, name);
	OUTPUT:
		RETVAL



int
gen_from_email_contact_object(generator, email_contact)
		SDP_Generator *      generator
		SDP_EmailContact *   email_contact
	CODE:
		RETVAL = SDP_GenFromEmailContact(generator, email_contact);
	OUTPUT:
		RETVAL



int
gen_phone_contact_field(generator, number, name)
		SDP_Generator *   generator
		const char *      number
		const char *      name
	CODE:
		RETVAL = SDP_GenPhoneContactField(generator, number, name);
	OUTPUT:
		RETVAL



int
gen_from_phone_contact_object(generator, phone_contact)
		SDP_Generator *      generator
		SDP_PhoneContact *   phone_contact
	CODE:
		RETVAL = SDP_GenFromPhoneContact(generator, phone_contact);
	OUTPUT:
		RETVAL



int
gen_connection_field(generator, network_type, address_type, address, ttl, total_addresses)
		SDP_Generator *   generator
		const char *      network_type
		const char *      address_type
		const char *      address
		int               ttl
		int               total_addresses
	CODE:
		RETVAL = SDP_GenConnectionField(
			generator,
			network_type,
			address_type,
			address,
			ttl,
			total_addresses
		);
	OUTPUT:
		RETVAL



int
gen_from_connection_object(generator, connection)
		SDP_Generator *    generator
		SDP_Connection *   connection
	CODE:
		RETVAL = SDP_GenFromConnection(generator, connection);
	OUTPUT:
		RETVAL



int
gen_bandwidth_field(generator, modifier, value)
		SDP_Generator *   generator
		const char *      modifier
		long              value
	CODE:
		RETVAL = SDP_GenBandwidthField(generator, modifier, value);
	OUTPUT:
		RETVAL



int
gen_from_bandwidth_object(generator, bandwidth)
		SDP_Generator *   generator
		SDP_Bandwidth *   bandwidth
	CODE:
		RETVAL = SDP_GenFromBandwidth(generator, bandwidth);
	OUTPUT:
		RETVAL



int
gen_session_play_time_field(generator, start_time, end_time)
		SDP_Generator *   generator
		time_t            start_time
		time_t            end_time
	CODE:
		RETVAL = SDP_GenSessionPlayTimeField(
			generator, start_time, end_time
		);
	OUTPUT:
		RETVAL



int
gen_from_session_play_time_object(generator, session_play_time)
		SDP_Generator *         generator
		SDP_SessionPlayTime *   session_play_time
	CODE:
		RETVAL = SDP_GenFromSessionPlayTime(
			generator, session_play_time
		);
	OUTPUT:
		RETVAL



int
gen_repeat_time_field(generator, repeat_interval, active_duration, repeat_offsets)
		SDP_Generator *   generator
		const char *      repeat_interval
		const char *      active_duration
		const char *      repeat_offsets
	CODE:
		RETVAL = SDP_GenRepeatTimeField(
			generator,
			repeat_interval,
			active_duration,
			repeat_offsets
		);
	OUTPUT:
		RETVAL



int
gen_from_repeat_time_object(generator, repeat_time)
		SDP_Generator *    generator
		SDP_RepeatTime *   repeat_time
	CODE:
		RETVAL = SDP_GenFromRepeatTime(generator, repeat_time);
	OUTPUT:
		RETVAL



# No gen_zone_adjustment_field XSUB because SDP_GenZoneAdjustmentField()
# takes variable-length arguments, and absent some stack magic, we can't call
# that C function dynamically. So we have to use this one instead:

int
gen_from_zone_adjustment_objects(generator, ...)
		SDP_Generator *generator
	PREINIT:
		SDP_ZoneAdjustment *zone_adjustments;
	CODE:
	{
		SDP_ARRAY_TO_LINKED_LIST(
			zone_adjustments, SDP_ZoneAdjustment, items - 1
		);

		RETVAL = SDP_GenFromZoneAdjustments(
			generator, zone_adjustments
		);
	}
	OUTPUT:
		RETVAL



int
gen_encryption_field(generator, method, key)
		SDP_Generator *   generator
		const char *      method
		const char *      key
	CODE:
		RETVAL = SDP_GenEncryptionField(generator, method, key);
	OUTPUT:
		RETVAL



int
gen_from_encryption_object(generator, encryption)
		SDP_Generator *    generator
		SDP_Encryption *   encryption
	CODE:
		RETVAL = SDP_GenFromEncryption(generator, encryption);
	OUTPUT:
		RETVAL



int
gen_attribute_field(generator, name, value)
		SDP_Generator *   generator
		const char *      name
		const char *      value
	CODE:
		RETVAL = SDP_GenAttributeField(generator, name, value);
	OUTPUT:
		RETVAL



int
gen_from_attribute_object(generator, attribute)
		SDP_Generator *   generator
		SDP_Attribute *   attribute
	CODE:
		RETVAL = SDP_GenFromAttribute(generator, attribute);
	OUTPUT:
		RETVAL



int
gen_media_description_field(generator, media_type, port, total_ports, transport_protocol, formats)
		SDP_Generator *   generator
		const char *      media_type
		unsigned short    port
		int               total_ports
		const char *      transport_protocol
		const char *      formats
	CODE:
		RETVAL = SDP_GenMediaDescriptionField(
			generator,
			media_type,
			port,
			total_ports,
			transport_protocol,
			formats
		);
	OUTPUT:
		RETVAL



int
gen_from_media_description_object(generator, media_description)
		SDP_Generator *          generator
		SDP_MediaDescription *   media_description
	CODE:
		RETVAL = SDP_GenFromMediaDescription(
			generator, media_description
		);
	OUTPUT:
		RETVAL



char *
get_generated_output(generator)
		SDP_Generator *generator
	CODE:
		RETVAL = SDP_GetGeneratedOutput(generator);
	OUTPUT:
		RETVAL



int
save_generated_output(generator, filename)
		SDP_Generator *   generator
		const char *      filename
	CODE:
		RETVAL = SDP_SaveGeneratedOutput(generator, filename);
	OUTPUT:
		RETVAL



void
destroy_generator(generator)
		SDP_Generator *generator
	CODE:
		SDP_DestroyGenerator(generator);







################################################################################
#
# The XSubs for the SDP_Description struct class:
#
################################################################################

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::Description



SDP_Description *
new_description(CLASS)
		char *CLASS
	CODE:
		RETVAL = SDP_NewDescription();
	OUTPUT:
		RETVAL



void
set_protocol_version(description, version)
		SDP_Description *   description
		int                 version
	CODE:
		SDP_SetProtocolVersion(description, version);



int
set_owner(description, username, session_id, session_version, network_type, address_type, address)
		SDP_Description *   description
		const char *        username
		const char *        session_id
		const char *        session_version
		const char *        network_type
		const char *        address_type
		const char *        address
	CODE:
		RETVAL = SDP_SetOwner(
			description,
			username,
			session_id,
			session_version,
			network_type,
			address_type,
			address
		);
	OUTPUT:
		RETVAL



int
set_session_name(description, session_name)
		SDP_Description *   description
		const char *        session_name
	CODE:
		RETVAL = SDP_SetSessionName(description, session_name);
	OUTPUT:
		RETVAL



int
set_session_information(description, session_information)
		SDP_Description *   description
		const char *        session_information
	CODE:
		RETVAL = SDP_SetSessionInformation(
			description, session_information
		);
	OUTPUT:
		RETVAL



int
set_uri(description, uri)
		SDP_Description *   description
		const char *        uri
	CODE:
		RETVAL = SDP_SetURI(description, uri);
	OUTPUT:
		RETVAL



void
add_email_contact(description, email_contact)
		SDP_Description *    description
		SDP_EmailContact *   email_contact
	CODE:
		SDP_AddEmailContact(description, email_contact);



int
add_new_email_contact(description, address, name)
		SDP_Description *   description
		const char *        address
		const char *        name
	CODE:
		RETVAL = SDP_AddNewEmailContact(description, address, name);
	OUTPUT:
		RETVAL



void
add_phone_contact(description, phone_contact)
		SDP_Description *    description
		SDP_PhoneContact *   phone_contact
	CODE:
		SDP_AddPhoneContact(description, phone_contact);



int
add_new_phone_contact(description, number, name)
		SDP_Description *   description
		const char *        number
		const char *        name
	CODE:
		RETVAL = SDP_AddNewPhoneContact(description, number, name);
	OUTPUT:
		RETVAL



int
set_connection(description, network_type, address_type, address, ttl, total_addresses)
		SDP_Description *   description
		const char *        network_type
		const char *        address_type
		const char *        address
		int                 ttl
		int                 total_addresses
	CODE:
		RETVAL = SDP_SetConnection(
			description,
			network_type,
			address_type,
			address,
			ttl,
			total_addresses
		);
	OUTPUT:
		RETVAL



int
set_bandwidth(description, modifier, value)
		SDP_Description *   description
		const char *        modifier
		long                value
	CODE:
		RETVAL = SDP_SetBandwidth(description, modifier, value);
	OUTPUT:
		RETVAL



void
add_session_play_time(description, session_play_time)
		SDP_Description *       description
		SDP_SessionPlayTime *   session_play_time
	CODE:
		SDP_AddSessionPlayTime(description, session_play_time);



int
add_new_session_play_time(description, start_time, end_time)
		SDP_Description *   description
		time_t              start_time
		time_t              end_time
	CODE:
		RETVAL = SDP_AddNewSessionPlayTime(
			description, start_time, end_time
		);
	OUTPUT:
		RETVAL



void
add_zone_adjustment(description, zone_adjustment)
		SDP_Description *      description
		SDP_ZoneAdjustment *   zone_adjustment
	CODE:
		SDP_AddZoneAdjustment(description, zone_adjustment);



int
add_new_zone_adjustment(description, time, offset)
		SDP_Description *   description
		time_t              time
		long                offset
	CODE:
		RETVAL = SDP_AddNewZoneAdjustment(description, time, offset);
	OUTPUT:
		RETVAL



int
set_encryption(description, method, key)
		SDP_Description *   description
		const char *        method
		const char *        key
	CODE:
		RETVAL = SDP_SetEncryption(description, method, key);
	OUTPUT:
		RETVAL



void
add_attribute(description, attribute)
		SDP_Description *   description
		SDP_Attribute *     attribute
	CODE:
		SDP_AddAttribute(description, attribute);



int
add_new_attribute(description, name, value)
		SDP_Description *   description
		const char *        name
		const char *        value
	CODE:
		RETVAL = SDP_AddNewAttribute(description, name, value);
	OUTPUT:
		RETVAL



void
add_media_description(description, media_description)
		SDP_Description *        description
		SDP_MediaDescription *   media_description
	CODE:
		SDP_AddMediaDescription(description, media_description);



int
add_new_media_description(description, media_type, port, total_ports, transport_protocol, formats, media_information)
		SDP_Description *   description
		const char *        media_type
		unsigned short      port
		unsigned short      total_ports
		const char *        transport_protocol
		const char *        formats
		const char *        media_information
	CODE:
		RETVAL = SDP_AddNewMediaDescription(
			description,
			media_type,
			port,
			total_ports,
			transport_protocol,
			formats,
			media_information
		);
	OUTPUT:
		RETVAL



int
get_protocol_version(description)
		SDP_Description *description
	CODE:
		RETVAL = SDP_GetProtocolVersion(description);
	OUTPUT:
		RETVAL



SDP_Owner *
get_owner(description)
		SDP_Description *description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::Owner";
	CODE:
		RETVAL = SDP_GetOwner(description);
	OUTPUT:
		RETVAL



char *
get_session_name(description)
		SDP_Description *description
	CODE:
		RETVAL = SDP_GetSessionName(description);
	OUTPUT:
		RETVAL



char *
get_session_information(description)
		SDP_Description *description
	CODE:
		RETVAL = SDP_GetSessionInformation(description);
	OUTPUT:
		RETVAL



char *
get_uri(description)
		SDP_Description *description
	CODE:
		RETVAL = SDP_GetURI(description);
	OUTPUT:
		RETVAL



SV *
get_email_contacts(description)
		SDP_Description *description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::EmailContact";
		SDP_EmailContact *email_contacts;
	PPCODE:
	{
		email_contacts = SDP_GetEmailContacts(description);

		SDP_RETURN_LINKED_LIST_AS_ARRAY(email_contacts, CLASS);
	}



void
remove_email_contact(description, email_contact)
		SDP_Description *    description
		SDP_EmailContact *   email_contact
	CODE:
		SDP_RemoveEmailContact(description, email_contact);



SV *
get_phone_contacts(description)
		SDP_Description *description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::PhoneContact";
		SDP_PhoneContact *phone_contacts;
	PPCODE:
	{
		phone_contacts = SDP_GetPhoneContacts(description);

		SDP_RETURN_LINKED_LIST_AS_ARRAY(phone_contacts, CLASS);
	}



void
remove_phone_contact(description, phone_contact)
		SDP_Description *    description
		SDP_PhoneContact *   phone_contact
	CODE:
		SDP_RemovePhoneContact(description, phone_contact);



SDP_Connection *
get_connection(description)
		SDP_Description *description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::Connection";
	CODE:
		RETVAL = SDP_GetConnection(description);
	OUTPUT:
		RETVAL



SDP_Bandwidth *
get_bandwidth(description)
		SDP_Description *description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::Bandwidth";
	CODE:
		RETVAL = SDP_GetBandwidth(description);
	OUTPUT:
		RETVAL



SV *
get_session_play_times(description)
		SDP_Description *description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::SessionPlayTime";
		SDP_SessionPlayTime *session_play_time;
	PPCODE:
	{
		session_play_time = SDP_GetSessionPlayTimes(description);

		SDP_RETURN_LINKED_LIST_AS_ARRAY(session_play_time, CLASS);
	}



void
remove_session_play_time(description, session_play_time)
		SDP_Description *       description
		SDP_SessionPlayTime *   session_play_time
	CODE:
		SDP_RemoveSessionPlayTime(description, session_play_time);



SV *
get_zone_adjustments(description)
		SDP_Description *description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::ZoneAdjustment";
		SDP_ZoneAdjustment *zone_adjustment;
	PPCODE:
	{
		zone_adjustment = SDP_GetZoneAdjustments(description);

		SDP_RETURN_LINKED_LIST_AS_ARRAY(zone_adjustment, CLASS);
	}



void
remove_zone_adjustment(description, zone_adjustment)
		SDP_Description *      description
		SDP_ZoneAdjustment *   zone_adjustment
	CODE:
		SDP_RemoveZoneAdjustment(description, zone_adjustment);



SDP_Encryption *
get_encryption(description)
		SDP_Description *description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::Encryption";
	CODE:
		RETVAL = SDP_GetEncryption(description);
	OUTPUT:
		RETVAL



SV *
get_attributes(description)
		SDP_Description *description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::Attribute";
		SDP_Attribute *attribute;
	PPCODE:
	{
		attribute = SDP_GetAttributes(description);

		SDP_RETURN_LINKED_LIST_AS_ARRAY(attribute, CLASS);
	}



void
remove_attribute(description, attribute)
		SDP_Description *   description
		SDP_Attribute *     attribute
	CODE:
		SDP_RemoveAttribute(description, attribute);



SV *
get_media_descriptions(description)
		SDP_Description *description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::MediaDescription";
		SDP_MediaDescription *media_description;
	PPCODE:
	{
		media_description = SDP_GetMediaDescriptions(description);

		SDP_RETURN_LINKED_LIST_AS_ARRAY(media_description, CLASS);
	}



void
remove_media_description(description, media_description)
		SDP_Description *        description
		SDP_MediaDescription *   media_description
	CODE:
		SDP_RemoveMediaDescription(description, media_description);



char *
output_descriptions_to_string(descriptions)
		SDP_Description *descriptions
	CODE:
		RETVAL = SDP_OutputDescriptionsToString(descriptions);
	OUTPUT:
		RETVAL



char *
output_description_to_string(description)
		SDP_Description *description
	CODE:
		RETVAL = SDP_OutputDescriptionToString(description);
	OUTPUT:
		RETVAL



int
output_descriptions_to_file(descriptions, filename)
		SDP_Description *   descriptions
		const char *        filename
	CODE:
		RETVAL = SDP_OutputDescriptionsToFile(descriptions, filename);
	OUTPUT:
		RETVAL



int
output_description_to_file(description, filename)
		SDP_Description *   description
		const char *        filename
	CODE:
		RETVAL = SDP_OutputDescriptionToFile(description, filename);
	OUTPUT:
		RETVAL



SDP_Description *
get_next_description(item)
		SDP_Description *item
	INIT:
		char CLASS[] = "Multimedia::SDP::Description";
	CODE:
		RETVAL = SDP_GetNextDescription(item);
	OUTPUT:
		RETVAL



SDP_Description *
get_previous_description(item)
		SDP_Description *item
	INIT:
		char CLASS[] = "Multimedia::SDP::Description";
	CODE:
		RETVAL = SDP_GetPreviousDescription(item);
	OUTPUT:
		RETVAL



void
destroy_descriptions(descriptions)
		SDP_Description *descriptions
	CODE:
		SDP_DestroyDescriptions(descriptions);



void
destroy_description(description)
		SDP_Description *description
	CODE:
		SDP_DestroyDescription(description);



void
destroy_email_contacts(description)
		SDP_Description *description
	CODE:
		SDP_DestroyEmailContacts(description);



void
destroy_phone_contacts(description)
		SDP_Description *description
	CODE:
		SDP_DestroyPhoneContacts(description);



void
destroy_session_play_times(description)
		SDP_Description *description
	CODE:
		SDP_DestroySessionPlayTimes(description);



void
destroy_zone_adjustments(description)
		SDP_Description *description
	CODE:
		SDP_DestroyZoneAdjustments(description);



void
destroy_attributes(description)
		SDP_Description *description
	CODE:
		SDP_DestroyAttributes(description);



void
destroy_media_descriptions(description)
		SDP_Description *description
	CODE:
		SDP_DestroyMediaDescriptions(description);







################################################################################
#
# The XSubs for the SDP_Owner struct class:
#
################################################################################

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::Owner



SDP_Owner *
new_owner(CLASS)
		char *CLASS
	CODE:
		RETVAL = SDP_NewOwner();
	OUTPUT:
		RETVAL



int
set_username(owner, username)
		SDP_Owner *    owner
		const char *   username
	CODE:
		RETVAL = SDP_SetUsername(owner, username);
	OUTPUT:
		RETVAL



int
set_session_id(owner, session_id)
		SDP_Owner *    owner
		const char *   session_id
	CODE:
		RETVAL = SDP_SetSessionID(owner, session_id);
	OUTPUT:
		RETVAL



int
set_session_version(owner, session_version)
		SDP_Owner *    owner
		const char *   session_version
	CODE:
		RETVAL = SDP_SetSessionVersion(owner, session_version);
	OUTPUT:
		RETVAL



int
set_owner_network_type(owner, network_type)
		SDP_Owner *    owner
		const char *   network_type
	CODE:
		RETVAL = SDP_SetOwnerNetworkType(owner, network_type);
	OUTPUT:
		RETVAL



int
set_owner_address_type(owner, address_type)
		SDP_Owner *    owner
		const char *   address_type
	CODE:
		RETVAL = SDP_SetOwnerAddressType(owner, address_type);
	OUTPUT:
		RETVAL



int
set_owner_address(owner, address)
		SDP_Owner *    owner
		const char *   address
	CODE:
		RETVAL = SDP_SetOwnerAddress(owner, address);
	OUTPUT:
		RETVAL



char *
get_username(owner)
		SDP_Owner *owner
	CODE:
		RETVAL = SDP_GetUsername(owner);
	OUTPUT:
		RETVAL



char *
get_session_id(owner)
		SDP_Owner *owner
	CODE:
		RETVAL = SDP_GetSessionID(owner);
	OUTPUT:
		RETVAL



char *
get_session_version(owner)
		SDP_Owner *owner
	CODE:
		RETVAL = SDP_GetSessionVersion(owner);
	OUTPUT:
		RETVAL



char *
get_owner_network_type(owner)
		SDP_Owner *owner
	CODE:
		RETVAL = SDP_GetOwnerNetworkType(owner);
	OUTPUT:
		RETVAL



char *
get_owner_address_type(owner)
		SDP_Owner *owner
	CODE:
		RETVAL = SDP_GetOwnerAddressType(owner);
	OUTPUT:
		RETVAL



char *
get_owner_address(owner)
		SDP_Owner *owner
	CODE:
		RETVAL = SDP_GetOwnerAddress(owner);
	OUTPUT:
		RETVAL



void
destroy_owner(owner)
		SDP_Owner *owner
	CODE:
		SDP_DestroyOwner(owner);







################################################################################
#
# The XSubs for the SDP_EmailContact struct class:
#
################################################################################

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::EmailContact



SDP_EmailContact *
new_email_contact(CLASS)
		char *CLASS
	CODE:
		RETVAL = SDP_NewEmailContact();
	OUTPUT:
		RETVAL



int
set_email_address(email_contact, address)
		SDP_EmailContact *   email_contact
		const char *         address
	CODE:
		RETVAL = SDP_SetEmailAddress(email_contact, address);
	OUTPUT:
		RETVAL



int
set_email_name(email_contact, name)
		SDP_EmailContact *   email_contact
		const char *         name
	CODE:
		RETVAL = SDP_SetEmailName(email_contact, name);
	OUTPUT:
		RETVAL



char *
get_email_address(email_contact)
		SDP_EmailContact *email_contact
	CODE:
		RETVAL = SDP_GetEmailAddress(email_contact);
	OUTPUT:
		RETVAL



char *
get_email_name(email_contact)
		SDP_EmailContact *email_contact
	CODE:
		RETVAL = SDP_GetEmailName(email_contact);
	OUTPUT:
		RETVAL



SDP_EmailContact *
get_next_email_contact(item)
		SDP_EmailContact *item
	INIT:
		char CLASS[] = "Multimedia::SDP::EmailContact";
	CODE:
		RETVAL = SDP_GetNextEmailContact(item);
	OUTPUT:
		RETVAL



SDP_EmailContact *
get_previous_email_contact(item)
		SDP_EmailContact *item
	INIT:
		char CLASS[] = "Multimedia::SDP::EmailContact";
	CODE:
		RETVAL = SDP_GetPreviousEmailContact(item);
	OUTPUT:
		RETVAL



void
destroy_email_contact(email_contact)
		SDP_EmailContact *email_contact
	CODE:
		SDP_DestroyEmailContact(email_contact);







################################################################################
#
# The XSubs for the SDP_PhoneContact struct class:
#
################################################################################

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::PhoneContact



SDP_PhoneContact *
new_phone_contact(CLASS)
		char *CLASS
	CODE:
		RETVAL = SDP_NewPhoneContact();
	OUTPUT:
		RETVAL



int
set_phone_number(phone_contact, number)
		SDP_PhoneContact *   phone_contact
		const char *         number
	CODE:
		RETVAL = SDP_SetPhoneNumber(phone_contact, number);
	OUTPUT:
		RETVAL



int
set_phone_name(phone_contact, name)
		SDP_PhoneContact *   phone_contact
		const char *        name
	CODE:
		RETVAL = SDP_SetPhoneName(phone_contact, name);
	OUTPUT:
		RETVAL



char *
get_phone_number(phone_contact)
		SDP_PhoneContact *phone_contact
	CODE:
		RETVAL = SDP_GetPhoneNumber(phone_contact);
	OUTPUT:
		RETVAL



char *
get_phone_name(phone_contact)
		SDP_PhoneContact *phone_contact
	CODE:
		RETVAL = SDP_GetPhoneName(phone_contact);
	OUTPUT:
		RETVAL



SDP_PhoneContact *
get_next_phone_contact(item)
		SDP_PhoneContact *item
	INIT:
		char CLASS[] = "Multimedia::SDP::PhoneContact";
	CODE:
		RETVAL = SDP_GetNextPhoneContact(item);
	OUTPUT:
		RETVAL



SDP_PhoneContact *
get_previous_phone_contact(item)
		SDP_PhoneContact *item
	INIT:
		char CLASS[] = "Multimedia::SDP::PhoneContact";
	CODE:
		RETVAL = SDP_GetPreviousPhoneContact(item);
	OUTPUT:
		RETVAL



void
destroy_phone_contact(phone_contact)
		SDP_PhoneContact *phone_contact
	CODE:
		SDP_DestroyPhoneContact(phone_contact);







################################################################################
#
# The XSubs for the SDP_Connection struct class:
#
################################################################################

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::Connection



SDP_Connection *
new_connection(CLASS)
		char *CLASS
	CODE:
		RETVAL = SDP_NewConnection();
	OUTPUT:
		RETVAL



int
set_connection_network_type(connection, network_type)
		SDP_Connection *   connection
		const char *       network_type
	CODE:
		RETVAL = SDP_SetConnectionNetworkType(connection, network_type);
	OUTPUT:
		RETVAL



int
set_connection_address_type(connection, address_type)
		SDP_Connection *   connection
		const char *       address_type
	CODE:
		RETVAL = SDP_SetConnectionAddressType(connection, address_type);
	OUTPUT:
		RETVAL



int
set_connection_address(connection, address)
		SDP_Connection *   connection
		const char *       address
	CODE:
		RETVAL = SDP_SetConnectionAddress(connection, address);
	OUTPUT:
		RETVAL



void
set_connection_ttl(connection, ttl)
		SDP_Connection *   connection
		int                ttl
	CODE:
		SDP_SetConnectionTTL(connection, ttl);



void
set_total_connection_addresses(connection, total_addresses)
		SDP_Connection *   connection
		int                total_addresses
	CODE:
		SDP_SetTotalConnectionAddresses(connection, total_addresses);



char *
get_connection_network_type(connection)
		SDP_Connection *connection
	CODE:
		RETVAL = SDP_GetConnectionNetworkType(connection);
	OUTPUT:
		RETVAL



char *
get_connection_address_type(connection)
		SDP_Connection *connection
	CODE:
		RETVAL = SDP_GetConnectionAddressType(connection);
	OUTPUT:
		RETVAL



char *
get_connection_address(connection)
		SDP_Connection *connection
	CODE:
		RETVAL = SDP_GetConnectionAddress(connection);
	OUTPUT:
		RETVAL



int
get_connection_ttl(connection)
		SDP_Connection *connection
	CODE:
		RETVAL = SDP_GetConnectionTTL(connection);
	OUTPUT:
		RETVAL



int
get_total_connection_addresses(connection)
		SDP_Connection *connection
	CODE:
		RETVAL = SDP_GetTotalConnectionAddresses(connection);
	OUTPUT:
		RETVAL



void
destroy_connection(connection)
		SDP_Connection *connection
	CODE:
		SDP_DestroyConnection(connection);







################################################################################
#
# The XSubs for the SDP_Bandwidth struct class:
#
################################################################################

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::Bandwidth



SDP_Bandwidth *
new_bandwidth(CLASS)
		char *CLASS
	CODE:
		RETVAL = SDP_NewBandwidth();
	OUTPUT:
		RETVAL



int
set_bandwidth_modifier(bandwidth, modifier)
		SDP_Bandwidth *   bandwidth
		const char *      modifier
	CODE:
		RETVAL = SDP_SetBandwidthModifier(bandwidth, modifier);
	OUTPUT:
		RETVAL



void
set_bandwidth_value(bandwidth, value)
		SDP_Bandwidth *   bandwidth
		long              value
	CODE:
		SDP_SetBandwidthValue(bandwidth, value);



char *
get_bandwidth_modifier(bandwidth)
		SDP_Bandwidth *bandwidth
	CODE:
		RETVAL = SDP_GetBandwidthModifier(bandwidth);
	OUTPUT:
		RETVAL



long
get_bandwidth_value(bandwidth)
		SDP_Bandwidth *bandwidth
	CODE:
		RETVAL = SDP_GetBandwidthValue(bandwidth);
	OUTPUT:
		RETVAL



void
destroy_bandwidth(bandwidth)
		SDP_Bandwidth *bandwidth
	CODE:
		SDP_DestroyBandwidth(bandwidth);







################################################################################
#
# The XSubs for the SDP_SessionPlayTime struct class:
#
################################################################################

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::SessionPlayTime



SDP_SessionPlayTime *
new_session_play_time(CLASS)
		char *CLASS
	CODE:
		RETVAL = SDP_NewSessionPlayTime();
	OUTPUT:
		RETVAL



void
set_start_time(session_play_time, start_time)
		SDP_SessionPlayTime *   session_play_time
		time_t                  start_time
	CODE:
		SDP_SetStartTime(session_play_time, start_time);



void
set_end_time(session_play_time, end_time)
		SDP_SessionPlayTime *   session_play_time
		time_t                  end_time
	CODE:
		SDP_SetEndTime(session_play_time, end_time);



void
add_repeat_time(session_play_time, repeat_time)
		SDP_SessionPlayTime *   session_play_time
		SDP_RepeatTime *        repeat_time
	CODE:
		SDP_AddRepeatTime(session_play_time, repeat_time);



int
add_new_repeat_time(session_play_time, repeat_interval, active_duration, ...)
		SDP_SessionPlayTime *   session_play_time
		unsigned long           repeat_interval
		unsigned long           active_duration
	PREINIT:
		unsigned long *repeat_offsets;
		int total_offsets;
	CODE:
	{
		total_offsets = items - 3;

		SDP_COPY_ARRAY_FROM_STACK(
			repeat_offsets, unsigned long, SvUV, total_offsets
		);

		RETVAL = SDP_AddNewRepeatTime(
			session_play_time,
			repeat_interval,
			active_duration,
			repeat_offsets,
			total_offsets
		);

		if (repeat_offsets)
			SDP_Destroy(repeat_offsets);
	}
	OUTPUT:
		RETVAL



time_t
get_start_time(session_play_time)
		SDP_SessionPlayTime *session_play_time
	CODE:
		RETVAL = SDP_GetStartTime(session_play_time);
	OUTPUT:
		RETVAL



time_t
get_end_time(session_play_time)
		SDP_SessionPlayTime *session_play_time
	CODE:
		RETVAL = SDP_GetEndTime(session_play_time);
	OUTPUT:
		RETVAL



SV *
get_repeat_times(session_play_time)
		SDP_SessionPlayTime *session_play_time
	PREINIT:
		char CLASS[] = "Multimedia::SDP::RepeatTime";
		SDP_RepeatTime *repeat_time;
	PPCODE:
	{
		repeat_time = SDP_GetRepeatTimes(session_play_time);

		SDP_RETURN_LINKED_LIST_AS_ARRAY(repeat_time, CLASS);
	}



void
remove_repeat_time(session_play_times, repeat_time)
		SDP_SessionPlayTime *   session_play_times
		SDP_RepeatTime *        repeat_time
	CODE:
		SDP_RemoveRepeatTime(session_play_times, repeat_time);



SDP_SessionPlayTime *
get_next_session_play_time(item)
		SDP_SessionPlayTime *item
	INIT:
		char CLASS[] = "Multimedia::SDP::SessionPlayTime";
	CODE:
		RETVAL = SDP_GetNextSessionPlayTime(item);
	OUTPUT:
		RETVAL



SDP_SessionPlayTime *
get_previous_session_play_time(item)
		SDP_SessionPlayTime *item
	INIT:
		char CLASS[] = "Multimedia::SDP::SessionPlayTime";
	CODE:
		RETVAL = SDP_GetPreviousSessionPlayTime(item);
	OUTPUT:
		RETVAL



void
destroy_session_play_time(session_play_time)
		SDP_SessionPlayTime *session_play_time
	CODE:
		SDP_DestroySessionPlayTime(session_play_time);



void
destroy_repeat_times(session_play_time)
		SDP_SessionPlayTime *session_play_time
	CODE:
		SDP_DestroyRepeatTimes(session_play_time);







################################################################################
#
# The XSubs for the SDP_RepeatTime struct class:
#
################################################################################

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::RepeatTime



SDP_RepeatTime *
new_repeat_time(CLASS)
		char *CLASS
	CODE:
		RETVAL = SDP_NewRepeatTime();
	OUTPUT:
		RETVAL



void
set_repeat_interval(repeat_time, repeat_interval)
		SDP_RepeatTime *   repeat_time
		unsigned long      repeat_interval
	CODE:
		SDP_SetRepeatInterval(repeat_time, repeat_interval);



void
set_active_duration(repeat_time, active_duration)
		SDP_RepeatTime *   repeat_time
		unsigned long      active_duration
	CODE:
		SDP_SetActiveDuration(repeat_time, active_duration);



int
set_repeat_offsets(repeat_time, ...)
		SDP_RepeatTime *repeat_time
	PREINIT:
		unsigned long *repeat_offsets;
		int total_offsets;
	CODE:
	{
		total_offsets = items - 1;

		SDP_COPY_ARRAY_FROM_STACK(
			repeat_offsets, unsigned long, SvUV, total_offsets
		);

		RETVAL = SDP_SetRepeatOffsets(
			repeat_time, repeat_offsets, total_offsets
		);

		if (repeat_offsets)
			SDP_Destroy(repeat_offsets);
	}
	OUTPUT:
		RETVAL



unsigned long
get_repeat_interval(repeat_time)
		SDP_RepeatTime *repeat_time
	CODE:
		RETVAL = SDP_GetRepeatInterval(repeat_time);
	OUTPUT:
		RETVAL



unsigned long
get_active_duration(repeat_time)
		SDP_RepeatTime *repeat_time
	CODE:
		RETVAL = SDP_GetActiveDuration(repeat_time);
	OUTPUT:
		RETVAL



unsigned long *
get_repeat_offsets(repeat_time)
		SDP_RepeatTime *repeat_time
	CODE:
		RETVAL = SDP_GetRepeatOffsets(repeat_time);
	OUTPUT:
		RETVAL



int
get_total_repeat_offsets(repeat_time)
		SDP_RepeatTime *repeat_time
	CODE:
		RETVAL = SDP_GetTotalRepeatOffsets(repeat_time);
	OUTPUT:
		RETVAL



SDP_RepeatTime *
get_next_repeat_time(item)
		SDP_RepeatTime *item
	INIT:
		char CLASS[] = "Multimedia::SDP::RepeatTime";
	CODE:
		RETVAL = SDP_GetNextRepeatTime(item);
	OUTPUT:
		RETVAL



SDP_RepeatTime *
get_previous_repeat_time(item)
		SDP_RepeatTime *item
	INIT:
		char CLASS[] = "Multimedia::SDP::RepeatTime";
	CODE:
		RETVAL = SDP_GetPreviousRepeatTime(item);
	OUTPUT:
		RETVAL



void
destroy_repeat_time(repeat_time)
		SDP_RepeatTime *repeat_time
	CODE:
		SDP_DestroyRepeatTime(repeat_time);







################################################################################
#
# The XSubs for the SDP_ZoneAdjustment struct class:
#
################################################################################

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::ZoneAdjustment



SDP_ZoneAdjustment *
new_zone_adjustment(CLASS)
		char *CLASS
	CODE:
		RETVAL = SDP_NewZoneAdjustment();
	OUTPUT:
		RETVAL



void
set_zone_adjustment_time(zone_adjustment, time)
		SDP_ZoneAdjustment *   zone_adjustment
		time_t                 time
	CODE:
		SDP_SetZoneAdjustmentTime(zone_adjustment, time);



void
set_zone_adjustment_offset(zone_adjustment, offset)
		SDP_ZoneAdjustment *   zone_adjustment
		long                   offset
	CODE:
		SDP_SetZoneAdjustmentOffset(zone_adjustment, offset);



time_t
get_zone_adjustment_time(zone_adjustment)
		SDP_ZoneAdjustment *zone_adjustment
	CODE:
		RETVAL = SDP_GetZoneAdjustmentTime(zone_adjustment);
	OUTPUT:
		RETVAL



long
get_zone_adjustment_offset(zone_adjustment)
		SDP_ZoneAdjustment *zone_adjustment
	CODE:
		RETVAL = SDP_GetZoneAdjustmentOffset(zone_adjustment);
	OUTPUT:
		RETVAL



SDP_ZoneAdjustment *
get_next_zone_adjustment(item)
		SDP_ZoneAdjustment *item
	INIT:
		char CLASS[] = "Multimedia::SDP::ZoneAdjustment";
	CODE:
		RETVAL = SDP_GetNextZoneAdjustment(item);
	OUTPUT:
		RETVAL



SDP_ZoneAdjustment *
get_previous_zone_adjustment(item)
		SDP_ZoneAdjustment *item
	INIT:
		char CLASS[] = "Multimedia::SDP::ZoneAdjustment";
	CODE:
		RETVAL = SDP_GetPreviousZoneAdjustment(item);
	OUTPUT:
		RETVAL



void
destroy_zone_adjustment(zone_adjustment)
		SDP_ZoneAdjustment *zone_adjustment
	CODE:
		SDP_DestroyZoneAdjustment(zone_adjustment);







################################################################################
#
# The XSubs for the SDP_Encryption struct class:
#
################################################################################

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::Encryption



SDP_Encryption *
new_encryption(CLASS)
		char *CLASS
	CODE:
		RETVAL = SDP_NewEncryption();
	OUTPUT:
		RETVAL



int
set_encryption_method(encryption, method)
		SDP_Encryption *   encryption
		const char *       method
	CODE:
		RETVAL = SDP_SetEncryptionMethod(encryption, method);
	OUTPUT:
		RETVAL



int
set_encryption_key(encryption, key)
		SDP_Encryption *   encryption
		const char *       key
	CODE:
		RETVAL = SDP_SetEncryptionKey(encryption, key);
	OUTPUT:
		RETVAL



char *
get_encryption_method(encryption)
		SDP_Encryption *encryption
	CODE:
		RETVAL = SDP_GetEncryptionMethod(encryption);
	OUTPUT:
		RETVAL



char *
get_encryption_key(encryption)
		SDP_Encryption *encryption
	CODE:
		RETVAL = SDP_GetEncryptionKey(encryption);
	OUTPUT:
		RETVAL



void
destroy_encryption(encryption)
		SDP_Encryption *encryption
	CODE:
		SDP_DestroyEncryption(encryption);







################################################################################
#
# The XSubs for the SDP_Attribute struct class:
#
################################################################################

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::Attribute



SDP_Attribute *
new_attribute(CLASS)
		char *CLASS
	CODE:
		RETVAL = SDP_NewAttribute();
	OUTPUT:
		RETVAL



int
set_attribute_name(attribute, name)
		SDP_Attribute *   attribute
		const char *      name
	CODE:
		RETVAL = SDP_SetAttributeName(attribute, name);
	OUTPUT:
		RETVAL



int
set_attribute_value(attribute, value)
		SDP_Attribute *   attribute
		const char *      value
	CODE:
		RETVAL = SDP_SetAttributeValue(attribute, value);
	OUTPUT:
		RETVAL



char *
get_attribute_name(attribute)
		SDP_Attribute *attribute
	CODE:
		RETVAL = SDP_GetAttributeName(attribute);
	OUTPUT:
		RETVAL



char *
get_attribute_value(attribute)
		SDP_Attribute *attribute
	CODE:
		RETVAL = SDP_GetAttributeValue(attribute);
	OUTPUT:
		RETVAL



SDP_Attribute *
get_next_attribute(item)
		SDP_Attribute *item
	INIT:
		char CLASS[] = "Multimedia::SDP::Attribute";
	CODE:
		RETVAL = SDP_GetNextAttribute(item);
	OUTPUT:
		RETVAL



SDP_Attribute *
get_previous_attribute(item)
		SDP_Attribute *item
	INIT:
		char CLASS[] = "Multimedia::SDP::Attribute";
	CODE:
		RETVAL = SDP_GetPreviousAttribute(item);
	OUTPUT:
		RETVAL



void
destroy_attribute(attribute)
		SDP_Attribute *attribute
	CODE:
		SDP_DestroyAttribute(attribute);







################################################################################
#
# The XSubs for the SDP_MediaDescription struct class:
#
################################################################################

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::MediaDescription



SDP_MediaDescription *
new_media_description(CLASS)
		char *CLASS
	CODE:
		RETVAL = SDP_NewMediaDescription();
	OUTPUT:
		RETVAL



int
set_media_type(media_description, media_type)
		SDP_MediaDescription *   media_description
		const char *             media_type
	CODE:
		RETVAL = SDP_SetMediaType(media_description, media_type);
	OUTPUT:
		RETVAL



void
set_media_port(media_description, port)
		SDP_MediaDescription *   media_description
		unsigned short           port
	CODE:
		SDP_SetMediaPort(media_description, port);



void
set_total_media_ports(media_description, total_ports)
		SDP_MediaDescription *   media_description
		unsigned short           total_ports
	CODE:
		SDP_SetTotalMediaPorts(media_description, total_ports);



int
set_media_transport_protocol(media_description, transport_protocol)
		SDP_MediaDescription *   media_description
		const char *             transport_protocol
	CODE:
		RETVAL = SDP_SetMediaTransportProtocol(media_description, transport_protocol);
	OUTPUT:
		RETVAL



int
set_media_formats(media_description, formats)
		SDP_MediaDescription *   media_description
		const char *             formats
	CODE:
		RETVAL = SDP_SetMediaFormats(media_description, formats);
	OUTPUT:
		RETVAL



int
set_media_information(media_description, media_information)
		SDP_MediaDescription *   media_description
		const char *             media_information
	CODE:
		RETVAL = SDP_SetMediaInformation(media_description, media_information);
	OUTPUT:
		RETVAL



int
set_media_connection(media_description, network_type, address_type, address, ttl, total_addresses)
		SDP_MediaDescription *   media_description
		const char *             network_type
		const char *             address_type
		const char *             address
		int                      ttl
		int                      total_addresses
	CODE:
		RETVAL = SDP_SetMediaConnection(media_description, network_type, address_type, address, ttl, total_addresses);
	OUTPUT:
		RETVAL



int
set_media_bandwidth(media_description, modifier, value)
		SDP_MediaDescription *   media_description
		const char *             modifier
		long                     value
	CODE:
		RETVAL = SDP_SetMediaBandwidth(media_description, modifier, value);
	OUTPUT:
		RETVAL



int
set_media_encryption(media_description, method, key)
		SDP_MediaDescription *   media_description
		const char *             method
		const char *             key
	CODE:
		RETVAL = SDP_SetMediaEncryption(media_description, method, key);
	OUTPUT:
		RETVAL



void
add_media_attribute(media_description, attribute)
		SDP_MediaDescription *   media_description
		SDP_Attribute *          attribute
	CODE:
		SDP_AddMediaAttribute(media_description, attribute);



int
add_new_media_attribute(media_description, name, value)
		SDP_MediaDescription *   media_description
		const char *             name
		const char *             value
	CODE:
		RETVAL = SDP_AddNewMediaAttribute(media_description, name, value);
	OUTPUT:
		RETVAL



char *
get_media_type(media_description)
		SDP_MediaDescription *media_description
	CODE:
		RETVAL = SDP_GetMediaType(media_description);
	OUTPUT:
		RETVAL



unsigned short
get_media_port(media_description)
		SDP_MediaDescription *media_description
	CODE:
		RETVAL = SDP_GetMediaPort(media_description);
	OUTPUT:
		RETVAL



unsigned short
get_total_media_ports(media_description)
		SDP_MediaDescription *media_description
	CODE:
		RETVAL = SDP_GetTotalMediaPorts(media_description);
	OUTPUT:
		RETVAL



char *
get_media_transport_protocol(media_description)
		SDP_MediaDescription *media_description
	CODE:
		RETVAL = SDP_GetMediaTransportProtocol(media_description);
	OUTPUT:
		RETVAL



char *
get_media_formats(media_description)
		SDP_MediaDescription *media_description
	CODE:
		RETVAL = SDP_GetMediaFormats(media_description);
	OUTPUT:
		RETVAL



char *
get_media_information(media_description)
		SDP_MediaDescription *media_description
	CODE:
		RETVAL = SDP_GetMediaInformation(media_description);
	OUTPUT:
		RETVAL



SDP_Connection *
get_media_connection(media_description)
		SDP_MediaDescription *media_description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::Connection";
	CODE:
		RETVAL = SDP_GetMediaConnection(media_description);
	OUTPUT:
		RETVAL



SDP_Bandwidth *
get_media_bandwidth(media_description)
		SDP_MediaDescription *media_description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::Bandwidth";
	CODE:
		RETVAL = SDP_GetMediaBandwidth(media_description);
	OUTPUT:
		RETVAL



SDP_Encryption *
get_media_encryption(media_description)
		SDP_MediaDescription *media_description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::Encryption";
	CODE:
		RETVAL = SDP_GetMediaEncryption(media_description);
	OUTPUT:
		RETVAL



SV *
get_media_attributes(media_description)
		SDP_MediaDescription *media_description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::Attribute";
		SDP_Attribute *attribute;
	PPCODE:
	{
		attribute = SDP_GetMediaAttributes(media_description);

		SDP_RETURN_LINKED_LIST_AS_ARRAY(attribute, CLASS);
	}



SDP_MediaDescription *
get_next_media_description(item)
		SDP_MediaDescription *item
	INIT:
		char CLASS[] = "Multimedia::SDP::MediaDescription";
	CODE:
		RETVAL = SDP_GetNextMediaDescription(item);
	OUTPUT:
		RETVAL



void
destroy_media_description(media_description)
		SDP_MediaDescription *media_description
	CODE:
		SDP_DestroyMediaDescription(media_description);



void
destroy_media_attributes(media_description)
		SDP_MediaDescription *media_description
	CODE:
		SDP_DestroyMediaAttributes(media_description);










################################################################################
#
# The XSubs for generic routines:
#
################################################################################

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::SinisterSdp



SDP_Error
get_last_error()
	CODE:
		RETVAL = SDP_GetLastError();
	OUTPUT:
		RETVAL



const char *
get_last_error_string()
	CODE:
		RETVAL = SDP_GetLastErrorString();
	OUTPUT:
		RETVAL



int
error_raised()
	CODE:
		RETVAL = SDP_ErrorRaised();
	OUTPUT:
		RETVAL



void
invoke_handlers_for_errors(invoke_handlers)
		int invoke_handlers
	CODE:
		SDP_InvokeHandlersForErrors(invoke_handlers);



int
is_known_field_type(type)
		char type
	CODE:
		RETVAL = SDP_IsKnownFieldType(type);
	OUTPUT:
		RETVAL



char *
get_field_type_description(type)
		char type
	CODE:
		RETVAL = SDP_GetFieldTypeDescription(type);
	OUTPUT:
		RETVAL



void
set_fatal_error_handler(handler)
		SV *handler
	CODE:
		SDP_SET_SV_IN_GLUE(_fatal_error_handler, handler);
		SDP_SetFatalErrorHandler(invoke_fatal_error_handler);



void
set_non_fatal_error_handler(handler)
		SV *handler
	CODE:
		SDP_SET_SV_IN_GLUE(_non_fatal_error_handler, handler);
		SDP_SetNonFatalErrorHandler(invoke_non_fatal_error_handler);
