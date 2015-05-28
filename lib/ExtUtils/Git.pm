#
#  This file is part of ExtUtils::Git.
#
#  This software is copyright (c) 2015 by Andrew Speer <andrew.speer@isolutions.com.au>.
#
#  This is free software; you can redistribute it and/or modify it under
#  the same terms as the Perl 5 programming language system itself.
#
#  Full license text is available at:
#
#  <http://dev.perl.org/licenses/>
#


#  Augment Perl ExtUtils::MakeMaker functions
#
package ExtUtils::Git;


#  Pragma
#
use strict qw(vars);
use vars qw($VERSION);
use warnings;
no warnings qw(uninitialized);
sub BEGIN {local $^W=0}


#  External Packages
#
use ExtUtils::Git::Util;
use ExtUtils::Git::Constant;
use IO::File;
use File::Spec;
use ExtUtils::Manifest;
use ExtUtils::MM_Any;
use Data::Dumper;
use File::Temp;
use File::Copy;
use File::Grep qw(fdo);
use Git::Wrapper;
use Software::LicenseUtils;
use Software::License;
use Module::Extract::VERSION;
use PPI;
use Cwd;


#  Data Dumper formatting
#
$Data::Dumper::Indent=1;
$Data::Dumper::Terse=1;


#  Make ExtUtils::Manifest quiet
#
$ExtUtils::Manifest::Quiet=1;


#  Version information in a format suitable for CPAN etc. Must be
#  all on one line
#
$VERSION='1.172';


#  All done, init finished
#
1;


#===================================================================================================


sub import {    # no subsort


    #  Let MakeMaker (MM) Module handle import routines
    #
    require ExtUtils::Git::MM;
    goto &ExtUtils::Git::MM::import;

}


sub git_arg {

    #  Dump args
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    msg("args \n%s\n\n", Dumper($param_hr));
    return \undef;

}


