package Yahoo::SysBuilder::HWRaid::LSI;
use strict;
use warnings 'all';
use Yahoo::SysBuilder::Utils qw(run_local fatal_error);
use Yahoo::SysBuilder::Proc;

sub new {
    my $class   = shift;
    my %params  = @_;
    my $modules = $params{modules};
    my $binary  = $params{binary} || 'megarc';
    my $verbose = $params{verbose};
    my $proc    = Yahoo::SysBuilder::Proc->new;

    my $self = bless {
        cli     => $binary,
        modules => $modules,
        verbose => 1 || $verbose,
    }, $class;

    unless ( -e "/dev/megadev0" ) {
        my $block = $proc->devices->{block};
        my $dev_number = $block->{megadev} || $block->{mdp}
            or fatal_error("megadev device not found");
        $self->system("mknod /dev/megadev0 c $dev_number 0");
    }
    return $self;
}

sub jbod {
    my $self = shift;
    my $cli  = $self->{cli};
    $self->system("$cli -EachDskRaid0 -a0 WB RAA CIO");

    1;
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
            $self->jbod;
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

    1;
}

sub system {
    my ($self, @args) = @_;
    print "% @args\n" if $self->{verbose};
    run_local(@args);
}

1;
