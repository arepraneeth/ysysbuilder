#!/usr/local/bin/perl

use strict;
use warnings 'all';

use FindBin(qw($Bin));
use lib qq($Bin/../lib);

use Test::More tests => 4;
use Test::Differences;

my $module = 'SysBuilder::Server';
use_ok($module);

can_ok( $module, 'create_ramdisk' );
can_ok( $module, 'create_installer' );

my $server = $module->new;

$ENV{PATH} = "/bin64";
$server->_set_path;
eq_or_diff(
    $ENV{PATH},
    "/bin64:/usr/local/bin:/sbin:/usr/sbin:/bin:/usr/bin",
    "PATH set correctly"
);

1;
