#
#
#  Copyright (c) 2003 Andrew W. Speer <andrew.speer@isolutions.com.au>. All rights 
#  reserved.
#
#  This file is part of ExtUtils::CVS.
#
#  ExtUtils::CVS is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#
#  $Id: CVS.pm,v 1.32 2004/06/08 01:35:07 aspeer Exp $
#


#  Augment Perl ExtUtils::MakeMaker cvs functions
#
package ExtUtils::CVS;


#  Compiler Pragma
#
sub BEGIN   { $^W=0 };
use strict  qw(vars);
use vars    qw($VERSION $REVISION $PACKAGE);
use warnings;
no  warnings qw(uninitialized);


#  External Packages
#
use IO::File;
use IO::Dir;
use File::Spec;
use Tie::IxHash;
use ExtUtils::Manifest;
use Data::Dumper;
use Date::Parse qw(str2time);
use File::Find qw(find);
use File::Touch;
use Cwd qw(cwd);
use CPAN;
use Carp;


#  Version information in a formate suitable for CPAN etc. Must be
#  all on one line
#
$VERSION = eval { require ExtUtils::CVS::VERSION; do $INC{'ExtUtils/CVS/VERSION.pm'}};


#  Revision information, auto maintained by CVS
#
$REVISION=(qw$Revision: 1.32 $)[1];


#  Load up our config file
#
our $Config_hr;


#  Vars to hold chained soubroutines, if needed (loaded by import). Must be
#  global (our) vars. Also need to remember import param
#
our ($Const_config_chain_cr, $Dist_ci_chain_cr, $Makefile_chain_cr);


#  Intercepts method arguments, holds some info across method calls to be used
#  my message routines
#
my %Arg;


#  All done, init finished
#
1;


#===================================================================================================


#  Manage activation of const_config and dist_ci targets via import tags. Import tags are
#
#  use ExtUtils::CVS qw(const_config) to just replace the macros section of the Makefile
#  .. qw(dist_ci) to replace standard MakeMaker targets with our own
#  .. qw(:all) to get both of the above, usual usage
#
sub import {


    #  Get params
    #
    my ($self, @param)=(shift(), @_);
    no warnings;
    #print "IMPORT\n";


    #  Read config
    #
    $Config_hr=$self->_config_read() ||
	return $self->_err('unable to process load config file');



    #  Store for later use in MY::makefile section
    #
    #(%MY::Import_class, $MY::Import_param_ar)=($self, \@param);
    $MY::Import_class{$self}=\@param;
    #print "CVS import $self\n";


    #  Code ref for params
    #
    my $const_config_cr=sub {

	$Const_config_chain_cr=UNIVERSAL::can('MY', 'const_config');
	#print "CVS $Const_config_chain_cr\n";
	*MY::const_config=sub { &const_config(@_) };
	0 && MY::const_config();

    };
    my $dist_ci_cr=sub {

	$Dist_ci_chain_cr=UNIVERSAL::can('MY', 'dist_ci');
	*MY::dist_ci=sub { &dist_ci(@_) };
	0 && MY::dist_ci();

    };
    my $makefile_cr=sub {

	$Makefile_chain_cr=UNIVERSAL::can('MY', 'makefile');
	*MY::makefile=sub { &makefile(@_) };
	0 && MY::makefile();

    };


    #  Put into hash
    #
    my %param=(

	const_config	=>  $const_config_cr,
	dist_ci		=>  $dist_ci_cr,
	makefile        =>  $makefile_cr,
	':all'		=>  sub { $const_config_cr->(); $dist_ci_cr->(); $makefile_cr->() }

       );


    #  Run appropriate
    #
    foreach my $param (@param) {
	$param{$param} && ($param{$param}->());
    }


    #  Done
    #
    *ExtUtils::CVS::import=sub { 
    	my $self=shift();
    	$MY::Import_class{$self}=\@param;
	$self->SUPER::import(@_) 
    };
    return $self->SUPER::import(@_);
    #return \undef;

}


#  MakeMaker::MY replacement const_config section
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
    return $Const_config_chain_cr->($self);


}


#  MakeMaker::MY update ci section to include an "import" function
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
	return $self->_err("unable to open $patch_fn, $!");


    #  Add in. We are replacing dist_ci entirely, so do not
    #  worry about chaining.
    #
    my  @dist_ci = map { chomp; $_ } <$patch_fh>;


    #  Close
    #
    $patch_fh->close();


    #  All done, return result
    #
    return join($/, @dist_ci);

}


