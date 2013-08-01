#!/usr/local/bin/perl

use strict;
use warnings 'all';

use FindBin(qw($Bin));
use lib qq($Bin/../lib);

use Test::More tests => 6;
use Test::Differences;

my $module = 'SysBuilder::Modules';
use_ok($module);
use SysBuilder::Utils qw(read_file);
use YAML ();

my @modules;

sub my_modprobe {
    my ( $mod_type, $module ) = @_;
    push @modules, [ $mod_type, $module ];
}

my @vmware = read_file("files/vmware-lspci1");
my $m      = SysBuilder::Modules->new(
    pcimap   => "files/pcimap-2.6.9-42.ELsmp-i686",
    pcitable => "/dev/null",
    devices  => \@vmware,
    modprobe => \&my_modprobe
);

$m->load;
eq_or_diff(
    \@modules, [
        [ 'storage',    'Unknown-8086:7111' ],
        [ 'storage',    'mptspi' ],
        [ 'scsi disks', 'sd_mod' ],
        [ 'network',    'pcnet32' ]
    ],
    "Loading modules (vmware 1 unknown device)"
);

@modules = ();
$m->load("/tmp/modules-test.$$");

my $mod = YAML::LoadFile("/tmp/modules-test.$$");
my %expected = ( 'net' => ['pcnet32'], 'scsi' => [ 'Unknown-8086:7111', 'mptspi' ] );

eq_or_diff( $mod, \%expected, "Generates yaml description" );
unlink("/tmp/modules-test.$$");

my @dl160 = read_file("files/dl160g5.lspci");
$m = SysBuilder::Modules->new(
    pcimap   => "/dev/null",
    pcitable => "files/pcitable-vmware-352",
    devices  => \@dl160,
    modprobe => \&my_modprobe
);
@modules = ();
$m->load;
eq_or_diff(
    \@modules, [
        [ 'storage',    'Unknown-8086:269e' ],
        [ 'storage',    'Unknown-8086:2681' ],
        [ 'storage',    'mptscsi_2xx' ],
        [ 'scsi disks', 'sd_mod' ],
        [ 'network',    'ignore' ]
    ],
    "Loading modules using esx pcitable"
);

$m = SysBuilder::Modules->new(
    pcimap   => "files/pcimap-2.4.21-57.ELvmnix",
    pcitable => "files/pcitable-vmware-352",
    devices  => \@dl160,
    modprobe => \&my_modprobe
);
@modules = ();
$m->load;
eq_or_diff(
    \@modules, [
        [ 'storage',    'Unknown-8086:269e' ],
        [ 'storage',    'ahci' ],
        [ 'storage',    'mptscsi_2xx' ],
        [ 'scsi disks', 'sd_mod' ],
        [ 'network',    'tg3' ]
    ],
    "Loading modules using esx pcitable and pcimap"
);

my @dl145 = read_file("files/dl145.lspci");
$m = SysBuilder::Modules->new(
    pcimap   => "files/pcimap-2.6.9-42.ELsmp-i686",
    pcitable => "/dev/null",
    devices  => \@dl145,
    modprobe => \&my_modprobe
);
@modules = ();
$m->load;
eq_or_diff(
    \@modules, [
        [ 'storage',    'Unknown-8086:24db' ],
        [ 'storage',    'aic79xx' ],
        [ 'scsi disks', 'sd_mod' ],
        [ 'network',    'tg3' ]
    ],
    "Loading modules using aic79xx hack"
);
