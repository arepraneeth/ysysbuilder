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
use SysBuilder::Utils qw(run_local untar_cmd get_base fatal_error);
use SysBuilder::DiskConfig;

my $cfg = YAML::LoadFile('/sysbuilder/etc/config.yaml');
exit 0 if $cfg->{only_reconfigure};

my $image = $cfg->{image};
die "Need an image" unless $image;

my $base      = get_base();
my $image_url = "$base/$image";

my $exit_code;

image_linux($image_url);
clean_up_image();

sub clean_up_image {
    for my $f ( glob("/mnt/etc/ssh/ssh*key*") ) {
        unlink $f;
    }

    open my $fh, ">", "/mnt/var/log/messages";
    close $fh;
}

sub image_linux {
    my $image_url = shift;
    my $untar = untar_cmd( url => $image_url, use_pv => 1 );

    # preconditions: all the file systems are mounted
    system("mount | grep -q /mnt");
    if ($?) {
        fatal_error("Filesystems are not mounted");
    }

    chdir("/mnt");
    my $cmd = "wget -q -O - $image_url | $untar";
    my $err = run_local($cmd);
    chown 0, 0, "/mnt/";
    exit( ($err>>8)||1 ) if $err;

    # handle symlinks
    my $disks = SysBuilder::DiskConfig->new( cfg => $cfg );
    $disks->symlinks;
    return $disks->config_files;
}

