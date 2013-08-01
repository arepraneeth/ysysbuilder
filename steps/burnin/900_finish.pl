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

$|++;

print "INFO: Notifying boothost we're done\n";

# notify boothost we're done (unless we're running under vm)
notify_boothost( nextboot => 'burn_in_done', broadcast => 'no' );

open my $ok_file, ">", "/tmp/sysbuilder-installer-ok";
close $ok_file;

print "BURN-IN COMPLETED\n\n";

exit 0;