#  MakeMaker::MY replacement Makefile section
#
sub makefile {


    #  Change package
    #
    package MY;
   

    #  Get self ref
    #
    my $self=shift();


    #  Get original makefile text
    #
    my $makefile=$Makefile_chain_cr->($self);


    #  Array to hold result
    #
    my @makefile;


    #  Build the  makefile -M line
    #
    my $makefile_module;
    #print Data::Dumper::Dumper(\%MY::Import_class);
    while (my ($class, $param_ar)=each %MY::Import_class) {
    #if (my @param=@{$MY::Import_param_ar}) {
	    if ($param_ar) {
	        $makefile_module.=" -M$class=".join(',', @{$param_ar});
	    }
	    else {
	        $makefile_module.=" -M$class";
	    }
    }


    #  Target line to replace. Will need to change here if ExtUtils::MakeMaker ever
    #  changes format of this line
    #
    my $find=q[$(PERL) "-I$(PERL_ARCHLIB)" "-I$(PERL_LIB)" Makefile.PL];
    my $rplc=
        sprintf(q[$(PERL) "-I$(PERL_ARCHLIB)" "-I$(PERL_LIB)" %s Makefile.PL],
                $makefile_module);
    my $make;


    #  Go through line by line
    #
    foreach my $line (split(/^/m, $makefile )) {


	#  Chomp
	#
	chomp $line;


	#  Check for target line
	#
	$line=~s/\Q$find\E/$rplc/i && ($make=$line);
	
	
	#  Also look for 'false' at end, erase
	#
	next if $line=~/^\s*false/;
	push @makefile, $line;


    }
    
    
    #  For rebuilding Makefile.PL without error, used after ci
    #
    #push @makefile, undef, undef;
    push @makefile, 'Makefile_PL :';
    #push @makefile, $make;


    #  Done, return result
    #
    return join($/, @makefile);	

}


#===================================================================================================


#  Public methods. Each one of the routines below corresponds with a Makefile target, eg
#
#  'make ci_tag' will tag the current cvs files
#

sub ci_tag {


    #  Build unique tag for checked in files
    #
    my $self=shift();
    my $param_hr=$self->_arg(@_);
    my $distname=$param_hr->{'DISTNAME'} ||
	return $self->_err('unable to get distname');


    #  Get cvs binary name
    #
    my $bin_cvs=$Config_hr->{'CVS'} ||
        return $self->_err('unable to determine cvs binary name');


    #  Read in version number, convers .'s to -
    #
    my $version_cvs=$self->ci_version(@_) ||
        return $self->_err('unable to get version number');
    $version_cvs=~s/\./-/g;


    #  Add distname
    #
    my $tag=join('_', $distname, $version_cvs);
    $self->_msg(qq[tagging as "$tag"]);


    #  Run cvs program to update
    #
    system($bin_cvs, 'tag', $tag);


}


sub ci_status {


    #  Checks that all files in the manifest are up to date with respect to
    #  CVS/Entries file
    #
    my $self=shift();
    my $param_hr=$self->_arg(@_);
    my $version_from=$param_hr->{'VERSION_FROM'} ||
	return $self->_err('unable to get version_from');


    #  Stat the master version file
    #
    my $version_from_mtime=(stat($version_from))[9] ||
	return $self->_err("unable to stat file $version_from, $!");


    #  Get the manifest
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();


    #  Ignore the ChangeLog file
    #
    if (my $changelog_fn=$Config_hr->{'CHANGELOG'}) {
        delete $manifest_hr->{$changelog_fn};
    }


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


    #  Array for files that may be out of date,
    #
    my @modified_fn;


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
	    return $self->_err("unable to open $entries_fn, $!");



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
		return $self->_err("unable to stat file $entry_fn, $!");
	    #print "mtime_fn $mtime_fn commit_time $commit_time, vtime $version_from_mtime\n";


	    #  Compare
	    #
	    ($mtime_fn > $commit_time) && do {

	    	#print "mtime > commit\n";


		#  Give it one more chance
		#
		$mtime_fn=$self->_ci_mtime_sync($entry_fn, $commit_time) ||
		    $mtime_fn;
		($mtime_fn > $commit_time) && do {
		        push @modified_fn, $entry_fn;
		        next;
		};


	    };


	    #  Check against version
	    #
	    ($mtime_fn > $version_from_mtime) && do {

	    	#print "mtime > version_mtime\n";

		#  Give it one more chance
		#
		$mtime_fn=$self->_ci_mtime_sync($entry_fn, $commit_time) ||
		    $mtime_fn;
		($mtime_fn > $version_from_mtime) && do {
		    push @modified_fn, $entry_fn;
		    next;
		};


	    };

	}


	#  Done with entries file
	#
	$entries_fh->close();

    }


    #  Check for modified files, quit if found
    #
    (@modified_fn) && do {
        my $err="The following files have an mtime > commit time or VERSION_FROM ($version_from) file:\n";
        $err.=Data::Dumper::Dumper(\@modified_fn);
        return $self->_err($err);
    };


    #  All looks OK
    #
    $self->_msg("all files up-to-date");


    #  All OK
    #
    return \undef;


}


