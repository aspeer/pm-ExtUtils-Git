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

    NAME				 =>  __PACKAGE__,
    MAN3PODS				 =>  {},
    VERSION_FROM			 =>  'VERSION.pm',
    PM					 =>  {

	'CVS.pm'			 =>  '$(INST_LIBDIR)/CVS.pm',
	'VERSION.pm'			 =>  '$(INST_LIBDIR)/CVS/VERSION.pm',
	'Config.pm'			 =>  '$(INST_LIBDIR)/CVS/Config.pm',
	'support/dist_ci.inc'		 =>  '$(INST_LIBDIR)/CVS/dist_ci.inc',
	'LICENSE',			 =>  '$(INST_LIBDIR)/Lint/LICENSE',

    },

    'dist'				 =>  {

	COMPRESS			 =>  'gzip -9f',
	SUFFIX				 =>  '.gz',

    },


    'depend'				 =>  {
	Makefile			 =>  '$(VERSION_FROM)',
    },


    'macro'				 =>  {
        COPYRIGHT			 =>  'Copyright (c) 2003 Andrew Speer, All rights reserved',
    	LICENSE				 =>  'Commercial (see LICENSE file)',
    	statl				 =>  'c',
    },


    ($] >= 5.005 ?
      (ABSTRACT_FROM 			 => 'CVS.pm',
       AUTHOR     			 => 'Andrew Speer <andrew.speer@isolutions.com.au>') : ()
    ),

   );

