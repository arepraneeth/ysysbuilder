package Yahoo::SysBuilder::HWRaid::Megacli;
use strict;
use warnings 'all';
use Yahoo::SysBuilder::Utils qw(run_local fatal_error);
use Yahoo::SysBuilder::Proc;

sub new {
    my $class   = shift;
    my %params  = @_;
    my $modules = $params{modules};
    my $binary  = $params{binary} || 'megacli';
    my $verbose = $params{verbose};
    my $proc    = Yahoo::SysBuilder::Proc->new;

    my $self = bless {
        cli     => $binary,
        modules => $modules,
        verbose => 1 || $verbose,
    }, $class;

    return $self;
}

sub jbod {
    my $self = shift;
    my $adapter = $_[0] || "a0";

    my $cli = $self->{cli};
    $self->system("$cli -CfgLdDel -LALL -$adapter");
    $self->system("$cli -CfgEachDskRaid0 WB RA -$adapter");
}

sub setup {
    my ( $self, $lsi ) = @_;

    fatal_error('usage $LSI->setup(disk_config)')
        unless $lsi || ref($lsi) ne 'HASH';

    my $cli = $self->{cli};

    for my $adapter ( keys %$lsi ) {
        print "Configuring LSI Adapter $adapter:\n" if $self->{verbose};
        my $config = $lsi->{$adapter}{config};
        if ( lc($config) eq 'jbod' ) {
            $self->jbod($adapter);
        }
        else {
            my @cmds      = @$config;
            my $first_cmd = shift @cmds;
            $self->system("$cli -newCfg -a0 $first_cmd");
            for my $cmd (@cmds) {
                $self->system("$cli -addCfg -a0 $cmd");
            }
        }
    }

    # get new scsi devices
    system("rmmod megaraid_sas; sleep 1; modprobe megaraid_sas");
    1;
}

sub system {
    my ( $self, @args ) = @_;
    print "% @args\n" if $self->{verbose};
    run_local(@args);
}

1;
