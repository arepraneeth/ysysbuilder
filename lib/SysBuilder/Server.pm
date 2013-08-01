######################################################################
# Copyright (c) 2012, Yahoo! Inc. All rights reserved.
#
# This program is free software. You may copy or redistribute it under
# the same terms as Perl itself. Please see the LICENSE.Artistic file 
# included with this project for the terms of the Artistic License
# under which this project is licensed. 
######################################################################

package SysBuilder::Server;

use strict;
use warnings 'all';

use File::Path;
use File::Basename;
use Carp;

sub new {
    my $class = shift;
    my $self  = {
        verbose     => 0,
        steps_dir   => '/libexec/sysbuilder/steps',
        tmp_dir     => '/tmp/sysbuilder',
        support_dir => '/libexec/sysbuilder/support',
        @_
    };

    mkdir $self->{tmp_dir}, oct(775);
    bless $self, $class;

    $self->_set_path;
    return $self;
}

sub _set_path {
    my $self = shift;

    my @path = split ':', $ENV{PATH};
    my %path = map { $_ => 1 } @path;

    for my $dir (qw{/usr/local/bin /sbin /usr/sbin /bin /usr/bin})
    {
        push @path, $dir
            unless $path{$dir};    # add to path unless it's already there
    }

    $ENV{PATH} = join( ":", @path );
}

sub create_ramdisk {
    my ( $self, %opt ) = @_;
    my $tmp             = $self->{tmp_dir};
    my $spt             = $self->{support_dir};
    my @arch            = @{ $opt{arch} };
    my $dest            = $opt{dest};
    my $gz              = $opt{gzip} || 9;
    my $kernel_versions = $opt{kernel};
    my @kernel_versions = @$kernel_versions;
    @kernel_versions = ('2.6.9-42.ELsmp') unless @kernel_versions;

    my $img = "$tmp/j-$$";
    my $mnt = "$tmp/mnt-$$";

    $self->_system("gunzip <$spt/sysbuilder.img >$img")
        or die("$spt/sysbuilder.img: $!");
    $self->_system("rm -rf $mnt");
    mkdir $mnt or die "$mnt: $!";

    $self->_system("mount -o loop $img $mnt") or die("mount $img $mnt: $!");

    unless ( $self->_system("rsync -a $spt/client/ $mnt/sysbuilder/") ) {
        $self->_cleanup_mount($mnt);
        die("rsync $spt/client/ $mnt/sysbuilder/: $!");
    }

    unless ( $self->_copy_modules( out => "$mnt/sysbuilder/lib/" ) ) {
        $self->_cleanup_mount($mnt);
        die("copy_modules failed: $!");
    }

    for my $arch (@arch) {
        for my $version (@kernel_versions) {
            die "No $spt/linux-modules/$version.$arch.tar.gz\n"
                unless -r "$spt/linux-modules/$version.$arch.tar.gz";
            my $ok
                = $self->_system(
                      "tar -xzpf $spt/linux-modules/$version.$arch.tar.gz -C"
                    . " $mnt/lib/modules/" );
            unless ($ok) {
                $self->_cleanup_mount($mnt);
                die("tar failed ($spt/linux-modules/$version.$arch.tar.gz -C $mnt/lib/modules/)"
                );
            }
        }
    }
    $self->_cleanup_mount($mnt);
    $self->_system("gzip -$gz $img")   or die("gzip $img: $!");
    $self->_system("mv $img.gz $dest") or die("mv $img.gz $dest: $!");
}

sub _cleanup_mount {
    my ( $self, $mnt ) = @_;
    $self->_system("umount $mnt");    # ignore errors here, nothing we can do
    $self->_system("rm -rf $mnt");
}

