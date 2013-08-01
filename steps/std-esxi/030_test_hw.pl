#!/usr/bin/perl

use strict;
use warnings 'all';
use YAML qw();
use lib '/sysbuilder/lib';
use Yahoo::SysBuilder::TestHW;

my $cfg = YAML::LoadFile('/sysbuilder/etc/config.yaml');

# for backwards compatibility with tools that didn't
# set quick_install - revert to the old behavior: don't test
exit 0 unless exists $cfg->{quick_install};

# exit quickly if they are in a hurry
exit 0 if $cfg->{quick_install} || $cfg->{only_reconfigure};

# run full hardware diagnostics
my $test_hw = Yahoo::SysBuilder::TestHW->new($cfg);
$test_hw->run_tests;
exit 0;
