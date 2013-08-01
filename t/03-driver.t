#!/usr/local/bin/perl

use strict;
use warnings 'all';

# test SysBuilder::Driver

use FindBin(qw($Bin));
use lib qq($Bin/../lib);

use Test::More tests => 1;

BEGIN { use_ok('SysBuilder::Driver'); }

# I have no idea how to test this, other than 'it compiles' :(
