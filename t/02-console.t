#!/usr/local/bin/perl

use strict;
use warnings 'all';

# test SysBuilder::Console

use FindBin(qw($Bin));
use lib qq($Bin/../lib);

use Test::More tests => 10;

BEGIN { use_ok('SysBuilder::Console'); }

my $c = SysBuilder::Console->new(
    cmdline => "ro root=/dev/VolGroup00/LogVol00 pci=nommconf hda=noprobe rhgb quiet" );

ok( $c->live_console eq "console", "default console" );
ok( !$c->is_serial, "default console is not serial" );

$c = SysBuilder::Console->new(
    cmdline => "root=/dev/hda1 initrd=foo.img console=tty0" );

ok( $c->live_console eq "tty0", "tty0 console" );
ok( !$c->is_serial, "tty0 console is not serial" );

$c = SysBuilder::Console->new(
    cmdline => "root=/dev/cciss/c0d0p0 initrd=foo-console-ttyS0.img console=tty0" );
ok( $c->live_console eq "tty0", "ttyS0 string doesn't confuse us" );

$c = SysBuilder::Console->new(
    cmdline => "root=/dev/cciss/c0d0p0 initrd=foo-console-ttyS0.img console=ttyS0" );
ok( $c->live_console eq "ttyS0", "ttyS0 console" );
ok( $c->is_serial, "ttyS0 is serial" );

$c = SysBuilder::Console->new(
    cmdline => "root=/dev/cciss/c0d0p0 initrd=foo-ttyS0.img console=ttyS1,96008N1" );
ok( $c->live_console eq "ttyS1", "ttyS1 console with arguments" );
ok( $c->is_serial, "ttyS1 is serial" );

