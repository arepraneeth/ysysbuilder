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

my $cfg = YAML::LoadFile('/sysbuilder/etc/config.yaml');

# we don't audit the hardware if the user just wants to reconfig
# the machine
exit 0 if $cfg->{only_reconfigure};

# audit the hardware here
exit 0;
