package Yahoo::SysBuilder::Console;

# Console from the live system

use strict;
use warnings 'all';
use FindBin(qw($Bin));
use lib qq($Bin/../lib);
use Yahoo::SysBuilder::Proc;
use YAML qw();

sub new {
    my $class  = shift;
    my %params = @_;

    my $cmdline = $params{cmdline};    # for testing
    return bless { console => undef, cmdline => $cmdline }, $class;
}

=item

boot_console is the console we're going to use during the normal boot
process

=cut

sub boot_console {
    my $self = shift;
    my $cfg  = shift;

    my @settings = $self->boot_serial_settings($cfg);
    return "" unless @settings;
    return "console=ttyS$settings[0],$settings[1]";
}

sub boot_serial_settings {
    my $self = shift;
    my $cfg  = shift;

    my $serial_port      = $cfg->{console_serial_port};
    my $serial_speed     = $cfg->{console_serial_speed} || 9600;
    my $skip_auto_detect = $cfg->{console_skip_autodetect};

    unless ($skip_auto_detect) {

        # load overrides if present
        eval {
            my $overrides = YAML::LoadFile("/sysbuilder/etc/overrides.yaml");
            if ( defined $overrides->{console_serial_port} ) {
                $serial_port = $overrides->{console_serial_port};
            }
        };

    }
    return unless defined $serial_port;
    return if $serial_port eq "IGNORE";
    return ( $serial_port, $serial_speed );
}

=item

current_console is the console for this installer

=cut

sub live_console {
    my $self = shift;

    my $console = $self->{console};
    return $console if defined $console;

    my $cmdline;
    if ( defined $self->{cmdline} ) {

        # the user specified a command line so use it
        $cmdline = $self->{cmdline};
    }
    else {

        # get the command line from the live system
        my $yproc = Yahoo::SysBuilder::Proc->new;
        $cmdline = $yproc->cmdline;
    }

    my @console_fields = grep {/^console/} split( ' ', $cmdline );
    unless (@console_fields) {
        $console = "console";
    }
    else {
        $console = _parse_console( $console_fields[-1] );
    }
    $self->{console} = $console;
    return $console;
}

sub is_serial {
    my $self    = shift;
    my $console = $self->live_console;

    return $console =~ /\AttyS/ms;

}

sub _parse_console {
    my $console = shift;
    if ( $console =~ /^console=([^,]+)/ ) {
        return $1;
    }
    return "console";
}

1;
