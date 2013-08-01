#!/usr/local/bin/perl

use strict;
use warnings 'all';

use FindBin(qw($Bin));
use lib qq($Bin/../lib);
use Test::More tests => 7;
use Test::Differences;

my $module = 'SysBuilder::Template';

# compiles
use_ok($module);

# public interface
can_ok( $module, 'expand' );
can_ok( $module, 'write' );

use SysBuilder::Network;
use SysBuilder::Proc;

my $IP_INFO = "ip=169.254.100.10:1.2.3.4:169.254.100.1:255.255.255.0:xen-vm:eth1:off";
my $net     = SysBuilder::Network->new(
    proc   => SysBuilder::Proc->new( cmdline => "ro root=/dev/sda1 $IP_INFO" ),
    dryrun => 1
);

my $tpl = SysBuilder::Template->new(
    net => $net,
    cfg => {
        hostname => "foo.example.com",
        domain   => "example.com"
    }
);

my $test_str = "asdf asdf adsf";
eq_or_diff(
    $tpl->expand($test_str),
    $test_str,

    "template preserves strings with no ::TOKENS::"
);

$test_str = "::THIS_DOES_NOT_EXIST:: adfadfl;kjaldsfj";
eq_or_diff( $tpl->expand($test_str), $test_str, "unknown tokens are preserved" );

$test_str = "http://::IP::/something?h=::HOSTNAME::";
eq_or_diff(
    $tpl->expand($test_str),
    "http://169.254.100.10/something?h=foo.example.com",
    "tokens expanded"
);

eq_or_diff( $tpl->expand("::SHORT_HOSTNAME::"), "foo", "short name works" );
