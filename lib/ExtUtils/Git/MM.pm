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
package ExtUtils::Git::MM;


#  Compiler Pragma
#
use strict qw(vars);
use vars qw($VERSION @ISA);
use warnings;
no warnings qw(uninitialized);
sub BEGIN {local $^W=0}


#  External Packages
#
use ExtUtils::Git::Util;
use ExtUtils::Git::Constant;
use Software::License;
use Software::LicenseUtils;
use IO::File;
use File::Spec;
use Data::Dumper;
use Carp;
use Cwd;


#  Version information in a formate suitable for CPAN etc. Must be
#  all on one line
#
$VERSION='1.173';


#  use ExtUtils::MakeMaker as our parent class.
#
use base 'ExtUtils::MakeMaker';


#  All done, init finished
#
1;


#===================================================================================================


sub import {

    #  Manage activation of const_config and dist_ci targets via import tags. Import tags are
    #
    #  use ExtUtils::Git::MM qw(const_config) to just replace the macros section of the Makefile
    #  .. qw(dist_ci) to replace standard MakeMaker targets with our own
    #  .. qw(:all) to get both of the above, usual usage
    #

    #  Get params, bless self ref and remember import tags spec'd for later
    #  re-use
    #
    my $self=bless \my %self, shift();
    my %import_tag=map {$_ => 1} @{$self{'import_tag'}=\@_};
    $import_tag{':all'}++ unless keys %import_tag;


    #  Store for later use in MY::makefile section
    #
    $self{'ISA'}=\@INC;


    #  sections to replace
    #
    my @section=qw(
        const_config
        distdir
        depend
        postamble
        );    #dist_ci
    {   no warnings 'redefine';
        foreach my $section (grep {$import_tag{$_} || $import_tag{':all'}} @section) {
            $self{$section}=UNIVERSAL::can('MY', $section);
            *{"MY::${section}"}=sub {&{$section}($self, @_)};
        }
    }


}


sub const_config {


    #  Get self ref
    #
    my ($self, $mm)=(shift(), @_);


    #  Import Constants into macros
    #
    while (my ($key, $value)=each %ExtUtils::Git::Constant::Constant) {


        #  Update macros with our config
        #
        $mm->{'macro'}{$key}=$value;

    }


    #   Update license data. Get license type and author
    #
    my $license=$mm->{'LICENSE'} ||
        return err ('no license specified in Makefile');
    my @author=@{
        $mm->{'AUTHOR'}
            ||
            return err ('no author specified in Makefile')};
    my $author=shift(@author);


    #  Choose appropriate module
    #
    my @license_module=Software::LicenseUtils->guess_license_from_meta_key($license);
    @license_module ||
        return err ("unable to determine correct license module from string: $license");
    (@license_module > 1) &&
        return err ("ambiguous license string: $license, resolves to %s", join(',', @license_module));
    my $license_or=(shift @license_module)->new({holder => $author});


    #  Generate data later used in META files
    #
    @{$mm->{'macro'}}{qw(LICENSE AUTHOR)}=($license, $author);
    $mm->{'META_MERGE'}{'resources'}{'license'}=$license_or->url();


    #  Adjust PERLRUN to include @INC and this module
    #
    my $perlrun;
    my %perlrun_inc;
    my $perlrun_inc=join(' ', map {"-I$_"} grep {!$perlrun_inc{$_}++} @{$self->{'ISA'}});
    my $class=ref($self);
    if (my $include_tags_ar=$self->{'include_tags'}) {
        $perlrun=sprintf("\$(PERL) $perlrun_inc -M${class}=%s", join(',', @{$include_tags_ar}));
    }
    else {
        $perlrun="\$(PERL) $perlrun_inc -M${class}";
    }
    $mm->{'PERLRUN'}=$perlrun;


    #  Keep copy of DIST_DEFAULT
    #
    $mm->{'macro'}{'DIST_DEFAULT_TARGET'}=$mm->{'DIST_DEFAULT'};


    #  Return whatever our parent does
    #
    return $self->{'const_config'}(@_);


}


#  MakeMaker::MY replacement const_config section
#
sub depend {


    #  Get self ref
    #
    my ($self, $mm)=(shift(), @_);


    #  Get original and modify
    #
    my $depend=$self->{'depend'}(@_);


    #  If nothing generate default
    #
    if (!$depend && $mm->{'VERSION_FROM'}) {
        $depend='Makefile : $(VERSION_FROM)';
    }
    return $depend;

}


#  MakeMaker::MY update postamble section to include a "git_import" and other functions
#
sub distdir {


    #  Get self ref
    #
    my $self=shift();


    #  Get original and modify
    #
    my $distdir=$self->{'distdir'}(@_);
    $distdir=~s/distmeta/distmeta git_distchanges/;
    return $distdir;

}


sub postamble {


    #  Get self ref
    #
    my $self=shift();


    #  Get patch dir and file name
    #
    my $patch_fn=$TEMPLATE_POSTAMBLE_FN;


    #  Open it
    #
    my $patch_fh=IO::File->new($patch_fn, O_RDONLY) ||
        return err ("unable to open $patch_fn, $!");


    #  Get original and append
    #
    my $postamble=$self->{'postamble'}(@_);
    $postamble.=join('', <$patch_fh>);


    #  Close
    #
    $patch_fh->close();


    #  All done, return result
    #
    return $postamble;

}

