package Yahoo::SysBuilder::Utils;

use strict;
use warnings 'all';
use Exporter;
use Fcntl;
use Term::ReadKey;
use Carp;

our @ISA       = qw/Exporter/;
our @EXPORT_OK = qw/optional_shell run_steps time_repr printbold
    run_local set_status fatal_error
    read_file write_file notify_boothost url_encode
    untar_cmd get_base backtick is_xen_paravirt wait_for_dev/;
our %EXPORT_TAGS = ( all => [@EXPORT_OK] );

our $VERBOSE = 1;

{
    my $_base;

    sub get_base {
        return $_base if $_base;
        my $cmdline = read_file("/proc/cmdline");

        if ( $cmdline =~ /\bbase=(\S+)/ ) {
            $_base = $1;
        }
        else {

            # we can't just use Network::boothost_ip since they use us
            # let's look at the dhclient.yaml instead
            my $boothost_ip;

            if ( -e "/sysbuilder/etc/dhclient.yaml" ) {
                require YAML;
                my $dhclient
                    = YAML::LoadFile("/sysbuilder/etc/dhclient.yaml");
                for my $eth ( sort keys %$dhclient ) {
                    $boothost_ip = $dhclient->{$eth}{dhcp_server_identifier};
                }
                if ($boothost_ip) {
                    $_base = 'http://' . $boothost_ip . ':4080/';
                }
                else {
                    return;
                }
            }
        }

        return $_base;
    }
}

sub is_xen_paravirt {
    return -d "/proc/xen" && !-e "/proc/xen/balloon";
}

sub write_file {
    my ( $file, $contents ) = @_;
    open my $fh, ">", "$file.new" or fatal_error("write_file: $file.new: $!");
    print $fh $contents or fatal_error("can't write to $file: $!");
    close $fh;
    unlink $file;
    rename "$file.new" => $file
        or fatal_error("rename: $file.new -> $file: $!");
}

sub untar_cmd {
    my %args = (
        'use_pv' => 0,
        @_
    );
    my $url = $args{url};
    unless ($url) {
        carp("untar_cmd requires a url argument");
        fatal_error("internal error: untar_cmd called with wrong args");
    }

    my ( $uncompress, $untar ) = ( "", "" );

    my @cmd;
    if ( $args{use_pv} ) {
        push @cmd, "pv -N Network";
    }

    if ( $url =~ /(?:\.(tar|cpio|img))?(?:\.(gz|bz2))?\z/msx ) {
        my ( $fmt, $compress ) = ( $1, $2 );
        $compress ||= "";
        $fmt      ||= "";

        if ( $compress eq "bz2" ) {
            push @cmd, "bzip2 -dc";
        }
        elsif ( $compress eq "gz" ) {
            push @cmd, "gzip -dc";
        }

        if ( $fmt eq "cpio" ) {
            push @cmd,
                "cpio -i --sparse --make-directories --preserve-modification-time";
        }
        elsif ( $fmt eq "tar" ) {
            push @cmd, "tar xpSf -";
        }
    }

    return join " | ", @cmd;
}

sub read_file {
    my $file = shift;
    sysopen my $fh, $file, O_RDONLY or croak "$file: $!";
    my $size = -s $fh || 1048576;    # for /proc files
    my ($retval,$retval_total, $res);
    do {
        $retval = sysread $fh, ( my $buff ), $size;
        $res .= $buff;
        $retval_total += $retval;
       	croak "$file: Tried to read more than $size bytes" if ($retval_total > $size);
       	croak "$file: $!" if (!defined $retval );
    }while($retval);
    close $fh;

    return $res unless wantarray;
    return split( "\n", $res );
}

sub optional_shell {
    my $time = shift || 5;
    print "Press 'X' if you want a shell...";

    ReadMode 3;                   # cbreak
    while (1) {
        my $key = ReadKey($time);
        unless ( defined $key ) {

            # restore terminal settings and return if timer expired
            ReadMode 1;
            print "\n";
            return;
        }
        last if $key eq "X";
    }

    ReadMode 1;
    print "\n";
    system("/bin/sh");
}

