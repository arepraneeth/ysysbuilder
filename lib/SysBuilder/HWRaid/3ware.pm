######################################################################
# Copyright (c) 2012, Yahoo! Inc. All rights reserved.
#
# This program is free software. You may copy or redistribute it under
# the same terms as Perl itself. Please see the LICENSE.Artistic file 
# included with this project for the terms of the Artistic License
# under which this project is licensed. 
######################################################################

package SysBuilder::HWRaid::3ware;

use strict;
use warnings 'all';
use POSIX qw();
use FindBin(qw($Bin));
use lib qq($Bin/../lib);
use SysBuilder::Utils qw(fatal_error set_status);
use Carp qw(confess);

sub new {
    my $class   = shift;
    my %params  = @_;
    my $modules = $params{modules};
    my $binary  = $params{binary};
    my $verbose = $params{verbose};

    unless ($binary) {
        my $arch = ( POSIX::uname() )[3];
        $binary
            = $arch eq "x86_64"
            ? "/usr/sbin/tw_cli.x86_64"
            : "/sbin/tw_cli";
    }

    return bless {
        cli     => $binary,
        modules => $modules,
        verbose => $verbose,
    }, $class;
}

sub jbod {
    my $self = shift;
    for my $c ( $self->get_controllers ) {
        $self->clear_controller($c);
    }
}

# setup according to the YAML definition
sub setup {
    my ( $self, $cfg ) = @_;
    confess("3ware->setup(cfg)") unless ( $cfg
        && ref $cfg eq "HASH" );

    my $config = $cfg->{"3ware"} || $cfg->{"hwraid"};
    $self->{config} = $config;

    for my $c ( sort keys %$config ) {
        $self->clear_controller($c);
        for my $u ( sort keys %{ $config->{$c} } ) {
            my $cfg_u  = $config->{$c}->{$u};
            my $spares = $cfg_u->{spares} || 0;
            my @disks  = $self->get_ports( $c, $cfg_u->{physicaldisks}, $spares );
            my $type   = $cfg_u->{raidtype};
            $self->maker( $c, $type, \@disks, $spares );
        }
    }
    return 1;
}

sub maker {
    my ( $self, $c, $type, $disks, $spares ) = @_;
    my $cmd = "/$c add type=$type disk=" . join( ":", @$disks );
    $self->cli($cmd);

    # add spares
    my @spare_ports = $self->get_ports( $c, $spares, 0 );
    for my $port (@spare_ports) {
        $self->cli("/$c/p$port export quiet");
    }

    $self->cli("/$c rescan");
    if (@spare_ports) {
        $self->cli( "/$c add type=spare disk=" . join( ":", @spare_ports ) );
        $self->cli("/$c rescan");
    }

    my $controller_cfg = $self->{config}->{ "c" . $c };

    # support autocarve
    my $autocarve = $controller_cfg->{autocarve};
    if ($autocarve) {
        $self->cli("/$c set autocarve=on");

        # $autocarve should be a number [1024,2048] or 'auto'
        if ( $autocarve eq "auto" ) {
            $autocarve = round( $self->unit_size( $c, "u0" ) );
            $autocarve = 1024 if $autocarve < 1024;
            $autocarve = 2048 if $autocarve > 2048;
        }
        if ( $autocarve >= 1024 and $autocarve <= 2048 ) {
            $self->cli("/$c set carvesize=$autocarve");
        }
        else {
            $self->error("3ware: carvesize must be between 1024 and 2048");
        }
    }
    else {
        $self->cli("/$c set autocarve=off");
    }

    $self->cli("/$c rescan");
    system("sync;sync");
}

sub clear_controller {
    my ( $self, $controller ) = @_;
    my @units = $self->get_units($controller);

    for my $unit (@units) {
        $self->cli("/$controller/$unit del");
    }
}

sub get_controllers {
    my $self = shift;
    my $cli  = $self->{cli};
    my @controllers;

    open my $info, "$cli info" or fatal_error("$cli info failed");
    while (<$info>) {
        next unless /\A c (\d+)/msx;
        push @controllers, $1;
    }
    close $info;

    return @controllers;
}

sub get_units {
    my ( $self, $controller ) = @_;

    my @info = $self->controller_info($controller);
    my @units;
    for (@info) {
        next unless /\A(u\d+)\s/msx;
        push @units, $1;
    }
    return @units;
}

sub get_ports {
    my ( $self, $controller, $what, $spares ) = @_;

    my @ports = $self->get_free_ports($controller);
    if ( $what eq "all" ) {
        $what = @ports - $spares;    # we want all (minus spares)
    }

    my $free   = @ports;
    my $needed = $what + $spares;

    if ( $free >= $needed ) {
        return splice( @ports, 0, $what );
    }
    else {
        $self->error(
            "Need $needed free ports ($what + $spares) but only $free available");
        return;
    }
}

sub get_free_ports {
    my ( $self, $controller ) = @_;
    my @info = $self->controller_info($controller);
    my @ports;
    for (@info) {
        next unless /\A p (\d+) \s+ OK \s+ - \s/msx;
        push @ports, $1;
    }
    return @ports;
}

sub controller_info {
    my $self = shift;
    my $c    = shift;
    my $cli  = $self->{cli};
    open my $pipe, "$cli info $c |"
        or $self->error("$cli info $c");
    my @info = <$pipe>;
    close $pipe;

    return @info;
}

sub cli {
    my ( $self, $cmd ) = @_;
    confess("Usage: 3ware->cli(cmd)") unless defined $cmd;
    my $cli = $self->{cli};
    system("yes | $cli $cmd");
    print "% yes | $cli $cmd\n" if $self->{verbose};
    if ($?) {
        $self->error("$cli $cmd");
    }
}

sub error {
    my $self = shift;
    my $msg  = shift;
    fatal_error($msg);
}

1;
