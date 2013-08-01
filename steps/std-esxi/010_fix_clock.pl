#!/usr/bin/perl

use strict;
use warnings 'all';
use YAML qw();
use lib '/sysbuilder/lib';
use Yahoo::SysBuilder::Utils qw(run_local printbold);
use Yahoo::SysBuilder::Network;

my $cfg      = YAML::LoadFile('/sysbuilder/etc/config.yaml');
my $dhclient = YAML::LoadFile('/sysbuilder/etc/dhclient.yaml');
my $net      = Yahoo::SysBuilder::Network->new( cfg => $cfg );

my $err = 1;

my $iface_name  = $net->primary_iface;
my $ntp_servers = $dhclient->{$iface_name}{ntp_servers};

if ($ntp_servers) {
    foreach my $server ( split ' ', $ntp_servers ) {
        $err = run_local("ntpdate $server");
        last unless $err;
    }
}

unless ($err) {
    run_local("hwclock --systohc");
}

# warn on ntp errors if we can't reach an ntp server.
if ($err) {
    printbold("ALERT! no working ntp server found! Unable to set the correct date and time.\n");
}

exit 0;
