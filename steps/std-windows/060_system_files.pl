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
use lib '/sysbuilder/lib';
use SysBuilder::Utils qw(run_local untar_cmd get_base fatal_error);
use SysBuilder::Network;
use Socket;
use YAML qw(LoadFile);

my $cfg = YAML::LoadFile('/sysbuilder/etc/config.yaml');
exit 0 if $cfg->{only_reconfigure};
fatal_error("Couldn't load config.yaml") unless $cfg;

my $dhclient = YAML::LoadFile('/sysbuilder/etc/dhclient.yaml');
fatal_error("Couldn't load dhclient.yaml") unless $dhclient;

my $network = SysBuilder::Network->new( cfg => $cfg );

my $hostname = $cfg->{hostname};

my ( $ip, $netmask, $gateway, $device, $dns1, $dns2 );

# pull from config.yaml first to respect private builds

# get ip, netmask
if ( exists $cfg->{interfaces}{PRIMARY} ) {
    $ip      = $cfg->{interfaces}{PRIMARY}{ip};
    $netmask = $cfg->{interfaces}{PRIMARY}{netmask};
}

# get gateway
if ( exists $cfg->{gateway_ip} ) {
    $gateway = $cfg->{gateway_ip};
}

# get DNS
if ( exists $cfg->{dns} ) {
    ( $dns1, $dns2 ) = @{ $cfg->{dns}{nameserver} };
}

# fill in missing gaps from dhclient, get device name
for my $eth ( sort keys %$dhclient ) {
    my @dns = split ' ', $dhclient->{$eth}{domain_name_servers};
    $dns1    ||= $dns[0];
    $dns2    ||= $dns[1];
    $gateway ||= $dhclient->{$eth}{routers};
    $ip      ||= $dhclient->{$eth}{ip_address};
    $netmask ||= $dhclient->{$eth}{subnet_mask};
    $device = $dhclient->{$eth}{interface};
}

# always get MAC from dhclient
my $devices = $network->net_devices();
my $mac     = $devices->{$device}{mac};

print "Updating IpInput...\n";
print
    "ip: $ip, subnet: $netmask, gateway: $gateway, dns1: $dns1, dns2: $dns2, mac: $mac\n";

system( "mkdir -p /mnt/winpe/post.config" ) if ! -d "/mnt/winpe/post.config";
open IP, ">/mnt/winpe/post.config/ipinput.txt"
    or fatal_error("Couldn't open ipinput.txt for writing");
{
    local $\ = "\r\n";
    print IP "ip:$ip";
    print IP "subnetmask:$netmask";
    print IP "gateway:$gateway";
    print IP "dns1:$dns1";
    print IP "dns2:$dns2";
    print IP "mac:$mac";
    
    if( my $dns1r = gethostbyaddr(inet_aton($dns1),AF_INET) ) {
        print IP "dns1resolv:$dns1r";
    }
    
    if( my $dns2r = gethostbyaddr(inet_aton($dns2),AF_INET) ) {
        print IP "dns2resolv:$dns2r";
    }
}
close IP;

exit 0;

