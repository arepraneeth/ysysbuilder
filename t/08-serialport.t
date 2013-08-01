#!/usr/local/bin/perl

use strict;
use warnings 'all';

use FindBin(qw($Bin));
use lib qq($Bin/../lib);

use Test::More tests => 23;
use Test::Differences;

my $module = 'SysBuilder::SerialPort';
use_ok($module);

my $host1 = <<EOT;
serinfo:1.0 driver revision:
0: uart:16550A port:000003F8 irq:4 tx:178 rx:0 RTS|DTR
1: uart:16550A port:000002F8 irq:3 tx:1739314 rx:25 RTS|CTS|DTR|DSR
2: uart:unknown port:000003E8 irq:4
3: uart:unknown port:000002E8 irq:3
4: uart:unknown port:00000000 irq:0
5: uart:unknown port:00000000 irq:0
6: uart:unknown port:00000000 irq:0
7: uart:unknown port:00000000 irq:0
EOT

my $s = SysBuilder::SerialPort->new( split( "\n", $host1 ) );
my @ports = $s->serial_ports;
eq_or_diff( \@ports, [ 0, 1 ], '2 standard serial ports' );
eq_or_diff( $s->live_serial, 1, 'ttyS1 detected' );

my $old_driver = <<EOT;
serinfo:1.0 driver:5.05c revision:2001-07-08
0: uart:16550A port:3F8 irq:4 baud:9600 tx:111 rx:0 RTS|DTR
1: uart:16550A port:2F8 irq:3 baud:9600 tx:2233283 rx:0 RTS|DTR
EOT

$s = SysBuilder::SerialPort->new( split( "\n", $old_driver ) );
@ports = $s->serial_ports;

my $warning = "";
$SIG{__WARN__} = sub { $warning = $_[0] };
eq_or_diff( \@ports, [ 0, 1 ], '2 ports detected' );
eq_or_diff( defined( $s->live_serial ), undef, 'cant autodetect' );

# the above should have printed a warning
ok( length($warning) > 0, "warning printed when we couldn't autodetect" );
$warning = "";

my $both_ports = <<EOT;
serinfo:1.0 driver revision:
0: uart:16550A port:000003F8 irq:4 tx:176 rx:0 RTS|DTR
1: uart:16550A port:000002F8 irq:3 tx:29441 rx:7 RTS|DTR
2: uart:unknown port:000003E8 irq:4
3: uart:unknown port:000002E8 irq:3
EOT

$s = SysBuilder::SerialPort->new( split( "\n", $both_ports ) );
@ports = $s->serial_ports;

eq_or_diff( \@ports, [ 0, 1 ], '2 ports detected' );
eq_or_diff( defined( $s->live_serial ), undef, 'cant autodetect' );

# the above should have printed a warning
ok( length($warning) > 0, "warning printed (newer fmt)" );
$warning = "";

my $serial0 = <<EOT;
serinfo:1.0 driver revision:
0: uart:16550A port:000003F8 irq:4 tx:2464490 rx:50 RTS|CTS|DTR|DSR
1: uart:16550A port:000002F8 irq:3 tx:172 rx:0 RTS|DTR
2: uart:unknown port:000003E8 irq:4
3: uart:unknown port:000002E8 irq:3
4: uart:unknown port:00000000 irq:0
5: uart:unknown port:00000000 irq:0
EOT

$s = SysBuilder::SerialPort->new( split( "\n", $serial0 ) );
@ports = $s->serial_ports;

eq_or_diff( \@ports, [ 0, 1 ], '2 ports detected' );
ok( $s->live_serial == 0, 'ttyS0 detected' );

# the above should have printed a warning
ok( length($warning) == 0, "warning not printed" );
$warning = "";

my $not_connected = <<EOT;
serinfo:1.0 driver revision:
0: uart:16550A port:000003F8 irq:4 tx:0 rx:0
1: uart:unknown port:000002F8 irq:3
2: uart:unknown port:000003E8 irq:4
3: uart:unknown port:000002E8 irq:3
EOT
$s = SysBuilder::SerialPort->new( split( "\n", $not_connected ) );
@ports = $s->serial_ports;
eq_or_diff( \@ports, [0], '1 port detected' );
eq_or_diff( defined( $s->live_serial ), undef, 'no live port' );
$warning = "";

my $vmware = <<EOT;
serinfo:1.0 driver revision:
0: uart:16550A port:000003F8 irq:4 tx:0 rx:0 CTS|DSR|CD
1: uart:16550A port:000002F8 irq:3 tx:0 rx:0 CTS|DSR|CD
2: uart:unknown port:000003E8 irq:4
3: uart:unknown port:000002E8 irq:3
4: uart:unknown port:00000000 irq:0
5: uart:unknown port:00000000 irq:0
6: uart:unknown port:00000000 irq:0
7: uart:unknown port:00000000 irq:0
EOT
$s = SysBuilder::SerialPort->new( split( "\n", $vmware ) );
@ports = $s->serial_ports;
eq_or_diff( \@ports, [ 0, 1 ], '2 ports detected - vmware' );
eq_or_diff( defined( $s->live_serial ), undef, 'cant autodetect' );
ok( length($warning) > 0, "warning printed (vmware)" );
$warning = "";

