#
#
#  Copyright (c) 2003 Andrew W. Speer <andrew.speer@isolutions.com.au>. All rights 
#  reserved.
#
#  This program is NOT free software,  it licensed under the conditions provided 
#  in the LICENSE file included with the software. If you are not able to locate 
#  the LICENSE file, or need  further information you  should contact the author 
#  at the email adddress give above.
#
#
#  $Id: Config.pm,v 1.2 2003/09/01 04:35:27 aspeer Exp $


$_ = {

    CVS		 =>  '/usr/bin/cvs',
    
    CVS2CL	 =>  '/usr/local/bin/cvs2cl.pl',
    
    CVSROOT	 =>  $ENV{'CVSROOT'}


} || 1;
