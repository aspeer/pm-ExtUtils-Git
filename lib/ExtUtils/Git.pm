#
#  Copyright (C) 2003,2004 Andrew Speer <andrew.speer@isolutions.com.au>. All rights
#  reserved.
#
#  This file is part of ExtUtils::Git.
#
#  ExtUtils::Git is free software; you can redistribute it and/or modify
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
#


#  Augment Perl ExtUtils::MakeMaker functions
#
package ExtUtils::Git;


#  Compiler Pragma
#
sub BEGIN   { $^W=0 };
use strict  qw(vars);
use vars    qw($VERSION);
use warnings;
no  warnings qw(uninitialized);


#  External Packages
#
use ExtUtils::Git::Constant;
use IO::File;
use File::Spec;
use ExtUtils::Manifest;
use ExtUtils::MM_Any;
use Data::Dumper;
use File::Touch;
use Carp;
use File::Grep qw(fdo);


#  Version information in a formate suitable for CPAN etc. Must be
#  all on one line
#
$VERSION = '1.143';


#  Load up our config file
#
our $Config_hr;


#  Vars to hold chained soubroutines, if needed (loaded by import). Must be
#  global (our) vars. Also need to remember import param
#
our ($Const_config_chain_cr, $Dist_ci_chain_cr, $Makefile_chain_cr, $Metafile_target_chain_cr, $Platform_constants_cr);


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
#  use ExtUtils::Git qw(const_config) to just replace the macros section of the Makefile
#  .. qw(dist_ci) to replace standard MakeMaker targets with our own
#  .. qw(:all) to get both of the above, usual usage
#
sub import {


    #  Get params
    #
    my ($self, @import)=(shift(), @_);
    no warnings;


    #  Store for later use in MY::makefile section
    #
    $MY::Import_class{$self}=\@import;
    $MY::Import_inc=\@INC;


    #  Code ref for params
    #
    my $const_config_cr=sub {

	$Const_config_chain_cr=UNIVERSAL::can('MY', 'const_config');
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
    my $metafile_target_cr=sub {

	$Metafile_target_chain_cr=UNIVERSAL::can('MY', 'metafile_target');
	*ExtUtils::MM_Any::metafile_target=sub { &metafile_target(@_) };
	0 && ExtUtils::MM_Any::metafile_target();

    };
    my $platform_constants_cr=sub {

	$Platform_constants_cr=UNIVERSAL::can('MY', 'platform_constants');
	*MY::platform_constants=sub { &platform_constants(@_) };
	0 && MY::platform_constants();

    };


    #  Put into hash
    #
    my %import=(

	const_config		=>  $const_config_cr,
	dist_ci			=>  $dist_ci_cr,
	makefile        	=>  $makefile_cr,
	metafile_target 	=>  $metafile_target_cr,
	platform_constants	=>  $platform_constants_cr,
	':all'			=>  sub { $const_config_cr->(); $dist_ci_cr->(); $makefile_cr->(); $metafile_target_cr->(); $platform_constants_cr->() },

       );


    #  Run appropriate
    #
    foreach my $import (@import ? @import : ':all') {
	$import{$import} && ($import{$import}->());
    };


    #  Also include utilities into the MY address space
    #
    foreach my $sr (qw(_err)) {
	*{"MY::${sr}"}=\&{$sr};
    }


    #  Done. Replace with stub so not run again
    #
    *ExtUtils::Git::import=sub {
    	my $self=shift();
    	$MY::Import_class{$self}=\@import;
    	$MY::Import_inc=\@INC;
	$self->SUPER::import(@_)
    };


    #  And call any other import routine needed
    #
    return $self->SUPER::import(@_ ? @_ : ':all');

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


    #  Import Constants into macros
    #
    while (my ($key, $value)=each %ExtUtils::Git::Constant::Constant) {


	#  Update macros with our config
	#
	$self->{'macro'}{$key}=$value;

    }


    #  Return whatever our parent does
    #
    return $Const_config_chain_cr->($self);


}


#  MakeMaker::MY update ci section to include a "git_import" and other functions
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
    (my $patch_dn=$INC{'ExtUtils/Git.pm'})=~s/\.pm$//;


    #  And now file name
    #
    my $patch_fn=File::Spec->catfile($patch_dn, 'dist_ci.inc');


    #  Open it
    #
    my $patch_fh=IO::File->new($patch_fn, &ExtUtils::Git::O_RDONLY) ||
	return ExtUtils::Git->_err("unable to open $patch_fn, $!");


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
    my $class=__PACKAGE__;
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
    while (my ($class, $param_ar)=each %MY::Import_class) {
	if (@{$param_ar}) {
	    $makefile_module.=qq("-M$class=").join(',', @{$param_ar});
	}
	else {
	    $makefile_module.=qq("-M$class");
	}
    }
    
    
    #  Get the INC files
    #
    my $makefile_inc;
    use Data::Dumper;
    if (my @inc=@{$MY::Import_inc}) {
        my %inc;
        foreach my $inc (@inc) {
            $makefile_inc.=qq( "-I$inc") unless $inc{$inc}++;
        }
        #$makefile_inc=join(' ', map { qq("-I$_") } @inc);
        #print Dumper(\@inc, $makefile_inc);
    }

    
    #  Target line to replace. Will need to change here if ExtUtils::MakeMaker ever
    #  changes format of this line
    #
    my @find=(q[$(PERL) "-I$(PERL_ARCHLIB)" "-I$(PERL_LIB)" Makefile.PL],
	      q[$(PERLRUN) Makefile.PL]);
    my $rplc=
        sprintf(q[$(PERL) %s "-I$(PERL_ARCHLIB)" "-I$(PERL_LIB)" %s Makefile.PL],
                $makefile_inc, $makefile_module);
    my $match;


    #  Go through line by line
    #
    foreach my $line (split(/^/m, $makefile )) {


	#  Chomp
	#
	chomp $line;


	#  Check for target line
	#
	for (@find) { $line=~s/\Q$_\E/$rplc/i && ($match=$line) };


	#  Also look for 'false' at end, erase
	#
	next if $line=~/^\s*false/;
	push @makefile, $line;


    }

    #  Warn if line not found
    #
    $class->_msg('warning! ExtUtils::Makemaker makefile section replacement not successful') unless
	$match;


    #  Done, return result
    #
    return join($/, @makefile);

}


