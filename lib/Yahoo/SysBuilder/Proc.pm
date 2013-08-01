package Yahoo::SysBuilder::Proc;

=head1 NAME

Yahoo::SysBuilder::Proc - Interaction with /proc

=head1 SYNOPSIS

my $yproc = Yahoo::SysBuilder::Proc->new;
my $cmdline = $yproc->cmdline;

print "Kernel cmdline is $cmdline\n";

unless ($yproc->nodetect) {
   # do autodetection
}

=head1 DESCRIPTION

An Interface to deal with /proc

=cut

use strict;
use warnings 'all';
use FindBin(qw($Bin));
use lib qq($Bin/../lib);
use Yahoo::SysBuilder::Utils qw(read_file);
use Net::Netmask;

sub new {
    my $class  = shift;
    my %params = @_;
    bless { _cmdline => $params{cmdline} }, $class;
}

# returns /proc/cpuinfo
sub cpuinfo {
    my $self = shift;
    if ( $self->{_cpuinfo} ) {
        return $self->{_cpuinfo};
    }

    my $cpuinfo = read_file("/proc/cpuinfo");
    $self->{_cpuinfo} = $cpuinfo;
    return $cpuinfo;
}

# counts logical cpus
sub cpucount {
    my $self    = shift;
    my $cpuinfo = $self->cpuinfo;
    my @procs   = ( $cpuinfo =~ /(^processor \s* : \s* \d+)/gmsx );
    return scalar @procs;
}

sub memsize {
    my $self     = shift;
    my $memtotal = $self->{_memtotal};
    unless ($memtotal) {
        my @meminfo = grep {/\A MemTotal: /msx} read_file("/proc/meminfo");
        $memtotal = $meminfo[0];
    }

    my $size = ( $memtotal =~ /\A MemTotal: \s+ (\d+) \s+ kB/msx )[0];
    return $size;
}

sub devices {
    my $self     = shift;
    my $char     = {};      # character devices
    my $block    = {};      # block devices
    my $cur_hash = undef;

    # parse /proc/devices
    my @file = read_file("/proc/devices");
    for (@file) {
        if (/Character devices/) {
            $cur_hash = $char;
        }
        elsif (/Block devices/) {
            $cur_hash = $block;
        }
        else {
            my ( $dev_number, $dev_name ) = split;
            next unless defined($dev_number) and defined($dev_name);
            $cur_hash->{$dev_name} = $dev_number;
        }
    }

    return { char => $char, block => $block };
}

sub cmdline {
    my $self    = shift;
    my $cmdline = $self->{_cmdline};
    return $cmdline if defined $cmdline;

    $cmdline = read_file("/proc/cmdline");
    $self->{_cmdline} = $cmdline;
    return $cmdline;
}

sub nodetect {
    my $self    = shift;
    my $cmdline = $self->cmdline;
    return $cmdline =~ /\b nodetect \b/msx;
}

sub serialports {
    my $self = shift;
    my $file = "/proc/tty/driver/serial";
    return unless -f $file;
    my @ports = read_file($file);
    return @ports;
}

sub partitions {
    my $self  = shift;
    my $file  = "/proc/partitions";
    my @parts = read_file($file);
    my %res;
    for my $part (@parts) {
        next unless $part;
        my ( $major, $minor, $blocks, $name ) = split ' ', $part;
        next unless $major =~ /\A \d/msx;
        $res{$name} = {
            major  => $major,
            minor  => $minor,
            blocks => $blocks,
        };
    }
    return \%res;
}

sub disks {
    my $self       = shift;
    my $partitions = $self->partitions;
    my @disks;
    for my $name ( keys %$partitions ) {
        push @disks, $name if ( $partitions->{$name}{minor} % 16 ) == 0;
    }
    return \@disks;
}

# return the real boothost based on the base=PROTO://BOOTHOST/...
# cmdline option (if set)
sub boothost_from_base {
    my $self    = shift;
    my $cmdline = $self->cmdline;
    if ($cmdline =~ m{
\b \w+ # protocol
://    # separator
([^/:]+) # hostname
}msx
        )
    {
        return $1;
    }
    return;
}

# return the network information passed to the kernel
# in the command line
sub ip_info {
    my $self = shift;

    # ip=<client-ip>:<srv-ip>:<gw-ip>:<netmask>:<host>:<device>:<autoconf>
    my $cmdline = $self->cmdline;
    return unless $cmdline =~ /\bip=(\S+)\b/;

    my ( $ip, $boothost_ip, $gateway_ip, $netmask, $hostname, $dev )
        = split ':', $1;

    my $block = Net::Netmask->new( $ip, $netmask );

    my $base      = $block->base;
    my $broadcast = $block->broadcast;

    return {
        'ip'          => $ip,
        'boothost_ip' => $boothost_ip,
        'gateway_ip'  => $gateway_ip,
        'netmask'     => $netmask,
        'hostname'    => $hostname,
        'device'      => $dev,
        'broadcast'   => $broadcast,
        'network'     => $base,
    };
}

1;