sub git_autocopyright {


    #  Make sure copyright header is added to every file
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my ($license, $author, $name, $pm_to_inst_ar, $exe_files_ar)=
        @{$param_hr}{qw(LICENSE AUTHOR NAME TO_INST_PM_AR EXE_FILES_AR)};
    debug('in git_autocopyright');


    #  Get the license object
    #
    my @license_guess=Software::LicenseUtils->guess_license_from_meta_key($license);
    @license_guess ||
        return err ("unable to determine license from string $license");
    (@license_guess > 1) &&
        return err ("ambiguous license from string $license");
    my $license_guess=shift @license_guess;
    my $license_or=$license_guess->new({holder => $author});


    #  Open copyright header template
    #
    my $template_or=Text::Template->new(

        type   => 'FILE',
        source => $TEMPLATE_COPYRIGHT_FN,

    ) || return err ("unable to open template, $TEMPLATE_COPYRIGHT_FN $!");


    #  Fill in with out self ref as a hash
    #
    my $copyright=$template_or->fill_in(

        HASH => {
            name   => $name,
            notice => $license_or->notice(),
            url    => $license_or->url()
        },
        DELIMITERS => ['<:', ':>'],

    ) || return err ("unable to fill in template $TEMPLATE_COPYRIGHT_FN, $Text::Template::ERROR");
    debug("copyright $copyright");


    #  Add comment fields and a CR
    #
    $copyright=~s/^(.*)/\#  $1/mg;
    $copyright=~s/^\#\s+$/\#/mg;
    chomp($copyright); $copyright.="\n";


    #  Get manifest - only update files listed there
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();


    #  Load exclusion file
    #
    my $exclude_fn=File::Spec->catfile(cwd(), $GIT_AUTOCOPYRIGHT_EXCLUDE_FN);
    my $exclude_ar;
    if (-f $exclude_fn) {
        $exclude_ar=eval {
            do {$exclude_fn}
        };
        $exclude_ar ||
            return err ("unable to read $exclude_ar, $@");
    }
    my %exclude_fn=map {$_ => 1} @{$exclude_ar};


    #  Iterate across files to protect
    #
    foreach my $fn (@{$pm_to_inst_ar}, @{$exe_files_ar}) {


        #  Check for specific targets via env variable
        #
        if (my $fn_list=$ENV{'GIT_AUTOCOPYRIGHT'}) {
            next unless grep {$fn eq $_} split(/\s+/, $fn_list);
        }

        #unless (grep {$fn=~/$_/} @{$GIT_AUTOCOPYRIGHT_INCLUDE_AR}) {
        #    msg("skipping $fn: not in include filter");
        #    next;
        #}
        #  Check for exclusion;
        if (grep {$fn=~/$_/} @{$GIT_AUTOCOPYRIGHT_EXCLUDE_AR}) {
            msg("skipping $fn: matches exclude filter");
            next;
        }
        if ($exclude_fn{$fn}) {
            msg("skipping $fn: matches exclusion in $GIT_AUTOCOPYRIGHT_EXCLUDE_FN");
            next;
        }
        unless (exists $manifest_hr->{$fn}) {
            msg("skipping $fn: not in MANIFEST");
            next;
        }


        #  Open file for read
        #
        my $fh=IO::File->new($fn, O_RDONLY) ||
            return err ("unable to open file $fn, $!");


        #  Setup keywords we are looking for
        #
        my $keyword=$COPYRIGHT_KEYWORD;
        debug("keyword $keyword");
        my @header;


        #  Flag set if existing copyright notice detected
        #
        my $keyword_found_fg;


        #  Turn into array, search for delims
        #
        my ($lineno, @line)=0;
        while (my $line=<$fh>) {
            push @line, $line;
            debug("line $lineno, @line");
            push(@header, $lineno || 0) if $line=~/^#.*\Q$keyword\E/i;
            $lineno++;
        }


        #  Close
        #
        $fh->close();


        #  Only do cleanup of old copyright if copyright keyword was
        #  found in top x lines
        #
        if (defined($header[0]) && ($header[0] <= $COPYRIGHT_HEADER_MAX_LINES)) {


            #  Valid copyright block (probably) found. Set flag
            #
            debug("keyword found");
            $keyword_found_fg++;


            #  Start looks for start and end of header
            #
            for (my $lineno_header=$header[0]; $lineno_header < @line; $lineno_header++) {


                #  We are going forwards through file, as soon as we
                #  see a non comment line we quit
                #
                my $line_header=$line[$lineno_header];
                last unless $line_header=~/^#/;
                $header[1]=$lineno_header;


            }
            for (my $lineno_header=$header[0]; $lineno_header >= 0; $lineno_header--) {


                #  We are going backwards through the file, as soon as we
                #  see a non comment line we quit
                #
                my $line_header=$line[$lineno_header];
                last if $line_header=~/^#\!/;
                last unless ($line_header=~/^#/);
                $header[0]=$lineno_header;


            }

        }
        else {


            #  Just make top of file, unless first line is #! (shebang) shell
            #  meta
            #
            debug("keyword not found");
            if   ($line[0]=~/^#\!/) {@header=(1, 1)}
            else                    {@header=(0, 0)}


        }


        #  Only do update if no match
        #
        my $header_copyright=join('', @line[$header[0]..$header[1]]);
        debug("hc: $header_copyright, c: $copyright");
        if ($header_copyright ne $copyright) {


            #  Need to update. If delim found, need to splice out
            #
            msg "updating $fn\n";
            if ($keyword_found_fg) {


                #  Yes, found, so splice existing notice out
                #
                splice(@line, $header[0], ($header[1]-$header[0]+1));


            }
            else {


                #  Not found, add a copy of cr's to notice as a spacer this
                #  first time in. Take into account shebang lines.
                #
                #$copyright="\n" . $copyright if $header[0];
                $copyright.="\n" if (($line[0]=~/^#/) && $line[0] !~ /^#\!/);


            }


            #  Splice new notice in now
            #
            splice(@line, $header[0], 0, $copyright);


            #  Re-open file for write out
            #
            $fh=IO::File->new($fn, O_TRUNC | O_WRONLY) ||
                return err ("unable to open $fn, $!");
            print $fh join('', @line);
            $fh->close();

        }
        else {

            msg "checked $fn\n";

        }

    }

}


sub git_autolicense {


    #  Generate license file
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my ($license, $author)=@{$param_hr}{qw(LICENSE AUTHOR)};
    my @license_guess=Software::LicenseUtils->guess_license_from_meta_key($license);
    @license_guess ||
        return err ("unable to determine license from string $license");
    (@license_guess > 1) &&
        return err ("ambiguous license from string $license");
    my $license_guess=shift @license_guess;
    my $license_or=$license_guess->new({holder => $author});
    my $license_fh=IO::File->new($LICENSE_FN, O_WRONLY | O_TRUNC | O_CREAT) ||
        return err ("unable to open file $LICENSE_FN, $!");
    print $license_fh $license_or->fulltext();
    $license_fh->close();
    msg("generated $license_guess LICENSE file");


    #  Add to manifest and git if needed
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();
    unless ($manifest_hr->{$LICENSE_FN}) {
        ExtUtils::Manifest::maniadd({$LICENSE_FN => undef});
        my $git_or=$self->_git();
        $git_or->add($LICENSE_FN);
    }


}


sub git_branch_development {


    #  Branch
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my $git_or=$self->_git();


    #  Get current branch
    #
    my $branch=$self->_git_branch_current() ||
        return err ('unable to get current branch');
    if ($branch eq $GIT_BRANCH_MASTER) {
        unless (grep {/$GIT_BRANCH_DEVELOPMENT/} $git_or->branch()) {
            msg("creating branch $GIT_BRANCH_DEVELOPMENT");
            $git_or->branch($GIT_BRANCH_DEVELOPMENT);
        }
        msg("checkout $GIT_BRANCH_DEVELOPMENT");
        $git_or->checkout($GIT_BRANCH_DEVELOPMENT);
        msg("merge $GIT_BRANCH_DEVELOPMENT");
        $git_or->merge($GIT_BRANCH_DEVELOPMENT);
        msg('checkout complete');
        $self->git_version_increment(@_);
    }
    elsif ($branch eq $GIT_BRANCH_DEVELOPMENT) {
        msg("already on $GIT_BRANCH_DEVELOPMENT branch");
    }
    else {
        return err ("can only branch from $GIT_BRANCH_MASTER currently");
    }
}


sub git_branch_master {


    #   Merge current branch to master
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my $git_or=$self->_git();


    #  Get current branch
    #
    my $branch=$self->_git_branch_current() ||
        return err ('unable to get current branch');
    unless ($branch eq $GIT_BRANCH_MASTER) {
        msg("checkout $GIT_BRANCH_MASTER");
        $git_or->checkout("$GIT_BRANCH_MASTER");
        msg("merge $branch");
        $git_or->merge($branch);
        msg('checkout complete');
        $self->git_version_increment(@_);
    }
    else {
        return err ("can't merge while on $GIT_BRANCH_MASTER branch");
    }


}


sub git_commit {


    #  Commit modified file
    #
    my $self=shift();


    #  Do it
    #
    unless (system($GIT_EXE, 'commit', '-a') == 0) {
        return err ("error on git commit, $?");
    }


    #  All done
    #
    return \undef;


}


sub git_development {
    &git_branch_development(@_);
}


sub git_ignore {


    #  Init git repo. Most done in Makefile, just add .gitignore
    #
    my ($self, $param_hr)=(shift(), arg(@_));


    #  Add files to .gitignore
    #
    my $fh=IO::File->new($GIT_IGNORE_FN, O_WRONLY | O_TRUNC | O_CREAT) ||
        return err ("unable to open $GIT_IGNORE_FN, $!");


    #  Write them out
    #
    foreach my $fn (@{$GIT_IGNORE_AR}) {
        print $fh $fn, $/;
    }


    #  Ignore dists packed/unpacked here also
    #
    printf $fh "%s-*\n", $param_hr->{'DISTNAME'};


    #  Add the gitignore file itself
    #
    my $git_or=$self->_git();
    $git_or->add($GIT_IGNORE_FN);

}


sub git_import {


    #  Import all files in MANIFEST into Git.
    #
    my ($self, $param_hr)=(shift(), arg(@_));


    #  Check all files present
    #
    ExtUtils::Manifest::manicheck() &&
        return err ('MANIFEST manicheck error');


    #  Get the manifest
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();


    #  Remove the ChangeLog, META.yml etc. from the manifest - they are generated at distribution time, and
    #  is not tracked by Git
    #
    foreach my $fn_glob (@{$GIT_IGNORE_AR}) {
        foreach my $fn (glob($fn_glob)) {
            delete $manifest_hr->{$fn};
        }
    }


    #  Add remaining files from manfest
    #
    #}
    my $git_or=$self->_git();
    $git_or->add(keys %{$manifest_hr});


    #  All OK
    #
    msg('Git import successful');
    return \undef;


}


sub git_lint {


    #  Check for old CVS references (RCS keywords etc)
    #
    my ($self, $param_hr)=(shift(), arg(@_));


    #  Get the manifest
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();


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
            if ($line=~/copyright/i && (my @year=($line=~/\d{4}/g)) && ($fn !~ /LICENSE/)) {
                my $copyyear=$year[-1];
                my $thisyear=(localtime())[5]+1900;

                if (($copyyear < $thisyear)) {
                    push @match, "found old copyright notice ($copyyear) $match";
                }
            }
        }
        $fn
    }


    #  If any matches found error out
    #
    if (@match) {

        return err (join($/, @match));

    }


    #  Done
    #
    return \undef;

}


sub git_make {


    #  Remake makefile
    #
    system($MAKE_EXE);

}


sub git_manicheck {


    #  Checks that all files in the manifest are checked in to Git
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my $distname=$param_hr->{'DISTNAME'} ||
        return err ('unable to get distname');


    #  Get manifest
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();


    #  Check self-generated files (created when dist is made) or ignored files that are in MANIFEST and shouldn't be there
    #
    my $fail;
    {   my @test;
        foreach my $fn_glob (@{$GIT_IGNORE_AR}) {
            foreach my $fn (glob($fn_glob)) {
                push @test, $fn if exists $manifest_hr->{$fn};
            }
        }
        if (@test) {
            msg(
                "the following self-generated or ignored files are in MANIFEST: \n\n\%s\n",
                Dumper(\@test)
            );
            $fail++;
        }
    }


    #  Check manifest files present on file system
    #
    {   my %missing=map {$_ => 1} ExtUtils::Manifest::manicheck();

        #  Ignore files caught by above test
        foreach my $fn_glob (@{$GIT_IGNORE_AR}) {
            foreach my $fn (glob($fn_glob)) {
                delete $missing{$fn};
            }
        }
        if (my @missing=keys %missing) {
            msg(
                "the following files are in MANIFEST but missing from the file system: \n\n\%s\n",
                Dumper(\@missing)
            );
            $fail++;
        }
    }


    #  Read in all the Git files skipping any in MANIFEST.SKIP
    #
    my $maniskip_or=ExtUtils::Manifest::maniskip();
    my %git_manifest=map {$_ => 1} grep {!$maniskip_or->($_)} $self->_git->ls_files;


    #  Check for files in Git, but not in the manifest, or vica versa
    #
    {   my %test=%{$manifest_hr};
        map {delete $test{$_}} keys %git_manifest;
        foreach my $fn_glob (@{$GIT_IGNORE_AR}) {
            foreach my $fn (glob($fn_glob)) {
                delete $test{$fn};
            }
        }
        if (keys %test) {
            msg(
                "the following files are in MANIFEST but not in Git: \n\n%s\n",
                Dumper([keys %test]));
            $fail++;
        }
    }


    #  Now the vica-versa
    #
    {   my %test=%git_manifest;
        map {delete $test{$_}} keys %{$manifest_hr};
        foreach my $fn_glob (@{$GIT_IGNORE_AR}) {
            foreach my $fn (glob($fn_glob)) {
                delete $test{$fn};
            }
        }
        if (keys %test) {
            msg(
                "the following files are in Git but not in MANIFEST: \n\n%s\n",
                Dumper([keys %test]));
            $fail++;
        }
    }


    #  Check that ChangeLog etc. are not tracked by Git
    #
    {   my @test=grep {$git_manifest{$_}} @{$GIT_IGNORE_AR};
        if (@test) {
            msg(
                "the following files are self-generated and should not be tracked by Git: \n\n%s\n",
                Dumper(\@test));
            $fail++;
        }
    }


    #  All done
    #
    return $fail ? err ('MANIFEST check failed') : msg('Git and MANIFEST are in sync');

}


sub git_master {
    &git_branch_master(@_);
}


sub git_push {


    #  Push to all remotes
    #
    my ($self, $param_hr)=(shift(), arg(@_));


    #  Iterate through remote targets and add
    #
    my $git_or=$self->_git();
    my @remote=$git_or->remote('-v');
    my %remote;
    foreach my $remote (@remote) {
        my ($name, $repo, $method)=split(/\s+/, $remote);
        $remote{$name}=$repo if $method=~/\(push\)/;
    }
    foreach my $name (sort keys %remote) {
        my $repo=$remote{$name};
        msg("push refs to $name: $repo");
        $git_or->push($name,);
        msg(join($/, @{$git_or->ERR}));
        msg("push tags to $name: $repo");
        $git_or->push($name, '--tags');
        msg(join($/, @{$git_or->ERR}));
    }

}


sub git_remote {


    #  Add default remote git repositories
    #
    my ($self, $param_hr)=(shift(), arg(@_));


    #  Iterate through remote targets and add
    #
    my $git_or=$self->_git();
    my @remote=$git_or->remote('-v');
    my %remote;
    foreach my $remote (@remote) {
        my ($name, $repo)=split(/\s+/, $remote);
        $remote{$name}=$repo;
    }
    while (my ($name, $repo)=each %{$GIT_REMOTE_HR}) {
        my $repo_location=sprintf($repo, $param_hr->{'DISTNAME'});
        if (exists($remote{$name}) && ($remote{$name} ne $repo_location)) {

            #  Already exists - delete
            #
            msg("updating remote repo $name: $repo_location");
            $git_or->remote('remove', $name);
            $git_or->remote('add', $name, $repo_location);
        }
        elsif (!$remote{$name}) {
            msg("adding remote repo $name: $repo_location");
            $git_or->remote('add', $name, $repo_location);
        }
        else {
            msg("checking remote repo $name: $repo_location OK");
        }
    }

}


sub git_status {


    #  Checks that all files in the manifest checked in, and are not
    #  newer than the VERSION_FROM file.
    #
    my $self=shift();
    my $param_hr=arg(@_);
    my $version_from=$param_hr->{'VERSION_FROM'} ||
        return err ('unable to get version_from');


    #  Stat the master version file
    #
    my $version_from_mtime=(stat($version_from))[9] ||
        return err ("unable to stat file $version_from, $!");


    #  Get the manifest
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();


    #  Get list of modified files
    #
    my $git_modified_hr=$self->_git_modified();


    #  If any modfied file bail now
    #
    if (keys %{$git_modified_hr}) {
        my $err="The following files have been modified since last commit:\n";
        $err.=Data::Dumper::Dumper($git_modified_hr);
        return err ($err);
    }


    #  Array for files that may be newer than version_from file
    #
    my @modified_fn;


    #  All looks OK
    #
    msg("git files up-to-date");


    #  All OK
    #
    return \undef;

}


sub git_tag {


    #  Build unique tag for checked in files
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my $distname=$param_hr->{'DISTNAME'} ||
        return err ('unable to get distname');


    #  Read in version number, convers .'s to -
    #
    my $version=$self->git_version(@_) ||
        return err ('unable to get version number');


    #  Add distname
    #
    my $tag="${distname}_${version}";
    msg(qq[git tagging as "$tag"]);


    #  Run git program to update
    #
    #unless (system($GIT_EXE, 'tag', '-a', '-m', $tag, $tag) == 0) {
    #    return err("error on git tag, $?");
    #}
    my $git_or=$self->_git();
    $git_or->tag('-a', '-m', $tag, $tag);


    #  All done
    #
    return \undef;


}


sub git_version {


    #  Print current version from version_from file
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my $version_from=$param_hr->{'VERSION_FROM'} ||
        return err ('unable to get version_from file name');


    #  Get version from version_from file
    #
    my $version_git=eval {MM->parse_version(File::Spec->rel2abs($version_from))} ||
        return err ("unable to read version info from version_from file $version_from, $!");


    #  Display
    #
    msg("git version $version_git");


    #  Done
    #
    return $version_git;

}


sub git_version_increment {


    #  Increment the version of all package files
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my ($version_from_fn, $pm_to_inst_ar, $exe_files_ar)=
        @{$param_hr}{qw(VERSION_FROM TO_INST_PM_AR EXE_FILES_AR)};
    $version_from_fn ||
        return err ('unable to get version_from file name');


    #  Get current version
    #
    my $version=$self->git_version(@_) ||
        return err ("unable to get existing version from $version_from_fn");
    my @version=split(/\./, $version);
    my $version_new;


    #  Check branch and make alpha if not on master
    #
    unless ((my $branch=$self->_git_branch_current) eq $GIT_BRANCH_MASTER) {


        #  Get new alpha suffix
        #
        $version[-1]=~s/_.*//;
        $version[-1]++;
        my $suffix=sprintf('%08i', hex($self->_git_rev_parse_short()));


        #  Add _ to ver number
        #
        $version_new=join('.', @version);
        $version_new.="_$suffix";


        #  Check is different
        #
        if ($version_new eq $version) {
            msg("no git changes detected - version increment *NOT* performed.");
            return \undef;
        }

    }
    else {


        #  On master branch - are we promoting alpha, i.e. can we delete _ char ?
        #
        unless ($version[-1]=~s/_.*//) {

            #  No - just increment
            #
            $version[-1]++;

        }
        $version[-1]=sprintf('%03d', $version[-1]);
        $version_new=join('.', @version);

    }

    #  Get manifest - only update files listed there
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();


    #  Now update files
    #
    foreach my $fn ((grep {/\.p(m|l)$/} @{$pm_to_inst_ar}), @{$exe_files_ar}) {
        if (exists $manifest_hr->{$fn}) {
            msg("version update $fn");
            $self->git_version_update_file($fn, $version_new) ||
                return err ("unable to update file $fn");
        }
        else {
            msg("skipping $fn, not in MANIFEST");
        }
    }


    #  Done
    #
    return \undef;

}


sub git_version_reset {


    #  Reset the version of all package files
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my ($pm_to_inst_ar, $exe_files_ar, $version)=
        @{$param_hr}{qw(TO_INST_PM_AR EXE_FILES_AR VERSION)};
    my $version_new=$ENV{'GIT_VERSION_RESET'} || $version || '0.001';


    #  Get manifest - only update files listed there
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();


    #  Now update files
    #
    #foreach my $fn ((grep {/\.p(m|od|l)$/} @{$pm_to_inst_ar}), @{$exe_files_ar}) {
    foreach my $fn ((grep {/\.p(m|l)$/} @{$pm_to_inst_ar}), @{$exe_files_ar}) {
        if (exists $manifest_hr->{$fn}) {
            msg("version update $fn");
            $self->git_version_update_file($fn, $version_new, (my $force=1)) ||
                return err ("unable to update file $fn");
        }
        else {
            msg("skipping $fn, not in MANIFEST");
        }
    }


    #  Done
    #
    return \undef;
}


sub git_version_increment_commit {


    #  Update commit message after version bump
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my $version=$self->git_version(@_);
    my $git_or=$self->_git();
    $git_or->commit('-a', '-m', "VERSION increment: $version");

}


sub perlver {


    #  Use Perl::Minimumversion to find minimum Perl version required
    #
    my ($self, $param_hr)=(shift(), arg(@_));


    #  Try to load modules we need
    #
    eval {
        require Perl::MinimumVersion;
        1;
    } || return err ('cannot load module Perl::MinimumVersion');


    #  Get manifest - only test files in manifest
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();


    #  Get modules and exe files and iterate
    #
    my %perlver;
    my ($pm_to_inst_ar, $exe_files_ar)=
        @{$param_hr}{qw(TO_INST_PM_AR EXE_FILES_AR)};
    foreach my $fn ((grep {/\.p(m|od|l)$/} @{$pm_to_inst_ar}), @{$exe_files_ar}) {


        #  Skip LICENSE, non-Manifest files
        #
        next if ($fn eq $LICENSE_FN);
        next unless exists $manifest_hr->{$fn};
        my $pv_or=Perl::MinimumVersion->new($fn) ||
            return err ("unable to create new Perl::MinimumVersion object for file $fn, $!");
        my $v_or=$perlver{$fn}=$pv_or->minimum_version();
        msg("Perl::MinimumVersion for $fn: %s (%s)", $v_or->normal(), $v_or->numify());

    }


    #  Sort
    #
    my @perlver=sort {version->parse($b) <=> version->parse($a)} values %perlver;
    my $v_or=shift(@perlver) ||
        return err ('unable to determine minimum perl version');


    #  Done
    #
    msg("Perl::MinimumVersion result: %s (%s)", $v_or->normal(), $v_or->numify());
    return \undef;

}


sub kwalitee {


    #  Use to find minimum Perl version required
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my ($distvname, $dist_default, $suffix)=
        @{$param_hr}{qw(DISTVNAME DIST_DEFAULT_TARGET SUFFIX)};
    my %suffix=(
        tardist => "tar${suffix}",
        zip     => 'zip'
    );
    my $distvname_suffix=$suffix{$dist_default} ||
        return err ("unable to determine suffix for dist_default type: $dist_default");
    my $distvname_fn="${distvname}.${distvname_suffix}";
    msg("distvname $distvname_fn");


    #  Check file exists
    #
    unless (-f $distvname_fn) {

        #return err("unable to check distribution file $distvname_fn, file not present");
    }


    #  Load CPANTs modules
    #
    eval {
        require Module::CPANTS::Kwalitee;
        Module::CPANTS::Kwalitee->import();
    } || return err ('cannot load module Module::CPANTS::Kwalitee');
    eval {
        require Module::CPANTS::Analyse;
    } || return err ('cannot load module Perl::MinimumVersion');
    eval {
        require Module::CPANTS::SiteKwalitee;
    } || return err ('cannot load module Module::CPANTS::SiteKwalitee');


    #  Start CPANTS check
    #
    my $cpants_or=Module::CPANTS::Analyse->new(
        {
            dist => $distvname_fn
        });


    #  Add extra indicators
    #
    $cpants_or->mck(Module::CPANTS::SiteKwalitee->new);
    $cpants_or->run;


    #  Get results
    #
    my %error;
    my $kwalitee_hr=$cpants_or->d->{'kwalitee'};
    my $indicator_ar=$cpants_or->mck->get_indicators;
    foreach my $indicator_hr (@{$indicator_ar}) {
        unless ($kwalitee_hr->{my $name=$indicator_hr->{'name'}}) {
            next if $indicator_hr->{'needs_db'};
            next if $indicator_hr->{'is_experimental'};
            $error{$name}={
                error  => $indicator_hr->{'error'},
                remedy => $indicator_hr->{'remedy'}
            };
            msg("fail kwalitee test: $name");
        }
    }


    #  Return
    #
    if (keys %error) {
        return err (Dumper(\%error));
    }
    else {
        return msg("Kwalitee check OK");
    }

}


sub git_version_update_file {


    #  Change file version number
    #
    my ($self, $fn, $version_new, $force)=@_;


    #  Get existing version
    #
    my (undef, undef, $version_old, undef, $lineno)=Module::Extract::VERSION->parse_version_safely($fn);
    $version_old ||
        return err ("unable to determine current version number in file $fn");
    $lineno ||
        return err ("unable to line number of version string in file $fn");


    #  Check old version not newer than proposed version number
    #
    if ((version->parse($version_old) > version->parse($version_new)) && !$force) {
        return err ("version of file $fn ($version_old) is later than proposed version ($version_new)");
    }


    #  Open file for read + tmp file handle
    #
    my $old_fh=IO::File->new($fn, O_RDONLY) ||
        return err ("unable to open file '$fn' for read, $!");
    my $tmp_fh=File::Temp->new(UNLINK => 0) ||
        return err ('unable to create temporary file');
    my $tmp_fn=$tmp_fh->filename();


    #  Seek to version string
    #
    for (1..($lineno-1)) {print $tmp_fh scalar <$old_fh>}
    my $line_version=<$old_fh>;
    unless ($line_version=~s/\Q$version_old\E/$version_new/) {
        return err ("unable to substitute version string in $line_version");
    }
    print $tmp_fh $line_version;


    #  Finish wrinting file
    #
    while (my $line=<$old_fh>) {
        print $tmp_fh $line
    }
    $old_fh->close();
    $tmp_fh->close();


    #  Overwrite existing file
    #
    File::Copy::move($tmp_fn, $fn) ||
        return err ("unable to replace $fn with newer version, $!");


    #  All OK
    #
    msg("updated $fn from version $version_old to $version_new");


    #  Done
    #
    return \undef;

}


sub docbook2pod {


    #  Convert XML files to POD and append
    #
    my ($self, $param_hr)=(shift(), arg(@_));


    #  Try to load modules we need
    #
    eval {
        require Perl::MinimumVersion;
        1;
    } || return err ('cannot load module Perl::MinimumVersion');


    #  Get manifest - only test files in manifest
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();


    #  Look for all XML files
    #
    my @manifest_xml_fn=grep {/\.xml$/} keys %{$manifest_hr};
    msg('found following xml files for conversion %s', Dumper(\@manifest_xml_fn));


    #  Load
    #
    my $dn=File::Temp->newdir(CLEANUP => 1) ||
        return err ("unable to create new temp dir, $!");
    msg("tmp_dn $dn");
    eval {
        require IPC::Cmd;
        IPC::Cmd->import(qw(can_run));
        require IPC::Run3;
        IPC::Run3->import(qw(run3));
        1;
    } || return err ('unable to load IPC::Run3');


    #  Check for xlstproc;
    #
    use File::Find;
    my $xsltproc_exe=can_run('xsltproc') ||
        return err ('can\'t find xlstproc installed on system');
    my $man_exe=can_run('groff') ||
        return err ('can\'t find man installed on system');
    my $rman_exe=can_run('rman') ||
        return err ('can\'t find rman installed on system');


    #  Process files
    #
    foreach my $fn (@manifest_xml_fn) {

        my @command=(
            $xsltproc_exe,
            '-o',
            "$dn/",
            '/usr/share/sgml/docbook/xsl-stylesheets-1.78.1/manpages/docbook.xsl',
            $fn
        );
        run3(\@command, \undef, \undef, \undef) ||
            return err ('unable to run3 %s', Dumper(\@command));
        if ((my $err=$?) >> 8) {
            return err ("error $err on run3 of: %s", Dumper(\@command));
        }
        my $cwd=cwd();
        my $wanted_cr=sub {

            msg("process $File::Find::name");
            return unless -f $File::Find::name;
            my $tmp_fh=File::Temp->new(UNLINK => 1) ||
                return err ("unable to create new temp file, $!");
            my $tmp_fn=$tmp_fh->filename();

            my @command=(
                $man_exe,
                '-e',
                '-mandoc',
                '-Tascii',
                $File::Find::name,
            );
            my $stdout;

            #run(command => \@command, verbose=>1, buffer=>\$stdout);
            use IPC::Run3;
            my $pid=run3(\@command, undef, $tmp_fh, \undef);
            $tmp_fh->close();
            msg("fn $tmp_fn");
            my $pod;
            @command=(
                $rman_exe,
                '-f',
                'pod',
                $tmp_fn
            );
            $pid=run3(\@command, undef, \$pod, \undef);

            #@print "pid $pid, stdout $tmp_fn, pod $pod";
            $pod ||
                return err ('unable to generate POD file');

            #msg("pod $pod");

            #  Get target file name;
            #
            (my $target_fn=$fn)=~s/\.xml$//;
            msg("target fn $target_fn");
            use Cwd qw(cwd);
            use File::Spec;
            $target_fn=File::Spec->catfile($cwd, $target_fn);
            msg("on target $target_fn");
            return unless (-f $target_fn);

            my $ppi_doc_or=PPI::Document->new($target_fn);
            my $ppi_pod_or=PPI::Document->new(\$pod);

            #msg $ppi_pod_or->print();

            #  Prune existing POD
            #
            $ppi_doc_or->prune('PPI::Token::Pod');
            if (my $ppi_doc_end_or=$ppi_doc_or->find_first('PPI::Statement::End')) {
                $ppi_doc_end_or->prune('PPI::Token::Comment');
                $ppi_doc_end_or->prune('PPI::Token::Whitespace');
            }
            else {
                $ppi_doc_or->add_element(PPI::Token::Separator->new('__END__'));
                $ppi_doc_or->add_element(PPI::Token::Whitespace->new("\n"));
            }

            #$ppi_doc_or->add_element(@{$ppi_pod_or->find('PPI::Token::Pod')});
            $ppi_doc_or->add_element($ppi_pod_or);
            $ppi_doc_or->save('/tmp/as.pl');

            msg("compelete update $target_fn");

        };
        find($wanted_cr, $dn);
    }


}


#===================================================================================================

#  Private methods. Utility functions - use externally at own risk
#


sub _git {

    my $git_or=Git::Wrapper->new(cwd(), 'git_binary' => $GIT_EXE) ||
        return err ('unable to get Git::Wrapper object');

}


sub _git_branch_current {

    my $self=shift();
    my $git_or=$self->_git();
    foreach my $branch ($git_or->branch()) {
        if ($branch=~/^\*\s+(.*)/) {
            return $1;
        }
    }

}


sub _git_modified {


    #  Return a hash of modified files
    #
    my $self=shift();
    my $git_or=$self->_git();
    my %git_modified;
    if (my $statuses_or=$git_or->status()) {
        foreach my $status_or ($statuses_or->get('changed')) {
            my $fn=$status_or->to() || $status_or->from();
            my $mode=$status_or->mode();
            $git_modified{$fn}=$mode;
        }
    }
    return \%git_modified;

}


sub _git_rev_parse_short {

    my ($self, $rev)=@_;
    $rev ||= 'HEAD';
    my $git_or=$self->_git();
    return ($git_or->rev_parse('--short', $rev))[0];

}


sub debug {
    CORE::printf(shift() . "\n", @_) if $ENV{'EXTUTILS-GIT_DEBUG'};
}


1;
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

=head1 LICENSE

This software is copyright (c) 2015 by Andrew Speer <andrew.speer@isolutions.com.au>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

Full license text is available at:

<http://dev.perl.org/licenses/>
