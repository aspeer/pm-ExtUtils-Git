#  This file is part of ExtUtils::Git.
#  
#  This software is copyright (c) 2014 by Andrew Speer <andrew.speer@isolutions.com.au>.
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


#  Compiler Pragma
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
use File::Touch;
use File::Grep qw(fdo);
use Git::Wrapper;
use Software::LicenseUtils;
use Software::License;
use Cwd;


#  Version information in a formate suitable for CPAN etc. Must be
#  all on one line
#
$VERSION='1.158_106129258';


#  All done, init finished
#
1;


#===================================================================================================


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
    foreach my $fn (@{$GIT_IGNORE_AR}) {
        delete $manifest_hr->{$fn};
    }


    #  Add remaining files from manfest
    #
    #}
    my $git_or=$self->_git();
    $git_or->add(keys %{$manifest_hr});


    #  All OK
    #
    msg('git import successful');
    return \undef;


}


sub git_manicheck {


    #  Checks that all files in the manifest are checked in to Git
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my $distname=$param_hr->{'DISTNAME'} ||
        return err ('unable to get distname');


    #  Check manifest files present on file system
    #
    my $fail;
    my @missing=ExtUtils::Manifest::manicheck();
    if (@missing) {
        msg(
            "the following files are in the manifest but missing from the file system: \n\n\%s\n\n",
            Dumper(\@missing)
            )
    }


    #  Get manifest
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();


    #  Read in all the Git files skipping any in MANIFEST.SKIP
    #
    my $maniskip_or=ExtUtils::Manifest::maniskip();
    my %git_manifest=map {$_ => 1} grep {!$maniskip_or->($_)} $self->_git->ls_files;


    #  Check for files in Git, but not in the manifest, or vica versa
    #
    my %test0=%{$manifest_hr};
    map {delete $test0{$_}} keys %git_manifest;
    if (keys %test0) {
        msg(
            "the following files are in the manifest but not in git: \n\n%s\n\n",
            Dumper([keys %test0]));
        $fail++;
    }
    my %test1=%git_manifest;
    map {delete $test1{$_}} keys %{$manifest_hr};
    if (keys %test1) {
        msg(
            "the following files are in git but not in the manifest: \n\n%s\n\n",
            Dumper([keys %test1]));
        $fail++;
    }


    #  All done
    #
    return $fail ? err ('MANIFEST check failed') : msg('MANIFEST and git in sync');

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


sub git_version_increment {


    #  Increment the VERSION_FROM file
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my $version_from_fn=$param_hr->{'VERSION_FROM'} ||
        return err ('unable to get version_from file name');


    #  Get current version
    #
    my $version=$self->git_version(@_) ||
        return err ("unable to get existing version from $version_from_fn");

    #$version=(split /_/, $version)[0];
    my @version=split(/\./, $version);
    $version[-1]=~s/_.*//;

    #$version[-1]++;
    #$version[-1]=sprintf('%03d', $version[-1]);
    #my $version_new=join('.', @version);
    my $version_new;


    #  Check branch and make alpha if not on master
    #
    unless ((my $branch=$self->_git_branch) eq 'master') {


        #  Get new alpha suffix
        #
        my $suffix=hex($self->_git_rev_parse_short());


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


        #  On master branch
        #
        $version[-1]++;
        $version[-1]=sprintf('%03d', $version[-1]);
        $version_new=join('.', @version);

    }


    #  Open file handles for read and write
    #
    my $old_fh=IO::File->new($version_from_fn, O_RDONLY) ||
        return err ("unable to open file '$version_from_fn' for read, $!");
    my $new_fh=IO::File->new("$version_from_fn.tmp", O_WRONLY | O_CREAT | O_TRUNC) ||
        return err ("unable to open file '$version_from_fn.tmp' for write, $!");


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
        return err ("unable to replace $version_from_fn with newer version, $!");


    #  All OK
    #
    msg("updated $version_from_fn from version $version to $version_new");


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


sub git_version_increment_files {


    #  Check for files that have changed and edit to update version numvers
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my $version_from_fn=$param_hr->{'VERSION_FROM'} ||
        return err ('unable to get version_from file name');


    #  Get manifest.
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();
    use File::Temp;
    use File::Copy;


    #  Get list of modified files
    #
    #my %git_modified=map {chomp($_); $_ => 1} split($/, qx($GIT_EXE ls-files --modified));
    my $git_modified_hr=$self->_git_modified();


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
            return err ("revision too high ($revision) - update release ?");
        }

        #print "$fn, $revision\n";

        my $temp_fh=File::Temp->new() ||
            return err ("unable to open tempfile, $!");
        my $temp_fn=$temp_fh->filename() ||
            return err ("unable to obtain tempfile name from fh $temp_fh");
        my $fh=IO::File->new($fn) ||
            return err ("unable to open file $fn for readm $!");
        my ($update_fg, $version_seen_fg);
        while (my $line=<$fh>) {

            if ($line=~/^\$VERSION\s*=\s*'(\d+)\.(\d+)'/ && !$version_seen_fg && $git_modified_hr->{$fn}) {
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
                    return err ("error - $fn existing version $1.$2 > proposed version $1.$revision !");
                }
                elsif ($2 == $revision) {
                    print "skipping update of $fn, version $1.$2 identical to proposed rev $1.$revision\n";
                }
            }
            elsif ($line=~/^\$VERSION/ && $line !~ /^\$VERSION\s*=\s*'\d+\.\d+'/ && !$version_seen_fg) {
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
                return err ("error moving file $temp_fn=>$fn, $!")
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


sub git_commit0 {


    #  Commit modified file
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


    #  Run git program to update
    #
    unless (system($GIT_EXE, 'commit', qw(-a -e -m), qq[Tag: $tag]) == 0) {
        return err ("error on git commit, $?");
    }


    #  All done
    #
    return \undef;


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


sub git_version_dump {


    #  Get self ref
    #
    my ($self, $param_hr)=(shift(), arg(@_));


    #  Get version we are saving
    #
    my $have_version=$self->git_version(@_);


    #  Get location of Dumper file, load up module, version info
    #  that we are processing, save again
    #
    my $dump_fn=File::Spec->catfile($DUMPER_FN);
    my $dump_hr=do($dump_fn);
    my %dump=(
        $param_hr->{'NAME'} => $have_version
    );


    #  Check if we need not update
    #
    my $dump_version=$dump_hr->{$param_hr->{'NAME'}};
    if ("v$dump_version" ne "v$have_version") {

        my $dump_fh=IO::File->new($dump_fn, O_WRONLY | O_TRUNC | O_CREAT) ||
            err ("unable to open file $dump_fn, $!");
        binmode($dump_fh);
        $Data::Dumper::Indent=1;
        print $dump_fh (Data::Dumper->Dump([\%dump], []));
        $dump_fh->close();
        msg('git version dump complete');


    }
    else {


        #  Message
        #
        msg('git version dump file up-to-date');


    }


    #  Done
    #
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
            if ($line=~/REVISION/) {
                push @match, "found obsolete REVISION keyword $match";
            }

            #if ($line=~/copyright.*?(\d{4})*\s*(,|-)*\s*(\d{4})/i && ($fn!~/LICENSE/)) {
            if ($line=~/copyright/i && (my @year=($line=~/\d{4}/g)) && ($fn !~ /LICENSE/)) {
                my $copyyear=$year[-1];
                my $thisyear=(localtime())[5]+1900;

                #print "cr match $copyyear\n";
                if (($copyyear < $thisyear)) {
                    push @match, "found old copyright notice ($copyyear) $match";
                }
            }
            if ($line=~/copyright\s+\(/i && ($line=~/andrew/i) && $line !~ /Copyright \(C\) \d{4}-\d{4} Andrew Speer.*?(\<andrew\@webdyne\.org>)?/ && ($fn !~ /LICENSE$/) && ($fn !~ /ChangeLog$/)) {
                push @match, "inconsistant copyright format $match";
            }
            if ($line=~/\s+(.*?)\@isolutions\.com\.au/ && ($fn !~ /ChangeLog$/i)) {
                push @match, "found isolutions email address $2\@isolutions.com.au $match";
            }
            if ($line=~/\s+andrew\.speer\@/ && ($fn !~ /ChangeLog$/i)) {
                push @match, "found andrew.speer@ email address $2\@isolutions.com.au $match";
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


sub git_merge {


    #   Merge current branch to master
    #
    my $self=shift();
    my $git_or=$self->_git();


    #  Get current branch
    #
    msg('run');
    my $branch=$self->_git_branch() ||
        return err ('unable to get current branch');
    unless ($branch eq 'master') {
        msg('checkout master');
        $git_or->checkout('master');
        msg('checkout merger');
        $git_or->merge($branch);
        msg('checkout complete');
    }
    else {
        return err ('cant merge while on master branch');
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
    printf $fh "/%s-*\n", $param_hr->{'DISTNAME'};


    #  Add the gitignore file itself
    #
    my $git_or=$self->_git();
    $git_or->add($GIT_IGNORE_FN);

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


sub git_autocopyright {


    #  Make sure copyright header is added to every file
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my ($license, $author, $name, $pm_to_inst_ar)=@{$param_hr}{qw(LICENSE AUTHOR NAME TO_INST_PM_AR)};


    #  Get the license object
    #
    my @license_guess=Software::LicenseUtils->guess_license_from_meta_key($license);
    @license_guess ||
        return err ("unable to determine license from string $license");
    (@license_guess > 1) &&
        return err ("ambiguous license from string $license");
    my $license_guess=shift @license_guess;
    my $license_or=$license_guess->new({holder => $author});


    #  Open stuff it into template
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


    #  Add comment fields
    #
    $copyright=~s/^(.*)/\#  $1/mg;


    #  Get manifest - only update files listed there
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();


    #  Iterate across files to protect
    #
    foreach my $fn (@{$pm_to_inst_ar}) {


        #  Skip unless matches filter for files to add copyright header to
        #
        unless (grep {$fn=~/$_/} @{$GIT_AUTOCOPYRIGHT_INCLUDE_AR}) {
            msg("skipping $fn: not in include filter");
            next;
        }
        if (grep {$fn=~/$_/} @{$GIT_AUTOCOPYRIGHT_EXCLUDE_AR}) {
            msg("skipping $fn: matches exclude filter");
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
        my @header;


        #  Flag set if existing copyright notice detected
        #
        my $keyword_found_fg;


        #  Turn into array, search for delims
        #
        my ($lineno, @line)=0;
        while (my $line=<$fh>) {
            push @line, $line;
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
            $keyword_found_fg++;


            #  Start looks for start and end of header
            #
            for (my $lineno_header=$header[0]; $lineno_header < @line; $lineno_header++) {


                #  We are going backwards through the file, as soon as we
                #  see something we quit
                #
                my $line_header=$line[$lineno_header];
                last unless $line_header=~/^#/;
                $header[1]=$lineno_header;


            }
            for (my $lineno_header=$header[0]; $lineno_header >= 0; $lineno_header--) {


                #  We are going backwards through the file, as soon as we
                #  see something we quit
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
            if   ($line[0]=~/^#\!/) {@header=(1, 1)}
            else                    {@header=(0, 0)}


        }


        #  Only do update if md5's do not match
        #
        my $header_copyright=join('', @line[$header[0]..$header[1]]);
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
                #  first time in
                #
                $copyright="\n" . $copyright if $header[0];
                $copyright.="\n";


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


sub git_make {


    #  Remake makefile
    #
    system($MAKE_EXE);

}


#===================================================================================================

#  Private methods. Utility functions - use externally at own risk
#


sub _git_mtime_sync0 {


    #  Sync mtime of file to commit time if not modfied
    #
    my ($self, $fn, $commit_time)=@_;


    #  Is modifed ?
    #
    if (system($GIT_EXE, 'diff', '--exit-code', $fn) == 0) {


        #  No, update mtime
        #
        my $touch_or=File::Touch->new(

            'mtime' => $commit_time,

        );
        $touch_or->touch($fn) ||
            return err ("error on touch of file $fn, $!");
        msg(
            "synced file $fn to git commit time (%s)\n",
            scalar(localtime($commit_time)));

        #  Return commit time
        #
        return $commit_time;

    }
    else {

        #  Has been modfied, return undef
        #
        msg("file $fn changed, kept mtime");
        return;

    }

}


sub _git_modified0 {


    #  Return a hash of modified files
    #
    my %git_modified;
    foreach my $status (split($/, qx($GIT_EXE status --porcelain))) {
        my ($flags, $fn)=($status=~/^(.{2})\s+(.*)/);
        $flags=~s/^\s*//;
        $flags=~s/\s*$//;
        next if $flags eq '??';
        $git_modified{$fn}=$flags;
    }
    return \%git_modified;


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


sub _git {

    my $git_or=Git::Wrapper->new(cwd(), 'git_binary' => $GIT_EXE) ||
        return err ('unable to get Git::Wrapper object');

}


sub _git_run {

    my $self=shift();
    my $git_or=$self->_git();
    return [$git_or->RUN(@_)];

}


sub _git_branch {

    my $self=shift();
    my $git_or=$self->_git();
    foreach my $branch ($git_or->branch()) {
        if ($branch=~/^\*\s+(.*)/) {
            return $1;
        }
    }

}


sub _git_rev_parse_short {

    my ($self, $rev)=@_;
    $rev ||= 'HEAD';
    my $git_or=$self->_git();
    return ($git_or->rev_parse('--short', $rev))[0];

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

=head1 COPYRIGHT

Copyright (C) 2008 Andrew Speer <andrew.speer@isolutions.com.au>. All rights
reserved.