sub platform_constants {


    #  Change package
    #
    my $class=__PACKAGE__;
    package MY;


    #  Get self ref
    #
    my $self=shift();


    #  Get original constants
    #
    my $constants=$Platform_constants_cr->($self);
    
    
    #  Get INC
    #
    my $makefile_inc;
    if (my @inc=@{$MY::Import_inc}) {
        $makefile_inc=join(' ', map { qq("-I$_") } @inc);
    }
    
    
    #  Update fullperlrun, used by test
    #
    $constants.=join("\n", 
    
        undef,
    
        "FULLPERLRUN = \$(FULLPERL) $makefile_inc",
        "MAKEFILELIB = $makefile_inc",
        
        undef
    );
    

    #  Done
    #
    $constants;
    

}


sub metafile_target {


    #  Change package
    #
    package MY;


    #  Get self ref
    #
    my $self=shift();


    #  Get original makefile text
    #
    my $metafile=$Metafile_target_chain_cr->($self);
    $metafile=~s/\$\(DISTVNAME\)\/META.yml/META.yml/;
    $metafile=~s/^metafile\s*:\s*create_distdir/metafile :/;

    #  Done, return modified version
    #
    return $metafile;

}


#===================================================================================================


sub git_import {


    #  Import all files in MANIFEST into Git.
    #
    my $self=shift();
    my $param_hr=$self->_arg(@_);


    #  Check all files present
    #
    ExtUtils::Manifest::manicheck() &&
	return $self->_err('MANIFEST manicheck error');


    #  Get the manifest
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();


    #  Remove the ChangeLog, META.yml from the manifest - they are generated at distribution time, and
    #  is not tracked by Git
    #
    delete @{$manifest_hr}{$CHANGELOG_FN, $METAFILE_FN};
    #delete $manifest_hr->{$METAFILE_FN};


    #  Build import command
    #
    my @system=($GIT_EXE, 'add', keys %{$manifest_hr});
    unless (system(@system) == 0) {
	return $self->_err("failed to execute git import: $?") }



    #  All OK
    #
    $self->_msg('git import successful');
    return \undef;


}


