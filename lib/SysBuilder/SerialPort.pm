######################################################################
# Copyright (c) 2012, Yahoo! Inc. All rights reserved.
#
# This program is free software. You may copy or redistribute it under
# the same terms as Perl itself. Please see the LICENSE.Artistic file 
# included with this project for the terms of the Artistic License
# under which this project is licensed. 
######################################################################

package SysBuilder::SerialPort;

use strict;
use warnings 'all';
use FindBin(qw($Bin));
use lib qq($Bin/../lib);
use SysBuilder::Proc;

sub new {
    my ( $class, @ports ) = @_;

    unless (@ports) {
        my $proc = SysBuilder::Proc->new;
        @ports = $proc->serialports;
    }

    return bless { serialports => [@ports] }, $class;
}

sub serial_ports {
    my $self = shift;

    return map { /\A(\d+):/msx and $1 }
        grep {/\A\d+: \s uart:(?!unknown)/msx} @{ $self->{serialports} };
}

sub _serial_from_candidate {
    my $serial = shift;

    if ( $serial =~ /\A(\d+):/msx ) {
        return $1;
    }
    else {
        return;
    }
}

sub live_serial {
    my $self       = shift;
    my @ports      = @{ $self->{serialports} };
    my @candidates = grep {/DTR/msx} @ports;
    if ( @candidates == 1 ) {
        return _serial_from_candidate( $candidates[0] );
    }

    @candidates = grep {/DSR/msx} @ports;
    if ( @candidates and @candidates > 1 ) {
        warn "WARN: too many serial ports with DSR set. Not autodetecting.\n";
        return;
    }
    unless (@candidates) {
        @candidates = grep {/RTS\|DTR/msx} @ports;
        if ( @candidates > 1 ) {
            warn
                "WARN: too many serial ports with RTS/DTR set. Not autodetecting.\n";
            return;
        }
    }
    return unless @candidates;
    return _serial_from_candidate( $candidates[0] );
}

1;
