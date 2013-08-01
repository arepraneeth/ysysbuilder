#!/usr/local/bin/perl

use strict;
use warnings 'all';

# test SysBuilder::CfgManagement

use FindBin(qw($Bin));
use lib qq($Bin/../lib);

use Test::More tests => 16;
use SysBuilder::Utils qw(write_file read_file);

my $module = 'SysBuilder::CfgManagement';

use_ok($module);
can_ok( $module, 'fetch' );
can_ok( $module, 'activate' );

my @args;
my $exit_code;
my $fatal_error = 0;

undef *SysBuilder::CfgManagement::run_local;
undef *SysBuilder::CfgManagement::fatal_error;
*SysBuilder::CfgManagement::run_local = sub { @args = @_; $exit_code };
*SysBuilder::CfgManagement::fatal_error = sub { $fatal_error = 1 };

use SysBuilder::Network;

my $net = SysBuilder::Network->new(
    dhclient_file => "files/network-dhclient.yaml",
    dryrun        => 1
);

my $cm = $module->new(
    { 'cm_fetch' => 'cm_fetch_cmd', 'cm_activate' => 'cm_activate_cmd' },
    resolv_conf => "/tmp/resolv.$$",
    net => $net );

# CfgManagement temporarily modifies /mnt/etc/resolv.conf, so make sure it doesn't make permanent changes
my $initial_resolv_conf = <<EOT;
nameserver 1.2.3.7
nameserver 1.2.3.8
EOT
write_file( "/tmp/resolv.$$", $initial_resolv_conf );

$exit_code = 0;
$cm->fetch;
is_deeply( \@args, ["chroot /mnt /bin/sh -c 'cm_fetch_cmd'"], "fetch" );
is($fatal_error, 0, 'fetch did not fail');

$cm->activate;
is_deeply( \@args, ["chroot /mnt /bin/sh -c 'cm_activate_cmd'"], "activate" );
is($fatal_error, 0, 'activate did not fail');

my $after_resolv_conf = read_file( "/tmp/resolv.$$" );
is( $after_resolv_conf, $initial_resolv_conf, 'resolv.conf was not permanently changed' );

# let's make it fail now
$exit_code = 1;
$cm->fetch;
is($fatal_error, 1, 'fetch failed detected');

$fatal_error = 0;
$cm->activate;
is($fatal_error, 1, 'activate failed detected');

$fatal_error = 0;
my $cm2 = $module->new({}, net => $net);
$cm2->fetch;
is($fatal_error, 0, 'fetch does nothing if key is missing');

$fatal_error = 0;
$cm2->activate;
is($fatal_error, 0, 'activate does nothing if key is missing');

# check that chroot => 0 does the right thing
$exit_code = 0;
$cm->{chroot} = 0;

$cm->fetch;
is_deeply( \@args, ["/bin/sh -c 'cm_fetch_cmd'"], "non-chroot fetch" );
is($fatal_error, 0, 'non-chroot fetch did not fail');

$cm->activate;
is_deeply( \@args, ["/bin/sh -c 'cm_activate_cmd'"], "non-chroot activate" );
is($fatal_error, 0, 'non-chroot activate did not fail');

unlink( "/tmp/resolv.$$" );