sub git_manicheck {


    #  Checks that all files in the manifest are checked in to Git
    #
    my $self=shift();
    my $param_hr=$self->_arg(@_);
    my $distname=$param_hr->{'DISTNAME'} ||
	return $self->_err('unable to get distname');


    #  Get manifest, touch ChangeLog, META.yml if it is supposed to exist - will be created/updated
    #  at dist time
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();
    foreach my $fn ($CHANGELOG_FN, $METAFILE_FN) {
    
            if (exists($manifest_hr->{$fn}) && !(-f $fn)) {

                #  Need to create it
                #
                touch $fn ||
                    return $self->_err("unable to create '$fn' file");
                $self->_msg("git touch '$fn'");

            }

    }


    #  Check manifest
    #
    ExtUtils::Manifest::manicheck() && return $self->_err('MANIFEST manicheck error');


    #  Read in all the Git files
    #
    my %git_manifest=map { chomp($_); $_=>1 } split($/, qx($GIT_EXE ls-files));


    #  Remove the ChangeLog from the manifest - it is generated at distribution time, and
    #  is not tracked by Git
    #
    delete @{$manifest_hr}{$CHANGELOG_FN, $METAFILE_FN};
    #delete $manifest_hr->{$CHANGELOG_FN};


    #  Check for files in Git, but not in the manifest, or vica versa
    #
    my $fail;
    my %test0=%{$manifest_hr};
    map { delete $test0{$_} } keys %git_manifest;
    if (keys %test0) {
	$self->_msg("the following files are in the manifest, but not in git: \n\n%s\n",
	       join("\n", keys %test0));
	$fail++;
    }
    my %test1=%git_manifest;
    map { delete $test1{$_} } keys %{$manifest_hr};
    if (keys %test1) {
	$self->_msg("the following files are in git, but not in the manifest: \n\n%s\n\n",
	       join("\n", keys %test1));
	$fail++;
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
	$self->_msg('git and manifest in sync');
    }


    #  All done
    #
    return \undef;

}


sub git_status {


    #  Checks that all files in the manifest checked in, and are not
    #  newer than the VERSION_FROM file.
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


    #  Get list of modified files
    #
    my %git_modified=map { chomp($_); $_=>1 } split($/, qx($GIT_EXE ls-files --modified));


    #  Remove the ChangeLog from the manifest - it is generated at distribution time, and
    #  is not tracked by Git, same with META.yml
    #
    delete @{$manifest_hr}{$CHANGELOG_FN, $METAFILE_FN};
    #delete $manifest_hr->{$CHANGELOG_FN};
    #delete $manifest_hr->{$METAFILE_FN};


    #  If any modfied file bail now
    #
    if (keys %git_modified)  {
        my $err="The following files have been modified since last commit:\n";
        $err.=Data::Dumper::Dumper([keys %git_modified]);
        return $self->_err($err);
    };


    #  Array for files that may be newer than version_from file
    #
    my @modified_fn;


    #  Start going through each file in the manifest and check mtime
    #
    foreach my $fn (keys %{$manifest_hr}) {


	#  Get commit time
	#
	my $commit_time=qx($GIT_EXE log -n1 --pretty=format:"%at" $fn) ||
	    $self->_err("unable to get commit time for file $fn");


	#  Stat file
	#
	my $mtime_fn=(stat($fn))[9] ||
	    return $self->_err("unable to stat file $fn, $!");


	#  Check against version file
	#
	if ($mtime_fn > $version_from_mtime) {

	    #  Give it one more chance
	    #
	    $mtime_fn=$self->_git_mtime_sync($fn, $commit_time) ||
		$mtime_fn;
	    if ($mtime_fn > $version_from_mtime)  {
		push @modified_fn, $fn;
		next;
	    };


	};

    }


    #  Check for modified files, quit if found
    #
    if (@modified_fn)  {
        my $err="The following files have an mtime > VERSION_FROM ($version_from) file:\n";
        $err.=Data::Dumper::Dumper(\@modified_fn);
        return $self->_err($err);
    };


    #  All looks OK
    #
    $self->_msg("git files up-to-date");


    #  All OK
    #
    return \undef;

}


