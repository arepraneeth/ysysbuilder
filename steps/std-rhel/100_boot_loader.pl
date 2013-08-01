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
use SysBuilder::Utils qw(run_local notify_boothost);
use SysBuilder::BootLoader;

my $cfg = YAML::LoadFile('/sysbuilder/etc/config.yaml');
my $loader = SysBuilder::BootLoader->new( cfg => $cfg );

# create devices.map
# use kernel cmd line + auto detected console for grub.conf
$loader->config( create_initrd => 1 );

# install grub
$loader->install;

exit 0;