sub ci_status_bundle {


    #  Checks that all files in the manifest are up to date with respect to
    #  CVS/Entries file
    #
    my $self=shift();
    my $param_hr=$self->_arg(@_);
    my $version_from=$param_hr->{'VERSION_FROM'} ||
	return $self->_err('unable to get version_from');


    #  Stat the master version file
    #
    my $version_from_mtime=(stat($version_from))[9] ||
	return $self->_err("unable to stat file $version_from, $!");


    #  Get cwd
    #
    my $cwd=cwd();
    $cwd=File::Spec->rel2abs($cwd);


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
	    return $self->_err("unable to open file $entries_fn, $!");


	#  Parse
	#
	my @entry=sort { $a cmp $b } <$entries_fh>;
	#foreach my $entry (<$entries_fh>) {
	while (my $entry=pop @entry) {


	    #  Split, skip non plain files
	    #
	    my ($fn_type, $fn, $version, $date)=split(/\//, $entry);
	    $fn_type && next;
	    
	    
	    #  Skip changelog
	    #
	    if ($fn eq $Config_hr->{'CHANGELOG'}) { next }


	    #  Rebuild
	    #
	    my $entry_fn=File::Spec->catfile(
		@entries_dn,
		$fn
	       );
	    $entry_fn=File::Spec->rel2abs($entry_fn);
	    #print "fn $fn entry_fn $entry_fn\n";


	    #  Get mtime
	    #
	    my $mtime_fn=(stat($entry_fn))[9];


	    #  Check against version
	    #
	    ($mtime_fn > $version_from_mtime) && do {


		#  Give it one more chance
		#
		$mtime_fn=$self->_ci_mtime_sync($entry_fn) ||
		    $mtime_fn;
		($mtime_fn > $version_from_mtime) &&
		    return
			$self->_err("$fn has mtime greater than $version_from, cvs commit may be required.");

	    };


	    #  Convert date to GMT
	    #
	    my $commit_time=str2time($date, 'GMT');


	    #  Compare
	    #
	    ($mtime_fn > $commit_time) && do {

		$mtime_fn=$self->_ci_mtime_sync($entry_fn) ||
		    $mtime_fn;
		($mtime_fn > $commit_time) &&
		    return
			$self->_err("$entry_fn has mtime greater commit time, cvs commit may be required.");

	    };
	}
    }


    #  All looks OK
    #
    $self->_msg('all files up-to-date');


    #  All OK
    #
    return \undef;


}


