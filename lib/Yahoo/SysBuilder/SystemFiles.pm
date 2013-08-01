package Yahoo::SysBuilder::SystemFiles;

use strict;
use warnings 'all';
use YAML qw();
use lib '/sysbuilder/lib';
use POSIX qw();
use Net::Netmask;

use Yahoo::SysBuilder::Utils
    qw(run_local fatal_error read_file write_file backtick optional_shell is_xen_paravirt);
use Yahoo::SysBuilder::Template;
use Yahoo::SysBuilder::SerialPort;
use Yahoo::SysBuilder::Console;
use Yahoo::SysBuilder::Network;

sub new {
    my $class  = shift;
    my %params = @_;

    my $cfg = $params{cfg}
        || YAML::LoadFile('/sysbuilder/etc/config.yaml');

    my $net
        = exists $params{net}
        ? $params{net}
        : Yahoo::SysBuilder::Network->new( cfg => $cfg );
    my $tpl = Yahoo::SysBuilder::Template->new( cfg => $cfg, net => $net );
    my $self = bless { cfg => $cfg, net => $net, tpl => $tpl }, $class;

    return $self;
}

# config everything we know how
sub config {
    my $self = shift;

    # our job is to configure the default /etc files
    $self->configure_inittab;
    $self->configure_network;
    $self->configure_persistent_net;
    $self->configure_sendmail;
    $self->configure_postfix;
    $self->configure_hostname;
    $self->configure_resolv_conf;
    $self->configure_ntp_conf;
    $self->configure_hardware;
    $self->configure_passwd;
    $self->configure_securetty;
    $self->configure_timezone;
    $self->configure_services;
    $self->configure_default_path;
    $self->configure_syslog_conf;
    $self->configure_logrotate;
    $self->configure_rc_local;
    $self->configure_ssh_keys;
    $self->configure_esx if $self->esx;
    $self->configure_mtab;

    # needs to be done after configure_esx
    $self->add_postinstall_steps;

}

sub add_postinstall_steps {
    my $self   = shift;
    my %params = ( file => "/mnt/etc/rc.d/rc.once.d/999_postinstall.sh", @_ );
    my $cfg    = $self->{cfg};

    my $postinstall = $cfg->{postinstall};
    return unless $postinstall;

    my $postinstall_cmds = join( "\n", @$postinstall );

    my $postinstall_sh = <<EOT;
#!/bin/sh

PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

cd /

$postinstall_cmds

EOT

    # create /mnt/etc/rc.d/rc.once.d if necessary
    if ( !-d "/mnt/etc/rc.d/rc.once.d"
        && $params{file} =~ m{^/mnt/etc/rc\.d/rc\.once\.d/} )
    {
        mkdir "/mnt/etc/rc.d/rc.once.d", oct("0755");
    }

    $self->{tpl}->write( $params{file}, $postinstall_sh );
    chmod oct('0555'), $params{file};
}

sub configure_ssh_keys {
    my $self     = shift;
    my $cfg      = $self->{cfg};
    my $keys_url = $cfg->{ssh_keys_location};
    my $hostname = $cfg->{hostname};

    if ($keys_url) {
        my $err
            = run_local(
            "wget -O - '$keys_url?hostname=$hostname' | tar xf - -C /mnt/etc/ssh/"
            );

        # if there is an error, attempt to restore the previously saved
        # copy of the keys, but first notify the user
        if ($err) {
            print "ERROR attempting to fetch ssh keys from $keys_url\n";
            optional_shell(30);
        }
        else {

            # all done here
            return;
        }
    }

    # we're here if we couldn't restore the keys from ssh_keys_location
    # (because of an error or because the user didn't specify a location)
    # if we could save the previous ssh keys
    # then we'll just restore those
    my $err = 1;
    if ( -d "/sysbuilder/saved-ssh" ) {
        $err = run_local( "mv /sysbuilder/saved-ssh/* /mnt/etc/ssh/" );
    }
    
    # if we are here, then there were not any ssh keys saved from before
    # the build so we will generate new keys now. CM3 needs this to be done
    # since it will configure and check sshd_config before sshd is started.
    if ( $err ) {
      my $key_gen_err 
        = run_local ( <<'EOT' );
chroot /mnt /usr/bin/ssh-keygen -q -t rsa1 -f /etc/ssh/ssh_host_key -C '' -N '' && \
chroot /mnt /usr/bin/ssh-keygen -q -t rsa -f /etc/ssh/ssh_host_rsa_key -C '' -N '' && \
chroot /mnt /usr/bin/ssh-keygen -q -t dsa -f /etc/ssh/ssh_host_dsa_key -C '' -N '' && \
chroot /mnt sh -c 'chmod 600 /etc/ssh/ssh_host_*' && \
chroot /mnt sh -c 'chmod 644 /etc/ssh/ssh_host_*.pub'
EOT

         if($key_gen_err) {
            fatal_error("ERROR Generating SSH keys");
         }
    }     
}

