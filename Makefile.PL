#  Makefile.PL
#
package ExtUtils::CVS;


#  Compiler Pragma
#
use strict  qw(vars);


#  External Modules
#
use ExtUtils::MakeMaker;


#  All done, init finished
#
#------------------------------------------------------------------------------


#  Create the Makefile
#
WriteMakefile(

    NAME				 => __PACKAGE__,
    MAN3PODS				 => {},
    VERSION_FROM			 => 'VERSION.pm',
    PM					 => {

	'CVS.pm'			 =>	'$(INST_LIBDIR)/CVS.pm',
	'VERSION.pm'			 =>	'$(INST_LIBDIR)/CVS/VERSION.pm',
	'Config.pm'			 =>	'$(INST_LIBDIR)/CVS/Config.pm',
	'support/dist_ci.inc'		 =>	'$(INST_LIBDIR)/CVS/dist_ci.inc',

    },

    'dist'				 =>  {

	COMPRESS			 =>	'gzip -9f',
	SUFFIX				 =>	'.gz',

    },

    'depend'				 => {
	Makefile			 =>	'$(VERSION_FROM)',
    },

    AUTHOR				 => 'Andrew Speer <andrew.speer@isolutions.com.au>',

   );

