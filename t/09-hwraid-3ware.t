#!/usr/local/bin/perl

use strict;
use warnings 'all';

use FindBin(qw($Bin));
use lib qq($Bin/../lib);

use Test::More 'no_plan';
use Test::Differences;
use FindBin qw/$Bin/;

use YAML;

my $module = 'SysBuilder::HWRaid::3ware';
use_ok($module);
can_ok( $module, 'setup' );

my $cfg = Load(<<EOT);
3ware:
  c0:
    u0:
      raidtype: raid10
      physicaldisks: all
blockdev:
  - scsidisk0:
      candidates: 3ware
      partitions:
        - part1:
            size: 4G
            fstype: ext3
            mountpoint: /
            label: /
        - part2:
            size: 4G
            fstype: swap
        - part3:
           minsize: 32G
           label: CRAWLSPACE
           fstype: ext3
           mountpoint: /export/crawlspace
EOT

my $hw_raid = SysBuilder::HWRaid::3ware->new(
    modules => ['3w-9xxx'],
    binary  => "$Bin/tw-cli.pl",
    verbose => 1,
);

#$hw_raid->setup($cfg);
