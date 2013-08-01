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

my $cfg      = YAML::LoadFile( '/sysbuilder/etc/config.yaml' );
my $dhclient = YAML::LoadFile( '/sysbuilder/etc/dhclient.yaml' );

my $info = {
    installdate          => scalar localtime,
    hostname             => $cfg->{hostname},
    boothost_ip          => $cfg->{boothost_ip},
    profile              => $cfg->{profile},
    image                => $cfg->{image},
    installer            => $cfg->{installer},
    kernel_cmdline       => $cfg->{kernel_cmdline},
    
};

YAML::DumpFile( "/mnt/etc/info", $info );
system("chmod 0644 /mnt/etc/info");

$|++;

# umount filesystems
# test
mkdir "/mnt/root/sysbuilder";
mkdir "/mnt/root/sysbuilder/dhclient";
mkdir "/mnt/root/sysbuilder/etc";

print "INFO: Killing Processes.\n";
system("fuser -km /mnt");

print "INFO: Preserving log files\n";
run_local("cp -r /tmp/dhclient* /mnt/root/sysbuilder/dhclient");
run_local("cp -r /sysbuilder/etc/* /mnt/root/sysbuilder/etc");
run_local("cp -r /tmp/* /mnt/root/sysbuilder");

print "INFO: Reading ssh host public keys\n";
chomp( my $rsa_key = qx[chroot /mnt ssh-keygen -f /etc/ssh/ssh_host_rsa_key.pub -l | awk \Q{print \$2}\E] );
chomp( my $dsa_key = qx[chroot /mnt ssh-keygen -f /etc/ssh/ssh_host_dsa_key.pub -l | awk \Q{print \$2}\E] );

print "INFO: Unmounting file systems\n";
umount();

print "INFO: Notifying boothost we're done\n";

# notify boothost we're done (unless we're running under vm)
notify_boothost( nextboot => 'done', rsa_key => $rsa_key, dsa_key => $dsa_key, build_id => $cfg->{build_id} )
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

