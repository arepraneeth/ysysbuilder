package Yahoo::SysBuilder::Driver;

use strict;
use warnings 'all';

use FindBin(qw($Bin));
use lib qq($Bin/../lib);
use Yahoo::SysBuilder::Utils qw(:all);
use Yahoo::SysBuilder::Modules;
use Yahoo::SysBuilder::Network;
use POSIX qw();
use YAML qw();

sub new {
    my $class = shift;
    return bless {
        modules    => Yahoo::SysBuilder::Modules->new,
        hostconfig => undef,
        network    => Yahoo::SysBuilder::Network->new,
        base       => undef,
        steps      => [
            qw (
                init
                banner

                check_integrity
                udev
                modules
                network_config
                ping_and_sleep

                get_hostconfig
                run_installer
                )
        ]
    }, $class;
}

sub run {
    $|++;

    my $self = shift;

    # will affect driver steps, but not the installer since run_installer fork+execs
    local $Yahoo::SysBuilder::Utils::VERBOSE = 0;
    run_steps($self);
}

sub init {
    my $self = shift;

    $ENV{PATH}
        = "/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/bin:/usr/local/sbin";
    print "*************** Starting SysBuilder ***************\n";
    run_local("echo 3 > /proc/sys/kernel/printk");
    run_local("cat /proc/kmsg > /tmp/kernel.log &");
    if ( -x "/usr/local/bin/svscanboot" ) {
        run_local("/usr/local/bin/svscanboot &");
    }
    if( -x "/usr/local/bin/tcpserver" ) {
        run_local("/usr/local/bin/tcpserver -H -R -l 0 0 8888 cat /tmp/status &");
    }
    run_local("ifconfig lo up 127.0.0.1 netmask 255.0.0.0");
    mkdir "/sysbuilder/etc";
}

sub udev {
    my $uts_release = ( POSIX::uname() )[2];
    if ( $uts_release !~ /\A 2\.4 /msx ) {
        run_local("/sbin/udevd >/dev/null 2>/dev/null </dev/null &");

        # attempt coldplug
        if( -x "/sbin/udevtrigger" && -x "/sbin/udevsettle" ) {
            run_local( "/sbin/udevtrigger" );
            run_local( "/sbin/udevsettle --timeout=180" );
        } elsif( -x "/sbin/udevadm" ) {
            run_local( "/sbin/udevadm trigger --type=subsystems" );
            run_local( "/sbin/udevadm trigger --type=devices" );
            run_local( "/sbin/udevadm settle --timeout=180" );
        }
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

    # update base after doing the network configuration
    $self->{base} = get_base();
}

sub get_hostconfig {
    my $self     = shift;
    my $net      = $self->{network};
    my $hostname = $net->hostname;
    my $base     = $self->{base};
    my $cmd
        = "wget -q $base/hostconfig.pl?h=$hostname -O - 2>/tmp/hostconfig.err";
    my $yaml = qx/$cmd/;
    if ($?) {
        my $extra_err = read_file("/tmp/hostconfig.err");
        print "ERROR: Can't get hostconfig\n$extra_err";
        optional_shell(30);
        exit;
    }

    my $yaml_config;
    eval { $yaml_config = YAML::Load($yaml); };
    if ($@) {
        print "ERROR: Hostconfig corrupted - $@\n";
        optional_shell(30);
        exit;
    }
    $self->{hostconfig} = $yaml_config;
    $self->{hostconfig}->{base} = $base;
    YAML::DumpFile( "/sysbuilder/etc/config.yaml", $self->{hostconfig} );
}

sub check_integrity {
    my $self = shift;

    my ( $version, $arch ) = ( POSIX::uname() )[ 2, 4 ];

    if ( -d "/lib/modules/$version.$arch" && ! -d "/lib/modules/$version" ) {
        # Alternate kernel modules location. Rename it to the correct one.
        rename "/lib/modules/$version.$arch" => "/lib/modules/$version";
    }

    unless ( -d "/lib/modules/$version" ) {
        printbold("Missing modules!\n");
        print "This kernel version is $version, but there's no "
            . "/lib/modules/$version directory. Are you using the "
            . "right installer kernel?\n\n";
        optional_shell(60);
        exit(1);
    }
}

sub banner {
    my $self = shift;
    my @fig = ( <<'FIG1', <<'FIG2', <<'FIG3', <<'FIG4', <<'FIG5' );

__   __    _             _   ___         ___      _ _    _
\ \ / /_ _| |_  ___  ___| | / __|_  _ __| _ )_  _(_) |__| |___ _ _
 \ V / _` | ' \/ _ \/ _ \_| \__ \ || (_-< _ \ || | | / _` / -_) '_|
  |_|\__,_|_||_\___/\___(_) |___/\_, /__/___/\_,_|_|_\__,_\___|_|
                                 |__/

