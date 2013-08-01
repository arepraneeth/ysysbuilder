#!/usr/local/bin/perl

use strict;
use warnings 'all';
use YAML qw();
use FindBin qw($Bin);

my $USER = $ENV{SUDO_USER} || $ENV{USER} || $ENV{LOGNAME};
die unless $USER;

my $state_file = "$Bin/../tmp/state-$USER.yaml";

my $state = load_state($state_file);

my $cmd = shift;
die "need something to do\n" unless $cmd;

if ($cmd eq "info") {
    print_info(@ARGV);
}
elsif ($cmd =~ m{^/(c\d)/?(u\d)?}) {
    my ($c, $u) = ($1, $2);
    $cmd = shift;
    if ($cmd eq "del" and defined $u) {
        delete_unit($c, $u);
    }
    elsif ($cmd eq "add") {
        my ($type, $disk);
        for (@ARGV) {
            if (/^type=(\w+)$/) {
                $type = $1;
            }
            elsif (/^disk=([\d:]+)$/) {
                $disk = $1;
            }
        }
        add_unit($c, $type, $disk);
    }
}
else {
    die "Unknown command: [$cmd]";
}

save_state($state_file);

sub add_unit {
    my ($c, $type, $disk) = @_;

    my $u     = new_unit_name($c);
    my @ports = split(":", $disk);
    my $p     = $state->{$c}{ports};
    for (@ports) {
        die "ERROR: no such port"
          unless exists $p->{"p$_"};
        die "ERROR: port in unit"
          unless $p->{"p$_"}{unit} eq "-";

        $p->{"p$_"}{unit} = $u;
    }
    $state->{$c}{units}{$u} = {
        type   => $type,
        status => "OK",
    };
}

sub new_unit_name {
    my $c     = shift;
    my $units = $state->{$c}{units};

    # find the first unused one
    my $i = 0;
    while (1) {
        return "u$i" unless exists $units->{"u$i"};
        $i++;
    }
}

sub delete_unit {
    my ($c, $u) = @_;
    die "Controller not found: $c" unless exists $state->{$c};
    die "$c $u not found"          unless exists $state->{$c}{units}{$u};

    delete $state->{$c}->{units}{$u};

    for my $p (keys %{ $state->{$c}{ports} }) {
        next unless $state->{$c}{ports}{$p}{unit} eq $u;
        $state->{$c}{ports}{$p}{unit} = "-";
    }
}

sub print_info {
    my $ctrl  = $_[0] || (keys %$state)[0];
    my $c     = $state->{$ctrl};
    my @units = keys %{ $c->{units} };
    my @ports = keys %{ $c->{ports} };
    my $num_d;
    for my $p (@ports) {
        my $status = $c->{ports}{$p};
        $num_d++ if $status eq "OK";
    }
    my $num_p = scalar @ports;

    unless (@_) {
        print <<EOT;

Ctl   Model        Ports   Drives   Units   NotOpt   RRate   VRate   BBU
------------------------------------------------------------------------
$ctrl    9500S-8      $num_p       $num_d        1       0        4       4       -        

EOT
        return;
    }

    print <<EOT;
Unit  UnitType  Status         \%Cmpl  Stripe  Size(GB)  Cache  AVerify  IgnECC
------------------------------------------------------------------------------
EOT

    for my $u (sort @units) {
        my $type = $c->{units}{$u}{'type'};
        print <<EOT;
$u    $type   OK              -      64K     931.281   OFF    OFF      ON       
EOT
    }

    print <<EOT;

Port   Status           Unit   Size        Blocks        Serial
---------------------------------------------------------------
EOT
    my %p = %{ $c->{ports} };
    for my $p (sort keys %p) {
        my ($u, $status) = ($p{$p}{unit}, $p{$p}{status});
        printf
"$p     %-12s %2s     232.88 GB   488397168     WD-WCAL76504353    \n",
          $status, $u;
    }
}

sub save_state {
    my $file = shift;
    YAML::DumpFile($file, $state);
}

sub load_state {
    my $file = shift;
    eval { $state = YAML::LoadFile($file); };
    $state = default_state() unless $state;
}

sub default_state {
    my $def = {
        'c0' => {
            units => {
                'u0' => {
                    type   => 'RAID-10',
                    status => 'OK'
                }
            },
            ports => {
                'p0' => {
                    status => 'OK',
                    unit   => 'u0',
                },
                'p1' => {
                    status => 'OK',
                    unit   => 'u0',
                },
                'p2' => {
                    status => 'OK',
                    unit   => 'u0',
                },
                'p3' => {
                    status => 'OK',
                    unit   => 'u0',
                },
                'p4' => {
                    status => 'OK',
                    unit   => 'u0',
                },
                'p5' => {
                    status => 'OK',
                    unit   => 'u0',
                },
                'p6' => {
                    status => 'NOT-PRESENT',
                    unit   => '-',
                },
                'p7' => {
                    status => 'NOT-PRESENT',
                    unit   => '-',
                },
            }
        }
    };
    return $def;
}
