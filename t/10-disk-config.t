#!/usr/local/bin/perl

use strict;
use warnings 'all';

use FindBin(qw($Bin));
use lib qq($Bin/../lib);
use SysBuilder::Utils qw/write_file/;
use Test::More tests => 32;
use Test::Differences;

my $module = 'SysBuilder::DiskConfig';
use_ok($module);
can_ok( $module, 'setup' );

my $cfg = {};
my $disk = SysBuilder::DiskConfig->new( cfg => $cfg );

ok( !$disk->_hwconfig_only, "default is linux - don't reboot" );

$cfg->{'hwconfig_only'} = 1;
$disk = SysBuilder::DiskConfig->new( cfg => $cfg );
ok( $disk->_hwconfig_only, "hwconfig_only present and true means reboot" );

$cfg->{'hwconfig_only'} = 0;
$disk = SysBuilder::DiskConfig->new( cfg => $cfg );
ok( !$disk->_hwconfig_only, "hwconfig_only present and false: don't reboot" );

eq_or_diff( $disk->parse_size( "12G", "12288" ),
            12 * 1024, "Parsing size (12G)" );
eq_or_diff( $disk->parse_size( "200G", "204800" ),
            200 * 1024, "Parsing size (200G)" );
eq_or_diff( $disk->parse_size( "200 G", "204800" ),
            200 * 1024, "Parsing size (200 G)" );
eq_or_diff( $disk->parse_size( "200M", "1000" ),
            200, "Parsing size (200M)" );
eq_or_diff( $disk->parse_size( "200 M", "1000" ),
            200, "Parsing size (200 M)" );
eq_or_diff( $disk->parse_size( "10M", "12288" ), 10,  "Parsing size (MB)" );
eq_or_diff( $disk->parse_size( "10%", 1000 ),    100, "Parsing size (%)" );
eq_or_diff( $disk->parse_size( "5 %", 1000 ),
            50, "Parsing size (% with a space)" );

# hack Proc to return a pre-set number
undef *SysBuilder::Proc::memsize;
*SysBuilder::Proc::memsize = sub { 2018 * 1024 };
eq_or_diff( $disk->parse_size( "memsize", 1 ), 2018, "Parsing memsize=2G" );
undef *SysBuilder::Proc::memsize;
*SysBuilder::Proc::memsize = sub { 20180 * 1024 };
eq_or_diff( $disk->parse_size( "memsize", 1 ),
    12 * 1024, "Parsing memsize=20G (should be capped)" );

*partition_name = *SysBuilder::DiskConfig::partition_name{CODE};

# get rid of the stupid warning
# 'SysBuilder::DiskConfig::partition_name used only once'
*partition_name = *SysBuilder::DiskConfig::partition_name{CODE};

eq_or_diff( partition_name( 'sda', 4 ),
    "sda4", "Partition name for scsi disks" );
eq_or_diff( partition_name( 'hda', 3 ),
    "hda3", "Partition name for IDE disks" );
eq_or_diff( partition_name( 'cciss/c0d0', 1 ),
    'cciss/c0d0p1', 'Partition name for cciss devices' );

open my $fh, ">", "/tmp/disk-cfg.$$" or die "/tmp/disk-cfg.$$: $!";
print $fh <<'EOT';
DEVICE partitions
  ARRAY /dev/md0 level=1 num-devices=2 devices=/dev/sda1,/dev/sdb1
  ARRAY /dev/md1 level=5 num-devices=6 devices=/dev/sda2,/dev/sdb2,/dev/sdc2,/dev/sdd2,/dev/sde2,/dev/sdf2
  ARRAY /dev/md2 level=1 num-devices=2 devices=/dev/cciss/c0d0p2,/dev/cciss/c0d0p1
EOT
close $fh;

*md_device = *SysBuilder::DiskConfig::first_device_in_md{CODE};

# get rid of the used once warning
*md_device = *SysBuilder::DiskConfig::first_device_in_md{CODE};

eq_or_diff( md_device( 'md0', "/tmp/disk-cfg.$$" ),
    "sda1", "Parsing mdadm.conf (1)" );
