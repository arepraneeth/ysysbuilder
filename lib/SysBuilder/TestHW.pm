######################################################################
# Copyright (c) 2012, Yahoo! Inc. All rights reserved.
#
# This program is free software. You may copy or redistribute it under
# the same terms as Perl itself. Please see the LICENSE.Artistic file 
# included with this project for the terms of the Artistic License
# under which this project is licensed. 
######################################################################

package SysBuilder::TestHW;

use strict;
use warnings 'all';
use SysBuilder::Utils qw(run_local fatal_error);

sub new {
    my ( $class, $cfg ) = @_;
    my $self = bless { cfg => $cfg }, $class;
    return $self;
}

sub run_tests {
    my $self = shift;
    $self->test_disks;
    $self->test_ram;
    $self->test_cpus;
}

sub test_disks {
    my $self     = shift;
    my $cfg      = $self->{cfg};
    my $hostname = $cfg->{hostname};

    my $min_speed   = $cfg->{min_disk_speed}    || 25;
    my $max_threads = $cfg->{zapsector_threads} || 8;

    my $cmd = "/usr/local/bin/zapsectoralldev.sh -r -ts $min_speed "
        . "-m $max_threads";
    print "BURNIN: $cmd\n";
    my $err = run_local($cmd);
    my ( $year, $month, $day, $hour, $min ) = (localtime)[ 5, 4, 3, 2, 1 ];
    $year += 1900;
    $month++;
    my $fmt_date
        = sprintf( '%d%02d%02d-%02d:%02d', $year, $month, $day, $hour, $min );

    my $status = $err ? "FAILED" : "PASSED";
    open my $fh, ">/tmp/zapsector.status" or die "zapsector: $!";
    print $fh "$hostname $fmt_date $status\n";

    opendir my $dir, "." or die ".: $!";
    my @devices = map { /^chk\.(\w+)\.log$/; $1 }
        grep {/^chk.*log$/} readdir($dir);
    closedir $dir;
    for my $dev (@devices) {
        open my $ifh, "<chk.$dev.log" or die "chk.$dev.log: $!";
        my @lines = <$ifh>;
        close $ifh;

        chomp(@lines);
        for (@lines) {
            print $fh "$dev: $_\n";
        }
    }
    print $fh "__END__\n";
    close $fh;
    unlink for glob("/tmp/chk*");

    # notify boothost
    if ( $status eq "FAILED" ) {
        fatal_error("disk test failed");
    }
    return 1;
}

sub test_ram {
}

sub test_cpus {
}

1;
