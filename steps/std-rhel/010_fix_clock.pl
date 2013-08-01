######################################################################
# Copyright (c) 2012, Yahoo! Inc. All rights reserved.
#
# This program is free software. You may copy or redistribute it under
# the same terms as Perl itself. Please see the LICENSE.Artistic file 
# included with this project for the terms of the Artistic License
# under which this project is licensed. 
######################################################################

#!/usr/bin/perl

use strict;
use warnings 'all';
use YAML qw();
use lib '/sysbuilder/lib';
use SysBuilder::Utils qw(run_local printbold);
use SysBuilder::Network;

my $cfg      = YAML::LoadFile('/sysbuilder/etc/config.yaml');
my $dhclient = YAML::LoadFile('/sysbuilder/etc/dhclient.yaml');
my $net      = SysBuilder::Network->new( cfg => $cfg );

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
