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
my $cfg = YAML::LoadFile('/sysbuilder/etc/config.yaml');

$|++;

# umount filesystems
# test
mkdir "/mnt/sysbuilder";
mkdir "/mnt/sysbuilder/dhclient";
mkdir "/mnt/sysbuilder/etc";

print "INFO: Killing Processes.\n";
system("killall -q minilogd");
system("killall -q cupsd");
system("killall -q acpid");
system(q(ps -ef|awk '/home/ && !/awk/{print $2}'|xargs kill 2>/dev/null));

print "INFO: Preserving log files\n";
run_local("cp -r /tmp/dhclient* /mnt/sysbuilder/dhclient");
run_local("cp -r /sysbuilder/etc/* /mnt/sysbuilder/etc");
run_local("cp -r /tmp/* /mnt/sysbuilder");

print "INFO: Unmounting file systems\n";
umount();

print "INFO: Notifying boothost we're done\n";

# notify boothost we're done (unless we're running under vm)
notify_boothost( nextboot => 'done', broadcast => 'no' )
    unless exists $cfg->{vm_user};

open my $ok_file, ">", "/tmp/sysbuilder-installer-ok";
close $ok_file;

print "IMAGING COMPLETED\n\n";
sleep 1;

exit 0;

sub umount {
    my @mount        = `mount`;
    my @mount_points = grep {m{\A/mnt}} map { (split)[2] } @mount;
    my $printed_ps   = 0;
    for my $m_point ( sort { length($b) <=> length($a) } @mount_points ) {
        my $err = run_local("umount $m_point");
        if ( $err && !$printed_ps ) {
            print "ERROR: umount $m_point failed.\n";
            chomp( my @ps = `ps -ef` );
            for my $line (@ps) {
                my @fields = split ' ', $line;
                next if $fields[-1] =~ /\A\[.*\]\z/;   # ignore kernel threads
                print "  $line\n";
            }
            $printed_ps = 1;
        }
    }
}

