#!/usr/bin/perl

use strict;
use warnings 'all';
use YAML qw();
use lib '/sysbuilder/lib';
use Yahoo::SysBuilder::Utils qw(run_local untar_cmd get_base fatal_error);
use Yahoo::SysBuilder::DiskConfig;

my $cfg = YAML::LoadFile('/sysbuilder/etc/config.yaml');
exit 0 if $cfg->{only_reconfigure};

my $image = $cfg->{image};
die "Need an image" unless $image;

my $base      = get_base();
my $image_url = "$base/$image";
my $disks = Yahoo::SysBuilder::DiskConfig->new( cfg => $cfg );

my $untar_img = untar_cmd( url => $image_url, use_pv => 0 );
my $dev = $disks->get_windows_device();

my $err = run_local( "wget -qO - $image_url | $untar_img | dd of=/dev/$dev" );
fatal_error( "Failed to image the disk." ) if $err;
