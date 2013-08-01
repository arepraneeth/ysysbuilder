#!/usr/bin/perl

use strict;
use warnings 'all';
use YAML qw();
use lib '/sysbuilder/lib';
use Yahoo::SysBuilder::ValidateHW;

my $cfg = YAML::LoadFile('/sysbuilder/etc/config.yaml');

# audit the hardware here
my $hw = Yahoo::SysBuilder::ValidateHW->new($cfg);
$hw->run_audit;
exit 0;
