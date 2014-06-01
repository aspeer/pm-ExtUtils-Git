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
use ExtUtils::Git::Base;
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
$VERSION='1.158_164338529';


#  use ExtUtils::MakeMaker as our parent class.
#
use base 'ExtUtils::MakeMaker';


#  All done, init finished
#
1;


#===================================================================================================


#  Manage activation of const_config and dist_ci targets via import tags. Import tags are
#
#  use ExtUtils::Git::MM qw(const_config) to just replace the macros section of the Makefile
#  .. qw(dist_ci) to replace standard MakeMaker targets with our own
#  .. qw(:all) to get both of the above, usual usage
#
sub import {


    #  Get params, bless self ref and remember import tags spec'd for later
    #  re-use
    #
    my $self=bless \my %self, shift();
    my %import_tag=map { $_=>1 } @{$self{'import_tag'}=\@_};
    $import_tag{':all'}++ unless keys %import_tag;


    #  Store for later use in MY::makefile section
    #
    $self{'ISA'}=\@INC;
    #my @import;
    #$MY::Import_class{$self}=\@import;
    #$MY::Import_inc=\@INC;
    
    
    #  sections to replace
    #
    my @section=qw(
        const_config
        dist_ci
        distdir
    ); #makefile #platform_constants
    {
        no warnings 'redefine';
        foreach my $section (grep {$import_tag{$_} || $import_tag{':all'}} @section) {
            $self{$section}=UNIVERSAL::can('MY', $section);
            #*{"MY::${section}"}=\&{$section} 
            *{"MY::${section}"}=sub { &{$section}($self, @_) };
        }
    }
    

}


#  MakeMaker::MY replacement const_config section
#
sub const_config {


    #  Get self ref
    #
    my ($self, $mm)=(shift(), @_);
    print "const_config ExtUtils::MakeMaker\n";


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
        return err('no license specified in Makefile');
    my @author=@{$mm->{'AUTHOR'} ||
        return err('no author specified in Makefile')};
    my $author=shift(@author);
    
    
    #  Choose appropriate module
    #
    my @license_module=Software::LicenseUtils->guess_license_from_meta_key($license);
    @license_module || 
        return err ("unable to determine correct license module from string: $license");
    (@license_module > 1) && 
        return err ("ambiguous license string: $license");
    my $license_or=(shift @license_module)->new({ holder=>$author });
    
    
    #  Generate data later used in META files
    #
    @{$mm->{'macro'}}{qw(LICENSE AUTHOR)}=($license, $author);
    $mm->{'META_MERGE'}{'resources'}{'license'}=$license_or->url();
    
    
    #  Adjust PERLRUN to include @INC and this module
    #
    my $perlrun;
    my $perlrun_inc=join(' ', map { "-I$_" } @{$self->{'ISA'}});
    my $class=ref($self);
    if (my $include_tags_ar=$self->{'include_tags'}) {
        #$makefile_module.=qq("-M$class=") . join(',', @{$include_tags_ar});
        $perlrun=sprintf("\$(PERL) $perlrun_inc -M${class}=%s", join(',', @{$include_tags_ar}));
    }
    else {
        $perlrun="\$(PERL) $perlrun_inc -M${class}";
        #$makefile_module.=qq("-M$class");
    }
    $mm->{'PERLRUN'}=$perlrun;


    #  Return whatever our parent does
    #
    #return $SUPER{'const_config'}->($self);
    return $self->{'const_config'}->(@_);


}


#  MakeMaker::MY update ci section to include a "git_import" and other functions
#
sub dist_ci {


    #  Change package
    #
    #package MY;


    #  Get self ref
    #
    my $self=shift();


    #  Found it, open our patch file. Get dir first
    #
    #(my $patch_dn=$INC{'ExtUtils/Git.pm'})=~s/\.pm$//;
    use Cwd;
    (my $patch_dn=Cwd::abs_path(__FILE__))=~s/\.pm$//;



    #  And now file name
    #
    my $patch_fn=File::Spec->catfile($patch_dn, 'dist_ci.inc');


    #  Open it
    #
    #my $patch_fh=IO::File->new($patch_fn, &ExtUtils::Git::O_RDONLY) ||
    my $patch_fh=IO::File->new($patch_fn, O_RDONLY) ||
        return err("unable to open $patch_fn, $!");


    #  Add in. We are replacing dist_ci entirely, so do not
    #  worry about chaining.
    #
    my @dist_ci=map {chomp; $_} <$patch_fh>;


    #  Close
    #
    $patch_fh->close();


    #  All done, return result
    #
    return join($/, @dist_ci);

}
    

