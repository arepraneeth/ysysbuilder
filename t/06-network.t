#!/usr/local/bin/perl

use strict;
use warnings 'all';

use FindBin(qw($Bin));
use lib qq($Bin/../lib);

use Test::More tests => 36;
use Test::Differences;
use SysBuilder::Proc;

my $module = 'SysBuilder::Network';
use_ok($module);

# make sure our public API is properly exposed
can_ok( $module, 'new' );
can_ok( $module, 'config' );
can_ok( $module, 'primary_iface' );
can_ok( $module, 'gateway_ip' );
can_ok( $module, 'gateway_ip6' );
can_ok( $module, 'hostname' );
can_ok( $module, 'boothost_ip' );
can_ok( $module, 'net_devices' );
can_ok( $module, 'ip' );
can_ok( $module, 'ip6' );
can_ok( $module, 'netmask' );

# we need to test the two methods of getting information

# 1. Using a dhclient generated output
my $n = SysBuilder::Network->new(
    dhclient_file => "files/network-dhclient.yaml",
    dryrun        => 1
);
eq_or_diff( $n->primary_iface, "eth0",                 "Primary interface is eth0" );
eq_or_diff( $n->hostname,      "js32.net.foo.com", "Hostname ok" );
eq_or_diff( $n->boothost_ip,   "169.254.100.254",      "Boothost IP" );
eq_or_diff( $n->gateway_ip,    "169.254.100.2",        "Gateway IP from dhclient" );
is        ( $n->gateway_ip6,    undef,                 "IPv6 gateway not set by dhclient" );
eq_or_diff( $n->ip,            "169.254.100.3",        "IP from dhclient" );
is        ( $n->ip6,            undef,                 "IPv6 address not set by dhclient" );
eq_or_diff( $n->netmask,       "255.255.255.0",        "netmask from dhclient" );

# 2. Using /proc/cmdline wiht ip=...
my $IP_INFO = "ip=169.254.100.10:1.2.3.4:169.254.100.1:255.255.255.0:xen-vm:eth1:off";
my $n2      = SysBuilder::Network->new(
    proc   => SysBuilder::Proc->new( cmdline => "ro root=/dev/sda1 $IP_INFO" ),
    dryrun => 1
);

undef $n;
eq_or_diff( $n2->primary_iface, "eth1",           "primary interface from ip_info" );
eq_or_diff( $n2->hostname,      "xen-vm",         "hostname from ip_info" );
eq_or_diff( $n2->boothost_ip,   "1.2.3.4",        "boothost_ip from ip_info" );
eq_or_diff( $n2->gateway_ip,    "169.254.100.1",  "gateway_ip from ip_info" );
is        ( $n2->gateway_ip6,   undef,            "IPv6 gateway not set by ip_info" );
eq_or_diff( $n2->netmask,       "255.255.255.0",  "netmask from ip_info" );
eq_or_diff( $n2->ip,            "169.254.100.10", "ip from ip_info" );
is        ( $n2->ip6,           undef,            "IPv6 address not set by ip_info" );

# 3. Using yaml profile keys
my $n3 = SysBuilder::Network->new(
    dhclient_file => "files/network-dhclient.yaml",
    cfg =>
      { gateway_ip => "169.254.100.10", gateway_ip6 => "fe80::1", interfaces => { 'PRIMARY' => { bootproto => 'static', ip => "169.254.100.11", netmask => "255.255.0.0", ip6 => "fe80::10" } } },
    dryrun => 1,
);

eq_or_diff( $n3->primary_iface, "eth0",                 "Primary interface is eth0" );
eq_or_diff( $n3->hostname,      "js32.net.foo.com", "Hostname falls through from profile to dhclient" );
eq_or_diff( $n3->boothost_ip,   "169.254.100.254",      "Boothost IP falls through from profile to dhclient" );
eq_or_diff( $n3->gateway_ip,    "169.254.100.10",       "Gateway IP from profile overrides dhclient" );
eq_or_diff( $n3->gateway_ip6,   "fe80::1",              "IPv6 gateway from profile" );
eq_or_diff( $n3->ip,            "169.254.100.11",       "IP from profile overrides dhclient" );
eq_or_diff( $n3->ip6,           "fe80::10",             "IPv6 address from profile" );
eq_or_diff( $n3->netmask,       "255.255.0.0",          "netmask from profile overrides dhclient" );
