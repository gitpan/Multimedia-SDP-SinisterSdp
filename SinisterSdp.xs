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
 * This macro takes an element from a SinisterSdp linked list and from it
 * returns either the first element (if the XSub is being called in scalar
 * context) or each element in the list (if the XSub is being called in list
 * context and there is more than one element in the list):
 */
#define SDPXS_RETURN_LINKED_LIST_AS_ARRAY(_item_, _supporter_, _class_) \
	while (_item_)                                                  \
	{                                                               \
		SV *sv;                                                 \
                                                                        \
		if (_supporter_)                                        \
			SDPXS_AddDependency(_supporter_, _item_);       \
                                                                        \
		EXTEND(SP, 1);                                          \
		sv = sv_newmortal();                                    \
		sv_setref_pv(sv, _class_, _item_);                      \
		PUSHs(sv);                                              \
                                                                        \
		if (GIMME == G_SCALAR)                                  \
			break;                                          \
		                                                        \
		_item_ = SDP_GetNext(_item_);                           \
	}

/*
 * This macro is used to copy each SV of the same type from the incoming @_
 * stack to a C array.
 */
#define SDPXS_COPY_ARRAY_FROM_STACK(_destination_, _type_, _svmac_, _total_)   \
	do {                                                                   \
		_destination_ = NULL;                                          \
                                                                               \
		if (_total_)                                                   \
		{                                                              \
			int i;                                                 \
			int sp_i;                                              \
			int array_i = items - (_total_);                       \
                                                                               \
			_destination_ = (_type_ *) SDP_Allocate(               \
				sizeof(_type_) * (_total_)                     \
			);                                                     \
			if (_destination_ == NULL)                             \
			{                                                      \
				SDP_RaiseFatalError(                           \
					SDP_ERR_OUT_OF_MEMORY,                 \
					"Couldn't allocate memory to "         \
					"copy an array from @_: %s.",          \
					SDP_OS_ERROR_STRING                    \
				);                                             \
				XSRETURN_UNDEF;                                \
			}                                                      \
                                                                               \
			for (i = 0, sp_i = array_i; i < (_total_); ++i,++sp_i) \
				_destination_[i] = (_type_) _svmac_(ST(sp_i)); \
		}                                                              \
	} while (0)

/*
 * This macro shifts objects off the stack and builds a doubly-linked list with
 * them:
 */
#define SDPXS_ARRAY_TO_LINKED_LIST(_destination_, _type_, _total_)   \
	do {                                                         \
		int i;                                               \
                                                                     \
		memset(&(_destination_), 0, sizeof(_destination_));  \
                                                                     \
		for (i = items - (_total_); i < items; ++i)          \
		{                                                    \
			SDP_LINK_INTO_LIST(                          \
				_destination_,                       \
				(_type_ *) SvIV((SV *) SvRV(ST(i))), \
				_type_                               \
			);                                           \
		}                                                    \
	} while (0)

/*
 * This is used to set an SV in the SDPXS_ParserGlue struct or in those global
 * error handling variables after it:
 */
#define SDPXS_SET_SV(_sv_to_set_, _sv_)      \
	if (_sv_to_set_ == NULL)             \
		_sv_to_set_ = newSVsv(_sv_); \
        else                                 \
		SvSetSV(_sv_to_set_, _sv_);

/*
 * This is used to retrieve a value from the SDPXS_ParserGlue struct or one of
 * those global error handlers after it:
 */
#define SDPXS_GET_SV(_sv_to_get_) \
	((_sv_to_get_) ? newSVsv(_sv_to_get_) : &PL_sv_undef)

/*
 * These two are used to increment and descrement the ref counts of those
 * SV's:
 */
#define SDPXS_INCREMENT_REFCOUNT(_sv_) \
	((_sv_) ? SvREFCNT_inc(_sv_) : (void) 0)
#define SDPXS_DECREMENT_REFCOUNT(_sv_) \
	((_sv_) ? SvREFCNT_dec(_sv_) : (void) 0)



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
} SDPXS_ParserGlue;

