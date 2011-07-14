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


#  Get MakeMaker args
#
my %arg;
&ExtUtils::MakeMaker::parse_args(\%arg, @ARGV);
my ($prereq_hr, $version_from_fn);


#  Create the Makefile
#
WriteMakefile(

    NAME					  =>  __PACKAGE__,

    VERSION_FROM				  =>  $version_from_fn=File::Spec->catfile(

	'lib',
	split(/::/, __PACKAGE__),

       ).'.pm',


    PREREQ_PM				    	  =>	do { $prereq_hr={

	'File::Touch'			    	  =>  undef,
	'File::Grep'			    	  =>  undef

       }; ($ENV{'PREREQ_PM'} eq '0') ? {} : $prereq_hr },


    CONFIGURE                               	  =>  sub { {

	PREREQ_PM			    	  =>  $prereq_hr

    } },


    'dist'					  =>  {

	COMPRESS				  =>  'gzip -9f',
	SUFFIX					  =>  '.gz',

    },


    'depend'					  =>  {
	Makefile				  =>  '$(VERSION_FROM)',
    },


    'macro'					  =>  {
        COPYRIGHT				  =>  'Copyright (C) 2003 Andrew Speer, All rights reserved',
	LICENSE					  =>  'GPL: GNU General Public License',
    },

    ($] >=  5.005 ?
	 (ABSTRACT_FROM				  => $version_from_fn,
	  AUTHOR				  => 'Andrew Speer <andrew.speer@isolutions.com.au>') : ()
	 ),


    ($mm_ver < 6.31 ? () : (

        LICENSE                             =>  'gpl',

    )),


    ($mm_ver <= 6.45 ? () : (
        
        META_MERGE => { resources => {
            
            license                         =>  'http://www.gnu.org/licenses/gpl.html'
            
        }}
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
