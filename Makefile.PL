#!/usr/bin/perl -w
use strict;
use Config;
use ExtUtils::MakeMaker;
use File::Basename;
use File::Spec::Functions;
use Getopt::Long;
use Text::Wrap;
use Text::ParseWords;

# the version of the C library we need:
use constant SINISTERSDP_VERSION_REQUIRED => 0.70;



# some default MakeMaker parameters:
my %makefile_options = (
	NAME         => 'Multimedia::SDP::SinisterSdp',
	VERSION_FROM => 'SinisterSdp.pm',
);

if ($] >= 5.005)
{
	$makefile_options{ABSTRACT_FROM} = 'SinisterSdp.pm',
	$makefile_options{AUTHOR}        =
		'William g. David <william_g_davis@users.sourceforge.net>';
}



# make sure the user has the SinisterSdp C library installed, and try to
# install it for them if they don't:
unless (UserHasUpToDateSinisterSdp())
{
	my $answer = AskUser(
		"You don't have SinisterSdp installed, or your version of " .
		"it isn't up to date. That's the C library I need to link " .
		"to. If you don't want to go to " .
		"http://sourceforge.net/projects/sinistersdp and download a " .
		"copy, I can try and download and install it for you. Would " .
		"you like that? Yes or no?",
		'yes'
	);
	Quit('Install it on your own and try again.') unless IsYes($answer);

	# first, lets try to use Net::FTP if it's installed:
	eval {
		require Net::FTP;
		Net::FTP->import;
	};

	if ($@)
	{
		$answer = AskUser(
			"You don't have Net::FTP installed. I need that " .
			"to download the requisite files. Should I try to " .
			"install Net::FTP from CPAN for you, and then go " .
			"and use that to install SinisterSdp? Yes or no?",
			'yes'
		);
		Quit('Install Net::FTP from www.cpan.org and try again.')
			unless IsYes($answer);

		# install it:
		InstallModule('Net::FTP')
			or Quit("Couldn't install module Net::FTP: $!\n");
		PromptUser('Installed module Net::FTP.');

		# ok, try it again:
		eval {
			require Net::FTP;
			Net::FTP->import;
		};
		Quit(
			"OK, I tried to install Net::FTP, and it " .
			"seemed to work, but just now when I tried " .
			"to require it, it didn't work. Check to " .
			"make sure Net::FTP is installed, and if it " .
			"isn't, install it manually yourself, then " .
			"try again."
		) if $@;
	}



	# now that we've got Net::FTP loaded and ready, connect to an FTP
	# mirror to download a release:
	PromptUser('Connecting to FTP server in passive mode...');
	my $ftp = new Net::FTP ('public.planetmirror.com', Passive => 1)
		or Quit("Couldn't connect to FTP server: $@");

	# login anonymously:
	PromptUser('Logging into FTP server...');
	$ftp->login('anonymous', '')
		or Quit("Couldn't login to FTP server anonymously: $@");

	# make our way to the SinisterSdp directory
	PromptUser('Getting to the SinisterSdp directory...');
	$ftp->cwd('/pub/sf/s/si/sinistersdp/')
		or Quit(
			"Couldn't change the current working directory on " .
			"the FTP server: $@"
		);

	# get the file releases
	PromptUser('Getting list of file releases...');
	my @releases = $ftp->dir
		or Quit("Couldn't get the file list from the FTP server: $@");

	# clear out abnormal, test, etc. releases that don't share the standard
	# "Name-v.sn" format (where "v" is the major version number and "sn" is
	# the minor version number):
	@releases = grep {/SinisterSdp-\d\.\d{2}\.tar\.gz/} @releases;

	# now sort through them for the newest stable one:
	my $file_to_download;
	my $version_to_download = 0;
	foreach my $release (@releases)
	{
		my ($file, $version) =
			$release =~ /(SinisterSdp-(\d\.\d{2})\.tar\.gz)/;

		if ($version > $version_to_download)
		{
			$file_to_download    = $file;
			$version_to_download = $version;
		}
	}

	# download the release:
	PromptUser(
		"Downloading SinisterSdp version $version_to_download " .
		"($file_to_download)..."
	);
	$ftp->get($file_to_download, $file_to_download)
		or Quit("Couldn't download $file_to_download: $@");

	PromptUser("Download complete.\n");

	$ftp->quit;



	# now decompress the *.tar.gz file:
	my $decompress = AskUser(
		'What command should I use to decompress the *.tar.gz file?',
		'gzip -d'
	);
	my $rc = system("$decompress $file_to_download");
	Quit("Couldn't decompress file: $!") if ($rc != 0);

	# get into the ./src dir to run the Makefile:
	chdir(catfile('.', "SinisterSdp-$version_to_download", 'src'));

	my $make = AskUser(
		'What command should I use for "make" to make the Makfile?',
		$Config{'make'}
	);

	my $special_lib_directory = AskUser(
		'Any place special you want the compiled library to go to?'
	);
	my $special_inc_directory = AskUser(
		'Any place special you want the header files to go to?'
	);

	# $ make
	my $make_command  = $make;
	   $make_command .= " LIBRARY_DESTINATION=$special_lib_directory"
		if ($special_lib_directory);
	   $make_command .= " HEADER_DESTINATION=$special_inc_directory"
		if ($special_inc_directory);
	$rc = system($make_command);
	Quit("Couldn't run \"$make\" on the SinisterSdp Makefile: $!") if $rc;

	# $ make install:
	$rc = system("$make install");
	Quit("Couldn't run \"$make install\" on the SinisterSdp Makefile: $!")
		if ($rc != 0);

	# $ make clean:
	$rc = system("$make clean");
	Quit("Couldn't run \"$make clean\" on the SinisterSdp Makefile: $!")
		if ($rc != 0);



	# go back:
	chdir(catfile('..', '..'));



	# check for the library again, which we just installed:
	UserHasUpToDateSinisterSdp() or Quit("Couldn't find library. Sorry.");
}



