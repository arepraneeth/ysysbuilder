package Yahoo::SysBuilder::FreeBSD;

use strict;
use warnings 'all';
use lib '/sysbuilder/lib';
use Yahoo::SysBuilder::Utils qw(run_local);

sub new {
    my $class = shift;
    my $self = bless {}, $class;

    return $self;
}

sub disable_logging {
    my $QUIET = ">/dev/null 2>&1 || :";
    run_local("sysctl net.inet.tcp.log_in_vain=0 $QUIET");
    run_local("sysctl net.inet.udp.log_in_vain=0 $QUIET");
    run_local("sysctl debug.bootverbose=0 $QUIET");
}

sub recommended_swap {
    chomp( my $maxmem = `sysctl -n hw.maxmem 2>/dev/null` );
    if ($maxmem) {

    }
}

1;

