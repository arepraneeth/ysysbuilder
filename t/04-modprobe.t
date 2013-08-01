#!/usr/local/bin/perl

use strict;
use warnings 'all';

use FindBin(qw($Bin));
use lib qq($Bin/../lib);

#use Test::More tests => 6;

use Test::More qw(no_plan);
use Test::Differences;
use SysBuilder::Utils qw(read_file);

my $module = "SysBuilder::Modprobe";
use_ok($module);
can_ok( $module, 'filename' );

my $m = SysBuilder::Modprobe->new(
    modules_filename => "files/modprobe-test-1.yaml" );
$m->ipv6(undef);    # we don't want ipv6
$m->generate("/tmp/modprobe.conf.$$");
my $generated = read_file("/tmp/modprobe.conf.$$");
my $expected  = <<EOT;
alias eth0 pcnet32
alias scsi_hostadapter mptspi
alias net-pf-10 off
options loop max_loop=256
EOT
eq_or_diff( $generated, $expected, "Ignoring Unknown devices" );

$m = SysBuilder::Modprobe->new(
    modules_filename => "files/modprobe-test-2.yaml" );
$m->ipv6(undef);
$m->generate("/tmp/modprobe.conf.$$");
$generated = read_file("/tmp/modprobe.conf.$$");
eq_or_diff( $generated, $expected, "Basic file ok" );

$expected = <<EOT;
alias eth0 e1000
alias eth1 e1000
alias eth2 e100
alias scsi_hostadapter mptspi
alias scsi_hostadapter1 sata_nv
alias net-pf-10 off
options loop max_loop=256
EOT

$m = SysBuilder::Modprobe->new(
    modules_filename => "files/modprobe-test-3.yaml" );
$m->generate("/tmp/modprobe.conf.$$");
$generated = read_file("/tmp/modprobe.conf.$$");
eq_or_diff( $generated, $expected, "Complex file ok" );

$m->ipv6(1);    # enable ipv6
$m->generate("/tmp/modprobe.conf.$$");
$generated = read_file("/tmp/modprobe.conf.$$");
$expected  = <<EOT;
alias eth0 e1000
alias eth1 e1000
alias eth2 e100
alias scsi_hostadapter mptspi
alias scsi_hostadapter1 sata_nv
options loop max_loop=256
EOT

eq_or_diff( $generated, $expected, "ipv6 support ok" );

$m->ip_conntrack(32768);    # set ip_conntrack hash
$m->generate("/tmp/modprobe.conf.$$");
$generated = read_file("/tmp/modprobe.conf.$$");
$expected  = <<EOT;
alias eth0 e1000
alias eth1 e1000
alias eth2 e100
alias scsi_hostadapter mptspi
alias scsi_hostadapter1 sata_nv
options ip_conntrack hashsize=32768
options loop max_loop=256
EOT

eq_or_diff( $generated, $expected, "ip_conntrack hash support ok" );


unlink "/tmp/modprobe.conf.$$";
