#  This file is part of ExtUtils::Git.
#
#  This software is copyright (c) 2014 by Andrew Speer <andrew.speer@isolutions.com.au>.
#
#  This is free software; you can redistribute it and/or modify it under
#  the same terms as the Perl 5 programming language system itself.
#
#  Full license text is available at:
#
#  <http://dev.perl.org/licenses/>
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


#  Find file in path
#
sub bin_find {


    #  Find a binary file
    #
    my @bin_fn=@_;
    my $bin_fn;


    #  Find the bin file/files if given array ref. If not supplied as array ref
    #  convert.
    #
    my @dir=grep {-d $_} split(/:|;/, $ENV{'PATH'});
    my %dir=map {$_ => 1} @dir;
    DIR: foreach my $dir (@dir) {
        next unless delete $dir{$dir};
        next unless -d $dir;
        foreach my $bin (@bin_fn) {
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

}


#  Get dn for path ref and make utility function to construct abs path for a file
#
(my $module_dn=$module_fn)=~s/\.pm$//;


sub fn {

    File::Spec->catfile($module_dn, @_)

}


#  Constants
#  <<<
%Constant=(

    GIT_EXE => &bin_find(qw(git git.exe)) ||
        die('unable to locate git binary in path'),

    MAKE_EXE => &bin_find(qw(make make.exe nmake.exe)) ||
        die('unable to locate git binary in path'),

    CHANGELOG_FN => 'ChangeLog',

    LICENSE_FN => 'LICENSE',

    METAFILE_FN => 'META.yml',

    DUMPER_FN => '.dumper.cache',

    EXTUTILS_ARGV => q["$(NAME)" "$(NAME_SYM)" "$(DISTNAME)" "$(DISTVNAME)" "$(VERSION)" ] .
        q["$(VERSION_SYM)" "$(VERSION_FROM)" "$(LICENSE)" "$(AUTHOR)" "$(TO_INST_PM)" "$(EXE_FILES)"],

    EXTUTILS_GIT => 'ExtUtils::Git',

    DIST_DEFAULT => 'git_dist',

    GIT_REPO => '/opt/git',

    GIT_GROUP => 'git',

    GIT_BRANCH_MASTER => 'master',

    GIT_BRANCH_DEVELOPMENT => 'development',

    GIT_REMOTE_HR => {
        origin => 'git@localhost:/%s.git',
    },

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
            )
    ],

    TEMPLATE_POSTAMBLE_FN => &fn('postamble.inc'),

    TEMPLATE_COPYRIGHT_FN => &fn('copyright.inc'),

    GIT_AUTOCOPYRIGHT_INCLUDE_AR => [qr/\.pl$/, qr/\.pm$/],

    GIT_AUTOCOPYRIGHT_EXCLUDE_AR => [],

    COPYRIGHT_HEADER_MAX_LINES => 20,

    COPYRIGHT_KEYWORD => 'Copyright',

    #  Local constants override anything above
    #
    %{do($local_fn)}

);

#  >>>


#  Export constants to namespace, place in export tags
#
require Exporter;
@ISA=qw(Exporter);
foreach (keys %Constant) {${$_}=$ENV{$_} ? $Constant{$_}=eval($ENV{$_}) : $Constant{$_}}    ## no critic
@EXPORT=map {'$' . $_} keys %Constant;
@EXPORT_OK=@EXPORT;
%EXPORT_TAGS=(all => [@EXPORT_OK]);
$_=\%Constant;

