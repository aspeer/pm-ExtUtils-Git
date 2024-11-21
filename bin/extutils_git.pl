#!/usr/bin/perl

#  This file is part of the ExtUtils::Git module
#
#
#


#  Compiler pragma
#
use strict qw(vars);
use vars qw($VERSION);


#  Base support modules
#
use FindBin qw($RealBin $Script);
FindBin::again();
use Getopt::Long qw(:config permute);
use Pod::Usage;
use Data::Dumper;
use File::Spec;
use Cwd;
$Data::Dumper::Indent=1;
$Data::Dumper::Terse=1;


#  Utility modules
#
use ExtUtils::Git::Util qw(msg);


#  Constants
#
use constant {

    #  Option defaults
    #
    OPT_DEFAULT_HR      =>      {
        %{do("$RealBin/${Script}.option") || {}},
        %{do(glob("~/.${Script}.option")) || {}}
    },
    
    
    #  Action synonyms
    #
    ACTION_SYNONYM      => {
    }

    
};


#  Version Info, must be all one line for MakeMaker, CPAN.
#
$VERSION = '0.001';


#  Var to control verbosity, silence
#
our ($Silent, $Verbose, $Logfile, $Debug);


#  Run main
#
exit ${ &main( &opt() ) || die 'unknown error'};


#===================================================================================================

sub main {

    my $opt_hr=shift();
    my $self=bless($opt_hr);
    &err_init($self) ||
        die('unable to setup error handler');
    return &dispatch($self) ||
        err('unknown error from dispatch handler');

}



sub opt {

    #  Default options
    #
    my %opt = (
        
        %{+OPT_DEFAULT_HR},

    );
    my @opt = ( qw(
        
        help|?
        version
        man
        fn:s
        silent
        verbose
        debug
    
    ));
    

    #  Routine to capture files/names to process into array
    #
    my $arg_cr=sub { 
        #  Eval to handle different Getopt:: module 
        $opt{'action'}=eval { $_[0]->name } || $_[0];
    };
    

    #  Get command line options, handle no action items (help, man etc.)
    #
    GetOptions( \%opt, @opt, '<>' => $arg_cr ) || pod2usage(2);
    
    
    #  If no action option try $0 as alias for symlink but not if same as
    #  file name
    #
    unless ($opt{'action'}) {
        unless (File::Spec->rel2abs($0) eq Cwd::realpath(__FILE__)) {
            #  We appear to be running as a symlink so use $0 as action
            #  after cleanup
            $opt{'action'}=[File::Spec->splitpath(File::Spec->rel2abs($0))]->[2];
            #  Strip any .pl suffix
            $opt{'action'}=~s/\.pl$//;
        }
    }
    if ($opt{'help'} || !$opt{'action'}) {
        pod2usage( -verbose => 99, -sections => 'SYNOPSIS|OPTIONS|USAGE', -exitval => 1 )
    }
    elsif ($opt{'man'}) {
        pod2usage( -exitstatus=>0, -verbose => 2 ) if $opt{'man'};
    }
    elsif ($opt{'version'}) {
        print "$Script version: $VERSION\n";
    };
    
    
    #  If silent set global flag
    #
    foreach my $opt (qw(silent verbose debug logfile)) {
        ${ucfirst($opt)}=$opt{$opt} if $opt{$opt}
    }
    
    
    #  Done
    #
    return \%opt;
    
    
}


sub err_init {

    my $self=shift();
    use Carp;
    *::err = sub { 
        croak &msg(sprintf(shift || 'undefined error', @_));
    }
    
}



sub dispatch {


    #  Dispatch
    #
    my $self=shift();
    my $action=$self->{'action'};
    $action = ACTION_SYNONYM->{$action} || $action;
    my $action_cr=__PACKAGE__->can("extutils_git_${action}") || 
        return err("unknown action: $action");
    return $action_cr->($self);


}    


sub extutils_git_noop {

    #  Null operation for debugging
    #
    $Debug++;
    msg(debug("noop: %s", __PACKAGE__));
    return \undef;
    
}


sub extutils_git_md2readme {

    #  Null operation for debugging
    #
    my $self=shift();
    msg(debug("md2pod: %s", __PACKAGE__));
    
    
    #  Get file name to convert
    #
    my $fn=$self->{'fn'} ||
        return err('no filename to convert specified');

    #  Convert file
    #
    use App::Markpod;
    my $markpod_or=App::Markpod->new({
        extract		=> 1,
        outfile		=> 'README.md'
    }) || return err('unable to create new App::Markpod object');
    $markpod_or->markpod($fn) ||
        return err("error on converting file $fn to markpod");


    #  Done
    #
    return \undef;
    
}


sub debug {

    my $caller=[caller(1)]->[3];
    my $package=__PACKAGE__;
    $caller=~s/^${package}:://e;
    msg("$caller: ". shift(), @_) if $Debug;
    
}
