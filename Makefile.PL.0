#  Makefile.PL
#
package ExtUtils::Git;


#  Compiler Pragma
#
use strict  qw(vars);


#  External Modules
#
use ExtUtils::MakeMaker;


#  Get MakeMaker version - from Test::Simple Makefile.PL
#
my $mm_ver = $ExtUtils::MakeMaker::VERSION;
if ($mm_ver =~ /_/) { # dev version
    $mm_ver = eval $mm_ver;
    die $@ if $@;
}


#  All done, init finished
#
#------------------------------------------------------------------------------



#  Cache vars
#
my ($prereq_hr, $version_from_fn);


#  Create the Makefile
#
WriteMakefile(

    NAME                                          =>  __PACKAGE__,

    VERSION_FROM                                  =>  $version_from_fn=File::Spec->catfile(

        'lib',
        split(/::/, __PACKAGE__),

       ).'.pm',


    PREREQ_PM                                     =>    do { $prereq_hr={

        'File::Touch'                             =>  0,
        'File::Grep'                              =>  0,
        'Git::Wrapper'                            =>  0,
        'Software::License'                       =>  0

       }; ($ENV{'PREREQ_PM'} eq '0') ? {} : $prereq_hr },


    CONFIGURE                                     =>  sub { {

        PREREQ_PM                                 =>  $prereq_hr

    } },


    'dist'                                        =>  {

        COMPRESS                                  =>  'gzip -9f',
        SUFFIX                                    =>  '.gz',

    },


    'depend'                                      =>  {
        Makefile                                  =>  '$(VERSION_FROM)',
    },


    ($] >=  5.005 ?
         (ABSTRACT_FROM                           => $version_from_fn,
          AUTHOR                                  => 'Andrew Speer <andrew.speer@isolutions.com.au>') : ()
         ),


    ($mm_ver < 6.31 ? () : (

        LICENSE                             =>  'gpl_2',

    )),


   );

package MY;

sub constants {

    #  Add license file, other support files here
    #
    my $mm_or=shift();
    $mm_or->{'PM'}{'LICENSE'}='$(INST_LIBDIR)/$(BASEEXT)/LICENSE';
    $mm_or->SUPER::constants;

};