int SDPXS_InvokeStartHandler(
	SDP_Parser *   parser,
	void *         user_data)
{
	dSP;
	SDPXS_ParserGlue *parser_glue = (SDPXS_ParserGlue *) user_data;

	ENTER;
	SAVETMPS;

	PUSHMARK(SP);
	XPUSHs(parser_glue->parser);
	XPUSHs(parser_glue->user_data);
	PUTBACK;

	perl_call_sv(parser_glue->start_handler, G_DISCARD|G_VOID);

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

int SDPXS_InvokeStartDescriptionHandler(
	SDP_Parser *   parser,
	int            description_number,
	void *         user_data)
{
	dSP;
	SDPXS_ParserGlue *parser_glue = (SDPXS_ParserGlue *) user_data;

	ENTER;
	SAVETMPS;

	PUSHMARK(SP);
	XPUSHs(parser_glue->parser);
	XPUSHs(sv_2mortal(newSViv(description_number)));
	XPUSHs(parser_glue->user_data);
	PUTBACK;

	perl_call_sv(parser_glue->start_description_handler, G_DISCARD|G_VOID);

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

int SDPXS_InvokeFieldHandler(
	SDP_Parser *   parser,
	char           field_type,
	const char *   field_value,
	void *         user_data)
{
	dSP;
	SDPXS_ParserGlue *parser_glue = (SDPXS_ParserGlue *) user_data;

	ENTER;
	SAVETMPS;

	PUSHMARK(SP);
	XPUSHs(parser_glue->parser);
	XPUSHs(sv_2mortal(newSVpvf("%c", field_type)));
	XPUSHs(sv_2mortal(newSVpv(field_value, 0)));
	XPUSHs(parser_glue->user_data);
	PUTBACK;

	perl_call_sv(parser_glue->field_handler, G_DISCARD|G_VOID);

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

int SDPXS_InvokeEndDescriptionHandler(
	SDP_Parser *   parser,
	int            description_number,
	void *         user_data)
{
	dSP;
	SDPXS_ParserGlue *parser_glue = (SDPXS_ParserGlue *) user_data;

	ENTER;
	SAVETMPS;

	PUSHMARK(SP);
	XPUSHs(parser_glue->parser);
	XPUSHs(sv_2mortal(newSViv(description_number)));
	XPUSHs(parser_glue->user_data);
	PUTBACK;

	perl_call_sv(parser_glue->end_description_handler, G_DISCARD|G_VOID);

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

void SDPXS_InvokeEndHandler(
	SDP_Parser *   parser,
	int            parser_result,
	void *         user_data)
{
	dSP;
	SDPXS_ParserGlue *parser_glue = (SDPXS_ParserGlue *) user_data;

	ENTER;
	SAVETMPS;

	PUSHMARK(SP);
	XPUSHs(parser_glue->parser);
	XPUSHs(sv_2mortal(newSViv(parser_result)));
	XPUSHs(parser_glue->user_data);
	PUTBACK;

	perl_call_sv(parser_glue->start_handler, G_DISCARD|G_VOID);

	FREETMPS;
        LEAVE;

	parser_glue->halt_parsing = 0;
}





/*
 * Same thing as above with SDPXS_ParserGlue. We can't register Perl
 * subroutines as the SinisterSdp error handlers, so instead we store them here
 * and then register functions to prepare the stack and invoke them properly:
 */
static SV *sdpxs_fatal_error_handler     = NULL;
static SV *sdpxs_non_fatal_error_handler = NULL;

void SDPXS_InvokeFatalErrorHandler(
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

	perl_call_sv(sdpxs_fatal_error_handler, G_DISCARD|G_VOID);

	FREETMPS;
	LEAVE;
}

int SDPXS_InvokeNonFatalErrorHandler(
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

	scalars_returned = perl_call_sv(
		sdpxs_non_fatal_error_handler, G_SCALAR
	);

	SPAGAIN;

	status = scalars_returned ? POPi : 0;

	PUTBACK;
	FREETMPS;
	LEAVE;

	return status;
}





/*
 * This hash stores pointers to the objects whose destruction must be delayed
 * for a while because objects within them (objects that they manage and they
 * are in charge of destroying) are still in use:
 */
static HV *sdpxs_objects_needing_cleanup = NULL;

#define SDPXS_MAX_MACHINE_ADDRESS_SIZE 64

static void SDPXS_RegisterForDelayedCleanup(void *address)
{
	char stringified_address[SDPXS_MAX_MACHINE_ADDRESS_SIZE] = "";

	if (sdpxs_objects_needing_cleanup == NULL)
		sdpxs_objects_needing_cleanup = newHV();

	snprintf(
		stringified_address, sizeof(stringified_address), "%p", address
	);

	hv_store(
		sdpxs_objects_needing_cleanup,
		stringified_address,
		strlen(stringified_address),
		newSViv(1),
		0
	);
}

static int SDPXS_IsCleanupPending(void *address)
{
	char stringified_address[SDPXS_MAX_MACHINE_ADDRESS_SIZE] = "";
	int length;
	SV **still_needs_cleanup;
	int exists;

	if (sdpxs_objects_needing_cleanup == NULL)
		sdpxs_objects_needing_cleanup = newHV();

	snprintf(
		stringified_address, sizeof(stringified_address), "%p", address
	);
	length = strlen(stringified_address); 

	/* Make sure the entry exists firsts before we check it: */
	exists = hv_exists(
		sdpxs_objects_needing_cleanup, stringified_address, length
	);
	if (!exists)
		return 0;

	/* Check the scalar: */
	still_needs_cleanup = hv_fetch(
		sdpxs_objects_needing_cleanup, stringified_address, length, 0
	);
	return SvTRUE(*still_needs_cleanup) ? 1 : 0;
}

static void SDPXS_DelayedCleanupCompleted(void *address)
{
	char stringified_address[SDPXS_MAX_MACHINE_ADDRESS_SIZE] = "";
	int length;
	SV *still_needs_cleanup;
	int exists;

	if (sdpxs_objects_needing_cleanup == NULL)
		sdpxs_objects_needing_cleanup = newHV();

	snprintf(
		stringified_address, sizeof(stringified_address), "%p", address
	);
	length = strlen(stringified_address);

	/* Make sure the entry exists firsts: */
	exists = hv_exists(
		sdpxs_objects_needing_cleanup, stringified_address, length
	);
	if (!exists)
		return;

	/* Delete it from the global hash: */
	still_needs_cleanup = hv_delete(
		sdpxs_objects_needing_cleanup, stringified_address, length, 0
	);

	SvREFCNT_dec(still_needs_cleanup);
}





/*
 * These two hash and the routines below that operate on them form the
 * dependency mechanism.
 */

static HV *sdpxs_active_dependents = NULL;
static HV *sdpxs_dependencies      = NULL;

void SDPXS_AddDependency(
	void *   supporter,
	void *   dependent)
{
	/* These store the supporter and dependent pointers as strings: */
	char supporter_address[SDPXS_MAX_MACHINE_ADDRESS_SIZE] = "";
	char dependent_address[SDPXS_MAX_MACHINE_ADDRESS_SIZE] = "";

	/* The lengths of each string: */
	int supporter_address_length, dependent_address_length;

	/*
	 * The will store a pointer to the hash that contains each object that
	 * dependents on this supporter object and the number of references
	 * that have been taken to them. When a dependent object gets added to
	 * the hash, it has an initial count of 1 as its value. When
	 * SDPXS_RemoveDependency() is called, this count gets decremented,
	 * and if it reaches zero, then the key/value pair is removed from the
	 * hash entirely. When the final pair is removed from this hash, the
	 * hash itself is destroyed, and the supporter object can be destroyed
	 * if needed:
	 */
	HV *dependents;

	/*
	 * This stores a pointer to a pointer to an SV that contains a
	 * reference to the dependents hash:
	 */
	SV **dependents_ref;

	/* Just used to store the return value of hv_exists(): */
	int exists;



	/* Initialize the hashes if we haven't done so yet: */
	if (sdpxs_active_dependents == NULL)
		sdpxs_active_dependents = newHV();
	if (sdpxs_dependencies == NULL)
		sdpxs_dependencies = newHV();

	/* Get stringified versions of each pointer supplied to us: */
	snprintf(supporter_address, sizeof(supporter_address), "%p", supporter);
	supporter_address_length = strlen(supporter_address);
	snprintf(dependent_address, sizeof(dependent_address), "%p", dependent);
	dependent_address_length = strlen(dependent_address);



	/*
	 * Check the sdpxs_active_dependents hash of hashes for an entry for
	 * this supporter, and create and store a new hash for it if there
	 * isn't one yet:
	 */
	exists = hv_exists(
		sdpxs_active_dependents,
		supporter_address,
		supporter_address_length
	);
	if (!exists)
		hv_store(
			sdpxs_active_dependents,
			supporter_address,
			supporter_address_length,
			newRV_noinc((SV *) newHV()),
			0
		);



	/* Get the hash reference from the hash, then dereference it: */
	dependents_ref = hv_fetch(
		sdpxs_active_dependents,
		supporter_address,
		supporter_address_length,
		0
	);
	dependents = (HV *) SvRV(*dependents_ref);

	/*
	 * Now check the hash of dependents for an entry for this dependent,
	 * and add one if it doesn't already exist, or increment it if it
	 * already does:
	 */
	exists = hv_exists(
		dependents, dependent_address, dependent_address_length
	);
	if (exists)
	{
		SV **dependent_object = hv_fetch(
			dependents,
			dependent_address,
			dependent_address_length,
			0
		);

		/* Increment it: */
		sv_setiv(*dependent_object, SvIV(*dependent_object) + 1);
	}
	else
	{
		hv_store(
			dependents,
			dependent_address,
			dependent_address_length,
			newSViv(1),
			0
		);
	}



	/* Now add an entry to the supporters hash: */
	hv_store(
		sdpxs_dependencies,
		dependent_address,
		dependent_address_length,
		newSVpvn(supporter_address, supporter_address_length),
		0
	);
}

int SDPXS_HasDependents(void *supporter)
{
	char supporter_address[SDPXS_MAX_MACHINE_ADDRESS_SIZE] = "";
	int length;

	/* Initialize the hashes if we haven't done so yet: */
	if (sdpxs_active_dependents == NULL)
		sdpxs_active_dependents = newHV();
	if (sdpxs_dependencies == NULL)
		sdpxs_dependencies = newHV();

	snprintf(supporter_address, sizeof(supporter_address), "%p", supporter);
	length = strlen(supporter_address);

	if (hv_exists(sdpxs_active_dependents, supporter_address, length))
	{
		HV *dependents;
		SV **dependents_ref;

		/*
		 * Dereference the hash and check to see if there are any
		 * dependents in it:
		 */
		dependents_ref = hv_fetch(
			sdpxs_active_dependents,
			supporter_address,
			length,
			0
		);
		dependents = (HV *) SvRV(*dependents_ref);

		return HvKEYS(dependents) ? 1 : 0;
	}
	else
	{
		return 0;
	}
}

int SDPXS_IsDependent(void *dependent)
{
	char dependent_address[SDPXS_MAX_MACHINE_ADDRESS_SIZE] = "";
	int dependent_address_length;
	int exists;

	/* Initialize the hashes if we haven't done so yet: */
	if (sdpxs_active_dependents == NULL)
		sdpxs_active_dependents = newHV();
	if (sdpxs_dependencies == NULL)
		sdpxs_dependencies = newHV();

	snprintf(dependent_address, sizeof(dependent_address), "%p", dependent);
	dependent_address_length = strlen(dependent_address);

	exists = hv_exists(
		sdpxs_dependencies, dependent_address, dependent_address_length
	);
	return exists ? 1 : 0;
}

void *SDPXS_GetSupporter(void *dependent)
{
	char dependent_address[SDPXS_MAX_MACHINE_ADDRESS_SIZE] = "";
	int dependent_address_length;
	int exists;

	snprintf(dependent_address, sizeof(dependent_address), "%p", dependent);
	dependent_address_length = strlen(dependent_address);

	exists = hv_exists(
		sdpxs_dependencies, dependent_address, dependent_address_length
	);
	if (exists)
	{
		SV **supporter;
		void *rv;

		supporter = hv_fetch(
			sdpxs_dependencies,
			dependent_address,
			dependent_address_length,
			0
		);
		sscanf(SvPV_nolen(*supporter), "%p", &rv);

		return rv;
	}
	else
	{
		return NULL;
	}
}

int SDPXS_RemoveDependency(void *dependent)
{
	/*
	 * This stores the supporter pointer as a string retrieved from the
	 * dependents hash:
	 */
	char *supporter_address;

	/* The length of the string: */
	STRLEN supporter_address_length;

	/* This stores the dependent pointer as a string: */
	char dependent_address[SDPXS_MAX_MACHINE_ADDRESS_SIZE] = "";

	/* The length of the string: */
	int dependent_address_length;

	SV *supporter;

	/*
	 * This stores a pointer to an SV pointer that contains a reference to
	 * the dependents array:
	 */
	SV **dependents_ref;

	/*
	 * This gets the array containing all of the dependents for this
	 * particular supporter from the sdpxs_active_dependents hash:
	 */
	HV *dependents;

	/*
	 * This stores a pointer to a pointer to an SV retrieved from the
	 * dependents hash:
	 */
	SV **dependent_object;

	int rv;



	/* Make sure the dependent actually depends on something first: */
	if (!SDPXS_IsDependent(dependent))
		return 0;



	/* Get stringified versions of each pointer: */
	snprintf(dependent_address, sizeof(dependent_address), "%p", dependent);
	dependent_address_length = strlen(dependent_address);
	supporter = hv_delete(
		sdpxs_dependencies,
		dependent_address,
		dependent_address_length,
		0
	);
	supporter_address = SvPV(supporter, supporter_address_length);



	/*
	 * Get the hash of depedents for this supporter from the depedents
	 * hash:
	 */
	dependents_ref = hv_fetch(
		sdpxs_active_dependents,
		supporter_address,
		supporter_address_length,
		0
	);
	dependents = (HV *) SvRV(*dependents_ref);

	/* Decrement the reference count for this dependent: */
	dependent_object = hv_fetch(
		dependents,
		dependent_address,
		dependent_address_length,
		0
	);
	sv_setiv(*dependent_object, SvIV(*dependent_object) - 1);

	/* Just delete the entry all together if the count dropped to zero: */
	if (SvIV(*dependent_object) <= 0)
	{
		hv_delete(
			dependents,
			dependent_address,
			dependent_address_length,
			0
		);
		SvREFCNT_dec(*dependent_object);
	}

	/*
	 * Get rid of the entire hash all together if there are no more
	 * dependents left:
	 */
	if (!HvKEYS(dependents))
	{
		void *supporter_object;

		hv_undef(dependents);
		hv_delete(
			sdpxs_active_dependents,
			supporter_address,
			supporter_address_length,
			0
		);
		SvREFCNT_dec(*dependents_ref);

		/*
		 * If all depedencies are gone and the supporter's cleanup was
		 * delayed, then tell the caller to cleanup it up:
		 */
		sscanf(supporter_address, "%p", &supporter_object);
	
		rv = SDPXS_IsCleanupPending(supporter_object) ? 1 : 0;
	}
	else
	{
		rv = 0;
	}



	SvREFCNT_dec(supporter);

	return rv;
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
		SDPXS_ParserGlue *parser_glue;
		SV *address;
	CODE:
	{
		parser = SDP_NewParser();
		if (parser == NULL)
			XSRETURN_UNDEF;

		parser_glue = (SDPXS_ParserGlue *) SDP_Allocate(
			sizeof(SDPXS_ParserGlue)
		);
		if (parser_glue == NULL)
		{
			SDP_DestroyParser(parser);
			XSRETURN_UNDEF;
		}

		SDP_SetUserData(parser, parser_glue);

		address = newSViv((int) parser);
		RETVAL  = newRV(address);
		sv_bless(RETVAL, gv_stashpv(CLASS, 1));

		parser_glue->parser = newSVsv(RETVAL);
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
		int is_stack_full = 0;
	PPCODE:
	{
		description = SDP_Parse(parser, string);

		/*
		 * Push as many description structs as we can on the stack, and
		 * just destroy the rest:
		 */
		while (description)
		{
			if (is_stack_full)
			{
				SDP_Description *description_to_destroy =
					description;

				description = SDP_GetNextDescription(
					description
				);

				SDP_DestroyDescription(
					description_to_destroy
				);
			}
			else
			{
				SV *sv;

				EXTEND(SP, 1);
				sv = sv_newmortal();
				sv_setref_pv(sv, CLASS, description);
				PUSHs(sv);

				if (GIMME == G_SCALAR)
					is_stack_full = 1;

				description = SDP_GetNextDescription(
					description
				);
			}
		}
	}



SV *
parse_file(parser, filename)
		SDP_Parser *   parser
		const char *   filename
	PREINIT:
		char CLASS[] = "Multimedia::SDP::Description";
		SDP_Description *description;
		int is_stack_full = 0;
	PPCODE:
	{
		description = SDP_ParseFile(parser, filename);

		/*
		 * Push as many description structs as we can on the stack, and
		 * just destroy the rest:
		 */
		while (description)
		{
			if (is_stack_full)
			{
				SDP_Description *description_to_destroy =
					description;

				description = SDP_GetNextDescription(
					description
				);

				SDP_DestroyDescription(
					description_to_destroy
				);
			}
			else
			{
				SV *sv;

				EXTEND(SP, 1);
				sv = sv_newmortal();
				sv_setref_pv(sv, CLASS, description);
				PUSHs(sv);

				if (GIMME == G_SCALAR)
					is_stack_full = 1;

				description = SDP_GetNextDescription(
					description
				);
			}
		}
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
		SDPXS_ParserGlue *parser_glue;
	CODE:
		parser_glue = (SDPXS_ParserGlue *) SDP_GetUserData(parser);
		parser_glue->halt_parsing = 1;



void
set_start_handler(parser, handler)
		SDP_Parser *   parser
		SV *           handler
	PREINIT:
		SDPXS_ParserGlue *parser_glue;
	CODE:
	{
		parser_glue = (SDPXS_ParserGlue *) SDP_GetUserData(parser);

		SDPXS_SET_SV(parser_glue->start_handler, handler);

		SDP_SetStartHandler(parser, SDPXS_InvokeStartHandler);
	}



void
set_start_description_handler(parser, handler)
		SDP_Parser *   parser
		SV *           handler
	PREINIT:
		SDPXS_ParserGlue *parser_glue;
	CODE:
	{
		parser_glue = (SDPXS_ParserGlue *) SDP_GetUserData(parser);

		SDPXS_SET_SV(parser_glue->start_description_handler, handler);

		SDP_SetStartDescriptionHandler(
			parser, SDPXS_InvokeStartDescriptionHandler
		);
	}



void
set_field_handler(parser, handler)
		SDP_Parser *   parser
		SV *           handler
	PREINIT:
		SDPXS_ParserGlue *parser_glue;
	CODE:
	{
		parser_glue = (SDPXS_ParserGlue *) SDP_GetUserData(parser);

		SDPXS_SET_SV(parser_glue->field_handler, handler);

		SDP_SetFieldHandler(parser, SDPXS_InvokeFieldHandler);
	}



void
set_end_description_handler(parser, handler)
		SDP_Parser *   parser
		SV *           handler
	PREINIT:
		SDPXS_ParserGlue *parser_glue;
	CODE:
	{
		parser_glue = (SDPXS_ParserGlue *) SDP_GetUserData(parser);

		SDPXS_SET_SV(parser_glue->end_description_handler, handler);

		SDP_SetEndDescriptionHandler(
			parser, SDPXS_InvokeEndDescriptionHandler
		);
	}



void
set_end_handler(parser, handler)
		SDP_Parser *   parser
		SV *           handler
	PREINIT:
		SDPXS_ParserGlue *parser_glue;
	CODE:
	{
		parser_glue = (SDPXS_ParserGlue *) SDP_GetUserData(parser);

		SDPXS_SET_SV(parser_glue->end_handler, handler);

		SDP_SetEndHandler(parser, SDPXS_InvokeEndHandler);
	}



void
set_user_data(parser, user_data)
		SDP_Parser *   parser
		void *         user_data
	PREINIT:
		SDPXS_ParserGlue *parser_glue;
	CODE:
		parser_glue = (SDPXS_ParserGlue *) SDP_GetUserData(parser);
		SDPXS_SET_SV(parser->user_data, user_data);



SV *
get_start_handler(parser)
		SDP_Parser *parser
	PREINIT:
		SDPXS_ParserGlue *parser_glue;
	CODE:
		parser_glue = (SDPXS_ParserGlue *) SDP_GetUserData(parser);
		RETVAL = SDPXS_GET_SV(parser_glue->start_handler);
	OUTPUT:
		RETVAL



SV *
get_start_description_handler(parser)
		SDP_Parser *parser
	PREINIT:
		SDPXS_ParserGlue *parser_glue;
	CODE:
		parser_glue = (SDPXS_ParserGlue *) SDP_GetUserData(parser);
		RETVAL = SDPXS_GET_SV(parser_glue->start_description_handler);
	OUTPUT:
		RETVAL



SV *
get_field_handler(parser)
		SDP_Parser *parser
	PREINIT:
		SDPXS_ParserGlue *parser_glue;
	CODE:
		parser_glue = (SDPXS_ParserGlue *) SDP_GetUserData(parser);
		RETVAL = SDPXS_GET_SV(parser_glue->field_handler);
	OUTPUT:
		RETVAL



SV *
get_end_description_handler(parser)
		SDP_Parser *parser
	PREINIT:
		SDPXS_ParserGlue *parser_glue;
	CODE:
		parser_glue = (SDPXS_ParserGlue *) SDP_GetUserData(parser);
		RETVAL = SDPXS_GET_SV(parser_glue->end_description_handler);
	OUTPUT:
		RETVAL



SV *
get_end_handler(parser)
		SDP_Parser *parser
	PREINIT:
		SDPXS_ParserGlue *parser_glue;
	CODE:
		parser_glue = (SDPXS_ParserGlue *) SDP_GetUserData(parser);
		RETVAL = SDPXS_GET_SV(parser_glue->end_handler);
	OUTPUT:
		RETVAL



SV *
get_user_data(parser)
		SDP_Parser *parser
	PREINIT:
		SDPXS_ParserGlue *parser_glue;
	CODE:
		parser_glue = (SDPXS_ParserGlue *) SDP_GetUserData(parser);
		RETVAL = SDPXS_GET_SV(parser_glue->user_data);
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



void DESTROY_parser(parser)
		SDP_Parser *parser
	CODE:
	{
		SDPXS_ParserGlue *parser_glue =
			(SDPXS_ParserGlue *) SDP_GetUserData(parser);

		SDPXS_DECREMENT_REFCOUNT(parser_glue->parser);

		SDPXS_DECREMENT_REFCOUNT(parser_glue->start_handler);
		SDPXS_DECREMENT_REFCOUNT(parser_glue->start_description_handler);
		SDPXS_DECREMENT_REFCOUNT(parser_glue->field_handler);
		SDPXS_DECREMENT_REFCOUNT(parser_glue->end_description_handler);
		SDPXS_DECREMENT_REFCOUNT(parser_glue->end_handler);

		SDPXS_DECREMENT_REFCOUNT(parser_glue->user_data);

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
		SDP_LinkedList zone_adjustments;
	CODE:
	{
		SDPXS_ARRAY_TO_LINKED_LIST(
			zone_adjustments, SDP_ZoneAdjustment, items - 1
		);

		RETVAL = SDP_GenFromZoneAdjustments(
			generator,
			(SDP_ZoneAdjustment *) SDP_GetListElements(
				zone_adjustments
			)
		);

		SDP_DESTROY_LIST(
			zone_adjustments,
			SDP_ZoneAdjustment,
			SDP_DestroyZoneAdjustment
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
DESTROY_generator(generator)
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
		SDPXS_AddDependency(description, email_contact);
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
		SDPXS_AddDependency(description, phone_contact);
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
		SDPXS_AddDependency(description, session_play_time);
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
		SDPXS_AddDependency(description, zone_adjustment);
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
		SDPXS_AddDependency(description, attribute);
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
		SDPXS_AddDependency(description, media_description);
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
		SDPXS_AddDependency(description, RETVAL);
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

		SDPXS_RETURN_LINKED_LIST_AS_ARRAY(
			email_contacts, description, CLASS
		);
	}



void
remove_email_contact(description, email_contact)
		SDP_Description *    description
		SDP_EmailContact *   email_contact
	CODE:
		SDPXS_RemoveDependency(email_contact);
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

		SDPXS_RETURN_LINKED_LIST_AS_ARRAY(
			phone_contacts, description, CLASS
		);
	}



void
remove_phone_contact(description, phone_contact)
		SDP_Description *    description
		SDP_PhoneContact *   phone_contact
	CODE:
		SDPXS_RemoveDependency(phone_contact);
		SDP_RemovePhoneContact(description, phone_contact);



SDP_Connection *
get_connection(description)
		SDP_Description *description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::Connection";
	CODE:
		RETVAL = SDP_GetConnection(description);
		SDPXS_AddDependency(description, RETVAL);
	OUTPUT:
		RETVAL



SDP_Bandwidth *
get_bandwidth(description)
		SDP_Description *description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::Bandwidth";
	CODE:
		RETVAL = SDP_GetBandwidth(description);
		SDPXS_AddDependency(description, RETVAL);
	OUTPUT:
		RETVAL



SV *
get_session_play_times(description)
		SDP_Description *description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::SessionPlayTime";
		SDP_SessionPlayTime *session_play_times;
	PPCODE:
	{
		session_play_times = SDP_GetSessionPlayTimes(description);

		SDPXS_RETURN_LINKED_LIST_AS_ARRAY(
			session_play_times, description, CLASS
		);
	}



void
remove_session_play_time(description, session_play_time)
		SDP_Description *       description
		SDP_SessionPlayTime *   session_play_time
	CODE:
		SDPXS_RemoveDependency(session_play_time);
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

		SDPXS_RETURN_LINKED_LIST_AS_ARRAY(
			zone_adjustment, description, CLASS
		);
	}



void
remove_zone_adjustment(description, zone_adjustment)
		SDP_Description *      description
		SDP_ZoneAdjustment *   zone_adjustment
	CODE:
		SDPXS_RemoveDependency(zone_adjustment);
		SDP_RemoveZoneAdjustment(description, zone_adjustment);



SDP_Encryption *
get_encryption(description)
		SDP_Description *description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::Encryption";
	CODE:
		RETVAL = SDP_GetEncryption(description);
		SDPXS_AddDependency(description, RETVAL);
	OUTPUT:
		RETVAL



SV *
get_attributes(description)
		SDP_Description *description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::Attribute";
		SDP_Attribute *attributes;
	PPCODE:
	{
		attributes = SDP_GetAttributes(description);

		SDPXS_RETURN_LINKED_LIST_AS_ARRAY(
			attributes, description, CLASS
		);
	}



void
remove_attribute(description, attribute)
		SDP_Description *   description
		SDP_Attribute *     attribute
	CODE:
		SDPXS_RemoveDependency(attribute);
		SDP_RemoveAttribute(description, attribute);



SV *
get_media_descriptions(description)
		SDP_Description *description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::MediaDescription";
		SDP_MediaDescription *media_descriptions;
	PPCODE:
	{
		media_descriptions = SDP_GetMediaDescriptions(description);

		SDPXS_RETURN_LINKED_LIST_AS_ARRAY(
			media_descriptions, description, CLASS
		);
	}



void
remove_media_description(description, media_description)
		SDP_Description *        description
		SDP_MediaDescription *   media_description
	CODE:
		SDPXS_RemoveDependency(media_description);
		SDP_RemoveMediaDescription(description, media_description);



char *
output_description_to_string(description)
		SDP_Description *description
	CODE:
		RETVAL = SDP_OutputDescriptionToString(description);
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



void
DESTROY_description(description)
		SDP_Description *description
	CODE:
	{
		if (SDPXS_HasDependents(description))
			SDPXS_RegisterForDelayedCleanup(description);
		else
			SDP_DestroyDescription(description);
	}







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
DESTROY_owner(owner)
		SDP_Owner *owner
	CODE:
	{
		if (SDPXS_IsDependent(owner))
		{
			SDP_Description *description;
			int description_needs_cleanup;

			description = (SDP_Description *) SDPXS_GetSupporter(
				owner
			);
			description_needs_cleanup = SDPXS_RemoveDependency(
				owner
			);

			if (description_needs_cleanup)
				SDP_DestroyDescription(description);
		}
		else
		{
			SDP_DestroyOwner(owner);
		}
	}







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



void
DESTROY_email_contact(email_contact)
		SDP_EmailContact *email_contact
	CODE:
	{
		if (SDPXS_IsDependent(email_contact))
		{
			SDP_Description *description;
			int description_needs_cleanup;

			description = (SDP_Description *) SDPXS_GetSupporter(
				email_contact
			);
			description_needs_cleanup = SDPXS_RemoveDependency(
				email_contact
			);

			if (description_needs_cleanup)
				SDP_DestroyDescription(description);
		}
		else
		{
			SDP_DestroyEmailContact(email_contact);
		}
	}







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



void
DESTROY_phone_contact(phone_contact)
		SDP_PhoneContact *phone_contact
	CODE:
	{
		if (SDPXS_IsDependent(phone_contact))
		{
			SDP_Description *description;
			int description_needs_cleanup;

			description = (SDP_Description *) SDPXS_GetSupporter(
				phone_contact
			);
			description_needs_cleanup = SDPXS_RemoveDependency(
				phone_contact
			);

			if (description_needs_cleanup)
				SDP_DestroyDescription(description);
		}
		else
		{
			SDP_DestroyPhoneContact(phone_contact);
		}
	}







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
DESTROY_connection(connection)
		SDP_Connection *connection
	CODE:
	{
		if (SDPXS_IsDependent(connection))
		{
			SDP_Description *description;
			int description_needs_cleanup;

			description = (SDP_Description *) SDPXS_GetSupporter(
				connection
			);		
			description_needs_cleanup = SDPXS_RemoveDependency(
				connection
			);

			if (description_needs_cleanup)
				SDP_DestroyDescription(description);
		}
		else
		{
			SDP_DestroyConnection(connection);
		}
	}







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
DESTROY_bandwidth(bandwidth)
		SDP_Bandwidth *bandwidth
	CODE:
	{
		if (SDPXS_IsDependent(bandwidth))
		{
			SDP_Description *description;
			int description_needs_cleanup;

			description = (SDP_Description *) SDPXS_GetSupporter(
				bandwidth
			);
			description_needs_cleanup = SDPXS_RemoveDependency(
				bandwidth
			);

			if (description_needs_cleanup)
				SDP_DestroyDescription(description);
		}
		else
		{
			SDP_DestroyBandwidth(bandwidth);
		}
	}







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
		SDPXS_AddDependency(session_play_time, repeat_time);
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

		SDPXS_COPY_ARRAY_FROM_STACK(
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
		SDP_RepeatTime *repeat_times;
	PPCODE:
	{
		repeat_times = SDP_GetRepeatTimes(session_play_time);

		SDPXS_RETURN_LINKED_LIST_AS_ARRAY(
			repeat_times, session_play_time, CLASS
		);
	}



void
remove_repeat_time(session_play_times, repeat_time)
		SDP_SessionPlayTime *   session_play_times
		SDP_RepeatTime *        repeat_time
	CODE:
		SDPXS_RemoveDependency(repeat_time);
		SDP_RemoveRepeatTime(session_play_times, repeat_time);



void
DESTROY_session_play_time(session_play_time)
		SDP_SessionPlayTime *session_play_time
	CODE:
	{
		if (SDPXS_IsDependent(session_play_time))
		{
			if (!SDPXS_HasDependents(session_play_time))
			{
				SDP_Description *description;
				int destroy_description;
				
				description =
					(SDP_Description *) SDPXS_GetSupporter(
						session_play_time
					);
				destroy_description = SDPXS_RemoveDependency(
					session_play_time
				);

				if (destroy_description)
					SDP_DestroyDescription(description);
			}
		}
		else
		{
			if (SDPXS_HasDependents(session_play_time))
				SDPXS_RegisterForDelayedCleanup(
					session_play_time
				);
			else
				SDP_DestroySessionPlayTime(session_play_time);
		}
	}







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

		SDPXS_COPY_ARRAY_FROM_STACK(
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



void
DESTROY_repeat_time(repeat_time)
		SDP_RepeatTime *repeat_time
	CODE:
	{
		if (SDPXS_IsDependent(repeat_time))
		{
			SDP_SessionPlayTime *session_play_time;
			int destroy_session_play_time;

			session_play_time =
				(SDP_SessionPlayTime *) SDPXS_GetSupporter(
					repeat_time
				);
			destroy_session_play_time = SDPXS_RemoveDependency(
				repeat_time
			);
			
			if (SDPXS_IsDependent(session_play_time))
			{
				SDP_Description *description;
				int destroy_description;

				description =
					(SDP_Description *) SDPXS_GetSupporter(
						session_play_time
					);
				destroy_description = SDPXS_RemoveDependency(
					session_play_time
				);
			
				if (destroy_description)
					SDP_DestroyDescription(description);
			}
			else
			{
				if (destroy_session_play_time)
					SDP_DestroySessionPlayTime(
						session_play_time
					);
			}
		}
		else
		{
			SDP_DestroyRepeatTime(repeat_time);
		}
	}







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



void
DESTROY_zone_adjustment(zone_adjustment)
		SDP_ZoneAdjustment *zone_adjustment
	CODE:
	{
		if (SDPXS_IsDependent(zone_adjustment))
		{
			SDP_Description *description;
			int destroy_description;

			description = (SDP_Description *) SDPXS_GetSupporter(
				zone_adjustment
			);
			destroy_description = SDPXS_RemoveDependency(
				zone_adjustment
			);

			if (destroy_description)
				SDP_DestroyDescription(description);
		}
		else
		{
			SDP_DestroyZoneAdjustment(zone_adjustment);
		}
	}







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
DESTROY_encryption(encryption)
		SDP_Encryption *encryption
	CODE:
	{
		if (SDPXS_IsDependent(encryption))
		{
			SDP_Description *description;
			int destroy_description;

			description = (SDP_Description *) SDPXS_GetSupporter(
				encryption
			);
			destroy_description = SDPXS_RemoveDependency(
				encryption
			);

			if (destroy_description)
				SDP_DestroyDescription(description);
		}
		else
		{
			SDP_DestroyEncryption(encryption);
		}
	}







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



void
DESTROY_attribute(attribute)
		SDP_Attribute *attribute
	CODE:
	{
		if (SDPXS_IsDependent(attribute))
		{
			SDP_Description *description;
			int destroy_description;

			description = (SDP_Description *) SDPXS_GetSupporter(
				attribute
			);
			destroy_description = SDPXS_RemoveDependency(
				attribute
			);

			if (destroy_description)
				SDP_DestroyDescription(description);
		}
		else
		{
			SDP_DestroyAttribute(attribute);
		}
	}







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
		RETVAL = SDP_SetMediaTransportProtocol(
			media_description, transport_protocol
		);
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
		RETVAL = SDP_SetMediaInformation(
			media_description, media_information
		);
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
		RETVAL = SDP_SetMediaConnection(
			media_description,
			network_type,
			address_type,
			address,
			ttl,
			total_addresses
		);
	OUTPUT:
		RETVAL



int
set_media_bandwidth(media_description, modifier, value)
		SDP_MediaDescription *   media_description
		const char *             modifier
		long                     value
	CODE:
		RETVAL = SDP_SetMediaBandwidth(
			media_description, modifier, value
		);
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
		SDPXS_AddDependency(media_description, attribute);
		SDP_AddMediaAttribute(media_description, attribute);



int
add_new_media_attribute(media_description, name, value)
		SDP_MediaDescription *   media_description
		const char *             name
		const char *             value
	CODE:
		RETVAL = SDP_AddNewMediaAttribute(
			media_description, name, value
		);
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
		char CLASS[] = "Multimedia::SDP::MediaConnection";
	CODE:
		RETVAL = SDP_GetMediaConnection(media_description);
		SDPXS_AddDependency(media_description, RETVAL);
	OUTPUT:
		RETVAL



SDP_Bandwidth *
get_media_bandwidth(media_description)
		SDP_MediaDescription *media_description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::MediaBandwidth";
	CODE:
		RETVAL = SDP_GetMediaBandwidth(media_description);
		SDPXS_AddDependency(media_description, RETVAL);
	OUTPUT:
		RETVAL



SDP_Encryption *
get_media_encryption(media_description)
		SDP_MediaDescription *media_description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::MediaEncryption";
	CODE:
		RETVAL = SDP_GetMediaEncryption(media_description);
		SDPXS_AddDependency(media_description, RETVAL);
	OUTPUT:
		RETVAL



SV *
get_media_attributes(media_description)
		SDP_MediaDescription *media_description
	PREINIT:
		char CLASS[] = "Multimedia::SDP::MediaAttribute";
		SDP_Attribute *attributes;
	PPCODE:
	{
		attributes = SDP_GetMediaAttributes(media_description);

		SDPXS_RETURN_LINKED_LIST_AS_ARRAY(
			attributes, media_description, CLASS
		);
	}



void
DESTROY_media_description(media_description)
		SDP_MediaDescription *media_description
	CODE:
	{
		if (SDPXS_IsDependent(media_description))
		{
			if (!SDPXS_HasDependents(media_description))
			{
				SDP_Description *description;
				int destroy_description;
				
				description =
					(SDP_Description *) SDPXS_GetSupporter(
						media_description
					);
				destroy_description = SDPXS_RemoveDependency(
					media_description
				);

				if (destroy_description)
					SDP_DestroyDescription(description);
			}
		}
		else
		{
			if (SDPXS_HasDependents(media_description))
				SDPXS_RegisterForDelayedCleanup(
					media_description
				);
			else
				SDP_DestroyMediaDescription(media_description);
		}
	}





################################################################################
#
# The DESTROY destructor methods for the Media wrapper classes. (These exist
# because Connection, Bandwidth, Encryption, Attribute objects need to know
# what type of object they belong to so they can destroy that object if need
# be. So we provide these classes with these DESTROY methods, and then just
# inherit from the *real* class using @INC in SinisterSdp.pm):
#
################################################################################

#define SDPXS_DESTROY_MEDIA(_object_, _destroy_function_)                      \
	do {                                                                   \
		if (SDPXS_IsDependent(_object_))                               \
		{                                                              \
			SDP_MediaDescription *media_description;               \
			int destroy_media_description;                         \
                                                                               \
			media_description =                                    \
				(SDP_MediaDescription *) SDPXS_GetSupporter(   \
					_object_                               \
				);                                             \
			destroy_media_description = SDPXS_RemoveDependency(    \
				_object_                                       \
			);                                                     \
			                                                       \
			if (SDPXS_IsDependent(media_description))              \
			{                                                      \
				SDP_Description *description;                  \
				int destroy_description;                       \
                                                                               \
				description =                                  \
					(SDP_Description*) SDPXS_GetSupporter( \
						media_description              \
					);                                     \
				destroy_description = SDPXS_RemoveDependency(  \
					media_description                      \
				);                                             \
			                                                       \
				if (destroy_description)                       \
					SDP_DestroyDescription(description);   \
			}                                                      \
			else                                                   \
			{                                                      \
				if (destroy_media_description)                 \
					SDP_DestroyMediaDescription(           \
						media_description              \
					);                                     \
			}                                                      \
		}                                                              \
		else                                                           \
		{                                                              \
			_destroy_function_(_object_);                          \
		}                                                              \
	} while (0)

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::MediaBandwidth

void
DESTROY_media_bandwidth(bandwidth)
		SDP_Bandwidth *bandwidth
	CODE:
	{
		SDPXS_DESTROY_MEDIA(bandwidth, SDP_DestroyBandwidth);
	}

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::MediaConnection

void
DESTROY_media_connection(connection)
		SDP_Connection *connection
	CODE:
	{
		SDPXS_DESTROY_MEDIA(connection, SDP_DestroyConnection);
	}

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::MediaEncryption

void
DESTROY_media_encryption(encryption)
		SDP_Encryption *encryption
	CODE:
	{
		SDPXS_DESTROY_MEDIA(encryption, SDP_DestroyEncryption);
	}

MODULE = Multimedia::SDP::SinisterSdp	PACKAGE = Multimedia::SDP::MediaAttribute

void
DESTROY_media_attribute(attribute)
		SDP_Attribute *attribute
	CODE:
	{
		SDPXS_DESTROY_MEDIA(attribute, SDP_DestroyAttribute);
	}







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
		SDPXS_SET_SV(sdpxs_fatal_error_handler, handler);
		SDP_SetFatalErrorHandler(SDPXS_InvokeFatalErrorHandler);



void
set_non_fatal_error_handler(handler)
		SV *handler
	CODE:
		SDPXS_SET_SV(sdpxs_non_fatal_error_handler, handler);
		SDP_SetNonFatalErrorHandler(SDPXS_InvokeNonFatalErrorHandler);



# the end.
