#
#
#  Copyright (C) 2003 Andrew Speer <andrew.speer@isolutions.com.au>. All rights
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
use strict qw(vars);
use vars qw($VERSION @ISA %EXPORT_TAGS @EXPORT_OK @EXPORT %Constant);
use warnings;
no warnings qw(uninitialized);
local $^W=0;


#  Needed external utils
#
use File::Spec;
use Cwd qw(abs_path);
     


#===================================================================================================


#  Get module file name and path, derive name of file to store local constants
#
my $module_fn=abs_path(__FILE__);
my $local_fn="${module_fn}.local";


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
    (ref($bin_ar) eq 'ARRAY') || do {$bin_ar=[$bin_ar]};
    my @dir=grep {-d $_} split(/:|;/, $ENV{'PATH'});
    my %dir=map {$_ => 1} @dir;
    DIR: foreach my $dir (@dir) {
        next unless delete $dir{$dir};
        next unless -d $dir;
        foreach my $bin (@{$bin_ar}) {
            if (-f File::Spec->catfile($dir, $bin)) {
                $bin_fn=File::Spec->catfile($dir, $bin);
                last DIR;
            }
        }
    }


    #  Normalize fn
    #
    $bin_fn=File::Spec->canonpath($bin_fn) if $bin_fn;


    #  Return
    #
    return $bin_fn;

};


#  Constants
#  <<<
%Constant=(

    GIT_EXE       => $bin_find_cr->([qw(git git.exe)]) || 
        die('unable to locate git binary in path') ,

    MAKE_EXE       => $bin_find_cr->([qw(make make.exe nmake.exe)]) || 
        die('unable to locate git binary in path') ,

    CHANGELOG_FN  => 'ChangeLog',
    
    LICENSE_FN    => 'LICENSE',

    METAFILE_FN   => 'META.yml',

    DUMPER_FN     => '.dumper.cache',

    EXTUTILS_ARGV => q["$(NAME)" "$(NAME_SYM)" "$(DISTNAME)" "$(DISTVNAME)" "$(VERSION)" ] .
        q["$(VERSION_SYM)" "$(VERSION_FROM)" "$(LICENSE)" "$(AUTHOR)"],

    EXTUTILS_GIT  => 'ExtUtils::Git',

    DIST_DEFAULT  => 'git_dist',

    GIT_REPO      => '/opt/git',

    GIT_GROUP     => 'git',
    
    GIT_BRANCH_MASTER => 'master',
    
    GIT_BRANCH_DEVELOPMENT => 'devlopment',
    
    GIT_IGNORE_FN => '.gitignore',
    
    GIT_IGNORE_AR => [qw(
        ChangeLog
        Makefile
        Makefile.old
        MYMETA.json
        MYMETA.yml
        META.yml
        blib/*
        pm_to_blib
        *.bak
        *.old
    )],
    
    
    #  Local constants override anything above
    #
    %{do($local_fn)}

);
#  >>>


#  Export constants to namespace, place in export tags
#
require Exporter;
@ISA=qw(Exporter);
foreach (keys %Constant) { ${$_}=$ENV{$_} ? $Constant{$_}=eval ( $ENV{$_} ) : $Constant{$_} }
@EXPORT=map {'$' . $_} keys %Constant;
@EXPORT_OK=@EXPORT;
%EXPORT_TAGS=(all => [@EXPORT_OK]);
$_=\%Constant;