sub _udev_version {
    my $self = shift;
        my $script = <<EOT;
if type -P udevadm >/dev/null 2>/dev/null ;
then
    udevadm info -V ;
elif type -P udevinfo >/dev/null 2>/dev/null ;
then
    udevinfo -V ;
fi
EOT
    my $udev_version_string = qx[chroot /mnt sh -c \Q$script\E];
    my ( $udev_version ) = ( $udev_version_string =~ /^(?:udevinfo, version )?(\d+)$/ );
    return $udev_version;
}

sub _generate_eth_rules {
    my %mac_for;

    # udev can't keep its story straight for long
    my $udev_version = __PACKAGE__->_udev_version();
    my $template;

    if( !int( $udev_version ) || $udev_version < 55 ) {
        # udev pre-055
        $template = q(KERNEL="eth*", SYSFS{address}="%s", NAME="%s");
    } elsif( $udev_version < 98 ) {
        # udev 055 through 097
        $template = q(KERNEL=="eth*", SUBSYSTEM=="net", DRIVER=="?*", SYSFS{address}=="%s", NAME="%s");
    } else {
        # udev 098 and up
        $template = q(KERNEL=="eth*", SUBSYSTEM=="net", DRIVERS=="?*", ATTR{address}=="%s", NAME="%s");
    }

    my @devices = backtick("ifconfig -a | grep eth");
    for (@devices) {
        my ( $eth, $mac ) = (split)[ 0, -1 ];
        $mac_for{$eth} = $mac;
    }

    my @file;
    push @file,
        "# Generated By Yahoo SysBuilder to prevent unwanted interface renaming";

    for my $eth ( sort keys %mac_for ) {
        my $mac = lc $mac_for{$eth};
        push @file, sprintf $template, $mac, $eth;
    }
    return join( "\n", @file ) . "\n";
}

sub configure_persistent_net {
    my $self = shift;
    my $rules = _generate_eth_rules();
    write_file( "/mnt/etc/udev/rules.d/65-ysysbuilder-eth.rules", $rules )
        if -d "/mnt/etc/udev/rules.d";
}

sub configure_default_path {
    my $self = shift;
    my $cfg  = $self->{cfg};

    my $path;

    if( $cfg->{default_path} ) {
        $path = $cfg->{default_path};
    } else {
        $path = "/home/y/bin:/usr/kerberos/bin:/usr/local/sbin:/usr/local/bin:"
        . "/usr/sbin:/sbin:/usr/bin:/bin";

        my $arch = ( POSIX::uname() )[4];
        if( $arch eq "x86_64" ) {
            $path = "/home/y/bin64:$path";
        }
    }

    my $pathmunge = <<'EOT';
pathmunge () {
        if ! echo $PATH | /bin/egrep -q "(^|:)$1($|:)" ; then
          if [ -d "$1" ] ; then
            if [ "$2" = "after" ] ; then
              PATH=$PATH:$1
            else
              PATH=$1:$PATH
            fi
          fi
        fi
}
EOT
    my @script = ( $pathmunge, "\n" );
    my @path_elts = split( ':', $path );
    for my $dir ( reverse @path_elts ) {
        push @script, "pathmunge $dir";
    }
    push @script, "\n";

    write_file( "/mnt/etc/profile.d/ysysbuilder.sh", join( "\n", @script ) );
    chmod oct('0755'), '/mnt/etc/profile.d/ysysbuilder.sh';
}