FIG1

                                         , _
(|  |  _,  |)    _   _  |    ()       , /|/_)      o |\  _|   _  ,_
 |  | / |  |/\  / \_/ \_|    /\ |  | / \_|  \|  |  | |/ / |  |/ /  |
  \/|/\/|_/|  |/\_/ \_/ o   /(_) \/|/ \/ |(_/ \/|_/|/|_/\/|_/|_/   |/
   (|                             (|

FIG2

__  __     __             __  ____         ___       _ __   __
\ \/ /__ _/ /  ___  ___  / / / __/_ _____ / _ )__ __(_) /__/ /__ ____
 \  / _ `/ _ \/ _ \/ _ \/_/ _\ \/ // (_-</ _  / // / / / _  / -_) __/
 /_/\_,_/_//_/\___/\___(_) /___/\_, /___/____/\_,_/_/_/\_,_/\__/_/
                               /___/

FIG3

 ___________________
< Yahoo! SysBuilder >
 -------------------
        \   ^__^
         \  (oo)\_______
            (__)\       )\/\
                ||----w |
                ||     ||

FIG4

     )                     ____  (
  ( /(         )          |   /  )\ )         (          (  (
  )\())   ) ( /(          |  /  (()/((      ( )\   (  (  )\ )\ )  (  (
 ((_)\ ( /( )\()) (   (   | /    /(_))\ ) ( )((_) ))\ )\((_|()/( ))\ )(
__ ((_))(_)|(_)\  )\  )\  |/    (_))(()/( )((_)_ /((_|(_)_  ((_))((_|()\
\ \ / ((_)_| |(_)((_)((_)(      / __|)(_)|(_) _ |_))( (_) | _| (_))  ((_)
 \ V // _` | ' \/ _ Y _ \)\     \__ \ || (_-< _ \ || || | / _` / -_)| '_|
  |_| \__,_|_||_\___|___((_)    |___/\_, /__/___/\_,_||_|_\__,_\___||_|
                                     |__/

FIG5

    printbold( $fig[int(rand(@fig))] );
}

sub run_installer {
    my $self          = shift;
    my $base          = $self->{base};
    my $hostconfig    = $self->{hostconfig};
    my $installer     = $hostconfig->{installer};
    chdir("/sysbuilder");
    mkdir("installer");
    chdir("installer");
    my $cmd =
      -e "../steps/$installer"
      ? "tar xzf ../steps/$installer"
      : "wget -q -O - '$self->{base}/$installer' | tar zxf - 2>/dev/null";
    run_local($cmd);

    run_local("./doinstall");

    unless ( -e "/tmp/ysysbuilder-installer-ok" ) {
        print "ERROR: The installer did not complete successfully.\n";
        print "\nDirectory after unpacking $installer\n";
        my $line = "-" x 30 . " cut here " . "-" x 30;
        print "$line\n";
        run_local("ls -l");
        print "$line\n";
        optional_shell(600);
    }
    else {
        optional_shell(10);
    }
    run_local("sync; sync; sync");
    system("reboot -f");
}

sub ping_and_sleep {
    my $self        = shift;
    my $boothost_ip = $self->{network}->boothost_ip;
    unless ($boothost_ip) {
        use Data::Dumper;
        print Dumper( $self->{network} );
        return;
    }
    return if $boothost_ip =~ /^169\.254/;

    run_local("ping -c 1 $boothost_ip");
    while ( $? != 0 ) {
        print "Failed to ping $boothost_ip: sleeping 1 minute\n";
        optional_shell(60);
        run_local("ping -c 1 $boothost_ip");
    }
}

1;
