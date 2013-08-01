######################################################################
# Copyright (c) 2012, Yahoo! Inc. All rights reserved.
#
# This program is free software. You may copy or redistribute it under
# the same terms as Perl itself. Please see the LICENSE.Artistic file 
# included with this project for the terms of the Artistic License
# under which this project is licensed. 
######################################################################

#!/usr/bin/perl

use strict;
use warnings 'all';
use YAML qw();
use lib '/sysbuilder/lib';
use SysBuilder::Firmware;

my $cfg = YAML::LoadFile('/sysbuilder/etc/config.yaml');

# we don't audit the hardware if the user just wants to reconfig
# the machine
exit 0 if $cfg->{only_reconfigure};


my $firmware = SysBuilder::Firmware->new();
my $hw_mfg = $firmware->get_mfg();
$firmware->get_firmwareconfig();

if( $cfg->{stage} eq 'firmware_update' ) {  
    print "[STAGE: BIOS Firmware Update]\n";
    if ($hw_mfg =~ /Dell/) {
        $firmware->get_dell_host_info();
    	$firmware->get_code( action => "get_firmware_update" );
    	$firmware->do_dell_update();
    } elsif (($hw_mfg =~/HP/)||($hw_mfg =~ /Compaq/)) {
    	$firmware->get_code( action => "get_firmware_update" );
    	$firmware->do_hp_update();
    }
} elsif ( $cfg->{stage} eq 'bios_update' ) {
    print "[STAGE: BIOS Config Update]\n";
    if ($hw_mfg =~ /Dell/) {
        $firmware->get_dell_host_info();
    	#$firmware->get_code( action => "get_bios_update" ); #no need to download anything for Dell Hosts.
    	$firmware->do_dell_ipmi() if $cfg->{ipmi} == 1;
    } elsif (($hw_mfg =~/HP/)||($hw_mfg =~ /Compaq/)) {
    	$firmware->get_code( action => "get_bios_update" );
    	$firmware->do_hp_ipmi() if $cfg->{ipmi} == 1;
    	
    }
    
}

exit 0;
