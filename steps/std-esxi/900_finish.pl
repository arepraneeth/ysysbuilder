#!/usr/bin/perl

use strict;
use warnings 'all';
use YAML qw();
use lib '/sysbuilder/lib';
use Yahoo::SysBuilder::Utils qw(run_local notify_boothost);

my $cfg      = YAML::LoadFile( '/sysbuilder/etc/config.yaml' );
my $dhclient = YAML::LoadFile( '/sysbuilder/etc/dhclient.yaml' );

my $ybiipinfo = {
    installdate          => scalar localtime,
    hostname             => $cfg->{hostname},
    boothost_ip          => $cfg->{boothost_ip},
    profile              => $cfg->{profile},
    image                => $cfg->{image},
    installer            => $cfg->{installer},
    kernel_cmdline       => $cfg->{kernel_cmdline},
    yinst_ybiip_profiles => $cfg->{yinst_ybiip_profiles},
    yinst_ybootserver    => $cfg->{yinst_ybootserver},
};


$|++;


print "INFO: Notifying boothost we're done\n";

# notify boothost we're done (unless we're running under yvm)
notify_boothost( nextboot => 'done', broadcast => 'no' )
    unless exists $cfg->{yvm_user};

open my $ok_file, ">", "/tmp/ysysbuilder-installer-ok";
close $ok_file;

print "IMAGING COMPLETED\n\n";
sleep 1;

exit 0;
