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
    VERSION_FROM			 =>  'VERSION.pm',
    PM					 =>  {

	'CVS.pm'			 =>  '$(INST_LIBDIR)/CVS.pm',
	'VERSION.pm'			 =>  '$(INST_LIBDIR)/CVS/VERSION.pm',
	'Config.pm'			 =>  '$(INST_LIBDIR)/CVS/Config.pm',
	'support/dist_ci.inc'		 =>  '$(INST_LIBDIR)/CVS/dist_ci.inc',
	'LICENSE',			 =>  '$(INST_LIBDIR)/Lint/LICENSE',

    },
    
    EXE_FILES                            =>  [
    
        'support/cvs2cl.pl',
        
    ],

    'dist'				 =>  {

	COMPRESS			 =>  'gzip -9f',
	SUFFIX				 =>  '.gz',

    },


    'depend'				 =>  {
	Makefile			 =>  '$(VERSION_FROM)',
    },


    'macro'				 =>  {
        COPYRIGHT			 =>  'Copyright (c) 2003 Andrew Speer, All rights reserved',
    	LICENSE				 =>  'GPL: GNU General Public License',
    	statl				 =>  'g',
    },


    ($] >= 5.005 ?
      (ABSTRACT_FROM 			 => 'CVS.pm',
       AUTHOR     			 => 'Andrew Speer <andrew.speer@isolutions.com.au>') : ()
    ),

   );