sub git_version_increment {


    #  Increment the VERSION_FROM file
    #
    my $self=shift();
    my $param_hr=$self->_arg(@_);
    my $version_from_fn=$param_hr->{'VERSION_FROM'} ||
	return $self->_err('unable to get version_from file name');


    #  Get current version
    #
    my $version=$self->git_version(@_) ||
	return $self->_err("unable to get existing version from $version_from_fn");
    my @version=split(/\./, $version);
    $version[-1]++;
    $version[-1]=sprintf('%03d', $version[-1]);
    my $version_new=join('.', @version);


    #  Open file handles for read and write
    #
    my $old_fh=IO::File->new($version_from_fn, O_RDONLY) ||
	return $self->_err("unable to open file '$version_from_fn' for read, $!");
    my $new_fh=IO::File->new("$version_from_fn.tmp", O_WRONLY|O_CREAT|O_TRUNC) ||
	return $self->_err("unable to open file '$version_from_fn.tmp' for write, $!");


    #  Now iterate through file, increasing version number if found
    #
    while (my $line=<$old_fh>) {
	$line=~s/\Q$version\E/$version_new/;
	print $new_fh $line;
    }

    #  Close file handles, overwrite existing file
    #
    $old_fh->close();
    $new_fh->close();
    rename("$version_from_fn.tmp", $version_from_fn) ||
	return $self->_err("unable to replace $version_from_fn with newer version, $!");


    #  All OK
    #
    $self->_msg("updated $version_from_fn from version $version to $version_new");


    #  Done
    #
    return \undef;

}


sub git_version_increment_files {


    #  Check for files that have changed and edit to update version numvers
    #
    my $self=shift();
    my $param_hr=$self->_arg(@_);
    my $version_from_fn=$param_hr->{'VERSION_FROM'} ||
	return $self->_err('unable to get version_from file name');


    #  Get manifest.
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();
    use File::Temp;
    use File::Copy;


    #  Get list of modified files
    #
    my %git_modified=map { chomp($_); $_=>1 } split($/, qx($GIT_EXE ls-files --modified));

    
    # Iterate through
    #
    foreach my $fn (keys %{$manifest_hr}) {
	
	
	#  Skip VERSION.pm file
	#
	#print "fn $fn, vfrom $version_from_fn\n"; 
	next if ($fn eq $version_from_fn);
	
	
	#  Get number of git checkins
	#
	my $git_rev_list=qx($GIT_EXE rev-list HEAD $fn);
	my $revision=(my @revision=split($/, $git_rev_list));
        $revision=sprintf('%03d', $revision);
	if ($revision > 998) {
	    return $self->_err("revision too high ($revision) - update release ?");
	}
	
	#print "$fn, $revision\n";
	
	my $temp_fh=File::Temp->new() ||
	    return $self->_err("unable to open tempfile, $!");
	my $temp_fn=$temp_fh->filename() ||
	    return $self->_err("unable to obtain tempfile name from fh $temp_fh");
	my $fh=IO::File->new($fn) ||
	    return $self->_err("unable to open file $fn for readm $!");
	my ($update_fg, $version_seen_fg);
	while (my $line=<$fh>) {
	    if ($line=~/^\$VERSION\s*=\s*'(\d+)\.(\d+)'/ && !$version_seen_fg && $git_modified{$fn}) {
		$version_seen_fg++;
		my $release=$1 || 1;
		print "found rev $2 vs git rev $revision\n";
		if ($2 < $revision) {
		    #  Update revision in anticipation of checkin
                    $revision=sprintf('%03d', $revision);
		    $line=~s/^(\$VERSION\s*=\s*)'(\d+)\.(\d+)'(.*)$/$1'$release.$revision'$4/;
		    print "updating $fn version from $2.$3 to $release.$revision\n";
		    #print "$line";
		    $update_fg++;
		}
		elsif ($2 > ($revision+1)) {
		    return $self->_err("error - $fn existing version $1.$2 > proposed version $1.$revision !");
		}
		elsif ($2 == $revision) {
		    print "skipping update of $fn, version $1.$2 identical to proposed rev $1.$revision\n";
		}
	    }
	    elsif ($line=~/^\$VERSION/ && $line!~/^\$VERSION\s*=\s*'(\d+)\.(\d+)'/ && !$version_seen_fg) {
		$version_seen_fg++;
		my $release=1;
		#  Update revision in anticipation of checkin
		$revision++;
                $revision=sprintf('%03d', $revision);
		print "changing $fn version format to $release.$revision\n";
		$line="\$VERSION='$release.$revision';\n";
		$update_fg++;
	    }
	    print $temp_fh $line;
	}
	$fh->close();
	$temp_fh->close();
	if ($update_fg) {
	    #print "Would update fn $fn\n";
	    File::Copy::move($temp_fn, $fn) ||
		return $self->_err("error moving file $temp_fn=>$fn, $!")
	}
	else {
	    #print "no \$VERSION match on file $fn\n";
	}	
    }


    #  All done
    #
    return \undef;

}


