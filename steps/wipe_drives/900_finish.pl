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
use SysBuilder::Utils qw( optional_shell run_local notify_boothost read_file);
my $cfg = YAML::LoadFile('/sysbuilder/etc/config.yaml');

$|++;

print "INFO: Killing Processes.\n";
system("killall -q minilogd");
system("killall -q cupsd");
system("killall -q acpid");
system(q(ps -ef|awk '/home/ && !/awk/{print $2}'|xargs kill 2>/dev/null));


print "INFO: Unmounting file systems\n";
umount();

print "INFO: Notifying boothost we're done\n";

# notify boothost we're done (unless we're running under vm)
my $status_msg = read_file('/tmp/wipe_status');

notify_boothost( nextboot => 'done', status => $status_msg, broadcast => 'no' )
    unless exists $cfg->{vm_user};


open my $ok_file, ">", "/tmp/sysbuilder-installer-ok";
close $ok_file;

print "\n\n\n\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n";
print " STATUS MESSAGES ARE BELOW AND REPORTED TO THE  SERVER \n"; 
print " YOU MUST MANUALLY REBOOT \n\n";
print " $status_msg \n\n";
print "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n\n\n\n\n";

sleep 1;

print "Downing network interfaces\n\n";
run_local( "/sbin/ifconfig eth0 down" );
run_local( "/sbin/ifconfig eth1 down" );

optional_shell(1209600);

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

