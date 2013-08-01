#!/usr/local/bin/perl

use strict;
use warnings 'all';

use FindBin(qw($Bin));
use lib qq($Bin/../lib);
use SysBuilder::Utils qw(read_file);

use Test::More tests => 19;
use Test::Differences;

my $module = 'SysBuilder::Proc';
use_ok($module);

# our public API
can_ok( $module, 'cmdline' );
can_ok( $module, 'ip_info' );
can_ok( $module, 'devices' );
can_ok( $module, 'nodetect' );
can_ok( $module, 'serialports' );
can_ok( $module, 'partitions' );

my $cmdline = read_file("/proc/cmdline");
my $p       = SysBuilder::Proc->new;

eq_or_diff( $p->cmdline, $cmdline, "cmdline just returns /proc/cmdline" );
eq_or_diff( $p->cmdline, $cmdline, "cmdline caching works" );

undef $p;
my $IP_INFO = "ip=169.254.100.10:1.2.3.4:169.254.100.1:255.255.255.0:xen-vm:eth1:off";
$cmdline = "root=/dev/sda1 $IP_INFO\n";
$p = SysBuilder::Proc->new( cmdline => $cmdline );

eq_or_diff( $p->cmdline, $cmdline, "overriding cmdline" );

my $ip_info = {
    boothost_ip => '1.2.3.4',
    broadcast   => '169.254.100.255',
    gateway_ip  => '169.254.100.1',
    ip          => '169.254.100.10',
    netmask     => '255.255.255.0',
    hostname    => 'xen-vm',
    device      => 'eth1',
    network     => '169.254.100.0',
};

eq_or_diff( $p->ip_info, $ip_info, "ip_info" );

ok( !$p->nodetect, "Missing nodetect from cmdline implies autodetection" );

$cmdline = "some cmds nodetect foobar";
$p = SysBuilder::Proc->new( cmdline => $cmdline );
ok( $p->nodetect, "No autodetection requested" );

$cmdline = "some cmds";
$p = SysBuilder::Proc->new( cmdline => $cmdline );
ok( !defined( $p->boothost_from_base ),
    "boothost_from_base returns undef when unspecified" );

$cmdline = "some cmds base=http://foo.bar/sysbuilder/";
$p = SysBuilder::Proc->new( cmdline => $cmdline );
eq_or_diff( $p->boothost_from_base, "foo.bar", "boothost name" );

$cmdline = "some cmds base=http://10.20.30.40:35800/";
$p = SysBuilder::Proc->new( cmdline => $cmdline );
eq_or_diff( $p->boothost_from_base, "10.20.30.40", "boothost name = IP" );

$p->{_memtotal} = "MemTotal:      2067256 kB\n";
eq_or_diff( $p->memsize, "2067256", "memsize" );

undef *SysBuilder::Proc::cpuinfo;

my $cpuinfo = <<EOT;
processor	: 0
vendor_id	: GenuineIntel
cpu family	: 6
model		: 15
model name	: Intel(R) Core(TM)2 CPU          6400  @ 2.13GHz
stepping	: 2
cpu MHz		: 1596.000
cache size	: 2048 KB
physical id	: 0
siblings	: 2
core id		: 0
cpu cores	: 2
fdiv_bug	: no
hlt_bug		: no
f00f_bug	: no
coma_bug	: no
fpu		: yes
fpu_exception	: yes
cpuid level	: 10
wp		: yes
flags		: fpu vme de pse tsc msr pae mce cx8 apic mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe nx lm constant_tsc pni monitor ds_cpl vmx est tm2 cx16 xtpr lahf_lm
bogomips	: 4258.45

processor	: 1
vendor_id	: GenuineIntel
cpu family	: 6
model		: 15
model name	: Intel(R) Core(TM)2 CPU          6400  @ 2.13GHz
stepping	: 2
cpu MHz		: 1596.000
cache size	: 2048 KB
physical id	: 0
siblings	: 2
core id		: 1
cpu cores	: 2
fdiv_bug	: no
hlt_bug		: no
f00f_bug	: no
coma_bug	: no
fpu		: yes
fpu_exception	: yes
cpuid level	: 10
wp		: yes
flags		: fpu vme de pse tsc msr pae mce cx8 apic mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe nx lm constant_tsc pni monitor ds_cpl vmx est tm2 cx16 xtpr lahf_lm
bogomips	: 4256.04
EOT

*SysBuilder::Proc::cpuinfo = sub {
    return $cpuinfo;
};

eq_or_diff( $p->cpucount, 2, "cpucount multicore" );

$cpuinfo = <<EOT;
processor       : 0
  vendor_id       : GenuineIntel
  cpu family      : 6
  model           : 15
  model name      : Intel(R) Core(TM)2 CPU          6400  @ 2.13GHz
stepping        : 8
cpu MHz         : 1596.022
cache size      : 2048 KB
fpu             : yes
fpu_exception   : yes
cpuid level     : 10
wp              : yes
flags           : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss syscall nx lm pni ds_cpl cx16 lahf_lm
bogomips        : 3205.83
clflush size    : 64
cache_alignment : 64
address sizes   : 36 bits physical, 48 bits virtual
power management:
EOT
eq_or_diff( $p->cpucount, 1, "cpucount up" );
