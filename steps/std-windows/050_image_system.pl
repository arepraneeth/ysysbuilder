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
use SysBuilder::Utils
    qw(run_local untar_cmd get_base fatal_error optional_shell);
use SysBuilder::DiskConfig;

my $cfg = YAML::LoadFile('/sysbuilder/etc/config.yaml');
exit 0 if $cfg->{only_reconfigure};

my $image = $cfg->{image};
fatal_error("Need an image") unless $image;

my $mbr = $cfg->{mbr};
fatal_error("Need an MBR") unless $mbr;

my $base      = get_base();
my $image_url = "$base/$image";
my $mbr_url   = "$base/$mbr";

my $exit_code;

my $dc   = SysBuilder::DiskConfig->new( cfg => $cfg );
my $dev  = $dc->get_windows_device;
my $part = SysBuilder::DiskConfig::partition_name($dev, 1);

unless( $part and $dev ) {
    fatal_error( "Couldn't find windows partition that we just created." );
}

print "Installing on device $dev, partition $part\n";

my $untar_mbr = untar_cmd( url => $mbr_url,   use_pv => 0 );
my $untar_img = untar_cmd( url => $image_url, use_pv => 0 );
my $err;

# =========
# = Steps =
# =========

# load modules
system( "modprobe fuse" );
system( "modprobe edd" );

# overwrite the MBR
$err = run_local( "wget -qO - $mbr_url | $untar_mbr | dd bs=446 count=1 of=/dev/$dev" );
fatal_error( "Failed to overwrite the MBR." ) if $err;

# stripe image into partition
# need --ignore-length to work around apache 1.x bug
$err = run_local( "wget --ignore-length -qO - $image_url | $untar_img | ntfsclone --restore-image --overwrite /dev/$part -" );
fatal_error( "Failed to stripe image onto partition." ) if $err;

# resize image partition to fill
$err = run_local( "echo y | ntfsresize /dev/$part" );
fatal_error( "Failed to resize partition." ) if $err;

# get geometry values from kernel module
open SECTORS, "</sys/firmware/edd/int13_dev80/legacy_sectors_per_track"
  or fatal_error("couldn't read /sys/firmware/edd/int13_dev80/legacy_sectors_per_track");
chomp(my $sectors = <SECTORS>);
close SECTORS;
open HEADS, "</sys/firmware/edd/int13_dev80/legacy_max_head"
  or fatal_error("couldn't read /sys/firmware/edd/int13_dev80/legacy_max_head");
chomp(my $heads = <HEADS>);
$heads++;
close HEADS;

# try to get start sector.
chomp(my $start = qx{fdisk -ul /dev/$dev | awk '/\\/dev\\/$part/ { print \$3 }'});
$start = 1 unless ($start =~ m/^\d+$/);
print "Found start sector: $start\n";

# Fix filesystem geometry
if ($sectors and $heads) {
    $err = run_local("ntfsfixboot -t $sectors -h $heads -s $start -w /dev/$part");
} else {
    $err = run_local("ntfsfixboot -w /dev/$part");
}
# ntfsfixboot can return nonzero when successful so let's just hope it worked
print "ntfsfixboot returned code $err, continuing...\n";

# mount the filesystem
$err = run_local( "ntfs-3g /dev/$part /mnt" );
fatal_error( "Failed to mount filesystem." ) if $err;
