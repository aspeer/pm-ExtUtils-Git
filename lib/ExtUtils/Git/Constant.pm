#
#
#  Copyright (c) 2003 Andrew W. Speer <andrew.speer@isolutions.com.au>. All rights 
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
#  $Id: Config.pm,v 1.18 2007/07/01 09:46:09 aspeer Exp $
#


#  This package finds, then stores in a cache the full path to various
#  executables and environment vars, including:
#
#  bin
#
#  If no cache file is found, this modules will go through the path and
#  look for the executables, then store the results away in a cache file
#
#


#
#
package ExtUtils::Git::Constant;


#  Compiler Pragma
#
sub BEGIN   { $^W=0 };
use strict  qw(vars);
use vars qw($VERSION @ISA %EXPORT_TAGS @EXPORT_OK @EXPORT %Constant);
use warnings;
no  warnings qw(uninitialized);


#  Need File::Find, other File utils
#
use File::Find;
use File::Spec;
use IO::File;
use Data::Dumper;


#===================================================================================================


#  Bin_find now anon sub to stop "subroutine redefined" type errors that
#  occur when this file is read several times
#
my $bin_find_cr=sub {


    #  Find a binary file
    #
    my $bin_ar=shift();
    my $bin_fn;


    #  Find the bin file/files if given array ref. If not supplied as array ref
    #  convert.
    #
    (ref($bin_ar) eq 'ARRAY') || do { $bin_ar=[$bin_ar] };
    my $wanted_cr=sub {
	foreach my $bin (@{$bin_ar}) {
	    ($File::Find::name=~/\/\Q$bin\E$/) && ($bin_fn=$File::Find::name);
	    last if $bin_fn;
	}
    };
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
my $cache_fn=$INC{'ExtUtils/Git/Constant.pm'} || File::Spec->rel2abs(__FILE__);
$cache_fn .= '.cache';


#  Cache can only be 60 sec old
#
if (-e $cache_fn && ((stat($cache_fn))[9] < (time() - (1 * 60)))) {


    #  Cache is stale, delete. Not fatal if fails, just blank out so
    #  we do not use;
    #
    unlink $cache_fn || ($cache_fn=undef);

}


#  Try to read in cache details, or search disk for binaries if needed
#
unless (%Constant = %{do($cache_fn)}) {


    #  Could not find cache file, create hash. Should probably put this stuff into a
    #  support/const.inc file later as a template, as contains some constants
    #
    %Constant= (

	GIT_EXE			 =>  $bin_find_cr->([qw(git git.exe)]),

	CHANGELOG_FN		 =>  'ChangeLog',

	METAFILE_FN		 =>  'META.yml',

	DUMPER_FN	         =>  '.dumper.cache',

	EXTUTILS_ARGV		 =>  q["$(NAME)" "$(NAME_SYM)" "$(DISTNAME)" "$(DISTVNAME)" "$(VERSION)" ].
	    q["$(VERSION_SYM)" "$(VERSION_FROM)"],

	EXTUTILS_GIT		 =>  'ExtUtils::Git',

	DIST_DEFAULT		 =>  'git_dist',

	GIT_REPO		 =>  'ssh://git@copper.isolutions.com.au/home/git'

       );


    #  Store in cache file. Does not matter if not writeable
    #
    if (my $fh=IO::File->new($cache_fn, O_WRONLY|O_CREAT|O_TRUNC)) {
        print $fh &Data::Dumper::Dumper(\%Constant)
    }


}


#  Export constants to namespace, place in export tags
#
require Exporter;
@ISA=qw(Exporter);
eval { require WebDyne::Constant; &WebDyne::Constant::local_constant_load(__PACKAGE__,\%Constant) };
foreach (keys %Constant) { ${$_}=$Constant{$_} }
@EXPORT=map { '$'.$_ } keys %Constant;
@EXPORT_OK=@EXPORT;
%EXPORT_TAGS=(all => [@EXPORT_OK]);
$_=\%Constant;

