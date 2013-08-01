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
use SysBuilder::Utils qw(notify_boothost);
my $cfg = YAML::LoadFile('/sysbuilder/etc/config.yaml');

$|++;

print "INFO: Killing Processes.\n";
system("killall -q minilogd");
system("killall -q cupsd");
system("killall -q acpid");
system(q(ps -ef|awk '/home/ && !/awk/{print $2}'|xargs kill 2>/dev/null));

print "INFO: Notifying boothost we're done\n";

# notify boothost we're done (unless we're running under vm)
notify_boothost( nextboot => 'done', broadcast => 'no' )
    unless exists $cfg->{vm_user};

open my $ok_file, ">", "/tmp/sysbuilder-installer-ok";
close $ok_file;

print "RESCUE SHELL COMPLETED\n\n";
sleep 1;

exit 0;