sub ci_manicheck {


    #  Checks that all files in the manifest are checked in to cvs
    #
    my $self=shift();
    my $param_hr=$self->_arg(@_);
    my $distname=$param_hr->{'DISTNAME'} ||
	return $self->_err('unable to get distname');


    #  Get cwd, dance around Win32 formatting
    #
    my $cwd=cwd();
    $cwd=(File::Spec->splitpath($cwd,1))[1];
    $cwd=File::Spec->rel2abs($cwd);


    #  Get the manifest, jump Win32 hoops with file names
    #
    ExtUtils::Manifest::manicheck() && return $self->_err('MANIFEST manicheck error');
    my $manifest_hr=ExtUtils::Manifest::maniread();
    foreach my $fn (keys %{$manifest_hr}) {
        delete $manifest_hr->{$fn};
        $manifest_hr->{File::Spec->canonpath($fn)}=undef;
    }
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


	#  Check that this is in the module we are interested
	#  in, start by opening CVS/Repository file
	#
	my $repository_fn=File::Spec->catfile(@entries_dn, 'Repository');
	my $repository_fh=IO::File->new($repository_fn, O_RDONLY) ||
	    return $self->_err("unable to open file $repository_fn, $!");
	my $repository_dn=<$repository_fh>; chomp($repository_dn);


	#  Get top level
	#
	my $repository=(File::Spec->splitdir($repository_dn))[0];
	next unless ($repository eq $distname);


	#  Get rid of empty directories
	#
	until ( pop @entries_dn ) {}


	#  Open
	#
	my $entries_fh=IO::File->new($entries_fn, O_RDONLY) ||
	    return $self->_err("unable to open file $entries_fn, $!");


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
	    $manifest_fn=File::Spec->rel2abs($manifest_fn);


	    #  Get rid of cwd, leading slash
	    #
	    $manifest_fn=~s/^\Q$cwd\E\/?//;
	    $manifest_fn=~s/^\\//;


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
	$self->_msg("the following files are in the manifest, but not in CVS: \n\n%s\n",
	       join("\n", keys %test0));
	$fail++;
    }
    my %test1=%manifest;
    map { delete $test1{$_} } keys %{$manifest_hr};
    if (keys %test1) {
	$self->_msg("the following files are in CVS, but not in the manifest: \n\n%s\n\n",
	       join("\n", keys %test1));
	$fail++;
    }


    #  Now look for a patch dir
    #
    if (-d (my $dn=File::Spec->catdir($cwd, 'patch'))) {


	#  Yes, must check files in that dir also. Process dir to get just file entries.
	#
	tie (my %fn_raw, 'IO::Dir', $dn) ||
	    return $self->_err("unable to tie IO::Dir to $dn, $!");
	my %fn=%fn_raw;
	map { delete $fn{$_} unless (-f File::Spec->catfile($cwd,'patch',$_)) } keys %fn;


	#  Now test for files in patch dir. not in manifest
	#
	my %test0=%fn;
	map { delete $test0{(File::Spec->splitpath($_))[2]}} keys %{$manifest_hr};
	if (keys %test0) {
	    $self->_msg("the following files are in the patch dir, but not in the manifest: \n\n%s\n",
		   join("\n", keys %test0));
	    $fail++;
	}


	#  And files in patch dir, not in CVS
	#
	my %test1=%fn;
	map { delete $test1{(File::Spec->splitpath($_))[2]}} keys %manifest;
	if (keys %test1) {
	    $self->_msg("the following files are in the patch dir, but not in the CVS: \n\n%s\n",
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
	    return $self->_err('bundle build aborted by user !')
	}
    }
    else {
	$self->_msg('manifest and cvs in sync');
    }


    #  All done
    #
    return \undef;

}


sub ci_version_dump {


    #  Get self ref
    #
    my $self=shift();
    my $param_hr=$self->_arg(@_);


    #  Get version we are saving
    #
    my $have_version=$self->ci_version(@_);


    #  Get location of Dumper file, load up module, version info
    #  that we are processing, save again
    #
    my $dump_fn=File::Spec->catfile(cwd(), $Config_hr->{'DUMPER_FN'});
    my $dump_hr=do ($dump_fn);
    #my $dump_tr=tie(my %dump, 'Tie::IxHash'), 
    #@dump{qw(NAME DISTNAME VERSION)}=(@{$param_hr}{qw(NAME DISTNAME)}, $have_version);
    my %dump=(
	$param_hr->{'NAME'} =>	$have_version
       );



    #  Check if we need not update
    #
    my $dump_version=$dump_hr->{'VERSION'};
    if (CPAN::Version->vcmp("v$dump_version", "v$have_version")) {

	my $dump_fh=IO::File->new($dump_fn, O_WRONLY|O_TRUNC|O_CREAT) ||
	    die ("unable to open file $dump_fn, $!");
	binmode($dump_fh);
	$Data::Dumper::Indent=1;
	print $dump_fh (Data::Dumper->Dump([\%dump],[]));
	$dump_fh->close();
	$self->_msg('cvs version dump complete');


    }
    else {


	#  Message
	#
	$self->_msg('cvs version dump file up-to-date');


    }


    #  Done
    #
    return \undef;

}


sub ci_version {


    #  Print current version from version_from file
    #
    my $self=shift();
    my $param_hr=$self->_arg(@_);
    my $version_from=$param_hr->{'VERSION_FROM'} ||
	return $self->_err('unable to get version_from');


    #  Get version from version_from file
    #
    my $version_cvs=do(File::Spec->rel2abs($version_from)) ||
	return $self->_err("unable to read version info from version_from file $version_from, $!");


    #  Display
    #
    $self->_msg("cvs version: $version_cvs");


    #  Done
    #
    return $version_cvs;

}