#  MakeMaker::MY replacement Makefile section
#
sub makefile0 {


    #  Change package
    #
    #my $class=__PACKAGE__;
    #package MY;


    #  Get self ref
    #
    my $self=shift();
    print "makefile ".Dumper($self)."\n";


    #  Get original makefile text
    #
    #my $makefile=$Makefile_chain_cr->($self);
    #my $makefile=$SUPER{'makefile'}->($self,@_);
    my $makefile=$self->{'makefile'}(@_);


    #  Array to hold result
    #
    my @makefile;


    #  Build the  makefile -M line
    #
    my $makefile_module;
    my $class=ref($self);
    #while (my ($class, $param_ar)=each %MY::Import_class) {
    #    if (@{$param_ar}) {
    #        $makefile_module.=qq("-M$class=") . join(',', @{$param_ar});
    #    }
    #    else {
    #        $makefile_module.=qq("-M$class");
    #    }
    #}
    if (my $include_tags_ar=$self->{'include_tags'}) {
        $makefile_module.=qq("-M$class=") . join(',', @{$include_tags_ar});
    }
    else {
        $makefile_module.=qq("-M$class");
    }

    #  Get the INC files
    #
    my $makefile_inc;
    use Data::Dumper;
    #if (my @inc=@{$MY::Import_inc}) {
    my %inc_dn;
    foreach my $inc_dn (@{$self->{'ISA'}}) {
        print "inc_dn $inc_dn\n";
    #if (my @inc=@{"${class}::INC"}) {
        #foreach my $inc (@inc) {
            $makefile_inc.=qq( "-I$inc_dn") unless $inc_dn{$inc_dn}++;
        #}

        #$makefile_inc=join(' ', map { qq("-I$_") } @inc);
        #print Dumper(\@inc, $makefile_inc);
    }
    #else {
    #    use vars qw(@ISA);
    #    print "class $class ".Dumper(\@{"${class}::ISA"}, \@ISA);
    #}


    #  Target line to replace. Will need to change here if ExtUtils::MakeMaker ever
    #  changes format of this line
    #
    my @find=(
        q[$(PERL) "-I$(PERL_ARCHLIB)" "-I$(PERL_LIB)" Makefile.PL],
        q[$(PERLRUN) Makefile.PL]
    );
    my $rplc=
        sprintf(
        q[$(PERL) %s "-I$(PERL_ARCHLIB)" "-I$(PERL_LIB)" %s Makefile.PL],
        $makefile_inc, $makefile_module
        );
    my $match;


    #  Go through line by line
    #
    foreach my $line (split(/^/m, $makefile)) {


        #  Chomp
        #
        chomp $line;


        #  Check for target line
        #
        for (@find) {$line=~s/\Q$_\E/$rplc/i && ($match=$line)}


        #  Also look for 'false' at end, erase
        #
        next if $line=~/^\s*false/;
        push @makefile, $line;


    }

    #  Warn if line not found
    #
    #$class->_msg('warning! ExtUtils::Makemaker makefile section replacement not successful') unless
    #    $match;


    #  Done, return result
    #
    return join($/, @makefile);

}


sub platform_constants0 {


    #  Change package
    #
    #my $class=__PACKAGE__;
    #package MY;


    #  Get self ref
    #
    my $self=shift();


    #  Get original constants
    #
    #my $constants=$Platform_constants_cr->($self);
    #my $constants=$SUPER{'platform_constants'}->($self, @_);
    my $constants=$self->{'platform_constants'}(@_);


    #  Get INC
    #
    my $makefile_inc;
    if (my @inc=@{$MY::Import_inc}) {
        $makefile_inc=join(' ', map {qq("-I$_")} @inc);
    }


    #  Update fullperlrun, used by test
    #
    $constants.=join(
        "\n",
        undef,
        "FULLPERLRUN = \$(FULLPERL) $makefile_inc",
        "MAKEFILELIB = $makefile_inc",
        undef
    );


    #  Done
    #
    return $constants;


}


sub distdir {


    #  Get self ref
    #
    my $self=shift();
    
    
    #  Get original and modify
    #
    #my $distdir=$SUPER{'distdir'}->($self, @_);
    my $distdir=$self->{'distdir'}(@_);
    $distdir=~s/distmeta/distmeta git_distchanges/;
    return $distdir;
    
}


#===================================================================================================