WriteMakefile(%makefile_options);







sub PromptUser
{
	print(wrap('', '', shift), "\n") if InInteractiveMode();
}





sub AskUser
{
	my ($question, $default) = @_;

	my $answer;
	if (InInteractiveMode())
	{
		$question .= " [$default]" if (defined $default);
		PromptUser($question);
		chomp($answer = <STDIN>);
	}

	$answer = $default unless (defined $answer and length $answer);

	return $answer;
}





sub InInteractiveMode { return 1 if (-t STDIN and -t STDOUT) }





sub IsYes { return 1 if (shift =~ /^y/i) }





sub UserHasUpToDateSinisterSdp
{
	my ($sinistersdp_lib_path, $sinistersdp_inc_path);



	# just get the ones we want, and leave the rest in @ARGV for MakeMaker:
	Getopt::Long::Configure('pass_through');
	GetOptions(
		SINISTERSDP_LIB_PATH => \$sinistersdp_lib_path,
		SINISTERSDP_INC_PATH => \$sinistersdp_inc_path
	);

	# If the user didn't specify a place to look for the library, then
	# we can use ExtUtils::Liblist to look for us:
	if (not $sinistersdp_lib_path and $] >= 5.006001)
	{
		require ExtUtils::Liblist;
		ExtUtils::Liblist->import;

		# XXX This doesn't work? At all?
		#($sinistersdp_lib_path) =
		#	ExtUtils::Liblist->ext('-lsinistersdp');
	}

	# just use the settings from Config.pm if nothing else (not a typo;
	# the library path setting in Config.pm is "libpth" and the include
	# path is "incpath"):
	$sinistersdp_lib_path = $Config{libpth} unless $sinistersdp_lib_path;
	$sinistersdp_inc_path = $Config{incpath} unless $sinistersdp_inc_path;

	# escape backslashes for Windows and VMS... Pain in the ass, but
	# parse_line() needs this:
	$sinistersdp_lib_path =~ s/\\/\\\\/g;
	$sinistersdp_inc_path =~ s/\\/\\\\/g;

	# search for a library:
	my @libraries_found;
	foreach my $path (parse_line('\s+', 0, $sinistersdp_lib_path))
	{
		push(@libraries_found, glob catfile($path, '*sinistersdp*'));
	}

	# search for a header:
	my @headers_found;
	foreach my $path (parse_line('\s+', 0, $sinistersdp_inc_path))
	{
		push(@headers_found, catfile($path, 'SinisterSdp.h'))
			if (-e catfile($path, 'SinisterSdp.h'));
	}

	my $library = shift @libraries_found;
	my $header  = shift @headers_found;
	return unless ($library and $header);


	# now go extract the library version number from the SinisterSdp.h
	# header:
	open(HEADER, $header) or Quit("Couldn't open $header file: $!");
	my $version;
	while (my $line = <HEADER>)
	{
		if ($line =~ /#define\s+SDP_SINISTERSDP_VERSION\s+"([\d\.]+)"/)
		{
			$version = $1;
			last;
		}
	}
	close HEADER;

	Quit(
		"Couldn't extract version info from SinisterSdp.h. " .
		"There's something wrong with it. Sorry."
	) unless $version;

	# make sure the library version is up-to-date:
	return unless ($version >= SINISTERSDP_VERSION_REQUIRED);

	# break up the library path and set the LIBS makefile option:
	my ($lib_base, $lib_path, $lib_extension) = fileparse($library, '\..*');
	$makefile_options{LIBS} = "-L$lib_path -l$lib_base";

	return 1;
}





sub InstallModule
{
	my $module = shift;

	PromptUser("Installing $module...");

	# ActivePerl has its own little installation tool called ppm that users
	# are expected to use instead of CPAN.pm:
	my $rc;
	if (RunningActivePerl())
	{
		$rc = system "ppm install $module";
	}
	else
	{
		$rc = system qq|perl -MCPAN -e 'install "$module"'|;
	}

	return ($rc == 0) ? 1 : 0;
}





sub RunningActivePerl
{
	my $perl_version = `perl -v`;

	return 1 if ($perl_version =~ /ActiveState/i
			or $perl_version =~ /ActivePerl/i);
}





sub Quit
{
	my $error_message  = '';
	   $error_message .= shift(@_) . "\n" if @_;
	   $error_message .= "Quitting... Bye!\n";

	die $error_message;
}
