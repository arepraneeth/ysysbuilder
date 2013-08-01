#!/usr/local/bin/perl

use strict;
use warnings 'all';

use FindBin(qw($Bin));
use lib qq($Bin/../lib);
use Test::More tests => 30;
use Test::Differences;

package MyTestProc;

sub new {
    return bless { _cpucount => 1 }, shift;
}

sub cpucount {
    my $self = shift;
    return $self->{_cpucount};
}

sub set_cpucount {
    my $self  = shift;
    my $count = shift;
    $self->{_cpucount} = $count;
}

package main;
my $module = 'SysBuilder::BootLoader';
use_ok($module);

# our public interface
can_ok( $module, 'new' );
can_ok( $module, 'config' );
can_ok( $module, 'install' );

my $proc = MyTestProc->new;

# test this object
my $b = SysBuilder::BootLoader->new(
    cfg    => {},
    fs_out => "files/filesystems.yaml",
    proc   => $proc,
);

# test boot_mountpoint, boot_device, boot_part
is( $b->boot_mountpoint, '/' );
is( $b->boot_device, '/dev/sda' );
is( $b->boot_part, 0 );

# test get_kernels
# this method should return a list of the installed kernel packages
# let's override backtick_local so we can lie about the output of 'rpm -qa'
undef *SysBuilder::BootLoader::backtick;
my $rpms = <<EOT;
audit-libs-1.0.15-3.EL4
bzip2-libs-1.0.2-13.EL4.3
krb5-libs-1.3.4-47
kernel-2.6.9-55.EL
net-snmp-libs-5.1.2-11.EL4.10
bind-libs-9.2.4-24.EL4
cups-libs-1.1.22-0.rc1.9.20
xorg-x11-libs-6.8.2-1.EL.18
libstdc++-devel-3.4.6-8
kernel-devel-2.6.9-55.EL
libtool-libs-1.5.6-4.EL4.1
audit-libs-1.0.15-3.EL4
bzip2-libs-1.0.2-13.EL4.3
keyutils-libs-1.0-2
libselinux-1.19.1-7.3
libsepol-1.1.1-2
libstdc++-3.4.6-8
krb5-libs-1.3.4-47
rpm-libs-4.3.3-22_nonptl
kernel-smp-2.6.9-55.EL
bluez-libs-2.10-2
net-snmp-libs-5.1.2-11.EL4.10
libsdp-1.1.0-7
opensm-libs-2.0.0-7
bind-libs-9.2.4-24.EL4
cups-libs-1.1.22-0.rc1.9.20
xorg-x11-libs-6.8.2-1.EL.18
kernel-utils-2.4-13.1.99
libstdc++-devel-3.4.6-8
kernel-smp-devel-2.6.9-55.EL
libtool-libs-1.5.6-4.EL4.1
libselinux-1.19.1-7.3
libsepol-1.1.1-2
libstdc++-3.4.6-8
rpm-libs-4.3.3-22_nonptl
bluez-libs-2.10-2
OpenIPMI-libs-1.4.14-1.4E.17
libselinux-devel-1.19.1-7.3
EOT

*SysBuilder::BootLoader::backtick = sub { return split '\n', $rpms; };

# override the need for read_file('/mnt/etc/redhat-release')
$b->{_release} = "Red Hat Enterprise Linux AS release 4 (Nahant Update 5)\n";

my @kernels = $b->get_kernels;

my $expected_kernels = [
    {   initrd  => '/initrd-2.6.9-55.EL.img',
        kernel  => '/vmlinuz-2.6.9-55.EL',
        title   => 'Red Hat Enterprise Linux AS-up (2.6.9-55.EL)',
        version => '2.6.9-55.EL',
    },
    {   initrd  => '/initrd-2.6.9-55.ELsmp.img',
        kernel  => '/vmlinuz-2.6.9-55.ELsmp',
        title   => 'Red Hat Enterprise Linux AS (2.6.9-55.ELsmp)',
        version => '2.6.9-55.ELsmp',
    }
];
eq_or_diff( \@kernels, $expected_kernels,
    "get_kernels detects and parses installed rpms" );

my $kernel_version = "2.6.9-55.ELsmp";
eq_or_diff( $b->_default_kernel_idx( \@kernels, $kernel_version, 2 ),
    1, "default kernel properly identifies our SMP kernel" );

eq_or_diff( $b->_default_kernel_idx( \@kernels, "", 2 ),
    1, "default RHEL4 kernel is SMP for SMP systems" );

eq_or_diff( $b->_default_kernel_idx( \@kernels, "", 1 ),
    0, "default RHEL4 kernel is UP for UP systems" );

$proc->set_cpucount(2);
eq_or_diff( $b->default_kernel_version, "2.6.9-55.ELsmp",
    "Default RHEL4 kernel version (smp)" );

$proc->set_cpucount(1);
eq_or_diff( $b->default_kernel_version, "2.6.9-55.EL",
    "Default RHEL4 kernel version (up)" );

