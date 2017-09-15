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
use ExtUtils::Manifest qw(maniread maniadd);
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
$VERSION='1.174';


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


sub git_autocopyright_pm {


    #  Make sure copyright header is added to every file
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my ($license, $author, $name, $pm_to_inst_ar, $exe_files_ar)=
        @{$param_hr}{qw(LICENSE AUTHOR NAME TO_INST_PM_AR EXE_FILES_AR)};
    debug('in git_autocopyright');


    #  Generate copyright
    #
    my $copyright=$self->copyright_generate($license, $author, $name) ||
        return err ("unable to generate copyright from license $license");


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
    my $exclude_fn_hr=$self->copyright_exclude_fn_hr($GIT_AUTOCOPYRIGHT_EXCLUDE_FN) ||
        return err ();


    #  Iterate across files to protect
    #
    foreach my $fn (@{$pm_to_inst_ar}, @{$exe_files_ar}) {


        #  Check for exclusions and skip;
        #
        msg("considering $fn");
        if (grep {$fn=~/$_/} @{$GIT_AUTOCOPYRIGHT_EXCLUDE_AR}) {
            msg("skipping $fn: matches exclude filter");
            next;
        }
        if ($exclude_fn_hr->{$fn}) {
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
        my @keyword=@{$COPYRIGHT_KEYWORD_AR};
        debug('keyword %s', Dumper(\@keyword));
        my @header;


        #  Flag set if existing copyright notice detected
        #
        my $keyword_found_fg;


        #  Turn into array, search for delims
        #
        my ($lineno, @line)=0;
        while (my $line=<$fh>) {
            push @line, $line;
            foreach my $keyword (@keyword) {
                debug("line $lineno, @line");
                if ($line=~/^#.*\Q$keyword\E/i) {
                    push(@header, $lineno || 0);
                    last;
                }
            }
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
            msg("copyright not found: $fn");


        }


        #  Only do update if no match
        #
        my $header_copyright=join('', @line[$header[0]..$header[1]]);
        debug("hc: $header_copyright, c: $copyright");
        if ($header_copyright ne $copyright) {


            #  Need to update. If delim found, need to splice out
            #
            msg "copyright updated: $fn";
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

            msg "copyright OK: $fn";

        }

    }

}


sub copyright_generate {


    #  Get params needed to generate copyright
    #
    my ($self, $license, $author, $name)=@_;


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


    #  Add CR and return
    #
    chomp($copyright); $copyright.="\n";
    return $copyright;


}


sub copyright_exclude_fn_hr {

    #  Load copyright exclusion file
    #
    my ($self, $fn)=@_;


    #  Load exclusion file
    #
    my $exclude_fn=File::Spec->catfile(cwd(), $fn);
    my $exclude_ar;
    if (-f $exclude_fn) {
        $exclude_ar=eval {
            do {$exclude_fn}
        };
        $exclude_ar ||
            return err ("unable to read $exclude_ar, $@");
    }
    my %exclude_fn=map {$_ => 1} @{$exclude_ar};


    #  Done, return hash ref
    #
    return \%exclude_fn;

}


sub git_autocopyright_pod {


    #  Make sure copyright section is updated in POD
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my ($license, $author, $name, $pm_to_inst_ar, $exe_files_ar)=
        @{$param_hr}{qw(LICENSE AUTHOR NAME TO_INST_PM_AR EXE_FILES_AR)};
    debug('in git_autocopyright');


    #  Generate copyright
    #
    my $copyright=$self->copyright_generate($license, $author, $name) ||
        return err ("unable to generate copyright from license $license");


    #  Get manifest - only update files listed there
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();
    my @fn=grep {/\.pod$/} keys %{$manifest_hr};


    #  Load exclusion file
    #
    my $exclude_fn_hr=$self->copyright_exclude_fn_hr($GIT_AUTOCOPYRIGHT_EXCLUDE_FN) ||
        return err ();


    #  Iterate across files to protect
    #
    foreach my $fn (@{$pm_to_inst_ar}, @{$exe_files_ar}, @fn) {


        #  Check for exclusion;
        msg("considering $fn");
        if (grep {$fn=~/$_/} @{$GIT_AUTOCOPYRIGHT_EXCLUDE_POD_AR}) {
            msg("skipping $fn: matches exclude filter");
            next;
        }
        if ($exclude_fn_hr->{$fn}) {
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
        my @keyword=@{$COPYRIGHT_KEYWORD_AR};
        debug('keyword %s', Dumper(\@keyword));
        my @header;


        #  Flag set if existing copyright notice detected
        #
        my $keyword_found_fg;


        #  Turn into array, search for keyword
        #
        my ($lineno, @line, $headno)=0;
        while (my $line=<$fh>) {
            push @line, $line;

            #debug("line $lineno, @line");
            foreach my $keyword (@keyword) {
                if ($line=~/^=head(\d+)\s+.*\Q$keyword\E/i) {
                    push(@header, $lineno || 0);
                    $headno=$1;
                    last;
                }
            }
            $lineno++;
        }
        debug("headno: $headno lineno $lineno. %s", Dumper(\@header));


        #  Close
        #
        $fh->close();


        #  Only do cleanup of old copyright if copyright section was found
        #
        if (defined($header[0])) {


            #  Valid copyright block (probably) found. Set flag
            #
            debug("keyword found");
            $keyword_found_fg++;


            #  Start looks for start and end of header
            #
            for (my $lineno_header=$header[0]+1; $lineno_header <= @line; $lineno_header++) {


                #  We are going forwards through file, as soon as we
                #  see a non comment line we quit
                #
                my $line_header=$line[$lineno_header];
                last if $line_header=~/^=head/;
                last if $line_header=~/^=cut/;
                $header[1]=$lineno_header;

            }
            $header[1] ||= @line;
            debug('header[0]:%s, header[1]:%s', @header);

        }
        else {


            # No match found. Skip
            #
            msg("copyright section not found: $fn");
            next;

        }


        #  Massage copyright with POD header, primitive link conversion
        #
        my $copyright_insert=sprintf($COPYRIGHT_HEADER_POD, $headno) . $copyright;
        $copyright_insert=~s/^\s*<http/L<http/m;


        #  Only do update if no match
        #
        my $header_copyright=join('', @line[$header[0]..$header[1]]);
        debug("hc: $header_copyright, c: $copyright_insert");
        if ($header_copyright ne $copyright_insert) {


            #  Need to update. If delim found, need to splice out
            #
            msg "copyright updated: $fn";
            if ($keyword_found_fg) {


                #  Yes, found, so splice existing notice out
                #
                debug('splicing out');
                splice(@line, $header[0], ($header[1]-$header[0]+1));


            }


            #  Splice new notice in now
            #
            splice(@line, $header[0], 0, $copyright_insert);


            #  Re-open file for write out
            #
            $fh=IO::File->new($fn, O_TRUNC | O_WRONLY) ||
                return err ("unable to open $fn, $!");
            print $fh join('', @line);
            $fh->close();

        }
        else {

            msg "copyright OK: $fn";

        }

    }

}


sub copyright_generate_xml {

    #  Generate XML::Twig copyright section
    #
    my ($self, $copyright, $section_tag)=@_;

    my $copyright_xml_or=XML::Twig::Elt->new($section_tag);
    XML::Twig::Elt->new('title', $COPYRIGHT_HEADER)->paste(
        'last_child',
        $copyright_xml_or
    );

    my @para;
    foreach my $line (split("\n", $copyright)) {
        if ($line=~/^\s*$/ && @para) {
            my $para_xml_or=XML::Twig::Elt->new('para', @para);
            $para_xml_or->paste('last_child', $copyright_xml_or);
            undef @para;
        }
        else {
            push @para, $line;;
        }    
    }
    if (@para) {
        my $para_xml_or=XML::Twig::Elt->new('para', @para);
        $para_xml_or->paste('last_child', $copyright_xml_or);
    }
    return $copyright_xml_or

}


sub git_autocopyright_xml {


    #  Make sure copyright section is updated in XML
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my ($license, $author, $name, $pm_to_inst_ar, $exe_files_ar)=
        @{$param_hr}{qw(LICENSE AUTHOR NAME TO_INST_PM_AR EXE_FILES_AR)};
    debug('in git_autocopyright');
    

    #  Need the XML::Twig module
    #
    eval {
        require XML::Twig;
        1;
    } || return err("error loading module XML::Twig, $@");


    #  Generate copyright
    #
    my $copyright=$self->copyright_generate($license, $author, $name) ||
        return err ("unable to generate copyright from license $license");
    

    #  Get manifest - only update files listed there
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();


    #  Load exclusion file
    #
    my $exclude_fn_hr=$self->copyright_exclude_fn_hr($GIT_AUTOCOPYRIGHT_EXCLUDE_FN) ||
        return err ();


    #  Iterate across files to protect
    #
    foreach my $fn (grep {/\.xml$/} keys %{$manifest_hr}) {


        #  Start processing
        #
        msg("considering $fn");


        #  Check for exclusion;
        if (grep {$fn=~/$_/} @{$GIT_AUTOCOPYRIGHT_EXCLUDE_XML_AR}) {
            msg("skipping $fn: matches exclude filter");
            next;
        }
        if ($exclude_fn_hr->{$fn}) {
            msg("skipping $fn: matches exclusion in $GIT_AUTOCOPYRIGHT_EXCLUDE_FN");
            next;
        }
        unless (exists $manifest_hr->{$fn}) {
            msg("skipping $fn: not in MANIFEST");
            next;
        }
        
        
        #  Subroutine to count section/refsections we see
        #
        my @section;
        my $section_cr=sub {
            my ($twig_or, $elt_or)=@_;
            my $title=$elt_or->field('title');
            foreach my $keyword (@{$COPYRIGHT_KEYWORD_AR}) {
                if ($title=~/\Q$keyword\E/i) {
                    push @section, $elt_or;
                    last;
                }
            }
        };


        #  Parse the file
        #
        my $twig_or=XML::Twig->new(
            TwigHandlers=> { section=>$section_cr, refsection=>$section_cr },

        );
        $twig_or->parsefile($fn);
        
        
        #  Did we find copyright section ? If not skip.
        #
        unless (@section) {
            msg("copyright section not found: $fn");
            next;
        }
        

        #  Get type of Docbook, article or refentry
        #
        my $elt_or=$twig_or->first_elt;
        my $doctype=$elt_or->name;
        my $section_type={
            article     => 'section',
            refentry    => 'refsection',
        }->{$doctype} ||
            return err("unable to get section type for Docbook template $doctype");
        msg("doctype of $doctype detected in: $fn");
        
        
        #  Generate XML
        #
        my $copyright_xml_or=$self->copyright_generate_xml(
            $copyright,
            $section_type
        );
        
        
        #  Now paste in
        #
        if (@section) {
            my $section_xml_or=shift @section;
            $copyright_xml_or->replace($section_xml_or);
        }
        else {
            #  Paste new section at end. Never called - leave here as code example
            #
            @section=$twig_or->get_xpath("${section_type}[last()]");
            my $section_xml_or=shift @section ||
                return err("unable to get last $section_type in file $fn");
            $copyright_xml_or->paste('after', $section_xml_or);
        }
        

        #  Write out the file
        #
        $twig_or->print_to_file($fn);
        
        
        #  Done
        #
        msg("copyright section updated: $fn");


    }

}



sub git_autocopyright_md {


    #  Make sure copyright section is updated in Markdown
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my ($license, $author, $name, $pm_to_inst_ar, $exe_files_ar)=
        @{$param_hr}{qw(LICENSE AUTHOR NAME TO_INST_PM_AR EXE_FILES_AR)};
    debug('in git_autocopyright');


    #  Generate copyright
    #
    my $copyright=$self->copyright_generate($license, $author, $name) ||
        return err ("unable to generate copyright from license $license");


    #  Get manifest - only update files listed there
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();


    #  Load exclusion file
    #
    my $exclude_fn_hr=$self->copyright_exclude_fn_hr($GIT_AUTOCOPYRIGHT_EXCLUDE_FN) ||
        return err ();


    #  Iterate across files to protect
    #
    foreach my $fn (grep {/\.md$/} keys %{$manifest_hr}) {


        #  Start processing
        #
        msg("considering $fn");

        #  Check for exclusion;
        if (grep {$fn=~/$_/} @{$GIT_AUTOCOPYRIGHT_EXCLUDE_MD_AR}) {
            msg("skipping $fn: matches exclude filter");
            next;
        }
        if ($exclude_fn_hr->{$fn}) {
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
        my @keyword=@{$COPYRIGHT_KEYWORD_AR};
        debug('keyword %s', Dumper(\@keyword));
        my @header;


        #  Flag set if existing copyright notice detected
        #
        my $keyword_found_fg;


        #  Turn into array, search for keyword
        #
        my ($lineno, @line, $headno)=0;
        while (my $line=<$fh>) {
            push @line, $line;
            debug("line $line");
            foreach my $keyword (@keyword) {
                if ($line=~/^(#+).*\Q$keyword\E/i) {
                    push(@header, $lineno || 0);
                    $headno=$1;
                    last;
                }
            }
            $lineno++;
        }
        debug("headno: $headno, lineno $lineno. %s", Dumper(\@header));


        #  Close
        #
        $fh->close();


        #  Only do cleanup of old copyright if copyright section was found
        #
        if (defined($header[0])) {


            #  Valid copyright block (probably) found. Set flag
            #
            debug("keyword found");
            $keyword_found_fg++;


            #  Start looks for start and end of header
            #
            for (my $lineno_header=$header[0]+1; $lineno_header <= @line; $lineno_header++) {


                #  We are going forwards through file, as soon as we
                #  see a non comment line we quit
                #
                my $line_header=$line[$lineno_header];
                last if $line_header=~/^#+/i;
                $header[1]=$lineno_header;

            }
            $header[1] ||= @line;
            debug('header[0]:%s, header[1]:%s', @header);

        }
        else {


            # No match found. Skip
            #
            msg("copyright section not found: $fn");
            next;

        }


        #  Massage copyright with POD header, primitive link conversion
        #
        my $copyright_insert="$headno $COPYRIGHT_HEADER_MD" . $copyright;


        #  Only do update if no match
        #
        my $header_copyright=join('', @line[$header[0]..$header[1]]);
        debug("hc: $header_copyright, c: $copyright_insert");
        if ($header_copyright ne $copyright_insert) {


            #  Need to update. If delim found, need to splice out
            #
            msg "copyright updated: $fn";
            if ($keyword_found_fg) {


                #  Yes, found, so splice existing notice out
                #
                debug('splicing out');
                splice(@line, $header[0], ($header[1]-$header[0]+1));


            }


            #  Splice new notice in now
            #
            splice(@line, $header[0], 0, $copyright_insert);


            #  Re-open file for write out
            #
            $fh=IO::File->new($fn, O_TRUNC | O_WRONLY) ||
                return err ("unable to open $fn, $!");
            print $fh join('', @line);
            $fh->close();

        }
        else {

            msg "copyright OK: $fn";

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


sub git_branch_current {


    #  Get current branch
    #
    my $self=shift();
    my $git_or=$self->_git();
    my @branch=grep {/^\*\s+/} ($git_or->branch());
    my $branch=shift @branch;
    $branch=~s/^\*\s+//;
    return $branch;

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
    my $branch=$self->git_branch_current();
    msg("pushing branch $branch");
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
        $git_or->push($name, $branch);
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


    #  Get list of conflicting files
    #
    my $git_conflict_hr=$self->_git_conflict();


    #  If any conflicting file bail now
    #
    if (keys %{$git_conflict_hr}) {
        my $err="The following files have conflicts preventing commit:\n";
        $err.=Data::Dumper::Dumper($git_conflict_hr);
        return err ($err);
    }


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
    my $version_old_numify=version->parse($version_old)->numify;
    my $version_new_numify=version->parse($version_new)->numify;
    if (($version_old_numify > $version_new_numify) && !$force) {
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


sub doc {


    #  Convert XML, MD files to POD, plaintext and append
    #
    my ($self, $param_hr)=(shift(), arg(@_));
    my $exe_files_ar=$param_hr->{'EXE_FILES_AR'};
    my %exe_files=map {$_ => 1} @{$exe_files_ar};


    #  Get manifest - only convert files in manifest
    #
    my $manifest_hr=ExtUtils::Manifest::maniread();
    
    
    #  Hierachy: 
    #  xml=>md
    #  xml=>pod
    #  xml=>text
    #  md=>pod
    #  md=>text


    #  Load Docbook2Pod module
    #
    eval {
        require Docbook::Convert;
        1;
    } || return err ('cannot load module Docbook::Convert');


    #  Look for all XML files
    #
    my @manifest_xml_fn=grep {/\.xml$/} keys %{$manifest_hr};
    msg('found following docbook files for conversion %s', Dumper(\@manifest_xml_fn))
        if @manifest_xml_fn;
    
    
    #  Hash to hold files we generate so not processed twice
    #
    my %ignore_fn;


    #  Iterate
    #
    foreach my $fn (@manifest_xml_fn) {


        #  Slurp in the file
        #
        my $xml=$self->doc_slurp($fn) ||
            return err();


        #  Get target file name;
        #
        (my $target_fn=$fn)=~s/\.xml$//;
        msg("considering $target_fn");
        if ($target_fn=~/\.pm$/ || $target_fn=~/\.pl$/ || $exe_files{$target_fn}) {
            my $pod=Docbook::Convert->pod($xml, { no_warn_unhandled=>1 }) ||
                return err ();
            Docbook::Convert->pod_replace($target_fn, $pod) ||
                return err ();
            msg("converted to POD: $target_fn");
        }
        else {
            #  Also convert README or INSTALL
            #
            if (grep {$target_fn eq $_} @{$TEXT_FN_AR}) {

                #  Markdown
                (my $md_fn=$target_fn).='.md';
                $ignore_fn{$md_fn}++;
                my $md=Docbook::Convert->markdown($xml, { no_warn_unhandled=>1 }) ||
                    return err ();
                $self->doc_blurp($md_fn, $md) ||
                    return err();
                maniadd({$md_fn=> undef});
                msg("converted to Markdown: $md_fn");

                #  Text
                my $text=$self->doc_docbook2text($xml);
                #  Bug in pandoc - remove lines with > only
                #
                my @text;
                foreach my $line (split(/\n/, $text)) {
                    next if $line=~/^>$/;
                    push @text, $line;
                };
                $text=join($/, @text);
                $self->doc_blurp($target_fn, $text);
                maniadd({$target_fn=> undef});
                msg("converted to Text: $target_fn");
            }
            else {
                msg("skipped $target_fn");
            }

        }
        
    }


    #  Look for all Markdown files ignoring ones we created ourselves
    #
    my @manifest_md_fn=grep {/\.md$/} keys %{$manifest_hr};
    @manifest_md_fn=grep {!$ignore_fn{$_}} @manifest_md_fn;
    msg('found following Markdown files for conversion %s', Dumper(\@manifest_md_fn))
        if @manifest_md_fn;


    #  Iterate
    #
    foreach my $fn (@manifest_md_fn) {
    
    
        #  Slurp in the file
        #
        my $md=$self->doc_slurp($fn) ||
            return err();


        #  Get target file name;
        #
        (my $target_fn=$fn)=~s/\.md$//;
        msg("considering $target_fn");
        if ($target_fn=~/\.pm$/ || $target_fn=~/\.pl$/ || $exe_files{$target_fn}) {
            my $pod=$self->doc_md2pod($md) ||
                return err ();
            Docbook::Convert->pod_replace($target_fn, $pod) ||
                return err ();
            msg("converted to POD: $target_fn");
        }
        else {
            #  Also convert to text if README or INSTALL
            #
            if (grep {$target_fn eq $_} @{$TEXT_FN_AR}) {
                #  Plain text
                $self->doc_md2text($md, $target_fn) ||
                    return err ();
                maniadd({$target_fn=> undef});
                msg("converted to text: $target_fn");
            }
            else {
                msg("skipped $target_fn");
            }

        }

    }


    #  Done
    #
    return \undef;

}


sub doc_slurp {

    #  Slurp in file content
    #
    my ($self, $fn)=@_;
    my $fh=IO::File->new($fn, O_RDONLY) ||
        return err ("unable to open file $fn, $!");
    my $text;
    local $/=undef;
    $text=<$fh>;
    $fh->close();
    return $text;
    
}
    

sub doc_blurp {

    #  Save to file
    #
    my ($self, $fn, $text)=@_;
    my $fh=IO::File->new($fn, O_WRONLY|O_CREAT|O_TRUNC) ||
        return err ("unable to open $fn for write, $!");
    print $fh $text;
    $fh->close();
    
}
    

sub doc_md2pod {


    #  Convert Markdown to POD
    #
    my ($self, $md)=@_;
    
    
    #  Meed Markdown::Pod module
    #
    eval {
        require Markdown::Pod;
        1
    } || return err('unable to load Markdown::Pod module');


    my $m2p_or=Markdown::Pod->new() ||
        return err ('unable to create new Markdown::Pod object');
    my $pod=$m2p_or->markdown_to_pod(
        dialect  => $MARKDOWN_DIALECT,
        markdown => $md,
    ) || return err ('unable to created pod from markdown');


    #  Done
    #
    return $pod;

}


sub doc_md2text {


    #  Convert Markdown to text
    #
    my ($self, $md, $fn)=@_;
    
    
    #  Need IPC::Run3
    #
    eval {
        require IPC::Run3;
        1;
    } || return err('unable to load IPC::Run3 module');
    
    
    #  Need pandoc for this bit
    #
    $PANDOC_EXE || 
        return err('pandoc is required for markdown to text conversion');

    #  Run the Pandoc conversion to markup
    #
    my $text;
    {   my $command_ar=
            $PANDOC_CMD_MD2TEXT_CR->($PANDOC_EXE, '-');
        IPC::Run3::run3($command_ar, \$md, ($fn || \$text), \undef) ||
            return err ('unable to run3 %s', Dumper($command_ar));
        if ((my $err=$?) >> 8) {
            return err ("error $err on run3 of: %s", Dumper($command_ar));
        }
    }

    #  Done
    #
    return $text;

}


sub doc_docbook2text {

    #  Convert Docbook to text
    #
    my ($self, $xml, $fn)=@_;
    

    #  Need IPC::Run3
    #
    eval {
        require IPC::Run3;
        1;
    } || return err('unable to load IPC::Run3 module');
    

    #  Need pandoc for this bit
    #
    $PANDOC_EXE || 
        return err('pandoc is required for markdown to text conversion');

    #  Run the Pandoc conversion to markup
    #
    my $text;
    {   my $command_ar=
            $PANDOC_CMD_DOCBOOK2TEXT_CR->($PANDOC_EXE, '-');
        IPC::Run3::run3($command_ar, \$xml, ($fn || \$text), \undef) ||
            return err ('unable to run3 %s', Dumper($command_ar));
        if ((my $err=$?) >> 8) {
            return err ("error $err on run3 of: %s", Dumper($command_ar));
        }
    }

    #  Done
    #
    return $text;

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
    return $self->_git_status('changed');

}


sub _git_conflict {


    #  Return a hash of conflicting files
    #
    my $self=shift();
    return $self->_git_status('conflict');

}


sub _git_status {

    my ($self, $group)=@_;
    my $git_or=$self->_git();
    my %git_fn;
    if (my $statuses_or=$git_or->status()) {
        foreach my $status_or ($statuses_or->get($group)) {
            my $fn=$status_or->to() || $status_or->from();
            my $mode=$status_or->mode();
            $git_fn{$fn}=$mode;
        }
    }
    return \%git_fn;

}


sub _git_rev_parse_short {

    my ($self, $rev)=@_;
    $rev ||= 'HEAD';
    my $git_or=$self->_git();
    return ($git_or->rev_parse('--short', $rev))[0];

}


sub debug {
    CORE::printf(shift() . "\n", @_) if $ENV{'EXTUTILS_GIT_DEBUG'};
}


1;
__END__

ExtUtils::Git
3
ExtUtils::Git
ExtUtils::MakeMaker helper module to add git related Makefile targets
perl -MExtUtils::Git Makefile.PL


=head1 Description

ExtUtils::Git is a ExtUtils::MakeMaker helper module that will add git related targets to the Makefile generated by a Makefile.PL run. It is intended to help during module development by enforcing some sanity checks around git related operations as they apply to Perl modules and provide other (sometime not git related) Makefile targets to improve productivity.

This module will undertake workflow check such as ensuring that all files in a Module MANIFEST file are present in git during checkin. It will increment version numbers and tag files during distribution builds and provide other utility functions.


=head1 Options

Once the Makefile is built as per the synopsis the following git related and utility targets are available:

git_init

Creates an empty git repository and creates a .gitignore file (using the git_ignore target). No files are added to the git repository

git_autocopyright

Will update copyright information (including updating copyright effective year) in all modules if found. If not found a copyright notice will be inserted at the top of the file derived from the LICENSE field in the Makefile.PL

git_autolicense

Will update or create an appropriate LICENSE file in the module MANIFEST and working directory with text obtained from the Software::License Perl module

git_ci

Check all changes into git repository for files found in the MANIFEST. Will run a sanity to check that only files in the MANIFEST are in the git repository and vica-versa

git_push

Push all changes into remote repositories.

git_release

Increment module version numbers, tag files and create a new distribution file for this module.

git_status

Report status of git managed files vs MANIFEST and status of files (clean, changed, conflict)

git_version_increment

Increment module version numbers

cw

Run perl -c -w against all files in the module

doc

Search for any DocBook or Markdown files in the directory structure and convert to POD. Files marked in the format module.pm.xml or module.pm.md will have their content converted to POD and appended to module.pm. Similarly for files in any bin directory.

kwalitee

Run Module::CPANTS::Kwalitee tests against a distribution and report results

perlcritic

Run perlcritic across all Perl files in the distribution MANIFEST and report results

perltidy

Run perltidy across all Perl files in the distribution MANIFEST

perlver

Run Perl::MinimumVersion across all Perl file in the distribution MANIFEST and report results

readme

Generate README file

subsort

Sort all subroutines in all Perl files in the distribution MANIFEST into alphabetical order
