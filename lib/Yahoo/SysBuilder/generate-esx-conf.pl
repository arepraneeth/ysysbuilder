#!/usr/bin/perl

use strict;
use warnings 'all';

use lib "/usr/lib/vmware/esx-perl/perl5/site_perl/5.8.0";
use VMware::PCI::HostInterface qw(GetDevicesFromHostProbe);
use VMware::PCI::PCIInfo qw(FindPCIDeviceManager);

use VMware::CmdTool;
use VMware::Log qw(LogMute);

LogMute();
my $config = VMware::CmdTool::LoadConfig(0);
my $dev_manager = FindPCIDeviceManager( $config, 0 );

my $vmnic = 0;
my $vmhba = 0;
my $dma   = 0;
my @devices;

my $config_data = $dev_manager->GetConfigData;
for my $dev ( sort keys %$config_data ) {
    my $dev_str  = "/device/$dev";
    my $dev_data = $config_data->{$dev};
    if ( $dev_data->{class} =~ /\A 0[12]0/msx ) {
        $dev_data->{owner} = "vmkernel";
    }
    if ( $dev_data->{name} =~ /\b DMA \b/msxi ) {
        $dev_data->{owner} = "vmkernel";
    }
    for my $dev_key ( sort keys %$dev_data ) {
        my $data = $dev_data->{$dev_key};
        unless ( defined $data ) {
            if ( $dev_key eq "vmkname" ) {
                if ( $dev_data->{class} =~ /\A 020/msx ) {
                    $data = "vmnic$vmnic";
                    $vmnic++;
                }
                elsif ( $dev_data->{class} =~ /\A 010/msx ) {
                    $data = "vmhba$vmhba";
                    $vmhba++;
                }
                elsif ( $dev_data->{name} =~ /\b DMA \b/msxi ) {
                    $data = "dma$dma";
                    $dma++;
                }
            }
        }
        push @devices, qq($dev_str/$dev_key = "$data") if defined $data;
    }
}

my @macs = `awk '/network.hwaddr/{print \$2}' /etc/sysconfig/hwconf`;
chomp(@macs);

my @pnics;
$vmnic--;
for my $i ( 0 .. $vmnic ) {
    my $pnic_str = sprintf( "/net/pnic/child[%04d]", $i );
    push @pnics, qq($pnic_str/mac = "$macs[$i]");
    push @pnics, qq($pnic_str/name = "vmnic$i");
}

# load template file
my @esx_conf = `cat /etc/vmware/esx.conf`;
chomp(@esx_conf);

@esx_conf = grep { !m{\A (?:/device | /net/pnic)}msx } @esx_conf;
my $primary_nic = get_primary_nic();
for (@esx_conf) {
    if (m(/net/vswitch/.*uplinks.*/pnic = "vmnic)) {

        #    s/vmnic\d/$primary_nic/;
    }
}

push @esx_conf, @devices, @pnics;
@esx_conf = sort(@esx_conf);

open my $ofh, ">", "/etc/vmware/esx.conf.new"
    or die "/etc/vmware/esx.conf.new";
print $ofh "$_\n" for @esx_conf;
close $ofh;

unlink "/etc/vmware/esx.conf";
rename "/etc/vmware/esx.conf.new" => "/etc/vmware/esx.conf";
exit 0;

# Read the network config to determine the primary NIC
# returns vmnic0, vmnic1, etc.
sub get_primary_nic {
    my $result = "vmnic0";
    if ( -r "/tmp/primary_nic.txt" ) {
        chomp( $result = `cat /tmp/primary_nic.txt` );
    }
    unlink "/tmp/primary_nic.txt";
    return $result;
}