# now our RHEL5 version
$rpms = <<EOT;
libstdc++-4.1.1-52.el5
net-snmp-libs-5.3.1-14.el5
sane-backends-libs-1.0.18-5.el5
libswt3-gtk2-3.2.1-18.el5
kernel-xen-devel-2.6.18-8.1.8.el5
audit-libs-1.3.1-1.el5
cups-libs-1.2.4-11.5.el5
libsoup-2.2.98-2.el5
e2fsprogs-libs-1.39-8.el5
postgresql-libs-8.1.4-1.1
libselinux-devel-1.33.4-2.el5
compat-libstdc++-33-3.2.3-61
kernel-devel-2.6.18-8.1.4.el5
libselinux-1.33.4-2.el5
system-config-printer-libs-0.7.32.5-1.el5
libsane-hpaio-1.6.7-4.1.el5
kernel-xen-2.6.18-8.1.8.el5
libsepol-devel-1.15.2-1.el5
kernel-2.6.18-8.1.4.el5
bluez-libs-3.7-1
libsilc-1.0.2-2.fc6
libsemanage-1.9.1-3.el5
rpm-libs-4.4.2-37.el5
audit-libs-python-1.3.1-1.el5
libselinux-python-1.33.4-2.el5
OpenIPMI-libs-2.0.6-5.el5.3
gimp-libs-2.2.13-1.fc6
libstdc++-devel-4.1.1-52.el5
compat-libstdc++-296-2.96-138
xen-libs-3.0.3-25.el5
cdparanoia-libs-alpha9.8-27.2
bind-libs-9.3.3-7.el5
bzip2-libs-1.0.3-3
libsysfs-2.0.0-6
pcsc-lite-libs-1.3.1-7
libsepol-1.15.2-1.el5
krb5-libs-1.5-17
oddjob-libs-0.27-7
elfutils-libs-0.125-3.el5
kernel-headers-2.6.18-8.1.8.el5
EOT

$b->{_release}    = "Red Hat Enterprise Linux Client release 5 (Tikanga)\n";
@kernels          = $b->get_kernels;
$expected_kernels = [
    
    {   'kernel'  => '/vmlinuz-2.6.18-8.1.8.el5xen',
        'version' => '2.6.18-8.1.8.el5xen',
        'initrd'  => '/initrd-2.6.18-8.1.8.el5xen.img',
        'title' => 'Red Hat Enterprise Linux Client-Xen (2.6.18-8.1.8.el5xen)'
    },
    {   'kernel'  => '/vmlinuz-2.6.18-8.1.4.el5',
        'version' => '2.6.18-8.1.4.el5',
        'initrd'  => '/initrd-2.6.18-8.1.4.el5.img',
        'title'   => 'Red Hat Enterprise Linux Client (2.6.18-8.1.4.el5)'
    },
    
];

eq_or_diff( \@kernels, $expected_kernels,
    "get_kernels detects and parses installed rpms (RHEL5)" );
eq_or_diff( $b->_default_kernel_idx( \@kernels, "", 2 ),
    1, "default RHEL5 kernel is EL" );
eq_or_diff( $b->_default_kernel_idx( \@kernels, "2.6.18-8.1.8.el5xen", 2 ),
    0, "Xen properly detected" );
eq_or_diff( $b->_default_kernel_idx( \@kernels, "xen", 2 ),
    0, "hint for kernel name" );
eq_or_diff( $b->_default_kernel_idx( \@kernels, "2.6.18.xxx", 2 ),
    -1, "default_kernel not present returns -1" );

eq_or_diff( $b->default_kernel_version, "2.6.18-8.1.4.el5",
    "Default RHEL5 kernel version" );





$b->{_release}    = "Red Hat Enterprise Linux Client release 5 (Tikanga)\n";
@kernels          = $b->get_kernels;
$expected_kernels = [

    {   'kernel'  => '/vmlinuz-2.6.18-8.1.8.el5xen',
        'version' => '2.6.18-8.1.8.el5xen',
        'initrd'  => '/initrd-2.6.18-8.1.8.el5xen.img',
        'title' => 'Red Hat Enterprise Linux Client-Xen (2.6.18-8.1.8.el5xen)'
    },
    
];

eq_or_diff( \@kernels, $expected_kernels,
    "get_kernels detects and parses installed rpms (RHEL5)" );
eq_or_diff( $b->_default_kernel_idx( \@kernels, "", 2 ),
    1, "default RHEL5 kernel is EL" );
eq_or_diff( $b->_default_kernel_idx( \@kernels, "2.6.18-8.1.8.el5xen", 2 ),
    0, "Xen properly detected" );
eq_or_diff( $b->_default_kernel_idx( \@kernels, "xen", 2 ),
    0, "hint for kernel name" );







mkdir "/tmp/boot.$$";
system("touch /tmp/boot.$$/xen.gz-3.3.0");
system("touch /tmp/boot.$$/xen.gz-2.6.18-128.el5");
my $xen_version = $b->xen_version( dir => "/tmp/boot.$$" );
system("rm -rf /tmp/boot.$$");

eq_or_diff( $xen_version, "xen.gz-3.3.0", "guesses the right xen version" );

$b->{cfg}{xen_version} = "xen.gz-1.2.3";
eq_or_diff( $b->xen_version, "xen.gz-1.2.3",
    "uses the profile version for xen" );

