#!/usr/local/bin/perl

use strict;
use warnings 'all';

use FindBin(qw($Bin));
use lib qq($Bin/../lib);

use Test::More 'no_plan';
use Test::Differences;
use FindBin qw/$Bin/;

my $hwraid = 'SysBuilder::HWRaid';
use_ok($hwraid);
can_ok( $hwraid, 'setup_raid' );

for my $module ( map { $hwraid . '::' . $_ } qw(LSI Megacli 3ware) ) {
    use_ok($module);
    can_ok( $module, 'setup' );
}
