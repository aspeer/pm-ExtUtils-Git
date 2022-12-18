#
#  This file is part of ExtUtils::Git.
#
#  This software is copyright (c) 2022 by Andrew Speer <andrew.speer@isolutions.com.au>.
#
#  This is free software; you can redistribute it and/or modify it under
#  the same terms as the Perl 5 programming language system itself.
#
#  Full license text is available at:
#
#  <http://dev.perl.org/licenses/>
#
package ExtUtils::Git::Util;


use strict;
use vars qw($VERSION @ISA @EXPORT);
use warnings;
no warnings qw(uninitialized);
sub BEGIN {local $^W=0}


#  External modules
#
require Exporter;
use Carp;


#  Export functions
#
@ISA=qw(Exporter);
@EXPORT=qw(err msg arg);


#  Version information in a format suitable for CPAN etc. Must be
#  all on one line
#
$VERSION='1.181';


#  Done
#
1;

#==================================================================================================


sub arg {

    #  Get args, does nothing but intercept distname for messages, convert to param
    #  hash
    #
    my (%param, @argv);
    (@param{qw(NAME NAME_SYM DISTNAME DISTVNAME VERSION VERSION_SYM VERSION_FROM LICENSE AUTHOR TO_INST_PM EXE_FILES DIST_DEFAULT_TARGET SUFFIX ABSTRACT_FROM)}, @argv)=@_;
    $param{'TO_INST_PM_AR'}=[split /\s+/, $param{'TO_INST_PM'}];
    $param{'EXE_FILES_AR'}=[split /\s+/,  $param{'EXE_FILES'}];
    $param{'ARGV_AR'}=\@argv;
    return \%param

}


sub err {


    #  Quit on errors
    #
    my $msg=shift();
    croak &fmt("*error*\n\n" . ucfirst($msg), @_);

}


sub fmt {


    #  Format message nicely. Always called by err or msg so caller=2
    #
    my $message=sprintf(shift(), @_);
    chomp($message);
    my $caller=(split(/:/, (caller(2))[3]))[-1];
    $caller=~s/^_?!(_)//;
    my $format=' @<<<<<<<<<<<<<<<<<<<<<< @<';
    formline $format, $caller . ':', undef;
    $message=$^A . $message; $^A=undef;
    return $message;

}


sub msg {


    #  Print message
    #
    return CORE::print &fmt(@_), "\n";

}

