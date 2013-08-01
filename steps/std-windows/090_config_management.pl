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
use SysBuilder::CfgManagement;

my $cfg = YAML::LoadFile('/sysbuilder/etc/config.yaml');

# run with chroot => 0 since chrooting into the ntfs partition is a bad idea
my $cm = SysBuilder::CfgManagement->new($cfg, chroot => 0);
$cm->fetch;
$cm->activate;

exit 0;
