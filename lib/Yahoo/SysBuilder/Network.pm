package Yahoo::SysBuilder::Network;

use strict;
use warnings 'all';
use YAML qw();
use FindBin(qw($Bin));
use lib qq($Bin/../lib);
use Yahoo::SysBuilder::Utils qw/backtick run_local fatal_error/;
use Yahoo::SysBuilder::Proc;

=head1 NAME

Yahoo::SysBuilder::Network - Deal with network devices and settings


=head1 SYNOPSIS

my $net = Yahoo::SysBuilder::Network->new(cfg => $cfg);

=head1 DESCRIPTION

We can get our values from dhcp (using dhclient) or from
the kernel command line which uses:

    ip=client-ip:srvip:gw-ip:netmask:host:device:autoconf

Yahoo::SysBuilder::Proc returns that info in a convenient hash

=cut

sub new {
    my $class         = shift;
    my %params        = @_;
    my $cfg           = $params{cfg} || {};
    my $dhclient_file = $params{dhclient_file};
    my $proc          = $params{proc} || Yahoo::SysBuilder::Proc->new;

    my $self = bless {
        cfg           => $cfg,
        dhclient_file => $dhclient_file,
        proc          => $proc,
        dryrun        => $params{dryrun},
    }, $class;

    return $self;
}

sub config {
    my $self = shift;

    # load ipv6 so we can disable autoconf
    run_local("modprobe ipv6");

    # check if ipv6 loaded
    if( -f "/proc/net/if_inet6" && -d "/proc/sys/net/ipv6/conf" ) {
        run_local("echo 0 > /proc/sys/net/ipv6/conf/all/accept_ra" );
        run_local("echo 0 > /proc/sys/net/ipv6/conf/all/accept_redirects" );
        run_local("echo 0 > /proc/sys/net/ipv6/conf/default/accept_ra" );
        run_local("echo 0 > /proc/sys/net/ipv6/conf/default/accept_redirects" );
    }

    # we config ourselves using ip=... from /proc/cmdline
    # or from a dhclient generated file
    # both of these two methods will set _configd to 1 when done

    my $ip_info = $self->{proc}->ip_info;
    if ($ip_info) {
        $self->_config_with_ip_info($ip_info);
    }
    else {
        $self->_start_dhclient;
    }
}

sub _load_config {
    my $self = shift;

    my $ip_info = $self->{proc}->ip_info;
    if ($ip_info) {
        $self->_load_ip_info($ip_info);
    }
    else {
        $self->_load_dhclient_data;
    }

    # we now have the _XXX settings
    # gotten from our install time values
    # let's get the real settings, based on $cfg and
    # use the _XXX versions as defaults
    my $cfg = $self->{cfg};
    $self->{hostname}      = $cfg->{hostname}      || $self->{_hostname};
    $self->{gateway_ip}    = $cfg->{gateway_ip}    || $self->{_gateway_ip};
    $self->{boothost_ip}   = $cfg->{boothost_ip}   || $self->{_boothost_ip};
    $self->{primary_iface} = $cfg->{primary_iface} || $self->{_primary_iface};

    my $pri_cfg = $cfg->{interfaces}{'PRIMARY'}
        || $cfg->{interfaces}{ $self->{primary_iface} };

    $self->{ip}      = $pri_cfg->{ip}      || $self->{_ip};
    $self->{netmask} = $pri_cfg->{netmask} || $self->{_netmask};

    # we may have also been provided an ipv6 address to configure
    $self->{ip6}         = $pri_cfg->{ip6}      || undef;
    $self->{gateway_ip6} = $cfg->{gateway_ip6}  || undef;
    
    $self->{_configd} = 1;
}

sub net_devices {
    my $self = shift;

    my %res;

    my @devices = backtick( "ifconfig -a | grep eth" );
    for my $device ( @devices ) {
        $device =~ s/^\s+//;
        my ( $name, $mac ) = ( split /\s+/, $device )[ 0, -1 ];
        $res{$name} = { mac => $mac };
    }

    return \%res;
}

