#
#
#  Copyright (c) 2003 Andrew W. Speer <andrew.speer@isolutions.com.au>. All rights 
#  reserved.
#
#  This file is part of ExtUtils::CVS.
#
#  ExtUtils::CVS is free software; you can redistribute it and/or modify
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
#  $Id: Config.pm,v 1.5 2003/11/02 15:49:11 aspeer Exp $
package ExtUtils::CVS;#  Need File::Find, other File utils#use File::Find;
use File::Spec;
use IO::File;


#  Bin_find now anon sub to stop "subroutine redefined" type errors that
#  occur when this file is read several times
#
my $bin_find_cr=sub {


    #  Find a binary file
    #
    my $bin=shift();
    my ($bin_fn, $wanted_cr);


    #  Find the bin file/files if given array ref
    #
    if (ref($bin) eq 'ARRAY') {
        $wanted_cr=sub {
	    foreach my $bin (@{$bin}) {
                ($File::Find::name=~/\/\Q$bin\E$/) && ($bin_fn=$File::Find::name);
		last if $bin_fn;
	    }
        };
    }
    else {
        $wanted_cr=sub {
	    ($File::Find::name=~/\/\Q$bin\E$/) && ($bin_fn=$File::Find::name);
        };
    }
    my @dir=grep { -d $_ } split(/:|;/, $ENV{'PATH'});
    find($wanted_cr, @dir);


    #  Normalize fn
    #
    $bin_fn=File::Spec->canonpath($bin_fn);


    #  Return
    #
    return $bin_fn;

};


#  Get cache file name
#
my $cache_fn=$INC{'ExtUtils/CVS.pm'}.'.cache';


#  Look for cache of bin locations
#
unless ($_=do($cache_fn)) {


    #  Could not find, create hash
    #
    my %Config= (

	CVS	 =>  $bin_find_cr->([qw(cvs cvs.exe)]),

	CVS2CL	 =>  $bin_find_cr->('cvs2cl.pl'),

	CVSROOT	 =>  $ENV{'CVSROOT'},

       );


    #  Store in cache file
    #
    if (my $fh=IO::File->new($cache_fn, O_WRONLY|O_CREAT|O_TRUNC)) {
        print $fh &Data::Dumper::Dumper(\%Config)
    }


    #  Return ref
    #
    $_=\%Config;

}
