######################################################################
# Copyright (c) 2012, Yahoo! Inc. All rights reserved.
#
# This program is free software. You may copy or redistribute it under
# the same terms as Perl itself. Please see the LICENSE.Artistic file 
# included with this project for the terms of the Artistic License
# under which this project is licensed. 
######################################################################

package SysBuilder::CfgManagement;
use strict;
use warnings 'all';
use SysBuilder::Utils qw(run_local fatal_error read_file write_file);
use SysBuilder::Network;
use SysBuilder::Template;

sub new {
    my $class  = shift;
    my $cfg    = shift;
    my %params = ( chroot => 1, resolv_conf => "/mnt/etc/resolv.conf", @_ );
    my $net
        = exists $params{net}
        ? $params{net}
        : SysBuilder::Network->new( cfg => $cfg );
    my $tpl = SysBuilder::Template->new( cfg => $cfg, net => $net );
    my $self = bless {
        cfg         => $cfg,
        tpl         => $tpl,
        resolv_conf => $params{resolv_conf},
        chroot      => $params{chroot},
    }, $class;

    return $self;
}

sub fetch {
    my $self = shift;
    $self->_chroot_cmd('cm_fetch');
}

sub activate {
    my $self = shift;
    $self->_chroot_cmd('cm_activate');
}

sub _chroot_cmd {
    my ( $self, $cmd_key ) = @_;
    my $cmd = $self->{cfg}->{$cmd_key};
    return unless $cmd;
    $cmd = $self->{tpl}->expand($cmd);

    my $err;

    if ( $self->{chroot} ) {
        $err = run_local(qq(chroot /mnt /bin/sh -c '$cmd'));
    }
    else {
        $err = run_local(qq(/bin/sh -c '$cmd'));
    }

    if ($err) {
        fatal_error("$cmd_key command [$cmd] FAILED");
    }
}

1;