#===================================================================================================

#  Private methods. Utility functions - use externally at own risk
#


sub _ci_mtime_sync {


    #  Last resort to ensure file mtime is correct based on what CVS thinks
    #
    my ($self, $fn, $mtime_fn)=@_;
    #print "$method:fn $sync_fn\n";


    #  Turn abs filenames into relative, cvs does not seem to like it
    #
    $fn=File::Spec->abs2rel($fn);


    #  Get timezone offset from GMT
    #
    my $time=time();
    #my $tz_offset=($time-timelocal(gmtime($time))) || 0;
    #print "tz_offset $tz_offset\n";


    #  Get cvs binary name
    #
    my $bin_cvs=$Config_hr->{'CVS'} ||
        return $self->_err('unable to determine cvs binary name');


    #  Run cvs status on file, suck into array
    #
    my $system_fh=IO::File->new("$bin_cvs status $fn|") ||
        return $self->_err("unable to get handle for cvs status command");
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
	return $self->_err("unable to stat file $fn, $!");


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
	    return $self->_err("unable to get handle for cvs log command");
	my @system=<$system_fh>;
	$system_fh->close();
	#print Data::Dumper::Dumper(\@system);


	#  Get line with date
	#
	my $line_date;
	for (0.. $#system) {
	    $system[$_]=~/revision\s+\Q$ver_working\E\s+/ &&
		do { $line_date=$system[++$_]; last };
	};


	#  Parse it out
	#
	if ($line_date && $line_date=~/^date:\s+(\S+)\s+(\S+)\;/) {


	    #  Convert string time
	    #
	    $mtime=str2time("$1 $2", 'GMT') ||
		return $self->_err("unable to parse date string $1 $2");
	    #print "choice of mtime $mtime (log) or $mtime_fn (commit)\n";

            #  Use oldest
            #
            $mtime=($mtime_fn < $mtime) ? $mtime_fn : $mtime;

	    #  Touch it
	    #
	    my $touch_or=File::Touch->new(

		'mtime'	=>  $mtime,

	       );
	    $touch_or->touch($fn) ||
		return $self->_err("error on touch of file $fn, $!");
	    $self->_msg("synced file $fn to cvs mtime $mtime (%s)\n",
		   scalar(localtime($mtime)));

	}

    }


    #  return the mtime
    #
    return $mtime;


}


#  Read in config file
#
sub _config_read {


    #  Get our dir
    #
    my $self=shift();
    (my $config_dn=$INC{'ExtUtils/CVS.pm'})=~s/\.pm$//;


    #  Unless absolute, add cwd
    #
    $config_dn=File::Spec->rel2abs($config_dn);


    #  And now file name
    #
    my $config_fn=File::Spec->catfile($config_dn, 'Config.pm');


    #  Read and return
    #
    my $config_hr=do($config_fn) || return $self->_err($!);


    #  Read any local config file. Only present for local customisation
    #
    my $local_hr=eval { do { File::Spec->catfile($config_dn, 'Local.pm') } };


    #  Local overrides global
    #
    map { $config_hr->{$_}=$local_hr->{$_} } keys %{$local_hr};


    #  Return
    #
    return $config_hr;


}



sub _repository {


    #  Modify repository
    #
    my ($self, $repository)=@_;
    $Config_hr->{'CVSROOT'}=$repository;
    return \$repository;


}


sub _err {


    #  Quit on errors
    #
    my $self=shift();
    my $message=$self->_fmt("*error*\n\n" . shift(), @_);
    croak $message;

}


sub _msg {


    #  Print message
    #
    my $self=shift();
    my $message=$self->_fmt(@_);
    CORE::print $message, "\n";

}


sub _fmt {


    #  Format message nicely
    #
    my $self=shift();
    my $caller=$self->_caller(3) || 'unknown';
    my $format=' @<<<<<<<<<<<<<<<< @<';
    my $message=sprintf(shift(), @_);
    chomp($message);
    $message=$Arg{'distname'} . ", $message" if ($Arg{'distname'});
    formline $format, $caller . ':', undef;
    $message=$^A . $message; $^A=undef;
    return $message;

}


