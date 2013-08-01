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
use SysBuilder::Modprobe;

my $cfg = YAML::LoadFile('/sysbuilder/etc/config.yaml');
exit 0 if $cfg->{only_reconfigure};

# generate /etc/modprobe.conf
# precondition /mnt has the root file system mounted, and writable

my $mod = SysBuilder::Modprobe->new;

# enable ipv6 via a profile setting
if ( $cfg->{ipv6} ) {
    $mod->ipv6(1);
}

if ( $cfg->{conntrack_hash} ) {
    $mod->ip_conntrack( $cfg->{conntrack_hash} );
}

my $filename = $mod->filename;
$mod->generate($filename);
exit 0;

