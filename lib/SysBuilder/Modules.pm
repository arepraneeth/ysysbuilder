######################################################################
# Copyright (c) 2012, Yahoo! Inc. All rights reserved.
#
# This program is free software. You may copy or redistribute it under
# the same terms as Perl itself. Please see the LICENSE.Artistic file 
# included with this project for the terms of the Artistic License
# under which this project is licensed. 
######################################################################

package SysBuilder::Modules;

use strict;
use warnings 'all';
use YAML qw();
use POSIX qw();

use SysBuilder::Utils qw(read_file is_xen_paravirt);

sub new {
    my $class   = shift;
    my $version = ( POSIX::uname() )[2];    # release

    my %config = (
        'pcimap'   => "/lib/modules/$version/modules.pcimap",
        'pcitable' => '/usr/share/hwdata/pcitable',
        'devices'  => undef,
        'modprobe' => \&_modprobe,
        @_
    );
    unless ( defined $config{devices} ) {
        my @devices = `/sbin/lspci -n`;
        $config{devices} = \@devices;
    }
    return bless \%config, $class;
}

sub detect_modules {
    my $self = shift;

    if ( is_xen_paravirt() ) {
        return ( ['xenblk'], ['xennet'] );
    }

    my $pci_ids = $self->_pci_mappings;
    my $devices = $self->{devices};
    my ( @scsi_modules, @net_modules );

    for (@$devices) {
        s/Class //;
        my ( $class, $id ) = (split)[ 1, 2 ];
        $class =~ s/:$//;

        my $num_class = hex($class);
        if ( $num_class >= 0x100 and $num_class < 0x200 ) {
            if ($id =~ m/1af4:100/) {
                return(['virtio_pci','virtio_blk'],['virtio_net']);
            }
            push @scsi_modules, _module_for( $pci_ids, $id, "Storage" );
        }
        elsif ( $num_class == 0x200 ) {
            push @net_modules, _module_for( $pci_ids, $id, "Network" );
        }
    }

    return ( \@scsi_modules, \@net_modules );
}

# loading the right modules
sub load {
    my $self         = shift;
    my $modules_file = shift;

    my ( $scsi_modules, $net_modules ) = $self->detect_modules;

    my %modules = (
        'scsi' => $scsi_modules,
        'net'  => $net_modules,
    );

    if ($modules_file) {
        YAML::DumpFile( $modules_file, \%modules );
    }

    # load the modules
    my %seen;
    my $modprobe = $self->{modprobe};
    for (@$scsi_modules) {
        $modprobe->( "storage", $_ ) unless $seen{$_}++;
    }
    if (@$scsi_modules) {
        $modprobe->( "scsi disks", "sd_mod" );
    }

    for (@$net_modules) {
        $modprobe->( "network", $_ ) unless $seen{$_}++;
    }
}

sub _pci_mappings {
    my $self     = shift;
    my $pcimap   = $self->{pcimap};
    my $pcitable = $self->{pcitable};

    my %pciid_module;

    if ( open my $fh, "<", $pcitable ) {
        while (<$fh>) {
            next if /^#/;
            my ( $vendor, $device, $module ) = split;
            for ( $vendor, $device ) {
                s/0x//;
            }
            $module =~ s/"//g;
            my $id = "$vendor:$device";
            $pciid_module{$id} = $module;
        }
        close $fh;
    }

    open my $fh, "<", $pcimap
        or die "Can't load $pcimap: $!";
    while (<$fh>) {
        next if /^#/;
        my ( $mod, $vendor, $device ) = split;
        for ( $vendor, $device ) {
            s/0x0000//;
        }
        my $id = "$vendor:$device";
        $pciid_module{$id} = $mod;
    }
    close $fh;

    # -- unknown scsi hardware on DL160G6-sata in AHCI mode
    # hack to get around missing line in modules.pcimap on rhel4
    $pciid_module{'8086:3a22'} ||= 'ahci';
    $pciid_module{'8086:3b22'} ||= 'ahci';

    return \%pciid_module;
}

sub _module_for {
    my ( $pci_ids, $id, $type ) = @_;
    my $module = $pci_ids->{$id};
    return $module if defined $module;

    # look for class:0xffffffff instead
    my $wildcard = join( ':', ( split( ':', $id ) )[0], '0xffffffff' );
    $module = $pci_ids->{$wildcard};
    return $module if defined $module;

    return "Unknown-$id";
}

sub _modprobe {
    my ( $type, $module ) = @_;
    return if $module =~ /^Unknown/;

    print "----> Loading $type module: $module\n";
    system("modprobe $module");
}

1;
