#  Makefile.PL
#
package ExtUtils::Git;


#  Compiler Pragma
#
use strict  qw(vars);


#  External Modules
#
use ExtUtils::MakeMaker;


#  All done, init finished
#
#------------------------------------------------------------------------------


#  Get MakeMaker args
#
my %arg;
&ExtUtils::MakeMaker::parse_args(\%arg, @ARGV);
my $prereq_hr;


#  Create the Makefile
#
WriteMakefile(

    NAME					  =>  __PACKAGE__,


    VERSION_FROM				  =>  File::Spec->catfile(

	'lib',
	split(/::/, __PACKAGE__),
	'VERSION.pm'

       ),


    PREREQ_PM				    	  =>	do { $prereq_hr={

	'File::Touch'			    	  =>  undef,
	'File::Grep'			    	  =>  undef

       }; ($ENV{'PREREQ_PM'} eq '0') ? {} : $prereq_hr },


    CONFIGURE                               	  =>  sub { {

	PREREQ_PM			    	  =>  $prereq_hr

    } },


    PM						  =>  {

	'lib/ExtUtils/Git.pm'			  =>  '$(INST_LIBDIR)/Git.pm',
	'lib/ExtUtils/Git/Constant.pm'		  =>  '$(INST_LIBDIR)/Git/Constant.pm',
	'lib/ExtUtils/Git/VERSION.pm'		  =>  '$(INST_LIBDIR)/Git/VERSION.pm',
	'lib/ExtUtils/Git/dist_ci.inc'		  =>  '$(INST_LIBDIR)/Git/dist_ci.inc',
	'LICENSE'				  =>  '$(INST_LIBDIR)/Git/LICENSE',

       },


    'dist'					  =>  {

	COMPRESS				  =>  'gzip -9f',
	SUFFIX					  =>  '.gz',

    },


    'depend'					  =>  {
	Makefile				  =>  '$(VERSION_FROM)',
    },


    'macro'					  =>  {
        COPYRIGHT				  =>  'Copyright (c) 2003 Andrew Speer, All rights reserved',
	LICENSE					  =>  'GPL: GNU General Public License',
    },


    ($] >=  5.005 ?
	 (#ABSTRACT_FROM				  => '$(LIBDIR)/Git.pm',
	  AUTHOR				  => 'Andrew Speer <andrew.speer@isolutions.com.au>') : ()
	 ),

   );

