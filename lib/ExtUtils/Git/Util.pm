#  Utility class for ExtUtils::Git
#
package ExtUtils::Git::Util;


#  Compiler Pragma
#
use strict qw(vars);
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


#  Done
#
1;

#==================================================================================================


sub err {


    #  Quit on errors
    #
    my $msg=shift();
    croak &fmt("*error*\n\n" . ucfirst($msg), @_);

}


sub msg {


    #  Print message
    #
    CORE::print &fmt(@_), "\n";

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


sub arg {

    #  Get args, does nothing but intercept distname for messages, convert to param
    #  hash
    #
    my %param;
    @param{qw(NAME NAME_SYM DISTNAME DISTVNAME VERSION VERSION_SYM VERSION_FROM LICENSE AUTHOR)}=@_;
    return \%param

}

