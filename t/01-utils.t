#!/usr/local/bin/perl

use strict;
use warnings 'all';

# test SysBuilder::Utils

use FindBin(qw($Bin));
use lib qq($Bin/../lib);

use Test::More tests => 16;

BEGIN { use_ok('SysBuilder::Utils'); }

sub write_file {
    my ( $name, $content ) = @_;
    open my $fh, ">", $name or die "$name: $!";
    print $fh $content;
    close $fh;
}

sub normalize_ws {
    my $str = shift;
    $str =~ s/\A\s+//ms;
    $str =~ s/\s+\z//ms;
    $str =~ s/\s+/ /gms;
    return $str;
}

# test read_file scalar mode
my $test_content = "foo 1\nfoo 2\n";
my @test_content = ( 'foo 1', 'foo 2' );
write_file( "/tmp/utils-$$", $test_content );

*rf = *SysBuilder::Utils::read_file;
my $contents = rf("/tmp/utils-$$");
my @contents = rf("/tmp/utils-$$");
is( $contents, $test_content, "scalar-context read_file" );
is_deeply( \@contents, \@test_content, 'list-context read_file' );

my $test_content2 = "foo 1\nfoo 2";         # note missing newline, shouldn't matter
my @test_content2 = ( 'foo 1', 'foo 2' );
my @contents2     = rf("/tmp/utils-$$");
write_file( "/tmp/utils-$$", $test_content2 );
is_deeply( \@contents2, \@test_content2, 'list-context read_file with missing newlines' );
unlink "/tmp/utils-$$";

# test untar_cmd
*ucmd = *SysBuilder::Utils::untar_cmd;
my $untar_cmd = ucmd( url => "http://example.com/foo.tar" );
is( normalize_ws($untar_cmd), "tar xpSf -", "simple tar file" );

$untar_cmd = ucmd( url => "http://example.com/foo.tar.gz" );
is( normalize_ws($untar_cmd), "gzip -dc | tar xpSf -", "gzipped tar file" );

$untar_cmd = ucmd( url => "http://example.com/foo.tar.bz2" );
is( normalize_ws($untar_cmd), "bzip2 -dc | tar xpSf -", "bzipped tar file" );

$untar_cmd = ucmd( url => "http://example.com/foo.tar", use_pv => 1 );
is( normalize_ws($untar_cmd), "pv -N Network | tar xpSf -", "simple tar + pv" );

$untar_cmd = ucmd( url => "http://example.com/foo.tar.gz", use_pv => 1 );
is( normalize_ws($untar_cmd),
    "pv -N Network | gzip -dc | tar xpSf -",
    "gzipped tar + pv"
);

$untar_cmd = ucmd( url => "http://example.com/foo.tar.bz2", use_pv => 1 );
is( normalize_ws($untar_cmd),
    "pv -N Network | bzip2 -dc | tar xpSf -",
    "bziped tar + pv"
);

$untar_cmd = ucmd( url => "http://example.com/foo.cpio.bz2", use_pv => 1 );
is( normalize_ws($untar_cmd),
    "pv -N Network | bzip2 -dc | "
        . "cpio -i --sparse --make-directories --preserve-modification-time",
    "bziped cpio + pv"
);

$untar_cmd = ucmd( url => "http://example.com/foo.gz", use_pv => 0 );
is( normalize_ws($untar_cmd),
    "gzip -dc",
    "gzipped"
);

$untar_cmd = ucmd( url => "http://example.com/foo.bz2", use_pv => 0 );
is( normalize_ws($untar_cmd),
    "bzip2 -dc",
    "bzipped"
);

# test run_steps
package Foo;

sub new {
    my $class = shift;
    return bless {
        res   => [],
        steps => [ 'foo_1', 'foo_2' ]
    }, $class;
}

sub foo_1 {
    my $self = shift;
    push @{ $self->{res} }, 'foo_1';
}

sub foo_2 {
    my $self = shift;
    push @{ $self->{res} }, 'foo_2';
}

1;

package main;

my $foo = Foo->new;
SysBuilder::Utils::run_steps( $foo, 0.1 );    # very quickly

is_deeply( $foo->{res}, [ 'foo_1', 'foo_2' ], 'run_steps works' );

*UE = *SysBuilder::Utils::url_encode;
is( UE("foo bar"), 'foo%20bar', 'Spaces are encoded' );

my $test_str = "adsfasdf1234awd";
is( UE($test_str), $test_str, "No specials characters are preserved" );
