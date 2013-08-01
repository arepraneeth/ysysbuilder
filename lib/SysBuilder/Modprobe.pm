######################################################################
# Copyright (c) 2012, Yahoo! Inc. All rights reserved.
#
# This program is free software. You may copy or redistribute it under
# the same terms as Perl itself. Please see the LICENSE.Artistic file 
# included with this project for the terms of the Artistic License
# under which this project is licensed. 
######################################################################

package SysBuilder::Modprobe;

use strict;
use warnings 'all';
use YAML qw();
use FindBin(qw($Bin));
use lib qq($Bin/../lib);

=head1 NAME

SysBuilder::Modprobe - generate /etc/modprobe.conf

=head1 SYNOPSIS

my $mp = SysBuilder::Modprobe->new;
$mp->generate;

=head1 DESCRIPTION

This module generates /etc/modprobe.conf (or /etc/modules.conf for 2.4
kernels).  It uses a config file as input, which is usually generated
by SysBuilder::Modules.

It will optionally enable/disable ipv6, and it generates alias entries
for ethernet cards and scsi controllers.

=cut

sub new {
    my ( $class, %params ) = @_;
    my $cfg_filename = $params{modules_filename}
        || '/sysbuilder/etc/modules.yaml';

    my $mod_cfg = YAML::LoadFile($cfg_filename);
    return bless { mod_cfg => $mod_cfg, ipv6 => undef }, $class;
}

sub ipv6 {
    my ( $self, $enable ) = @_;
    $self->{ipv6} = $enable;
}

# Set the size of the ip_conntrack module's hash table. ip_conntrack will in
# turn set /proc/sys/net/ipv4/ip_conntrack_max (on 2.6.18 kernels), the maximum
# number of NAT connections allowed, to eight (8) times that number.
sub ip_conntrack {
    my ( $self, $conntrack_hash ) = @_;
    $self->{ip_conntrack_hash} = $conntrack_hash;
}

sub filename {
    my $self    = shift;
    my $release = `uname -r`;

    if ( $release =~ /\A 2\.4 /msx ) {
        return "/mnt/etc/modules.conf";
    }
    else {
        return "/mnt/etc/modprobe.conf";
    }
}

sub generate {
    my ( $self, $modprobe ) = @_;
    my @net  = @{ $self->{mod_cfg}->{net} };
    my @scsi = @{ $self->{mod_cfg}->{scsi} };

    open my $fh, ">", $modprobe or die "$modprobe: $!";
    my $i = 0;
    for my $net_module (@net) {
        next if $net_module =~ /\AUnknown-/msx;
        print $fh "alias eth$i $net_module\n";
        $i++;
    }

    $i = "";
    for my $scsi_module (@scsi) {
        next if $scsi_module =~ /\AUnknown-/msx;
        print $fh "alias scsi_hostadapter$i $scsi_module\n";
        $i++;
    }

    unless ( $self->{ipv6} ) {
        # disable ipv6
        print $fh "alias net-pf-10 off\n";

        # on newer linuxes we need to set the option disable=1
        # but it triggers warnings on older ones -- so figure out where we are
        my @ipv6_ko = glob "/mnt/lib/modules/*/kernel/net/ipv6/ipv6.ko";
        if( $ipv6_ko[0] ) {
            my @ipv6_modinfo = qx!/sbin/modinfo $ipv6_ko[0]!;
            if( grep { /^parm:\s*disable:/ } @ipv6_modinfo ) {
                print $fh "options ipv6 disable=1\n";
            }
        }
    }

    if ( $self->{ip_conntrack_hash} ) {
        print $fh "options ip_conntrack hashsize=", $self->{ip_conntrack_hash}, "\n";
    }

    print $fh "options loop max_loop=256\n";

    close $fh;
}

1;
