#  Package to assist using CVS with Makefile.PL
#
package ExtUtils::CVS;


#  External Packages
#
use IO::File;
use IO::Dir;
use File::Spec;
use ExtUtils::Manifest;
use Data::Dumper;
use Date::Parse qw(str2time);
use File::Find qw(find);
use Cwd qw(cwd);
use CPAN;


#  Compiler Pragma
#
use strict  qw(vars);
use vars    qw($VERSION $REVISION $PACKAGE);


#  Version information in a formate suitable for CPAN etc. Must be
#  all on one line
#
$VERSION = eval { require ExtUtils::CVS::VERSION; do $INC{'ExtUtils/CVS/VERSION.pm'}};


#  Revision information, auto maintained by CVS
#
$REVISION=(qw$Revision: 1.14 $)[1];


#  Package info
#
$PACKAGE=__PACKAGE__;


#  Load up our config file
#
my $Config_hr=$PACKAGE->config_read();


#  Vars to hold chained soubroutines, if needed (loaded by import). Must be
#  global (our) vars.
#
our ($Const_config_chain_sr, $Dist_ci_chain_sr);


#  All done, init finished
#
1;


#------------------------------------------------------------------------------


#  Manage activation of const_config and dist_ci targets
#
sub import {


    #  Get params
    #
    my ($self, @param)=@_;


    #  Sub ref for params
    #
    my $const_config_sr=sub {

	$Const_config_chain_sr=UNIVERSAL::can('MY', 'const_config');
	*MY::const_config=sub { &const_config(@_) };
	0 && MY::const_config();

    };
    my $dist_ci_sr=sub {

	$Dist_ci_chain_sr=UNIVERSAL::can('MY', 'dist_ci');
	*MY::dist_ci=sub { &dist_ci(@_) };
	0 && MY::dist_ci();

    };


    #  Put into hash
    #
    my %param=(

	const_config	=>  $const_config_sr,
	dist_ci		=>  $dist_ci_sr,
	':all'		=>  sub { $const_config_sr->(); $dist_ci_sr->() }

       );


    #  Run appropriate
    #
    foreach my $param (@param) {
	$param{$param} && ($param{$param}->());
    }


    #  Done
    #
    return \undef;

}