sub _arg {

    #  Get args, does nothing but intercept distname for messages, cobvert to param
    #  hash
    #
    shift();
    @Arg{qw(NAME NAME_SYM DISTNAME DISTVNAME VERSION VERSION_SYM VERSION_FROM)}=@_;
    return \%Arg, @_[7..$#_];

}


sub _caller {


    #  Return the method name of the caller
    #
    shift();
    my $caller=(split(/:/, (caller(shift() || 1))[3]))[-1];
    $caller=~s/^_//;
    return $caller;

}


__END__


=head1 NAME

ExtUtils::CVS - Class to add cvs related targets to Makefile generated from perl Makefile.PL

=head1 SYNOPSIS

    perl -MExtUtils::CVS=:all Makefile.PL
    make import
    make ci_manicheck
    make ci
    make ci_status

=head1 DESCRIPTION

ExtUtils::CVS is a class that extends ExtUtils::MakeMaker to add cvs related
targets to the Makefile generated from Makefile.PL.

ExtUtils::CVS will enforce various rules during modules distribution, such as not
building a dist for a module before all components are checked in to CVS. It will
also not build a dist if the MANIFEST and CVS ideas of what are in the module are
out of sync.

=head1 OVERVIEW

Create a normal module using h2xs (see L<h2xs>). Either put ExtUtils::MakeMaker into
an eval'd BEGIN block in your Makefile.PL, or build the Makefile.PL with ExtUtils::CVS
as an included module.

=over 4

=item BEGIN block within Makefile.PL

A sample Makefile.PL may look like this:

        use strict;
        use ExtUtils::MakeMaker;

        WriteMakeFile ( 

                NAME    =>  'Acme::Froogle'
                ... MakeMaker options here

        );

        sub BEGIN {  eval('use ExtUtils::CVS') }

eval'ing ExtUtils::CVS within a BEGIN block allows user to build your module even if they
do not have a local copy of ExtUtils::CVS.

=item Using as a module when running Makefile.PL

If you do not want any reference to ExtUtils::CVS within your Makefile.PL, you can
build the Makefile with the following command:

        perl -MExtUtils::CVS=:all Makefile.PL

This will build a Makefile with all the ExtUtils::CVS targets.

=back

=head1 IMPORTING INTO CVS

Once you have created the first draft of your module, and included ExtUtils::CVS into the
Makefile.PL file in one of the above ways, you can import the module into CVS. Simply do a

        make import

in the working directory. All files in the MANIFEST will be imported into CVS. This does B<not>
create a CVS working directory in the current location.

You should move to a clean directory location and do a

        cvs co Acme-Froogle

Note the translation of '::' characters in the module name to '-' characters in CVS.

=head1 ADDING OR REMOVING FILES WITHIN THE PROJECT

Once checked out you can work on your files as per normal. If you add or remove a file from your
module project you need to undertake the corresponding action in cvs with a

        cvs add myfile.pm OR
        cvs del myfile.pm

You must remember to add or remove the file from the MANIFEST, or ExtUtils::CVS will generate a
error when you try to build the dist. This is by design - the contents of the MANIFEST file should
mirror the active CVS files.

=head1 CHECKING IN MODIFICATIONS

Periodically you will want to check modifications into the CVS repository. If you are not planning to make
a distribution at this time a normal

        cvs ci

will still work. As this is a stardard cvs checkin, no checking of the MANIFEST etc will be performed. 

If you wish to build a distribution from the current project working directory you should do a 

        make ci

Doing a 'make ci' will undertake a check to ensure that the MANIFEST and CVS are in sync. It will
check modified files in to CVS, incrementing the current module version. In addition, it will then
tag the repository with the new version in the form 'Acme-Froogle_1-26'. Thus at any time you can
checkout an earlier version of your module with a cvs command in the form of

        cvs co -r Acme-Froogle_1-10 Acme-Froogle

The checked out version will be 'sticky' (see L<cvs> for details), you will not be able to check
changes back into the repository without branching your project.


=head1 OTHER MAKEFILE TARGETS

As well as 'make import' and 'make ci', the following other targets are supported. Many
of these targets are called by the 'make ci' process, but can be run standalone also

=over 4

=item make ci_manicheck

Will check that MANIFEST and CVS agree on files included in the project

=item make ci_status

Will check that no project files have been modified since last checked in to the 
repository.

=item make ci_version

Will show the current version of the project in the working directory

=item make ci_tag

Will tag files with current version. Not recommended for manual use

=back

=head1 COPYRIGHT

Copyright (c) 2003 Andrew Speer <andrew.speer@isolutions.com.au>. All
rights reserved.