sub git_tag {


    #  Build unique tag for checked in files
    #
    my $self=shift();
    my $param_hr=$self->_arg(@_);
    my $distname=$param_hr->{'DISTNAME'} ||
	return $self->_err('unable to get distname');


    #  Read in version number, convers .'s to -
    #
    my $version=$self->git_version(@_) ||
        return $self->_err('unable to get version number');


    #  Add distname
    #
    my $tag="${distname}_${version}";
    $self->_msg(qq[git tagging as "$tag"]);


    #  Run git program to update
    #
    unless (system($GIT_EXE, 'tag', $tag) == 0) {
	return $self->_err("error on git tag, $?");
    }


    #  All done
    #
    return \undef;


}


sub git_commit {


    #  Commit modified file
    #
    my $self=shift();
    my $param_hr=$self->_arg(@_);
    my $distname=$param_hr->{'DISTNAME'} ||
	return $self->_err('unable to get distname');


    #  Read in version number, convers .'s to -
    #
    my $version=$self->git_version(@_) ||
        return $self->_err('unable to get version number');


    #  Add distname
    #
    my $tag="${distname}_${version}";


    #  Run git program to update
    #
    unless (system($GIT_EXE, 'commit', qw(-a -e -m), qq[Tag: $tag]) == 0) {
	return $self->_err("error on git commit, $?");
    }


    #  All done
    #
    return \undef;


}


sub git_version {


    #  Print current version from version_from file
    #
    my $self=shift();
    my $param_hr=$self->_arg(@_);
    my $version_from=$param_hr->{'VERSION_FROM'} ||
	return $self->_err('unable to get version_from');


    #  Get version from version_from file
    #
    #my $version_git=do(File::Spec->rel2abs($version_from)) ||
    my $version_git=eval {MM->parse_version(File::Spec->rel2abs($version_from)) } ||
	return $self->_err("unable to read version info from version_from file $version_from, $!");


    #  Display
    #
    $self->_msg("git version $version_git");


    #  Done
    #
    return $version_git;

}


sub git_version_dump {


    #  Get self ref
    #
    my $self=shift();
    my $param_hr=$self->_arg(@_);


    #  Get version we are saving
    #
    my $have_version=$self->git_version(@_);


    #  Get location of Dumper file, load up module, version info
    #  that we are processing, save again
    #
    my $dump_fn=File::Spec->catfile($DUMPER_FN);
    my $dump_hr=do ($dump_fn);
    my %dump=(
	$param_hr->{'NAME'} =>	$have_version
       );



    #  Check if we need not update
    #
    my $dump_version=$dump_hr->{$param_hr->{'NAME'}};
    if ("v$dump_version" ne "v$have_version") {

	my $dump_fh=IO::File->new($dump_fn, O_WRONLY|O_TRUNC|O_CREAT) ||
	    $self->_err("unable to open file $dump_fn, $!");
	binmode($dump_fh);
	$Data::Dumper::Indent=1;
	print $dump_fh (Data::Dumper->Dump([\%dump],[]));
	$dump_fh->close();
	$self->_msg('git version dump complete');


    }
    else {


	#  Message
	#
	$self->_msg('git version dump file up-to-date');


    }


    #  Done
    #
    return \undef;

}


