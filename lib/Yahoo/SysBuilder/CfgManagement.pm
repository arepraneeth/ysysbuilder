package Yahoo::SysBuilder::CfgManagement;
use strict;
use warnings 'all';
use Yahoo::SysBuilder::Utils qw(run_local fatal_error read_file write_file);
use Yahoo::SysBuilder::Network;
use Yahoo::SysBuilder::Template;

sub new {
    my $class  = shift;
    my $cfg    = shift;
    my %params = ( chroot => 1, resolv_conf => "/mnt/etc/resolv.conf", @_ );
    my $net
        = exists $params{net}
        ? $params{net}
        : Yahoo::SysBuilder::Network->new( cfg => $cfg );
    my $tpl = Yahoo::SysBuilder::Template->new( cfg => $cfg, net => $net );
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
