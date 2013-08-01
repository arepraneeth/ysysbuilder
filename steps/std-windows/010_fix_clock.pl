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
use SysBuilder::Utils qw(run_local);

my $cfg = YAML::LoadFile('/sysbuilder/etc/config.yaml');

my $ntp_server = $cfg->{ntp_server} || "pool.ntp.org";
my $err = run_local("ntpdate $ntp_server");
unless ($err) {
    run_local("hwclock --systohc");
}

# ignore errors if we can't reach an ntp server.
exit 0;