eq_or_diff( md_device( 'md1', "/tmp/disk-cfg.$$" ),
    "sda2", "Parsing mdadm.conf (2)" );
eq_or_diff( md_device( 'md2', "/tmp/disk-cfg.$$" ),
    "cciss/c0d0p2", "Parsing mdadm.conf with cciss devices" );
ok( !md_device( "md9", "/tmp/disk-cfg.$$" ),
    "Looking for missing md devices"
);
unlink "/tmp/disk-cfg.$$";

*disk_part_from_dev
    = *SysBuilder::DiskConfig::disk_part_from_dev{CODE};

# get rid of the used once warning
*disk_part_from_dev
    = *SysBuilder::DiskConfig::disk_part_from_dev{CODE};
eq_or_diff(
    [ disk_part_from_dev('sda1') ],
    [ 'sda', '1' ],
    'Parsing disk_part from normal devices'
);
eq_or_diff(
    [ disk_part_from_dev('hda10') ],
    [ 'hda', '10' ],
    'Parsing disk_part from normal devices (2)'
);
eq_or_diff(
    [ disk_part_from_dev('cciss/c0d0p1') ],
    [ 'cciss/c0d0', '1' ],
    'Parsing disk_part from cciss devices'
);
eq_or_diff(
    [ disk_part_from_dev('cciss/c0d0p21') ],
    [ 'cciss/c0d0', '21' ],
    'Parsing disk_part from cciss devices (2)'
);

chdir($Bin);
mkdir "files/etc";
mkdir "files/etc/sysconfig";
write_file( "files/etc/hostname", "foo.testing.example.com\n" );

eq_or_diff( $disk->_old_hostname("files"),
    "foo.testing.example.com", "Getting old hostname from /etc/hostname" );

unlink "files/etc/hostname";
write_file( "files/etc/sysconfig/network",
    "NETWORKING=yes\nHOSTNAME=another.test.example.com\nXxX=test\n" );
eq_or_diff( $disk->_old_hostname("files"),
    "another.test.example.com",
    "Getting old hostname from /etc/sysconfig/network" );

write_file( "files/etc/sysconfig/network",
    "NETWORKING=yes\nHOSTNAME=\"yet.another.test.example.com\"\nXxX=test\n" );
eq_or_diff( $disk->_old_hostname("files"),
    "yet.another.test.example.com",
    "Getting old hostname from /etc/sysconfig/network with quotes" );

unlink "files/etc/sysconfig/network";
rmdir "files/etc/sysconfig";
rmdir "files/etc";

# test parted_multiplier

# RHEL 4
do {
    no warnings 'redefine';
    local *SysBuilder::DiskConfig::run_local = sub {};
    local *SysBuilder::DiskConfig::backtick = sub {
        my $arg = shift;
        if( $arg eq 'parted --version' ) {
            return <<'EOT'
GNU Parted 1.6.19
EOT
        } else {
            die "bad arg: $arg";
        }
    };

    is( $disk->parted_multiplier, 0.0009765625 );
};

# RHEL 5
do {
    no warnings 'redefine';
    local *SysBuilder::DiskConfig::run_local = sub {};
    local *SysBuilder::DiskConfig::backtick = sub {
        my $arg = shift;
        if( $arg eq 'parted --version' ) {
            return <<'EOT'
GNU Parted 1.8.1
EOT
        } else {
            die "bad arg: $arg";
        }
    };

    is( $disk->parted_multiplier, 1.024e-3 );
};

# RHEL 6
do {
    no warnings 'redefine';
    local *SysBuilder::DiskConfig::run_local = sub {};
    local *SysBuilder::DiskConfig::backtick = sub {
        my $arg = shift;
        if( $arg eq 'parted --version' ) {
            return <<'EOT'
parted (GNU parted) 2.1
Copyright (C) 2009 Free Software Foundation, Inc.
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

Written by <http://parted.alioth.debian.org/cgi-bin/trac.cgi/browser/AUTHORS>.
EOT
        } else {
            die "bad arg: $arg";
        }
    };

    is( $disk->parted_multiplier, 1.024e-3 );
};