sub configure_syslog_conf {
    my $self = shift;
    my $cfg = $self->{cfg};

    my %params = (
        file          => "",
        @_
    );

    # configure remote syslogging, maybe
    if( $cfg->{syslog_server} ) {
        my $log_server = $cfg->{syslog_server};
        my $syslog_conf =
            $params{file}              ? $params{file}
          : -f "/mnt/etc/syslog.conf"  ? "/mnt/etc/syslog.conf"
          : -f "/mnt/etc/rsyslog.conf" ? "/mnt/etc/rsyslog.conf"
          :                              "";

        if( $log_server && $syslog_conf ) {
            open my $fh, ">>", $syslog_conf or die "open $syslog_conf: $!\n";
            print $fh "*.*       \@$log_server\n";
            close $fh;
        }
    }
}

# we want to make the default /etc/logrotate.conf create files with mode 0644
# except for /var/log/secure
sub configure_logrotate {
    my $self = shift;

    system(
        q(perl -pi -e 's/^create[ \t]*$/create 0644 root/' /mnt/etc/logrotate.conf)
    );

    my $syslog = <<'EOT';
/var/log/messages /var/log/maillog /var/log/spooler /var/log/boot.log /var/log/cron {
    sharedscripts
    postrotate
        /bin/kill -HUP `cat /var/run/syslogd.pid 2> /dev/null` 2> /dev/null || true
    endscript
}

/var/log/secure {
        create 0600 root
}
EOT
    write_file( "/mnt/etc/logrotate.d/syslog", $syslog );
    run_local("chroot /mnt logrotate -f /etc/logrotate.conf");
    run_local("rm -f /mnt/var/log/*.1");
}

sub configure_services {
    my $self = shift;
    my $cfg  = $self->{cfg};

    # desired state of services
    my %services_cfg = %{ $cfg->{services} };

    # for backwards compatibility
    if ( $cfg->{disable_kudzu} && ! defined $services_cfg{kudzu} ) {
        $services_cfg{kudzu} = 0;
    }

    # services installed on the box
    my @services_inst = map { ( split )[0] } backtick("chroot /mnt /sbin/chkconfig --list");

    my @on_off = ( 'off', 'on' );
    for my $service ( @services_inst ) {
        my $value = $services_cfg{$service};
        next if ! defined $value;
        my $on_off = $on_off[$value];
        fatal_error("Wrong value for service $service: $value")
            unless $on_off;
        run_local("chroot /mnt /sbin/chkconfig $service $on_off");
    }
}

sub configure_timezone {
    my $self = shift;
    my $cfg  = $self->{cfg};

    my $timezone = $cfg->{'timezone'} || 'UTC';

    my $tz_dir = "/usr/share/zoneinfo";
    unless ( -e "/mnt/$tz_dir/$timezone" ) {
        warn("WARNING: $timezone does not exist. Reverting to UTC\n");
        $timezone = "UTC";
    }

    my $clock = <<EOT;
ZONE="$timezone"
UTC=true
ARC=false
EOT
    write_file( "/mnt/etc/sysconfig/clock", $clock );
    if ( -x "/mnt/usr/sbin/tzdata-update" ) {
        run_local("chroot /mnt /usr/sbin/tzdata-update");
    }
    else {
        run_local("cp -p '/mnt/$tz_dir/$timezone' /mnt/etc/localtime");
    }
}

sub configure_securetty {
    my $self = shift;
    my $cfg  = $self->{cfg};

    system("egrep -v 'ttyS|xvc' /mnt/etc/securetty > /mnt/etc/securetty.new");
    open my $fh, ">>", "/mnt/etc/securetty.new"
        or die "securetty.new: $!";
    my @serial_ports = Yahoo::SysBuilder::SerialPort->new->serial_ports;
    for my $port (@serial_ports) {
        print $fh "ttyS$port\n";
    }
    print $fh "xvc0\n";    # for xen

    close $fh;
    unlink "/mnt/etc/securetty";
    rename "/mnt/etc/securetty.new", "/mnt/etc/securetty";
}

