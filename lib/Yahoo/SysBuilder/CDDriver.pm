package Yahoo::SysBuilder::CDDriver;

use strict;
use warnings 'all';

use FindBin(qw($Bin));
use lib qq($Bin/../lib);
use Yahoo::SysBuilder::Utils qw(:all);
use Yahoo::SysBuilder::Modules;
use Yahoo::SysBuilder::Network;
use Yahoo::SysBuilder::DiskConfig;

use POSIX qw();
use YAML qw();

sub new {
    my $class = shift;
    return bless {
        modules    => Yahoo::SysBuilder::Modules->new,
        hostconfig => undef,
        network    => Yahoo::SysBuilder::Network->new,
        base       => get_base(),
        steps      => [
            qw (
                init

                check_integrity
                modules
                udev
                network_config
                fix_config
                )
        ]
    }, $class;
}

sub run {
    $|++;

    my $self = shift;
    run_steps($self);
}

sub init {
    my $self = shift;

    $ENV{PATH}
        = "/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/bin:/usr/local/sbin";
    print "*************** Starting SysBuilder ***************\n";
    if ( -x "/usr/local/bin/svscanboot" ) {
        run_local("/usr/local/bin/svscanboot &");
    }
    run_local("ifconfig lo up 127.0.0.1 netmask 255.0.0.0");
    mkdir "/sysbuilder/etc";
}

sub udev {
    my $uts_release = ( POSIX::uname() )[2];
    unless ( $uts_release =~ /\A 2\.4 /msx ) {
        run_local("/sbin/udevd >/dev/null 2>/dev/null </dev/null &");
    }
}

sub modules {
    my $self = shift;

    # load modules, and write the results to etc/modules.yaml
    $self->{modules}->load('/sysbuilder/etc/modules.yaml');
}

sub network_config {
    my $self = shift;
    $self->{network}->config;
}

sub check_integrity {
    my $self = shift;

    my ( $version, $arch ) = ( POSIX::uname() )[ 2, 4 ];

    unless ( -d "/lib/modules/$version.$arch" ) {
        printbold("Missing modules!\n");
        print "This kernel version is $version, but there's no "
            . "/lib/modules/$version.$arch directory. Are you using the "
            . "right installer kernel?\n\n";
        optional_shell(60);
        exit(1);
    }

    rename "/lib/modules/$version.$arch" => "/lib/modules/$version";
}

sub find_mac {
    my $iface = shift;
    my $if    = `ifconfig $iface`;
    my $mac;
    if ( $if =~ /HWaddr \s+ ([\da-f:]+)/msxi ) {
        $mac = $1;
    }
    return $mac;
}

sub error {
    my $msg = shift;
    print "$msg\n";
    optional_shell(300);
    exit 1;
}

sub get_vm_config {
    my $mac = find_mac("eth0");
    unless ($mac) {
        error("ERROR: cannot get mac address for eth0");
    }

    my $cmd
        = "wget -q -O /sysbuilder/etc/config.yaml http://169.254.200.1:9999/hostconfig.pl?mac=$mac";
    system($cmd);
    if ($?) {
        error("COMMAND: $cmd [FAILED $?]");
    }
}

sub mount_fs {
    my $disk
        = Yahoo::SysBuilder::DiskConfig->new( cfg => { disk_config => {} } );
    $disk->label("sdb");

    my $mount_point = shift;
    my $sdb_size    = $disk->disksize("sdb");
    system("parted -s /dev/sdb mkpart primary 0 511");
    system("parted -s /dev/sdb mkpart primary 512 $sdb_size");
    my $rest = $sdb_size - 512;
    print "% Creating /home file system ($rest MB)\n";
    system("mke2fs -j -q /dev/sdb2");
    print "OK\n";

    system("mkswap /dev/sdb1");
    system("swapon /dev/sdb1");

    system("mount /dev/sda1 /mnt");
    if ( -d "/mnt/home" ) {
        mkdir "/mnt/newhome";
        system("mount /dev/sdb2 /mnt/newhome");
        system("cd /mnt/home; tar cpf - . | (cd /mnt/newhome; tar xpSf - )");
        system("rm -rf /mnt/home; umount /mnt/newhome");
    }
    mkdir "/mnt/home";
    system("mount /dev/sdb2 /mnt/home");
}

sub fix_config {
    get_vm_config();
    mount_fs("/mnt");
    optional_shell(30);
    system("reboot -f");
}

1;
