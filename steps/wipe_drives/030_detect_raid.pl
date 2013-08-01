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
use SysBuilder::DiskConfig;
use SysBuilder::Utils qw(  optional_shell fatal_error run_local );


my $hwconfig_cmd = "/usr/local/bin/hwconfig";
my @hwconfig_output = qx/$hwconfig_cmd/;
if( $? ) {
    fatal_error("hwconfig failed");
}

foreach (@hwconfig_output) {
    if( $_ =~ /RAID-\d+/ ){
        
        print "Found RAID disk configuration\n";
        print "Converting to JBOD\n";
        
        my $cfg = YAML::LoadFile('/sysbuilder/etc/config.yaml');
        #hack to add a disk config so that other code will execute properly
        $cfg->{disk_config}{hwraid} = 1;
        my $disks = SysBuilder::DiskConfig->new( cfg => $cfg );

        $disks->setup_hwraid_jbod( );
    
    
    }elsif ($_ =~ /JBOD/ ) {
        print "Found JBOD disk configuration\n";
    }
}     
        
exit 0;