sub git_lint {


    #  Check for old CVS references (RCS keywords etc)
    #
    my $self=shift();
    my $param_hr=$self->_arg(@_);


    #  Get the manifest
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();

    #  Get list of modified files
    #
    my %git_modified_fn=map { chomp($_); $_=>1 } split($/, qx($GIT_EXE ls-files --modified));


    #  Iterate over file list looking for problems.
    #
    my @match;
    foreach my $fn (keys %{$manifest_hr}) {
	#print "fn $fn\n";
	fdo {
	    my (undef, $pos, $line)=@_;
	    #print "line $line\n";
	    my $match="in $fn at line $pos";
	    # Obfuscate RCS keyworks so ExtUtils::Git does not warn when run on itself
	    if ($line=~/(\$A{1}uthor|\$D{1}ate|\$H{1}eader|\$I{1}d|\$L{1}ocker|\$L{1}og|\$N{1}ame|\$R{1}CSfile|\$R{1}evision|\$S{1}ource|\$S{1}tate|\$R{1}EVISION)/) {
		push @match, "found RCS keyword '$1' $match";
	    }
	    if ($line=~/REVISION/) {
		push @match, "found obsolete REVISION keyword $match";
	    }
	    #if ($line=~/copyright.*?(\d{4})*\s*(,|-)*\s*(\d{4})/i && ($fn!~/LICENSE/)) {
	    if ($line=~/copyright/i && (my @year=($line=~/\d{4}/g)) && ($fn!~/LICENSE/)) {
		my $copyyear=$year[-1];
		my $thisyear=(localtime())[5]+1900;
		#print "cr match $copyyear\n";
		if (($copyyear < $thisyear)) {
		    push @match, "found old copyright notice ($copyyear) $match";
		}		
	    }
	    if ($line=~/copyright\s+\(/i && ($line=~/andrew/i) &&  $line!~/Copyright \(C\) \d{4}-\d{4} Andrew Speer.*?(\<andrew\@webdyne\.org>)?/ && ($fn!~/LICENSE$/) && ($fn!~/ChangeLog$/)) {
	        push @match, "inconsistant copyright format $match";
            }
	    if ($line=~/\s+(.*?)\@isolutions\.com\.au/ && ($fn!~/ChangeLog$/i)) {
		push @match, "found isolutions email address $2\@isolutions.com.au $match";
	    }
	    if ($line=~/\s+andrew\.speer\@/ && ($fn!~/ChangeLog$/i)) {
		push @match, "found andrew.speer@ email address $2\@isolutions.com.au $match";
	    }
	} $fn
    }
    


    #  If any matches found error out
    #
    if (@match) {

	return $self->_err(join($/, @match));

    }


    #  Done
    #
    return \undef;

}


#===================================================================================================

#  Private methods. Utility functions - use externally at own risk
#

sub _git_mtime_sync {


    #  Sync mtime of file to commit time if not modfied
    #
    my ($self, $fn, $commit_time)=@_;


    #  Is modifed ?
    #
    if (system($GIT_EXE, 'diff', '--exit-code', $fn) == 0) {


	#  No, update mtime
	#
	my $touch_or=File::Touch->new(

	    'mtime'	=>  $commit_time,

	   );
	$touch_or->touch($fn) ||
	    return $self->_err("error on touch of file $fn, $!");
	$self->_msg("synced file $fn to git commit time (%s)\n",
		    scalar(localtime($commit_time)));

	#  Return commit time
	#
	return $commit_time;

    }
    else {

	#  Has been modfied, return undef
	#
	$self->_msg("file $fn changed, kept mtime");
	return undef;

    }

}


sub _err {


    #  Quit on errors
    #
    my $self=shift();
    my $message=$self->_fmt("*error*\n\n" . ucfirst(shift()), @_);
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
    my $format=' @<<<<<<<<<<<<<<<<<<<<<< @<';
    my $message=sprintf(shift(), @_);
    chomp($message);
    $message=$Arg{'distname'} . ", $message" if ($Arg{'distname'});
    formline $format, $caller . ':', undef;
    $message=$^A . $message; $^A=undef;
    return $message;

}


sub _arg {

    #  Get args, does nothing but intercept distname for messages, convert to param
    #  hash
    #
    my $self=shift();
    @Arg{qw(NAME NAME_SYM DISTNAME DISTVNAME VERSION VERSION_SYM VERSION_FROM)}=@_;
    return wantarray ? (\%Arg, @_[7..$#_]) : \%Arg;

}


sub _caller {


    #  Return the method name of the caller
    #
    my $self=shift();
    my $caller=(split(/:/, (caller(shift() || 1))[3]))[-1];
    $caller=~s/^_//;
    return $caller;

}


__END__


=head1 NAME

ExtUtils::Git - Class to add git related targets to Makefile generated from perl Makefile.PL

=head1 SYNOPSIS

    perl -MExtUtils::Git=:all Makefile.PL
    make git_import
    make git_manicheck
    make git_ci
    make git_status

=head1 DESCRIPTION

ExtUtils::Git is a class that extends ExtUtils::MakeMaker to add git related
targets to the Makefile generated from Makefile.PL.

ExtUtils::Git will enforce various rules during module distribution, such as
not building a dist for a module before all components are checked in to
Git.  It will also not build a dist if the MANIFEST and Git ideas of what
are in the module are out of sync.


=head1 OVERVIEW

Create a normal module using h2xs (see L<h2xs>). Either put ExtUtils::Git
into an eval'd BEGIN block in your Makefile.PL, or build the Makefile.PL
with ExtUtils::Git as an included module.

=over 4

=item BEGIN block within Makefile.PL

A sample Makefile.PL may look like this:

        use strict;
        use ExtUtils::MakeMaker;

        WriteMakeFile (

                NAME    =>  'Acme::Froogle'
                ... MakeMaker options here

        );

        sub BEGIN {  eval('use ExtUtils::Git') }

eval'ing ExtUtils::Git within a BEGIN block allows user to build your module
even if they do not have a local copy of ExtUtils::Git.

=item Using as a module when running Makefile.PL

If you do not want any reference to ExtUtils::Git within your Makefile.PL,
you can build the Makefile with the following command:

        perl -MExtUtils::Git Makefile.PL

This will build a Makefile with all the ExtUtils::Git targets.

=back

=head1 IMPORTING INTO GIT

Once you have created the first draft of your module, and included
ExtUtils::Git into the Makefile.PL file in one of the above ways, you can
import the module into Git.  Simply do a

        make git_import

in the working directory. All files in the MANIFEST will be imported into
Git and a new Git repository will be created in the current working
directory.

=head1 ADDING OR REMOVING FILES WITHIN THE PROJECT

Once checked out you can work on your files as per normal. If you add or
remove a file from your module project you need to undertake the
corresponding action in git with a

        git add myfile.pm OR
        git remove myfile.pm

You must remember to add or remove the file from the MANIFEST, or
ExtUtils::Git will generate a error when you try to build the dist.  This is
by design - the contents of the MANIFEST file should mirror the active Git
files.

=head1 CHECKING IN MODIFICATIONS

Periodically you will want to check modifications into the Git repository.
If you are not planning to make a distribution at this time a normal

        git commit

will still work. As this is a stardard git check in, no checking of the
MANIFEST etc will be performed.

If you wish to build a distribution from the current project working
directory you should do a

        make git_ci

Doing a 'make git_ci' will undertake a check to ensure that the MANIFEST and
Git are in sync.  It will check modified files into Git, incrementing the
current module version.  In addition, it will then tag the repository with
the new version in the form 'Acme-Froogle_1.26'.  Thus at any time you can
checkout an earlier version of your module with a git command in the form of

        git checkout Acme-Froogle_1.26


=head1 OTHER MAKEFILE TARGETS

As well as 'make git_import' and 'make git_ci', the following other targets
are supported.  Many of these targets are called by the 'make git_ci'
process, but can be run standalone also

=over 4

=item make git_manicheck

Will check that MANIFEST and Git agree on files included in the project

=item make git_status

Will check that no project files have been modified since last checked in to
the repository.

=item make git_version

Will show the current version of the project in the working directory

=item make git_tag

Will tag files with current version. Not recommended for manual use

=back

=head1 COPYRIGHT

Copyright (C) 2008 Andrew Speer <andrew.speer@isolutions.com.au>. All rights
reserved.