my $vmware2 = <<EOT;
serinfo:1.0 driver revision:
0: uart:16550A port:000003F8 irq:4 tx:1691 rx:43 RTS|CTS|DTR|DSR|CD
1: uart:16550A port:000002F8 irq:3 tx:0 rx:0 CTS|DSR|CD
2: uart:unknown port:000003E8 irq:4
3: uart:unknown port:000002E8 irq:3
4: uart:unknown port:00000000 irq:0
5: uart:unknown port:00000000 irq:0
6: uart:unknown port:00000000 irq:0
7: uart:unknown port:00000000 irq:0
EOT
$s = SysBuilder::SerialPort->new( split( "\n", $vmware2 ) );
@ports = $s->serial_ports;
eq_or_diff( \@ports, [ 0, 1 ], '2 ports detected - vmware2' );
eq_or_diff( defined( $s->live_serial ), 1, 'vmware2: ttyS0 auto-detected' );
$warning = "";

my $dell = <<EOT;
serinfo:1.0 driver revision:
0: uart:NS16550A port:000003F8 irq:4 tx:14671 rx:75 RTS|CTS|DTR|DSR|CD
1: uart:unknown port:000002F8 irq:3
2: uart:unknown port:000003E8 irq:4
3: uart:unknown port:000002E8 irq:3
4: uart:unknown port:00000000 irq:0
5: uart:unknown port:00000000 irq:0
6: uart:unknown port:00000000 irq:0
7: uart:unknown port:00000000 irq:0
EOT
$s = SysBuilder::SerialPort->new( split( "\n", $dell ) );
@ports = $s->serial_ports;
eq_or_diff( \@ports, [0], '1 port detected - dell' );
eq_or_diff( $s->live_serial, 0, 'dell ttyS0 auto-detected' );
$warning = "";

my $imm = <<EOT;
serinfo:1.0 driver revision:
0: uart:16550A port:000003F8 irq:4 tx:11 rx:0
1: uart:16550A port:000002F8 irq:3 tx:2616951 rx:68 RTS|DTR|DSR
2: uart:unknown port:000003E8 irq:4
3: uart:unknown port:000002E8 irq:3
4: uart:unknown port:00000000 irq:0
5: uart:unknown port:00000000 irq:0
6: uart:unknown port:00000000 irq:0
7: uart:unknown port:00000000 irq:0
8: uart:unknown port:00000000 irq:0
9: uart:unknown port:00000000 irq:0
10: uart:unknown port:00000000 irq:0
11: uart:unknown port:00000000 irq:0
12: uart:unknown port:00000000 irq:0
13: uart:unknown port:00000000 irq:0
14: uart:unknown port:00000000 irq:0
15: uart:unknown port:00000000 irq:0
16: uart:unknown port:00000000 irq:0
17: uart:unknown port:00000000 irq:0
18: uart:unknown port:00000000 irq:0
19: uart:unknown port:00000000 irq:0
20: uart:unknown port:00000000 irq:0
21: uart:unknown port:00000000 irq:0
22: uart:unknown port:00000000 irq:0
23: uart:unknown port:00000000 irq:0
24: uart:unknown port:00000000 irq:0
25: uart:unknown port:00000000 irq:0
26: uart:unknown port:00000000 irq:0
27: uart:unknown port:00000000 irq:0
28: uart:unknown port:00000000 irq:0
29: uart:unknown port:00000000 irq:0
30: uart:unknown port:00000000 irq:0
31: uart:unknown port:00000000 irq:0
32: uart:unknown port:00000000 irq:0
33: uart:unknown port:00000000 irq:0
34: uart:unknown port:00000000 irq:0
35: uart:unknown port:00000000 irq:0
36: uart:unknown port:00000000 irq:0
37: uart:unknown port:00000000 irq:0
38: uart:unknown port:00000000 irq:0
39: uart:unknown port:00000000 irq:0
40: uart:unknown port:00000000 irq:0
41: uart:unknown port:00000000 irq:0
42: uart:unknown port:00000000 irq:0
43: uart:unknown port:00000000 irq:0
44: uart:unknown port:00000000 irq:0
45: uart:unknown port:00000000 irq:0
46: uart:unknown port:00000000 irq:0
47: uart:unknown port:00000000 irq:0
48: uart:unknown port:00000000 irq:0
49: uart:unknown port:00000000 irq:0
50: uart:unknown port:00000000 irq:0
51: uart:unknown port:00000000 irq:0
52: uart:unknown port:00000000 irq:0
53: uart:unknown port:00000000 irq:0
54: uart:unknown port:00000000 irq:0
55: uart:unknown port:00000000 irq:0
56: uart:unknown port:00000000 irq:0
57: uart:unknown port:00000000 irq:0
58: uart:unknown port:00000000 irq:0
59: uart:unknown port:00000000 irq:0
60: uart:unknown port:00000000 irq:0
61: uart:unknown port:00000000 irq:0
62: uart:unknown port:00000000 irq:0
63: uart:unknown port:00000000 irq:0
64: uart:unknown port:00000000 irq:0
65: uart:unknown port:00000000 irq:0
66: uart:unknown port:00000000 irq:0
67: uart:unknown port:00000000 irq:0
EOT

$s = SysBuilder::SerialPort->new( split( "\n", $imm ) );
@ports = $s->serial_ports;
eq_or_diff( \@ports, [ 0, 1 ], '2 ports detected - hp' );
eq_or_diff( $s->live_serial, 1, 'rackable ttyS1 auto-detected' );