#  Read in config file
#
sub config_read {


    #  Get our dir
    #
    my @config_dn;
    ($config_dn[0]=$INC{'ExtUtils/CVS.pm'})=~s/\.pm$//;


    #  Unless absolute, add cwd
    #
    unless ($config_dn[0]=~/^\//) { unshift @config_dn, cwd() }


    #  And now file name
    #
    my $config_fn=File::Spec->catfile(@config_dn, 'Config.pm');


    #  Read and return
    #
    my $config_hr=do($config_fn) || die $!;


    #  Read any local config file. Only present for local customisation
    #
    my $local_hr=eval { do { File::Spec->catfile(@config_dn, 'Local.pm') } };


    #  Local overrides global
    #
    map { $config_hr->{$_}=$local_hr->{$_} } keys %{$local_hr};


    #  Return
    #
    return $config_hr;


}



#  Replacement const_config section
#
sub const_config {


    #  Change packages so SUPER works OK
    #
    package MY;


    #  Get self ref
    #
    my $self=shift();


    #  Update macros with our config
    #
    map { $self->{'macro'}{$_}=$Config_hr->{$_} } keys %{$Config_hr};


    #  Return whatever our parent does
    #
    return $Const_config_chain_sr->($self);


}


#  Update ci section to include an "import" function
#
sub dist_ci {


    #  Change package
    #
    package MY;


    #  Get self ref
    #
    my $self=shift();


    #  Found it, open our patch file. Get dir first
    #
    (my $patch_dn=$INC{'ExtUtils/CVS.pm'})=~s/\.pm$//;


    #  And now file name
    #
    my $patch_fn=File::Spec->catfile($patch_dn, 'dist_ci.inc');


    #  Open it
    #
    my $patch_fh=IO::File->new($patch_fn, &ExtUtils::CVS::O_RDONLY) ||
	die("unable to open $patch_fn, $!");


    #  Add in. We are replacing dist_ci entirely, so do not
    #  worry about chaining.
    #
    my  @dist_ci = map { chomp; $_ } <$patch_fh>;


    #  Close
    #
    $patch_fh->close();


    #  All done, return result
    #
    return join("\n", @dist_ci);

}


sub ci_status {


    #  Checks that all files in the manifest are up to date with respect to
    #  CVS/Entries file
    #
    my ($self, $version_fn)=@_;
    my $method=(split(/:/, (caller(0))[3]))[-1];


    #  Stat the master version file
    #
    my $version_fn_mtime=(stat($version_fn))[9] ||
	die("$method: unable to stat file $version_fn, $!");


    #  Get the manifest
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();


    #  Ignore the ChangeLog file
    #
    #delete $manifest_hr->{'ChangeLog'};


    #  Work out all the directory names
    #
    my %manifest_dn;
    foreach my $manifest_fn (keys %{$manifest_hr}) {


	#  Get directory name
	#
	my $manifest_dn=(File::Spec->splitpath($manifest_fn))[1];
	$manifest_dn{$manifest_dn}++;


    }
    #print Data::Dumper::Dumper(\%manifest_dn);


    #  Now go through, looking at files
    #
    foreach my $manifest_dn (sort { $a cmp $b } keys %manifest_dn) {


	#  Get Entries FN
	#
	my @manifest_dn=File::Spec->splitdir($manifest_dn);
	my $entries_fn=File::Spec->catfile(@manifest_dn, 'CVS', 'Entries');
	#print "Entries file $entries_fn\n";


	#  Only open if exists
	#
	(-f $entries_fn) || next;


	#  Open
	#
	my $entries_fh=IO::File->new($entries_fn, O_RDONLY) ||
	    die("unable to open $entries_fn, $!");



	#  Go through
	#
	my @entry=sort { $a cmp $b } <$entries_fh>;
	#while (my $entry=<$entries_fh>) {
	while (my $entry=pop @entry) {


	    #  Split, skip unless file we want
	    #
	    my (undef, $fn, $version, $date)=split(/\//, $entry);


	    #  Add cd to fn
	    #
	    my $entry_fn=File::Spec->catfile(@manifest_dn, $fn);


	    #  Skip unless manifest file
	    #
	    #print "looking at file $entry_fn\n";
	    exists($manifest_hr->{$entry_fn}) || next;
	    #print "found $fn in manifest\n";


	    #  Convert date to GMT
	    #
	    my $commit_time=str2time($date, 'GMT');


	    #  Stat file
	    #
	    my $mtime_fn=(stat($entry_fn))[9] ||
		die("$method: unable to stat file $entry_fn, $!");
	    #print "mtime_fn $mtime_fn commit_time $commit_time, vtime $version_fn_mtime\n";


	    #  Compare
	    #
	    ($mtime_fn > $commit_time) && do {

	    	#print "mtime > commit\n";


		#  Give it one more chance
		#
		$mtime_fn=$self->ci_mtime_sync($entry_fn) ||
		    $mtime_fn;
		($mtime_fn > $commit_time) &&
		    die("$method: $entry_fn has mtime $mtime_fn greater commit time $commit_time, ".
			    "cvs commit may be required.\n");


	    };


	    #  Check against version
	    #
	    ($mtime_fn > $version_fn_mtime) && do {

	    	#print "mtime > version_mtime\n";

		#  Give it one more chance
		#
		$mtime_fn=$self->ci_mtime_sync($entry_fn) ||
		    $mtime_fn;
		($mtime_fn > $version_fn_mtime) &&
		    die("$method: $fn has mtime greater than $version_fn, cvs commit may be required.\n");

	    };

	}


	$entries_fh->close();

    }


    #  All looks OK
    #
    print "$method: all files up-to-date\n";


    #  All OK
    #
    return \undef;


}


sub ci_status_bundle {


    #  Checks that all files in the manifest are up to date with respect to
    #  CVS/Entries file
    #
    my ($self, $version_fn)=@_;
    my $method=(split(/:/, (caller(0))[3]))[-1];


    #  Stat the master version file
    #
    my $version_fn_mtime=(stat($version_fn))[9] ||
	die("$method: unable to stat file $version_fn, $!");


    #  Get cwd
    #
    my $cwd=cwd();


    #  Find all the CVS/Entries files
    #
    my @entries;
    my $wanted_cr=sub {


	#  Is this a CVS entries file ? If so, add to hash
	#
	($File::Find::name=~/CVS\/Entries$/) &&
	    push @entries, $File::Find::name;


    };
    find($wanted_cr, $cwd);
    #print Dumper(\@entries);


    # Go through each Entries file, build up our own manifest
    #
    foreach my $entries_fn (@entries) {


	#  Work out complete path
	#
	my $entries_dn=(File::Spec->splitpath($entries_fn))[1];
	my @entries_dn=File::Spec->splitdir($entries_dn);
	#print Dumper(\@entries_dn);


	#  Check that this is in the module we are interested
	#  Get rid of 'CVS'
	#
	until ( pop @entries_dn ) {}


	#  Open
	#
	my $entries_fh=IO::File->new($entries_fn, O_RDONLY) ||
	    die("$method: unable to open file $entries_fn, $!");


	#  Parse
	#
	my @entry=sort { $a cmp $b } <$entries_fh>;
	#foreach my $entry (<$entries_fh>) {
	while (my $entry=pop @entry) {


	    #  Split, skip non plain files
	    #
	    my ($fn_type, $fn, $version, $date)=split(/\//, $entry);
	    $fn_type && next;


	    #  Rebuild
	    #
	    my $entry_fn=File::Spec->catfile(
		@entries_dn,
		$fn
	       );


	    #  Get mtime
	    #
	    my $mtime_fn=(stat($entry_fn))[9];


	    #  Check against version
	    #
	    ($mtime_fn > $version_fn_mtime) && do {


		#  Give it one more chance
		#
		$mtime_fn=$self->ci_mtime_sync($entry_fn) ||
		    $mtime_fn;
		($mtime_fn > $version_fn_mtime) &&
		    die("$method: $fn has mtime greater than $version_fn, cvs commit may be required.\n");

	    };


	    #  Convert date to GMT
	    #
	    my $commit_time=str2time($date, 'GMT');


	    #  Compare
	    #
	    ($mtime_fn > $commit_time) && do {

		$mtime_fn=$self->ci_mtime_sync($entry_fn) ||
		    $mtime_fn;
		($mtime_fn > $commit_time) &&
		    die("$method: $entry_fn has mtime greater commit time, cvs commit may be required.\n");

	    };
	}
    }


    #  All looks OK
    #
    print "$method: all files up-to-date\n";


    #  All OK
    #
    return \undef;


}


sub ci_manicheck {


    #  Checks that all files in the manifest are checked in to cvs
    #
    my ($self, $module)=@_;
    my $method=(split(/:/, (caller(0))[3]))[-1];


    #  Get cwd
    #
    my $cwd=cwd();


    #  Get the manifest
    #
    ExtUtils::Manifest::manicheck() && die('MANIFEST manicheck error');
    my $manifest_hr=ExtUtils::Manifest::maniread();
    my %manifest;


    #  Find all the CVS/Entries files
    #
    my @entries;
    my $wanted_cr=sub {


	#  Skip if not at least a directory in our manifest
	#
	#my $dn=$File::Find::dir;
	#$dn=~s/^\Q$cwd\E\/?//;

	#  Is this a CVS entries file ? If so, add to hash
	#
	($File::Find::name=~/CVS\/Entries$/) &&
	    push @entries, $File::Find::name;


    };
    find($wanted_cr, $cwd);


    # Go through each Entries file, build up our own manifest
    #
    foreach my $entries_fn (@entries) {


	#  Work out complete path
	#
	my $entries_dn=(File::Spec->splitpath($entries_fn))[1];
	my @entries_dn=File::Spec->splitdir($entries_dn);
	#print Dumper(\@entries_dn);


	#  Check that this is in the module we are interested
	#  in, start by opening CVS/Repository file
	#
	my $repository_fn=File::Spec->catfile(@entries_dn, 'Repository');
	my $repository_fh=IO::File->new($repository_fn, O_RDONLY) ||
	    die("$method: unable to open file $repository_fn, $!");
	my $repository_dn=<$repository_fh>; chomp($repository_dn);


	#  Get top level
	#
	my $repository=(File::Spec->splitdir($repository_dn))[0];
	#print "repository $repository, module $module\n";
	next unless ($repository eq $module);


	#  Get rid of empty directories
	#
	until ( pop @entries_dn ) {}


	#  Open
	#
	my $entries_fh=IO::File->new($entries_fn, O_RDONLY) ||
	    die("$method: unable to open file $entries_fn, $!");


	#  Parse
	#
	foreach my $entry (<$entries_fh>) {


	    #  Split, skip non plain files
	    #
	    my ($fn_type, $fn, $version, $date)=split(/\//, $entry);
	    $fn_type && next;


	    #  Rebuild
	    #
	    my $manifest_fn=File::Spec->catfile(
		@entries_dn,
		$fn
	       );


	    #  Get rid of cwd
	    #
	    $manifest_fn=~s/^\Q$cwd\E\/?//;


	    #  Add to manifest
	    #
	    $manifest{$manifest_fn}++;

	}
    }


    #  Check for files in CVS, but not in the manifest, or vica versa
    #
    my $fail;
    my %test0=%{$manifest_hr};
    map { delete $test0{$_} } keys %manifest;
    if (keys %test0) {
	printf("$method: the following files are in the manifest, but not in CVS: \n\n%s\n\n",
	       join("\n", keys %test0));
	$fail++;
    }
    my %test1=%manifest;
    map { delete $test1{$_} } keys %{$manifest_hr};
    if (keys %test1) {
	printf("$method: the following files are in CVS, but not in the manifest: \n\n%s\n\n",
	       join("\n", keys %test1));
	$fail++;
    }


    #  Now look for a patch dir
    #
    if (-d (my $dn=File::Spec->catdir($cwd, 'patch'))) {


	#  Yes, must check files in that dir also. Process dir to get just file entries.
	#
	tie (my %fn_raw, 'IO::Dir', $dn) ||
	    die("unable to tie IO::Dir to $dn, $!");
	my %fn=%fn_raw;
	map { delete $fn{$_} unless (-f File::Spec->catfile($cwd,'patch',$_)) } keys %fn;


	#  Now test for files in patch dir. not in manifest
	#
	my %test0=%fn;
	map { delete $test0{(File::Spec->splitpath($_))[2]}} keys %{$manifest_hr};
	if (keys %test0) {
	    printf("$method: the following files are in the patch dir, but not in the manifest: \n\n%s\n\n",
		   join("\n", keys %test0));
	    $fail++;
	}


	#  And files in patch dir, not in CVS
	#
	my %test1=%fn;
	map { delete $test1{(File::Spec->splitpath($_))[2]}} keys %manifest;
	if (keys %test1) {
	    printf("$method: the following files are in the patch dir, but not in the CVS: \n\n%s\n\n",
		   join("\n", keys %test1));
	    $fail++;
	}

    }


    #  Die if there was an error, otherwise print OK text
    #
    if ($fail) {
	my $yesno=ExtUtils::MakeMaker::prompt(
	    'Do you wish to continue [yes|no] ?','yes');
	if ($yesno=~/^n|no$/i) {
	    die("$method: bundle build aborted by user !")
	}
    }
    else {
	print "$method: manifest and cvs in sync\n";
    }


    #  All done
    #
    return \undef;

}


sub ci_mtime_sync {


    #  Last resort to ensure file mtime is correct based on what CVS thinks
    #
    my ($self, $fn)=@_;
    my $method=(split(/:/, (caller(0))[3]))[-1];
    #print "$method:fn $sync_fn\n";


    #  Turn abs filenames into relative, cvs does not seem to like it
    #
    $fn=File::Spec->abs2rel($fn);


    #  Get cvs binary name
    #
    my $bin_cvs=$Config_hr->{'CVS'} ||
        die('unable to determine cvs binary name');


    #  Run cvs status on file, suck into array
    #
    my $system_fh=IO::File->new("$bin_cvs status $fn|") ||
        die("unable to get handle for cvs status command");
    my @system=<$system_fh>;
    $system_fh->close();


    #  Look for uptodate flag
    #
    my $uptodate;
    for (@system) {
	/Status:\s+Up-to-date/i && do { $uptodate++; last } };


    #  And var to hold mtime
    #
    my $mtime=(stat($fn))[9] ||
	die("unable to stat file $fn, $!");


    #  If uptodate, we need to sync mtime with CVS mtime
    #
    if ($uptodate) {


	#  Get working rev
	#
	my $ver_working;
	for (@system) {
	    /Working revision:\s+(\S+)/ && do { $ver_working=$1; last } };
	#print "u2d $uptodate, ver $ver_working\n";


	#  Looks OK, search for date
	#
	my $system_fh=IO::File->new("$bin_cvs log $fn|") ||
	    die("unable to get handle for cvs log command");
	my @system=<$system_fh>;
	$system_fh->close();
	#print Data::Dumper::Dumper(\@system);


	#  Get line with date date
	#
	my $line_date;
	for (0.. $#system) {
	    $system[$_]=~/revision\s+\Q$ver_working\E\s+/ &&
		do { $line_date=$system[++$_]; last };
	};


	#  Parse it out
	#
	if ($line_date && $line_date=~/^date:\s+(\S+)\s+(\S+)\;/) {

	    $mtime=str2time("$1 $2", 'GMT') ||
		die("unable to parse date string $1 $2");


	    #  As note. Probably no need to touch, just get mtime, as cvs status will
	    #  bring have brough back into line
	    #

	    #  Touch it
	    #
	    #  remomber to 'use File::Touch' if re-instating this code
	    #my $touch_or=File::Touch->new(

		#'time'	=>  $mtime,

	       #);
	    #$touch_or->touch($fn) ||
		#die("error on touch of file $fn, $!");
	    printf("$method: synced file $fn to cvs mtime $mtime (%s)\n",
		   scalar(localtime($mtime)));

	}

    }


    #  return the mtime
    #
    return $mtime;


}



sub ci_version_dump {


    #  Get self ref
    #
    my ($self, $name, $version_fn)=@_;


    #  Get version we are saving
    #
    my $have_version_fn=File::Spec->catfile(cwd(), $version_fn);
    my $have_version=do($have_version_fn);


    #  Get location of Dumper file, load up module, version info
    #  that we are processing, save again
    #
    my $dump_fn=File::Spec->catfile(cwd(), 'Dumper.pm');
	#$ExtUtils::Bundle::FILE_CPAN_DUMPER);
    my $dump_hr=do ($dump_fn) || {};


    #  Check if we need not update
    #
    my $dump_version=$dump_hr->{$name};
    if (CPAN::Version->vcmp($dump_version, $have_version)) {

	$dump_hr->{$name}=$have_version;
	#print "Bundle:; UPDATING DUMPER FILE, hv $have_version, dv $dump_version\n";
	my $dump_fh=IO::File->new($dump_fn, O_WRONLY|O_TRUNC|O_CREAT) ||
	    die ("unable to open file $dump_fn, $!");
	$Data::Dumper::Indent=1;
	print $dump_fh (Data::Dumper->Dump([$dump_hr],[]));
	$dump_fh->close();


    }

    return \undef;

}


sub repository {


    #  Modify repository
    #
    my ($self, $repository)=@_;
    $Config_hr->{'CVSROOT'}=$repository;
    return \$repository;


}