# Uncomment to use. Fix up how to populate @files
#sub _copy_modules {
#    my $self = shift;
#    my %opt  = @_;
#    my $out  = $opt{'out'};
#    my $link = $opt{'link'};
#    my %done_path;
#
#    my $pkg_name = 'sysbuilder';
#
#    # Need to be fixed up
#    my @files
#        = `rpm -qa | awk '/site_perl/ { print \$1 }'`;
#    return if $?;
#    return unless @files;
#
#    for my $file (@files) {
#        chomp($file);
#        my $source = $file;
#        $file =~ s{.*/Foo}{F#oo};
#        my $dir = dirname($file);
#        mkpath("$out/$dir")
#            unless $done_path{"$out/$dir"}++;
#        if ($link) {
#            link $source => "$out/$file" or die "$out/$file: $!";
#        }
#        else {
#            $self->_system("cp $source $out/$file");
#        }
#    }
#    return 1;
#}

sub get_steps {
    my ( $self, $steps ) = @_;
    my $dir = $self->{steps_dir};

    my %step;
    my @all_steps;
    for my $step (@$steps) {
        croak "$step step not found.\n"
            unless -d "$dir/$step";

        push @all_steps, glob("$dir/$step/*");

    }

    for (@all_steps) {
        if (/(\d+)_/) {
            $step{$1} = $_;
        }
    }

    return @step{ sort keys %step };
}

sub verify_steps {
    my ( $self, $steps ) = @_;
    my $dir = $self->{steps_dir};
    my $err = 0;
    for my $step_dir (@$steps) {
        unless ( -d "$dir/$step_dir" ) {
            warn "$dir/$step_dir is not a directory\n";
            $err++;
        }
    }
    die if $err;
}

sub create_installer {
    my ( $self, %opt ) = @_;

    my $name    = $opt{name};
    my $steps   = $opt{steps} || ['std-rhel'];
    my $outdir  = $opt{out} || '/tftpboot';
    my $tmp_dir = $self->{tmp_dir} . "/$$";

    # verify steps
    $self->verify_steps;

    $self->_system("rm -rf $tmp_dir");
    mkdir $tmp_dir or die "$tmp_dir: $!";
    chdir("$tmp_dir");

    # copy the current perl modules to the lib directory
    $self->_copy_modules( out => "lib" ) or die "Can't copy modules: $!";

    # create doinstall for $name
    open my $fh, ">", "doinstall" or die "doinstall: $!";
    my $installer_hdr = << 'EOT';
#!/usr/bin/perl
use strict;
use warnings 'all';
use lib '/sysbuilder/installer/lib';
use SysBuilder::Utils qw(optional_shell time_repr set_status printbold);

$|++;
rename "/sysbuilder/lib" => "/sysbuilder/orig-lib";
symlink "/sysbuilder/installer/lib" => "/sysbuilder/lib";
my $time;
EOT
    print $fh $installer_hdr;
    my @steps = $self->get_steps($steps);
    for (@steps) {
        chomp;
        my $basename = basename($_);
        $self->_system("cp $_ $basename") or die "$_ => $basename: $!";
        my $step = <<"EOT";
\$time = time_repr();
printbold("\$time# $basename\\n");
set_status("installer: $basename");
system(q(./$basename));
if (\$?) {
    print STDERR "./$basename FAILED\n";
    optional_shell(300);
    system("reboot -f");
}
optional_shell(2);

EOT
        print $fh $step;
    }
    print $fh "unlink('/sysbuilder/lib');\n";
    print $fh "rename '/sysbuilder/orig-lib' => '/sysbuilder/lib';\n";
    close $fh;
    chmod oct(755), "doinstall";
    $self->_system("tar zcf ../$name.tar.gz *")
        or die "tar: creating ../$name.tar.gz: $!";
    $self->_system("rsync ../$name.tar.gz $outdir/$name.tar.gz")
        or die "rsync ../$name.tar.gz $outdir/$name.tar.gz: $!";
    chdir("..");
    $self->_system("rm -rf $tmp_dir");    # ignore error
}

# returns TRUE if ok, FALSE is there was an error
sub _system {
    my $self = shift;

    if ( $self->{verbose} ) {
        print STDERR "sysbuilder: @_ ";
    }

    my $err = system(@_);

    if ( $self->{verbose} ) {
        if ($err) {
            print STDERR "[Error $err]\n";
        }
        else {
            print STDERR "\n";
        }
    }
    elsif ($err) {
        warn "sysbuilder: @_ [Error $err]\n";
    }

    return $err == 0;
}

1;

