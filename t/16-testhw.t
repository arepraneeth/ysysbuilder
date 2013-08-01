#!/usr/local/bin/perl

use strict;
use warnings 'all';

# test SysBuilder::TestHW

use FindBin(qw($Bin));
use lib qq($Bin/../lib);

use Test::More tests => 3;

my $module = 'SysBuilder::TestHW';

use_ok($module);
can_ok( $module, 'new' );
can_ok( $module, 'run_tests' );
