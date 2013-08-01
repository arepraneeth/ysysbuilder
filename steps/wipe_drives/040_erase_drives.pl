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
use SysBuilder::Utils qw( optional_shell write_file );

my $cfg = YAML::LoadFile('/sysbuilder/etc/config.yaml');
my $disks = SysBuilder::DiskConfig->new( cfg => $cfg );

my $serials = $disks->get_serial_num;

if( ! $serials ) {
    print "No disks found\n";
    exit 1;
}

foreach my $disk (sort keys %$serials) {
    print "Wiping $disk ($serials->{$disk}->{serial}) \n";
}

print "\n\n\nDisk wipe will start in 15 sec. Press 'X' if this is not intended.\n";
optional_shell(15);


foreach my $disk (sort keys %$serials) {
    
    my $err = $disks->shred($disk);
    if ( $err ) {
        $serials->{$disk}->{wipe_status}='FAIL';
    }else {
        $serials->{$disk}->{wipe_status}='PASS';
    }
}

#create status message and write the file out
my $status_msg = "";

foreach my $key (sort keys %$serials) {
  $status_msg .= "$key serial number: $serials->{$key}->{serial}. Shred status: $serials->{$key}->{wipe_status}";
}

write_file('/tmp/wipe_status', $status_msg);


exit 0;