# this should be overriden by the cm system
sub configure_passwd {
    my $self = shift;
    my $cfg  = $self->{cfg};

    my $root = 'root:*:13790:0:99999:7:::';
    system(qq(perl -pi -e 's/^root.*/q($root)/e' /mnt/etc/shadow)) == 0
      or die "Failed to set root shadow entry"; # not run_local so it doesn't echo
}

sub configure_xen_inittab {
    system("perl -pi -e '$_=qq(#$_) if /mingetty tty/' /mnt/etc/inittab");
    system(
        "echo co:2345:respawn:/sbin/agetty xvc0 9600 vt100-nav >> /mnt/etc/inittab"
    );
}

sub configure_inittab {
    my $self = shift;
    my $cfg  = $self->{cfg};
    return if $cfg->{only_reconfigure};

    # do not configure inittab for RHEL 6 
    return if -d '/mnt/etc/init';
       
    if ( is_xen_paravirt() ) {
        $self->configure_xen_inittab;
        return;
    }

    my $boot_console  = Yahoo::SysBuilder::Console->new->boot_console($cfg);
    my @serial_ports  = Yahoo::SysBuilder::SerialPort->new->serial_ports;
    my $console_speed = $cfg->{console_serial_speed} || 9600;
    my $console_port  = "";

    if ( $boot_console =~ /\Aconsole=ttyS(\d+),\d+\z/ ) {
        $console_port = $1;
    }

    system("egrep -v '^c[0-9]' /mnt/etc/inittab > /mnt/etc/inittab.new");
    open my $fh, ">>", "/mnt/etc/inittab.new"
        or fatal_error("/mnt/etc/inittab.new: $!");
    for my $serial (@serial_ports) {
        my $speed = 9600;

        # add a getty line to /etc/inittab
        # for each serial port
        if ( $serial eq $console_port ) {
            $speed = $console_speed;
        }
        print $fh
            "c${serial}:2345:respawn:/sbin/agetty ttyS$serial $speed vt100-nav\n";
    }
    close $fh;
    unlink "/mnt/etc/inittab";
    rename "/mnt/etc/inittab.new", "/mnt/etc/inittab";
}

sub configure_hardware {
    my $self = shift;
    my $cfg  = $self->{cfg};

    if( -x "/mnt/usr/sbin/kudzu" ) {
        run_local(
            qq(chroot /mnt sh -c '/usr/sbin/kudzu -p -q >/etc/sysconfig/hwconf'));
    }
}

sub esx {
    my $self = shift;
    unless ( defined $self->{_esx} ) {
        my $uts_release = shift;
        $uts_release ||= ( POSIX::uname() )[2];
        if ( $uts_release =~ / ELvmnix /msx ) {
            $self->{_esx} = $uts_release;
        }
        else {

            $self->{_esx} = 0;
        }
    }
    return $self->{_esx};
}