sub run_steps {
    my $obj   = shift;
    my $delay = shift || 2;
    my $steps = $obj->{steps};

    $ENV{TZ} = "UTC";
    for my $step (@$steps) {
        my $time = time_repr();
        next if $step =~ /^!/;
        set_status("jumping -- $step");
        printbold("$time# $step\n");
        if ( $obj->can($step) ) {
            $obj->$step;
        }
        else {
            my $obj_name = ref($obj);
            warn "WARNING: Could not find step: $step in $obj_name ($0)\n";
        }
        optional_shell($delay);
    }
}

sub time_repr {
    my @time = localtime();
    sprintf( '%d/%d %02d:%02d:%02d', $time[4] + 1, @time[ 3, 2, 1, 0 ] );
}

sub backtick {
    my $str = shift;
    my $res = qx/$str/;
    unless ( defined $res ) {
        carp("$str: failed to return a value");
    }
    return wantarray ? split '\n', $res : $res;
}

sub run_local {
    my (@list) = @_;

    # remove dirname and maybe numbers from the name
    my $cur_program = $0;
    $cur_program =~ s{\A .* / (?:\d+ _)?}{}msx;
    open my $fh, ">>", "/tmp/install-commands.log"
        or die "/tmp/install-commands.log: $!";

    print "% @list\n" if $VERBOSE;
    system @list;
    my $exit_value  = $? >> 8;
    my $signal_num  = $? & 127;
    my $dumped_core = $? & 128;

    my $error_msg = "";
    $error_msg = "(Exit=$exit_value) " if $exit_value;
    $error_msg .= "(Signal $signal_num) " if $signal_num;
    $error_msg .= "(Dumped core)"         if $dumped_core;
    print $fh "$cur_program: @list $error_msg\n";

    print "@list $error_msg\n" if $error_msg;
    return $?;
}

sub wait_for_dev {
    my ($device) = @_;

    # $device will be in /dev
    $device = "/dev/$device" if $device !~ m!^/dev/!;

    # wait for $device to be created by udev
    my $tries = 0;
    while( $tries < 3000 && !-e $device ) {
        select( undef, undef, undef, 0.1 );
        $tries++;
    }

    if( !-e $device ) {
        print "E $device not created!\n";
        return 0;
    } else {
        return 1;
    }
}

sub url_encode {
    local $_ = shift;
    s/([^\w])/sprintf('%%%02x', ord($1))/ge;
    $_;
}

sub notify_boothost {
    my %params = @_;
    $params{nextboot}  ||= "done";
    $params{broadcast} ||= "no";
    $params{status}    ||= "OK";
    chomp( my $hostname = `hostname` );

    $params{status} = url_encode( $params{status} );
    my $base = get_base();
    my $cmd  = qq(wget -q -O - "$base/intercom.pl?host=$hostname)
        . sprintf( '&status=%s&broadcast=%s&nextboot=%s',
        $params{status}, $params{broadcast}, $params{nextboot} );

    $cmd .= sprintf( '&console=%s', url_encode( $params{console} ) )
        if $params{console};
    $cmd .= sprintf( '&root_device=%s', url_encode( $params{root_device} ) )
        if $params{root_device};
    $cmd .= sprintf( '&rsa_key=%s', url_encode( $params{rsa_key} ) )
        if $params{rsa_key};
    $cmd .= sprintf( '&dsa_key=%s', url_encode( $params{dsa_key} ) )
        if $params{dsa_key};
    $cmd .= sprintf( '&build_id=%s', url_encode( $params{build_id} ) )
        if $params{build_id};

    $cmd .= '"';

    print STDERR "% $cmd\n";
    system($cmd);
    sleep 1;
}

sub fatal_error {
    my $base = get_base();
    set_status("ERROR: @_\n");
    printbold("ERROR: ");
    print @_, "\n";
    notify_boothost( nextboot => "build", status => "@_" );
    optional_shell(7200);
    croak(@_);
}

sub printbold {
    print "[1m";
    print @_;
    print "[0m";
}

sub set_status {
    open my $status_fh, ">", "/tmp/status" or return;
    print $status_fh "@_\n";
    close $status_fh;
}

1;
