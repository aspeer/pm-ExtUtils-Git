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
#  $Id: Config.pm,v 1.4 2003/10/15 14:58:10 aspeer Exp $


#  Part of ExtUtils::CVS namespace
#
package ExtUtils::CVS;


#  Need File::Find, other File utils
#
use File::Find;
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