sub configure_rc_local {
    my $self     = shift;
    my $rc_local = <<'EOT';
#!/bin/sh
if [ -d /etc/rc.d/rc.once.d ]; then
  for f in /etc/rc.d/rc.once.d/*
  do
    test -x $f && $f
    rm -f $f
  done
fi

touch /var/lock/subsys/local
EOT

    write_file( "/mnt/etc/rc.d/rc.local", $rc_local );
    chmod oct("0755"), '/mnt/etc/rc.d/rc.local';
}

sub generate_esx_conf {
    my $self       = shift;
    my $net        = $self->{net};
    my $iface_name = $net->primary_iface;
    $iface_name =~ s/eth/vmnic/;
    write_file( "/mnt/tmp/primary_nic.txt", $iface_name );

    my $dest = "/tmp/generate-esx-conf.pl";
    run_local(
        "cp /sysbuilder/lib/Yahoo/SysBuilder/generate-esx-conf.pl /mnt$dest");
    chmod( oct("0755"), "/mnt$dest" );
    run_local(qq(chroot /mnt $dest));
    unlink "/mnt$dest";
}

sub configure_esx {
    my $self = shift;

    my $fs = YAML::LoadFile("/sysbuilder/etc/filesystems.yaml");
    return unless $fs->{'vmfs3'};

    $self->generate_esx_conf;

    my $rc_once = <<'EOT';
#!/bin/bash

PATH=/bin:/usr/bin:/usr/sbin:/sbin

echo Configuring VMFS3 volumes

devices=()
for part in $(fdisk -l|awk '$5 == "fb" {print $1}')
do
        dev=$(echo $part | sed 's/p\?[0-9]$//')
        part_nr=$(echo $part | sed "s,$dev,,")
        vmhba=$(esxcfg-vmhbadevs | awk -v dev="$dev" '$2 == dev {print $1}')

        devices=($devices $vmhba:$part_nr)
done

first_dev=${devices[0]}
vmkfstools -C vmfs3 -S default -b 4m $first_dev
rm -f /tmp/vmkfs-helper

for dev in ${devices[@]:1}
do
        echo spawn -noecho vmkfstools -Z $dev $first_dev > /tmp/vmkfs-helper
        echo "expect {" >> /tmp/vmkfs-helper
        echo '"0)" { send -- "0\r"' >> /tmp/vmkfs-helper
        echo '       exp_continue }' >> /tmp/vmkfs-helper
        echo 'eof { exit 0 } }' >> /tmp/vmkfs-helper
        expect /tmp/vmkfs-helper
        rm -f /tmp/vmkfs-helper
done

echo Configuring VMFS3 volumes: Completed
EOT
    mkdir "/mnt/etc/rc.d/rc.once.d", oct("0755");
    write_file( "/mnt/etc/rc.d/rc.once.d/create_vmfs3", $rc_once );
    chmod oct("0755"), '/mnt/etc/rc.d/rc.once.d/create_vmfs3';

}

sub configure_network {
    my $self = shift;
    my $cfg  = $self->{cfg};
    my $tpl  = $self->{tpl};
    my $net  = $self->{net};

    my $sys = '/mnt/etc/sysconfig';

    # extra lines for /etc/sysconfig/network
    my @sysconfig_network;

    # get the pci information
    my $devices = $self->{net}->net_devices;

    # does this OS use MACADDR= or HWADDR= in network-scripts
    my $hwaddr = $self->esx ? "MACADDR" : "HWADDR";

    # remove existing ifcfg-eth files
    unlink glob "$sys/network-scripts/ifcfg-eth*";

    # get interfaces listed in the hostconfig
    my %ifaces = %{ $cfg->{interfaces} };

    # rename special key "PRIMARY"
    my $primary_iface = $net->primary_iface;
    if( $ifaces{PRIMARY} ) {
        if( $primary_iface && $devices->{$primary_iface} ) {
            $ifaces{$primary_iface} = delete $ifaces{PRIMARY};
        } else {
            fatal_error("no interface found for primary=$primary_iface");
        }
    }

    # for each interface
    for my $iface ( sort keys %$devices ) {
        my $iface_cfg = $ifaces{$iface};
        my $iface_dev = $devices->{$iface};
        my $iface_name_for_os
            = ( $self->esx && $iface eq $primary_iface ) ? "vswif0" : $iface;

        # bootproto required for configured ifaces
        my $bootproto = $iface_cfg && $iface_cfg->{bootproto};
        if( $iface_cfg && ! defined $bootproto ) {
            fatal_error("bootproto needs to be defined for interface $iface");
        }

        if ( $iface eq $primary_iface and $bootproto eq "static" ) {
            my $gw_ip = $net->gateway_ip;
            push @sysconfig_network, "GATEWAY=$gw_ip";
            if ( $self->esx ) {
                push @sysconfig_network, "GATEWAYDEV=vswif0";
            }
            # enable ipv6 networking if the primary interface
            # has an address defined in $cfg
            #
            # for more info about ipv6 host support visit: 
            # http://twiki.corp.yahoo.com/view/IPv6/HostConfiguration
            if ( $cfg->{ipv6} and $net->gateway_ip6 and $net->ip6 ) {
                push @sysconfig_network, "NETWORKING_IPV6=yes";
                push @sysconfig_network, "IPV6_DEFAULTGW=" . $net->gateway_ip6 . "%" . $iface;
                push @sysconfig_network, "IPV6_AUTOCONF=no";
            } else {
                push @sysconfig_network, "NETWORKING_IPV6=no";
            }
        }

        # default for 'static' are the values in dhclient.yaml
        my @fields;
        my $comment = $iface_dev->{desc} || "";
        push @fields, "# $comment" if $comment;
        push @fields, "DEVICE=$iface_name_for_os";
        push @fields, "BOOTPROTO=$bootproto" if $bootproto;
        my $mac = $iface_dev->{mac};
        push @fields, "$hwaddr=$mac" if $mac;
        my $onboot = ( $iface_cfg ? $iface_cfg->{onboot} || 'yes' : 'no' );
        push @fields, "ONBOOT=$onboot";

        if ( $iface_cfg and $bootproto eq 'static' ) {
            push @fields,
                static_interface( $iface, $iface_cfg, $net );
        }

        if ( $self->esx ) {
            if ( $iface eq $primary_iface ) {
                push @fields, 'PORTGROUP="Service Console"';
            }
        }
        else {
            push @fields, "NOZEROCONF=1";
        }
        
        $tpl->write(
            "$sys/network-scripts/ifcfg-$iface_name_for_os",
            join( "\n", @fields ) . "\n" );
    }

    my $network = "NETWORKING=yes\nHOSTNAME=::HOSTNAME::\n" . ( join "\n", @sysconfig_network ) . "\n";
    $tpl->write( "$sys/network", $network );

    if (grep { /^GATEWAY=/ } @sysconfig_network) {
        $self->configure_static_hosts;
    }
    else {
        $tpl->write( "/mnt/etc/hosts",
            "127.0.0.1      ::HOSTNAME:: ::SHORT_HOSTNAME:: localhost.::DOMAIN:: localhost"
        );
    }
}

sub static_interface {
    my ( $name, $iface, $net ) = @_;

    my $ip      = $iface->{ip};
    my $netmask = $iface->{netmask};

    if ( $name ne $net->primary_iface ) {
        return unless $ip;    # can't guess about non-primary interfaces
    }

    $ip      ||= $net->ip;
    $netmask ||= $net->netmask;
    my $netblock  = Net::Netmask->new( $ip, $netmask );
    my $broadcast = $netblock->broadcast;
    my $network   = $netblock->base;

    my @res = (
        "IPADDR=$ip",           "NETMASK=$netmask",
        "BROADCAST=$broadcast", "NETWORK=$network"
    );
    
    # configure ipv6 address if we have one
    if ( $iface->{ip6} ) {
        push @res, "IPV6INIT=yes";
        push @res, "IPV6ADDR=$iface->{ip6}";
    }
    return @res;
}

# by default the image uses sendmail - disable the daemon
sub configure_sendmail {
    my $self = shift;
    my $tpl  = $self->{tpl};

    if ( -e "/mnt/etc/sysconfig/sendmail" ) {
        $tpl->write( "/mnt/etc/sysconfig/sendmail", "DAEMON=no\nQUEUE=1h\n" );
        system(   "perl -pi -e "
                . "'s/DnMAILER-DAEMON/DnMAILER-DAEMON\nDMyahoo-inc.com/' "
                . "/mnt/etc/mail/sendmail.cf" );
    }
}

# if we replaced sendmail with postfix, then install our config file
sub configure_postfix {
    my $self = shift;
    my $tpl  = $self->{tpl};

    if ( -e "/mnt/etc/postfix/main.cf" ) {
        $tpl->write( "/mnt/etc/postfix/main.cf", <<'EOT');
queue_directory = /var/spool/postfix
command_directory = /usr/sbin
daemon_directory = /usr/libexec/postfix
mail_owner = postfix
inet_interfaces = localhost
mydomain = ::DOMAIN::
myhostname = ::HOSTNAME::
mydestination = $myhostname, localhost.$mydomain, localhost
unknown_local_recipient_reject_code = 550
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
debug_peer_level = 2
sendmail_path = /usr/sbin/sendmail.postfix
newaliases_path = /usr/bin/newaliases.postfix
mailq_path = /usr/bin/mailq.postfix
setgid_group = postdrop
html_directory = no
manpage_directory = /usr/share/man
sample_directory = /usr/share/doc/postfix-2.2.10/samples
readme_directory = /usr/share/doc/postfix-2.2.10/README_FILES
EOT
    }
}

# use the resolv.conf provided by dhclient
# maybe allow users to override this in the config
sub configure_resolv_conf {
    my $self   = shift;
    my %params = ( file => "/mnt/etc/resolv.conf", @_ );
    my $cfg    = $self->{cfg};
    my $tpl    = $self->{tpl};
    my $dnscfg = $cfg->{dns};

    if ($dnscfg) {

        # write resolv.conf from hostconfig overrides
        my $search = $dnscfg->{search} || "::DOMAIN::";
        my $header = <<EOT;
; generated by ysysbuilder
search $search

options attempts:3
options timeout:1

EOT
        $tpl->write(
            $params{file},
            $header
                . join(
                "\n", map {"nameserver $_"} @{ $dnscfg->{nameserver} }
                )
                . "\n\n"
        );
    }
    else {

        # use resolv.conf from dhclient
        system("cp /etc/resolv.conf $params{file}");
    }
}

# use the ntp.conf provided by dhclient
# if present
sub configure_ntp_conf {
    my $self   = shift;
    my %params = (
        file          => "/mnt/etc/ntp.conf",
        dhclient_file => "/sysbuilder/etc/dhclient.yaml",
        @_
    );
    my $cfg = $self->{cfg};
    my $tpl = $self->{tpl};
    my $net = $self->{net};

    if ( -e $params{dhclient_file} ) {
        require YAML;
        my $dhclient    = YAML::LoadFile( $params{dhclient_file} );
        my $iface_name  = $net->primary_iface;
        my $ntp_servers = $dhclient->{$iface_name}{ntp_servers};

        if ($ntp_servers) {
            my @servers = split ' ', $ntp_servers;
            my $servers  = join( "\n", map {"server $_"} @servers );
            my $restrict = join( "\n", map {"restrict $_"} @servers );

            my $ntp_conf = <<EOT;
# Generated by ysysbuilder

driftfile /var/lib/ntp/drift
pidfile /var/run/ntpd.pid

$servers

restrict default ignore
restrict 127.0.0.1
$restrict

EOT

            $tpl->write( $params{file}, $ntp_conf );
        }
    }
    else {

        # backup plan: use file from dhclient
        return unless -r "/etc/ntp.conf";
        system("cp /etc/ntp.conf /mnt/etc/ntp.conf");
    }
}

# /etc/hostname needs to have our hostname
sub configure_hostname {
    my $self = shift;
    my $tpl  = $self->{tpl};

    $tpl->write( "/mnt/etc/hostname", "::HOSTNAME::\n" );
}

# /etc/hosts
sub configure_static_hosts {
    my $self = shift;
    my $tpl  = $self->{tpl};

    $tpl->write( "/mnt/etc/hosts", <<'EOT');
127.0.0.1       localhost localhost.::DOMAIN::
::IP::          ::HOSTNAME:: ::SHORT_HOSTNAME::
::BOOTHOST_IP:: boothost
::GATEWAY_IP::  gateway
EOT
}

sub configure_mtab {
    my $self  = shift;
    
    # bug 2676916 - if the image has an /etc/mtab with / mounted ro yinst will fail to install
    # so we're going to copy the mtab from the ramdisk and make it look right
    
    my $mtab = read_file('/etc/mtab');
    $mtab =~ s{/mnt/}{/}go;
    write_file( '/mnt/etc/mtab', $mtab );
}

1;
