######################################################################
# Copyright (c) 2012, Yahoo! Inc. All rights reserved.
#
# This program is free software. You may copy or redistribute it under
# the same terms as Perl itself. Please see the LICENSE.Artistic file 
# included with this project for the terms of the Artistic License
# under which this project is licensed. 
######################################################################

package SysBuilder::Template;

use strict;
use warnings 'all';
use FindBin(qw($Bin));
use lib qq($Bin/../lib);
use SysBuilder::Utils qw(get_base fatal_error);
use Carp qw(carp);

sub new {
    my $class  = shift;
    my %params = @_;

    my $cfg = $params{cfg};
    my $net = $params{net};

    my $hostname = $cfg->{hostname} || "";
    my $domain   = $cfg->{domain}   || "";
    my $short_hostname = $hostname;
    $short_hostname =~ s/\.$domain\z//;
    my %subs = (
        'BASE'           => get_base(),
        'HOSTNAME'       => $hostname,
        'DOMAIN'         => $domain,
        'SHORT_HOSTNAME' => $short_hostname,
        'IP'             => $net ? $net->ip : "",
        'GATEWAY_IP'     => $net ? $net->gateway_ip : "",
        'BOOTHOST_IP'    => $net ? $net->boothost_ip : "",
        'ROOT'           => '/mnt',
    );
    return bless { subs => \%subs }, $class;
}

sub expand {
    my ( $self, $text ) = @_;
    my $subs = $self->{subs};
    $text =~ s/::(\w+)::/defined $subs->{$1} ? $subs->{$1} : "::$1::"/ge;
    return $text;
}

sub write {
    my ( $self, $file, $text ) = @_;

    unless ( defined $file and defined $text ) {
        carp("Template->write(filename, text)");
        fatal_error(
            "Internal error: template->write called with wrong arguments");
    }

    $text = $self->expand($text);

    open my $fh, ">", "$file.tpl" or fatal_error "$file.tpl: $!";
    print $fh $text;
    close $fh;

    unlink $file;
    rename "$file.tpl" => $file or fatal_error("$file: $!");
}

1;