# we'll have to simulate dhclient as well
# to keep the rest of the code happy
sub _config_with_ip_info {
    my ( $self, $ip_info ) = @_;

    unless ( $self->{dryrun} ) {
        my $cmd = sprintf(
            'ifconfig %s up %s netmask %s broadcast %s',
            $ip_info->{'device'},  $ip_info->{'ip'},
            $ip_info->{'netmask'}, $ip_info->{'broadcast'}
        );

        run_local($cmd);
        run_local( 'route add default gw ' . $ip_info->{gateway_ip} );
        run_local( 'hostname ' . $ip_info->{hostname} );
    }
}

sub _load_ip_info {
    my ( $self, $ip_info ) = @_;
    my $boothost_ip = $self->{proc}->boothost_from_base
        || $ip_info->{boothost_ip};

    # save these for later
    $self->{_hostname}      = $ip_info->{hostname};
    $self->{_gateway_ip}    = $ip_info->{gateway_ip};
    $self->{_boothost_ip}   = $boothost_ip;
    $self->{_primary_iface} = $ip_info->{'device'};
    $self->{_ip}            = $ip_info->{'ip'};
    $self->{_netmask}       = $ip_info->{'netmask'};
}

sub ip {
    my $self = shift;
    $self->_load_config unless $self->{_configd};
    return $self->{ip};
}

sub ip6 {
    my $self = shift;
    $self->_load_config unless $self->{_configd};
    return $self->{ip6};
}

sub netmask {
    my $self = shift;
    $self->_load_config unless $self->{_configd};
    return $self->{netmask};
}

sub gateway_ip {
    my $self = shift;
    $self->_load_config unless $self->{_configd};
    return $self->{gateway_ip};
}

sub gateway_ip6 {
    my $self = shift;
    $self->_load_config unless $self->{_configd};
    return $self->{gateway_ip6};
}

sub boothost_ip {
    my $self = shift;
    $self->_load_config unless $self->{_configd};
    return $self->{boothost_ip};
}

sub hostname {
    my $self = shift;
    $self->_load_config unless $self->{_configd};
    return $self->{hostname};
}

sub primary_iface {
    my $self = shift;
    $self->_load_config unless $self->{_configd};
    return $self->{primary_iface};
}

sub _load_dhclient_data {
    my $self     = shift;
    my $cfg_file = $self->{dhclient_file};

    unless ( defined $cfg_file ) {
        $cfg_file = "/sysbuilder/etc/dhclient.yaml";
    }

    fatal_error("dhclient config file: $cfg_file does not exist")
        unless -r $cfg_file;

    my $cfg = $self->{dhcp_cfg} = YAML::LoadFile($cfg_file);
    my @keys = sort keys %$cfg;
    for my $iface (@keys) {
        if ( exists $cfg->{$iface}->{server_name} ) {
            $self->{_primary_iface} = $iface;
            last;
        }
    }
    $self->{_primary_iface} = $keys[0] unless $self->{_primary_iface};
    my $if     = $self->{_primary_iface};
    my $if_cfg = $cfg->{$if};

    $self->{_hostname}    = $if_cfg->{server_name};
    $self->{_gateway_ip}  = $self->{cfg}->{routers} || $if_cfg->{routers};
    $self->{_boothost_ip} = $self->{proc}->boothost_from_base
        || $if_cfg->{dhcp_server_identifier};
    $self->{_ip}      = $if_cfg->{ip_address};
    $self->{_netmask} = $if_cfg->{subnet_mask};
}

sub _start_dhclient {
    my $self = shift;

    # dhclient 4.1 (4.x?) won't consider an interface without an address as ok for broadcast
    # so we need to provide a list explicitly
    my @ifaces = map { /^\d:\s*(\w+)/; $1; } grep { /BROADCAST/ && !/LOOPBACK/ } `ip link`;
    run_local("dhclient @ifaces >/tmp/dhclient.log 2>&1") unless $self->{dryrun};
}

1;
