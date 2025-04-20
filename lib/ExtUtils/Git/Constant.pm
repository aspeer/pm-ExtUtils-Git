#
#  This file is part of ExtUtils::Git.
#
#  This software is copyright (c) 2025 by Andrew Speer <andrew.speer@isolutions.com.au>.
#
#  This is free software; you can redistribute it and/or modify it under
#  the same terms as the Perl 5 programming language system itself.
#
#  Full license text is available at:
#
#  <http://dev.perl.org/licenses/>
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


#  Version information in a format suitable for CPAN etc. Must be
#  all on one line
#
$VERSION='1.181';


#===================================================================================================


#  Get module file name and path, derive name of file to store local constants
#
my $module_fn=abs_path(__FILE__);
my $constant_local_fn="${module_fn}.local";
my $constant_home_fn=glob(sprintf('~/.%s.local', __PACKAGE__));


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
    return $bin_fn || '';

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

    CPANFILE_FN => 'cpanfile',

    METAFILE_FN => 'META.yml',

    EXTUTILS_ARGV => q["$(NAME)" "$(NAME_SYM)" "$(DISTNAME)" "$(DISTVNAME)" "$(VERSION)" ] .
        q["$(VERSION_SYM)" "$(VERSION_FROM)" "$(LICENSE)" "$(AUTHOR)" "$(TO_INST_PM)" "$(EXE_FILES)" "$(DIST_DEFAULT_TARGET)" "$(SUFFIX)" "$(ABSTRACT_FROM)"],

    EXTUTILS_GIT => 'ExtUtils::Git',

    DIST_DEFAULT => 'git_dist',

    GIT_GROUP => 'git',

    GIT_BRANCH_MAIN 	=> 'main',
    GIT_BRANCH_MASTER 	=> 'master',
    GIT_BRANCH_MASTER_QR => qr/^(master|main)$/,

    GIT_BRANCH_DEVELOPMENT => 'development',

    GIT_REMOTE_HR => {
        origin => 'gitea@localhost:/aspeer/%s-%s.git',
    },

    GIT_IGNORE_FN => '.gitignore',

    GIT_IGNORE_AR => [qw(
            ChangeLog
            Changes
            Makefile
            Makefile.old
            MYMETA.json
            MYMETA.yml
            META.yml
            META.json
            blib/*
            pm_to_blib
            *.bak
            *.old
            .DS_Store
            ._.DS_Store
            *~
            *.tmp
            .dumper.cache
            *.tdy
            .pm_filter.pf
            )
    ],

    TEMPLATE_POSTAMBLE_FN => &fn('postamble.inc'),

    TEMPLATE_COPYRIGHT_FN => &fn('copyright.inc'),

    GIT_AUTOCOPYRIGHT_EXCLUDE_AR => [qr/^LICENSE$/, qr/\.xml$/, qr/copyright\.inc$/, qr/postamble\.inc/],

    GIT_AUTOCOPYRIGHT_EXCLUDE_POD_AR => [qr/^LICENSE$/],

    GIT_AUTOCOPYRIGHT_EXCLUDE_XML_AR => [qr/^t\//],

    GIT_AUTOCOPYRIGHT_EXCLUDE_MD_AR => [],

    GIT_AUTOCOPYRIGHT_EXCLUDE_FN => '.git_autocopyright_exclude',

    COPYRIGHT_HEADER_MAX_LINES => 20,

    COPYRIGHT_KEYWORD => 'Copyright',

    COPYRIGHT_KEYWORD_AR => [qw(copyright copying license)],

    COPYRIGHT_HEADER_POD => "=head%s LICENSE and COPYRIGHT\n",

    COPYRIGHT_HEADER_XML => "<title>LICENSE and COPYRIGHT</title>\n\n",

    COPYRIGHT_HEADER_MD => "LICENSE and COPYRIGHT\n",
    
    COPYRIGHT_HEADER => 'LICENSE and COPYRIGHT',

    PANDOC_EXE => &bin_find(qw(pandoc pandoc.exe)),

    PANDOC_CMD_DOCBOOK2MD_CR => sub {
        return [
            shift(),                # PANDOC_EXE
            '-fdocbook',            # from docbook
            '-tmarkdown_github',    # to markdown (github dialect)
            shift(),                # File name
            ]
    },

    PANDOC_CMD_MD2TEXT_CR => sub {
        return [
            shift(),                # PANDOC_EXE
            '-fmarkdown_github',    # from markdown (github dialect)
            '-tplain',              # to plaintext
            shift(),                # File name
            ]
    },

    PANDOC_CMD_DOCBOOK2TEXT_CR => sub {
        return [
            shift(),                # PANDOC_EXE
            '-fdocbook',             # from docbook
            '-tplain',              # to plaintext
            shift(),                # File name
            ]
    },
    
    TEXT_FN_AR => [qw(README INSTALL)],


    #  Dialect one of Standard, Github, Theory
    #
    MARKDOWN_DIALECT => 'Theory',


    #  Local constants override anything above
    #
    %{do($constant_local_fn)},
    %{do($constant_home_fn)}
    

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

