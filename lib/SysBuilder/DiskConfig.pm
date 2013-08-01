######################################################################
# Copyright (c) 2012, Yahoo! Inc. All rights reserved.
#
# This program is free software. You may copy or redistribute it under
# the same terms as Perl itself. Please see the LICENSE.Artistic file 
# included with this project for the terms of the Artistic License
# under which this project is licensed. 
######################################################################

package SysBuilder::DiskConfig;

use strict;
use warnings 'all';
use FindBin(qw($Bin));
use lib qq($Bin/../lib);
use Digest::MD5 qw/md5_hex/;
use SysBuilder::Utils qw(fatal_error run_local backtick write_file read_file wait_for_dev);
use SysBuilder::HWRaid qw();
use SysBuilder::Proc qw();
use POSIX qw();
use YAML qw(Dump);
use Carp;

sub new {
    my $class  = shift;
    my %params = @_;

    my $cfg = $params{cfg};
    bless {
        cfg => $cfg,

        # disk config from config.yaml
        dcfg => $cfg->{disk_config},

        # our interface to /proc
        proc => SysBuilder::Proc->new,

       # table that maps a logical name to a physical device
       # it also can include the disk this refers to, and the partition number
        names => {},

        # generated fstab
        # currently it's an array of 4 fields:
        # device mountpoint fs-type mountoptions
        fstab => [],

        # fs contains some important file systems
        # that are useful to other tools, like grub
        fs => {}
    }, $class;
}

sub setup {
    my $self    = shift;
    my %options = @_;

    unless( $self->{dcfg} ) {
        fatal_error( "No disk_config section. The profile for this host might not be correct." );
    }

    $self->preserve_ssh_keys;

    $self->create_md_devices( 8 );

    $self->setup_hwraid( %options );
    if( $self->_hwconfig_only ) {
        notify_boothost( nextboot => "stage2" );
        system( "reboot -f" );
    }

    if( $self->win ) {
        $self->partition_drives( %options );
        $self->make_fs( %options );
        $self->write_output( %options );
    } else {
        $self->partition_drives( %options );
        $self->setup_swraid( %options );
        $self->setup_lvm( %options );
        $self->make_fs( %options );
        $self->mount_fs( %options );
        $self->generate_fstab( %options );
        $self->write_output( %options );
    }
}

sub _find_root_fs {
    my $self = shift;
    my $proc = $self->{proc};

    mkdir "/ssh";
    my $partitions = $proc->partitions;

    # 1. Find the root file system
    # 1.a attempt to find it using raw partitions
    for my $part ( sort keys %$partitions ) {
        system("mount /dev/$part /ssh 2>/dev/null");

        # if we couldn't mount, go to the next partition
        next if $?;

        # we could mount it, getting closer
        if ( -d "/ssh/etc/ssh" ) {
            return 1;    # found!
        }
        else {
            system("umount /ssh");
        }
    }

    # 1.b attempt to find it using lvm (unless we're using ESX)
    return if $self->esx;

    system("modprobe dm-mod; vgscan --mknodes; vgchange -ay");
    if ( -e "/dev/sys/root" ) {
        system("mount /dev/sys/root /ssh");
        return 1;
    }
    else {
        system("vgchange -an");
    }

    return;
}

sub _old_hostname {
    my $self = shift;
    my $dir  = shift;

    my $old;
    if ( -r "$dir/etc/hostname" ) {
        $old = read_file("$dir/etc/hostname");
        chomp($old);
    }
    elsif ( -r "$dir/etc/sysconfig/network" ) {
        my $net = read_file("$dir/etc/sysconfig/network");
        if ( $net =~ /HOSTNAME=(\S+)/ ) {
            $old = $1;
            $old =~ s/^"(\S+)"$/$1/;
        }
    }

    return $old;
}

sub _ssh_cleanup {
    my $self = shift;
    system("umount /ssh");
    if ( -d "/dev/sys" ) {
        system("vgchange -an");
    }
}

# attempt to preserve ssh keys if the old hostname
# is the same as this hostname
sub preserve_ssh_keys {
    my $self = shift;

    my $found = $self->_find_root_fs;
    return unless $found;

    # 2. Get the old hostname
    my $old_hostname = $self->_old_hostname("/ssh");

    # (exit if we couldn't read the hostname)
    unless ( defined $old_hostname ) {
        $self->_ssh_cleanup;
        return;
    }

    # 3. Exit if old hostname != current hostname
    my $hostname = $self->{cfg}{hostname};
    if ( $hostname ne $old_hostname ) {
        print "DEBUG: not preserving ssh keys since hostnames differ"
            . "($old_hostname != $hostname)\n";
        $self->_ssh_cleanup;
        return;
    }
    
    ## Stubbed out for OSS version 
    # 4. Exit if old keys are blacklisted 
    # my %bad_key = map { $_ => 1 } qw/ ADD KEYS HERE IF YOU WANT TO USE THIS FEATURE /;

    #if( my @bad = grep { $bad_key{$_} } map { md5_hex( scalar read_file( $_ ) ) } glob("/ssh/etc/ssh/ssh_host*") ) {
    #    print "DEBUG: not preserving ssh keys since existing ones are blacklisted"
    #        . "(md5sum = " . join (", ", @bad) . ")\n";
    #    $self->_ssh_cleanup;
    #    return;
    #}
    
    # 5. Copy keys
    mkdir "/sysbuilder/saved-ssh";
    system("cp -p /ssh/etc/ssh/ssh_host* /sysbuilder/saved-ssh/");

    $self->_ssh_cleanup;
}

sub _hwconfig_only {
    my $self = shift;
    my $cfg  = $self->{cfg};

    return $cfg->{hwconfig_only};
}

sub symlinks {
    my $self = shift;

    # stupid shell symlinks
    for my $shell (qw(bash zsh tcsh)) {
        symlink "/bin/$shell" => "/mnt/usr/local/bin/$shell";
    }

    my $sym_cfg = $self->{dcfg}{symlinks};
    return unless $sym_cfg;

    fatal_error("symlinks should be a reference to an array")
        unless ref($sym_cfg) eq "ARRAY";

    for my $pair (@$sym_cfg) {
        next unless my ( $dst, $src ) = @$pair;
        system("mkdir -p /mnt/$dst /mnt/$src");
        rmdir "/mnt/$dst";
        symlink $src => "/mnt/$dst"
            or warn "ERROR: symlink $src -> /mnt/$dst: $!\n";
    }
}

sub config_files {
    my $self = shift;
    my $err  = run_local("cp /tmp/fstab /mnt/etc/fstab");

    if ( -e "/tmp/mdadm.conf" ) {
        $err += run_local("cp /tmp/mdadm.conf /mnt/etc/mdadm.conf");
    }

    return $err;
}

sub write_output {
    my $self = shift;
    my $fs   = $self->{fs};
    YAML::DumpFile( "/sysbuilder/etc/filesystems.yaml", $fs );
}

sub setup_hwraid {
    my $self       = shift;
    my $hwraid_cfg = $self->{dcfg}{hwraid};
    return unless $hwraid_cfg;
    my $hwraid = SysBuilder::HWRaid->new( cfg => $hwraid_cfg );
    $hwraid->setup_raid;
}

sub setup_hwraid_jbod {
    my $self       = shift;
    my $hwraid_cfg = $self->{dcfg}{hwraid};
    return unless $hwraid_cfg;
    my $hwraid = SysBuilder::HWRaid->new( cfg => $hwraid_cfg );
    $hwraid->jbod;
}

sub use_blk_device {
    my ( $partitions, $restriction, $blk ) = @_;
    for my $part ( sort keys %$partitions ) {
        my $p = $partitions->{$part};
        next if $p->{assigned};
        next if $p->{minor} % 16;

        if ( $restriction eq "scsi" ) {
            next unless $p->{major} == 8;
        }

        if ( $restriction eq "ide" ) {
            next unless $p->{major} == 3;
        }

        # add more restrictions here
        #

        # passes our tests
        # assign it to $blk
        $p->{assigned} = $blk;
        return $part;
    }
    return;
}

sub disksize {
    my ( $self, $dev ) = @_;
    my $partitions = $self->partitions;
    my $blk_dev    = $partitions->{$dev};
    my $parted_mlt = $self->parted_multiplier;
    fatal_error("disksize can't determine size for $dev") unless $blk_dev;
    return $blk_dev->{blocks} * $parted_mlt;
}

# partitions->{dev}->{blocks} is # of 1024 byte blocks. parted mkpart
# (for at least parted v1.8.1) takes 1000000 byte units (cf. info
# parted) so we want to return ->{blocks} * 1024 / 1000000 or
# ->{blocks} * 1.024e-3 for newer versions of parted. 
#
# Since RHEL 4.8 uses parted 1.6.19 and RHEL 5.x uses parted 1.8.1 and
# RHEL 6.x uses parted 2.1, return the appropriate multiplier for the
# version of parted we are using. All versions less than 1.8.1 will
# use the old (1/1024 or 0.0009765625) multiplier because
# under-allocating is preferred to overallocating and crashing.
sub parted_multiplier {
    my ( $self ) = @_;
    # also run it with run_local so it gets captured in the logs
    run_local( "parted --version" );
    my $raw = backtick("parted --version");
    if ($raw =~ m/GNU Parted\s+(\d+)\.(\d+)\.(\d+)/i) {
        # old-style version string
        my ($major, $minor, $rev) = ($1, $2, $3);
        if (   $major == 1
            && (   (   $minor == 8
                    && $rev   >= 1 )
                || (   $major >= 8))) {
            return 1.024e-3;
        } else {
            return 0.0009765625;
        }
    } elsif ($raw =~ m/parted \(GNU parted\)\s+(\d+)\.(\d+)(?:$|\s)/i) {
        # RHEL 6 uses 2.1, which has a different style version string
        my ($major, $minor) = ($1, $2);
        if ( $major >= 2 ) {
            return 1.024e-3;
        } else {
            return 0.0009765625;
        }
    } else {
        print STDERR "Couldn't determine GNU Parted version from \"$raw\".\n";
        print STDERR "Assuming old GNU Parted version, your disks might be under-allocated.\n";
        return 0.0009765625;
    }
}

sub parse_size {
    my $self = shift;
    my ( $size, $total ) = @_; # total is in MB with no suffix
    confess("parse_size(size, total) = both size and total are required")
        unless defined $size and defined $total;

    my $size_mb = $size;
    if ( $size eq 'memsize' ) {
        my $memsize = $self->{proc}->memsize;
        $size_mb = int( $memsize / 1024 );
        if ( $size_mb > 12288 ) {
            $size_mb = 12288;
        }
    } elsif ($size =~ m/\A(\d+)\s*%\s*\Z/) {
        # % -> MB
        $size_mb = int( ( $1 / 100 ) * $total );
    } elsif ($size =~ m/(\d+)\s*G\s*\Z/) {
        # GB -> MB
        $size_mb = $1 * 1024;
    } elsif ($size =~ m/(\d+)\s*M\s*\Z/) {
        # MB -> MB
        $size_mb = $1;
    }

    return $size_mb;
}

sub partition {
    my ( $self, %options ) = @_;

    my $dev   = $options{dev};
    my $parts = $options{parts};

    # label the device
    $self->label($dev) unless $options{only_reconfigure};

    my $total_size = $self->disksize( $dev );
    my $free       = $self->parse_size( $options{free}, $total_size );
    my $remaining  = $total_size - $free;

    my @grow;

    # allocate partitions
    for my $part ( sort keys %$parts ) {
        my $minsize = $parts->{$part}->{minsize};
        my $size;
        if ($minsize) {
            push @grow, $part;
            $size = $minsize;
        }
        else {
            $size = $parts->{$part}->{size};
        }

        unless ($size) {
            fatal_error("You need to specify a size for partition $part");
        }

        $size = $self->parse_size( $size, $total_size );

        if ( $size =~ / \D /msx ) {
            fatal_error("Specified size ($size) for $part is not valid");
        }

        if ( $size > $remaining ) {
            fatal_error("Not enough space for $part ($size - $remaining)");
        }

        # allocate
        $parts->{$part}->{allocated} = $size;
        $remaining -= $size;
    }

    # add the remaining space to the grow partitions
    for my $part (@grow) {
        $parts->{$part}->{allocated} += $remaining / ( scalar @grow );
    }
    
    # label
    if( $self->win ) {
        run_local( "parted -s /dev/$dev mklabel msdos" );
    }

    # create the partitions
    my $type    = 'primary';
    my $start   = 0;
    my $part_nr = 0;
    my @parts   = sort keys %$parts;
    for my $part (@parts) {
        $part_nr++;

        my $size = $parts->{$part}->{allocated};
        my $fs_type = $parts->{$part}->{type} || 'ext2';
        unless ( $options{only_reconfigure} ) {
            run_local( "parted -s /dev/$dev mkpart $type $fs_type $start "
                    . ( $start + $size ) );

            wait_for_dev( partition_name( $dev, $part_nr) );
        }
        $start += $size;
        $self->{names}{$part} = {
            phys    => partition_name( $dev, $part_nr ),
            disk    => $dev,
            part_nr => $part_nr
        };
        if ( $fs_type eq 'vmfs3' ) {
            $self->{fs}{'vmfs3'} = {
                "phys"    => $self->{names}{$part}{phys},
                "disk"    => $dev,
                "part_nr" => $part_nr
            };
        }

    }
}

sub partition_name {
    my ( $device, $partition ) = @_;
    if ( $device =~ m{\Acciss/}msx ) {
        return $device . 'p' . $partition;
    }
    else {
        return "$device$partition";
    }
}

sub label {
    my ( $self, $dev ) = @_;
    my $disksize = $self->disksize($dev);

    run_local("parted -s /dev/$dev mklabel gpt");
}

sub partitions {
    my $self = shift;
    unless ( defined $self->{partitions} ) {
        $self->{partitions} = $self->{proc}->partitions;
    }
    return $self->{partitions};
}

sub zero {
    my ( $self, $dev ) = @_;
    run_local(
        "dd if=/dev/zero of=/dev/$dev bs=65536 count=1 >/dev/null 2>/dev/null"
    );
}

sub get_serial_num {
    my $self = shift;
    my $disks = $self->{proc}->disks;
    #if ( ! defined $disks ) {
    #    #check for raid and populate $disks with that
    #    my $hwraid_cfg = $self->{dcfg}{hwraid};
    #    my $hwraid = SysBuilder::HWRaid->new( cfg => $hwraid_cfg );
    #    $disks = $hwraid->list_disks;
    #} else {
     #   return undef
    #}
    my %serials;
    my $index=0;
    
    for my $disk (@$disks) {
        if ( $disk =~ /cciss/ ) {
            my $output = `/usr/sbin/smartctl -a -d cciss,$index /dev/cciss/c0d0`;
            if( $output =~ /Serial number:\s+([a-zA-Z0-9_-]+)/i) {
                $serials{$disk}->{serial} = $1;
            }
        }else {
            my $output = `/usr/sbin/smartctl -i /dev/$disk`;
            if( $output =~ /serial number:\s+([a-zA-Z0-9_-]+)/i) {
                $serials{$disk}->{serial} = $1;
            }else{
                $output = `/sbin/hdparm -i /dev/$disk`;
                if ($output =~ /SerialNum=([a-zA-Z0-9_-]+)/i) {
                    $serials{$disk}->{serial} = $1;
                }else{
                    $serials{$disk}->{serial} = 'Not Found';
                }
            }
        }
        $index++;
    }
    return \%serials;
}
              

sub shred {
    my ($self,$disk) = @_;
        
    return run_local("/usr/bin/shred -v -n 0 -z /dev/$disk");
}

# We need to get the device where the windows
# partition was created, so we're re-evaluating the same
# logic that was used to find it in the first place
sub get_windows_device {
    my $self    = shift;

    my $blk_cfg = $self->{dcfg}{blockdev};
    return unless $blk_cfg;

    my $partitions = $self->partitions;
    return unless $partitions;
    
    for my $blk ( sort keys %$blk_cfg ) {
        my $restriction = $blk_cfg->{$blk}{candidates} || "any";
        my $dev_name = use_blk_device( $partitions, $restriction, $blk );
        unless ($dev_name) {
                fatal_error("Could not find any partitions on $blk");
        }
        return $dev_name;
    }
    return;
}

sub partition_drives {
    my $self    = shift;
    my %options = @_;

    my $blk_cfg = $self->{dcfg}{blockdev};
    return unless $blk_cfg;

    unless ( $options{only_reconfigure} ) {

        # zero all disks
        my $disks = $self->{proc}->disks;
        for my $disk (@$disks) {
            # wait for $disk to appear
            wait_for_dev( $disk );

            $self->zero($disk);
        }
    }

    my $partitions = $self->partitions;
    for my $blk ( sort keys %$blk_cfg ) {
        my $restriction = $blk_cfg->{$blk}{candidates} || "any";
        my $dev_name = use_blk_device( $partitions, $restriction, $blk );
        unless ($dev_name) {
            fatal_error("could not find a partition for $blk");
        }

        # wait for $dev_name to appear
        wait_for_dev( $dev_name );

        $self->{names}{$blk} = { phys => $dev_name, disk => $dev_name };
        $self->zero($dev_name) unless $options{only_reconfigure};
        print STDERR "$dev_name is going to be used for $blk\n";

        # partition it
        $self->partition(
            %options,
            dev   => $dev_name,
            parts => $blk_cfg->{$blk}{partitions},
            free  => $blk_cfg->{$blk}{free} || 0,
        );
    }

    if ( $self->{cfg}{image} =~ /\A esx/msx && !$options{only_reconfigure} ) {
        my $disks = $self->{proc}->disks;
        for my $disk (@$disks) {
            next if $partitions->{$disk}{assigned};
            $self->vmfs($disk);
        }
    }
}

sub vmfs {
    my $self   = shift;
    my ($disk) = @_;
    my $size   = $self->disksize($disk);

    $self->label($disk);
    run_local("parted -s /dev/$disk mkpart primary vmfs3 0 $size");
}

sub setup_swraid {
    my $self    = shift;
    my %options = @_;

    my $sw_cfg = $self->{dcfg}{swraid};
    return unless $sw_cfg;

    my $names = $self->{names};
    my @mdadm_conf;

    # create the sw raid volumes
    for my $sw_raid ( sort keys %$sw_cfg ) {
        my $s           = $sw_cfg->{$sw_raid};
        my $type        = $s->{raidtype};
        my $parts       = $s->{partitions};
        my $chunk       = $s->{chunk} || $s->{chunksize};
        my $spares      = $s->{spares} || 0;
        my $metadata    = $s->{metadata};
        my $layout      = $s->{layout};

        my $opts = "";
        if ($chunk) {
            $opts = " --chunk $chunk";
        }
        if ($spares) {
            $opts .= " --spare-devices=$spares";
        }
        if ($metadata) { 
            $opts .= " --metadata=$metadata";
        }
        if ($layout) { 
            $opts .= " --layout=$layout";
        }
        $type =~ s/\Araid//ims;

        my $num_active = scalar @$parts - $spares;
        my @devices = map { "/dev/" . $names->{$_}{phys} } @$parts;
        for my $part (@$parts) {

            # set partition type to Linux raid
            my ( $disk, $part_nr )
                = ( $names->{$part}{disk}, $names->{$part}{part_nr} );
            run_local("parted -s /dev/$disk set $part_nr raid on");
        }
        
        my $mdadm
                = "mdadm --create  /dev/$sw_raid --run -l $type$opts "
                . "-n $num_active "
                . join( " ", @devices );
        
        my $exit_value = run_local("$mdadm 2>/dev/null");
        if ($exit_value) {
            fatal_error("failed to create /dev/$sw_raid");
        }

        push @mdadm_conf,
              "ARRAY /dev/$sw_raid level=$type num-devices="
            . scalar @devices
            . " devices="
            . join( ",", @devices );
        $self->{names}{$sw_raid} = { phys => $sw_raid };
    }

    if (@mdadm_conf) {
        unshift @mdadm_conf, "DEVICE partitions";
        push @mdadm_conf, "\n";
        write_file( "/tmp/mdadm.conf", join( "\n", @mdadm_conf ) );
    }
}

sub get_vg_free {
    my $vg   = shift;
    my $size = `vgs --noheadings -o vg_free --nosuffix --units M $vg`;
    $size =~ s/\s//g;
    return $size;
}

sub setup_lvm {
    my $self    = shift;
    my %options = @_;

    my $lvm_cfg = $self->{dcfg}{lvm};
    return unless $lvm_cfg;

    run_local("modprobe dm_mod");
    my $names = $self->{names};

    if ( $options{only_reconfigure} ) {
        run_local("vgchange -ay");

        # add to our names table
        for my $vg ( sort keys %$lvm_cfg ) {
            my $LVs = $lvm_cfg->{$vg}{LVs};
            for my $lv ( sort keys %$LVs ) {
                $names->{$lv} = { phys => "$vg/$lv" };
            }
        }
        return;
    }

    # create volume groups
    for my $vg ( sort keys %$lvm_cfg ) {
        my $PVs = $lvm_cfg->{$vg}{PVs};
        my $free = $lvm_cfg->{$vg}{free} || 0;
        fatal_error("Need at least one PV for VG $vg")
            unless $PVs;
        my @PVs;
        for my $pv (@$PVs) {
            my $device = '/dev/' . $names->{$pv}{phys};
            push @PVs, $device;
            my $err = run_local("pvcreate -y -ff $device >/dev/null");
            if ($err) {
                fatal_error("pvcreate $device failed");
            }
        }
        my $err = run_local("vgcreate $vg @PVs >/dev/null");
        if ($err) {
            fatal_error("vgcreate $vg @PVs failed");
        }

        my $total_size = get_vg_free($vg);
        my $free_size  = $self->parse_size( $free, $total_size );
        # Prioritize free space by claiming it first, then releasing
        # it after all other logical volumes are created.
        if( $free_size ) { run_local( "lvcreate -n freefree -L ${free_size}M $vg" ); }
        my $remaining  = $total_size - $free_size;
        my $LVs        = $lvm_cfg->{$vg}{LVs};
        my @grow;
        for my $lv ( sort keys %$LVs ) {
            my $size = $LVs->{$lv}{minsize};
            if ($size) {
                push @grow, $lv;
            }
            else {
                $size = $LVs->{$lv}{size};
            }

            unless ($size) {
                fatal_error("You need to specify a size for LV $lv (VG $vg)");
            }
            $size = $self->parse_size( $size, $total_size );

            if ( $size =~ / \D /msx ) {
                fatal_error(
                    "Specified size ($size) for $lv (VG $vg) is not valid");
            }

            if ( $size > $remaining ) {
                fatal_error("Not enough space for $lv (VG $vg)");
            }

            # allocate
            $LVs->{$lv}{allocated} = $size;
            $remaining -= $size;
        }

        my %grow = map { $_ => 1 } @grow;

        # create the logical volumes
        for my $lv ( sort keys %$LVs ) {

            # add to our 'names' table
            # should we use VG-LV as a name, or just LV?
            $names->{$lv} = { phys => "$vg/$lv" };

            next if $grow{$lv};
            my $size = $LVs->{$lv}{allocated};
            run_local("lvcreate -n $lv -L ${size}M $vg");
        }

        # create the 'grow' partitions
        my $num_grow = scalar @grow;
        while (@grow) {
            my $lv   = shift @grow;
            my $each = int( 100 / $num_grow );
            run_local("lvcreate -n $lv -l ${each}%FREE $vg");
        }
        if( $free_size ) { run_local( "lvremove -f $vg/freefree" ); }
    }
}

sub esx {
    my $self        = shift;
    my $uts_release = ( POSIX::uname() )[2];
    my $is_esx      = ( $uts_release =~ /vmnix/ );
    return $is_esx;
}

sub win {
    my $self = shift;
    return exists $self->{cfg}{mbr};
}

sub make_fs {
    my $self    = shift;
    my %options = @_;

    my $fs_cfg = $self->{dcfg}{filesystems};
    return unless $fs_cfg;

    my $names = $self->{names};
    my @fstab;
    my $is_esx = $self->esx;
    my $is_win = $self->win;
    for my $fs ( sort keys %$fs_cfg ) {
        my $fstype     = $fs_cfg->{$fs}{fstype}     || 'ext3';
        my $mountpoint = $fs_cfg->{$fs}{mountpoint} || '';
        my $label      = $fs_cfg->{$fs}{label}      || '';
        my $mkfsopts   = $fs_cfg->{$fs}{mkfsopts}   || '';
        my $mountopts  = $fs_cfg->{$fs}{mountopts}  || 'defaults';
        my $tunefsopts   = $fs_cfg->{$fs}{tunefs}   || '';

        if ( $fstype =~ /^ext[234]$/ && $mountopts eq 'defaults' ) {
            $mountopts = 'noatime';
        }

        my $phys    = $names->{$fs}{phys};
        my $disk    = $names->{$fs}{disk};
        my $part_nr = $names->{$fs}{part_nr};


        if ($label) {
            $mkfsopts .= " -L $label";
        }

     # TODO: ignore all file systems except swap / root for root only installs
        unless ( $options{only_reconfigure} ) {


            if ( $fstype eq 'ext4' ) {
                run_local("mkfs.ext4 -q $mkfsopts /dev/$phys");
            }
            elsif ( $fstype eq 'ext3' ) {
                run_local("mke2fs -q -j $mkfsopts /dev/$phys");

                unless ($is_esx) {
                    run_local(
                        "tune2fs -O +dir_index /dev/$phys >/dev/null 2>&1");
                }
            }
            elsif ( $fstype eq 'ext2' ) {
                run_local("mke2fs -q $mkfsopts /dev/$phys");
            }
            elsif ( $fstype eq 'xfs' ) {
                run_local("mkfs.xfs -q $mkfsopts -f /dev/$phys");
            }
            elsif ( $fstype eq 'reise' or $fstype eq 'reiserfs' ) {
                run_local("mkreiserfs $mkfsopts -q /dev/$phys");
            }
            elsif ( $fstype eq 'swap' ) {
                run_local("mkswap $mkfsopts /dev/$phys");
                $mountpoint = "none";
            }
            elsif ( $fstype eq 'ntfs' ) {
                run_local("mkntfs -F -Q -q /dev/$phys");
            }

            unless ($mountpoint) {
                warn "$fs - $fstype - no mountpoint defined \n";
                next;
            }
        }
        else {
            if ( $fstype eq 'swap' ) { $mountpoint = 'none' }
        }
        
        if( $tunefsopts ) {
            run_local(
                "tune2fs -o $tunefsopts /dev/$phys >/dev/null 2>&1");
        }
        
        # log interesting mountpoints
        if ( $mountpoint eq "/" or $mountpoint eq "/boot" ) {
            $self->{fs}{$mountpoint} = {
                "phys"    => $phys,
                "disk"    => $disk,
                "part_nr" => $part_nr
            };
        }

        if ($label) {
            $label = "LABEL=$label";
        } elsif ( $fstype eq 'tmpfs' ) {
            $label = $fs;
        } else {
            $label = "/dev/$phys";
        }

        # this is a hack - RHEL 4.x and 5.x sometimes have
        # problems creating the proper
        # initrd for LABEL=/ - since vm uses root-, we can't really know at
        # this point if it's rhel4, so we give up and don't use a label
        my $image_name = $self->{cfg}{vm_image} || $self->{cfg}{image};
        if ( $image_name =~ /\A (?:rhel[-_]?[45] | root)/msx ) {
            if ( $mountpoint eq '/' ) {
                $label = "/dev/$phys";
            }

            # rhel 4.0 is terribly broken wrt to labels, just don't use them
            if ( $image_name =~ /\A rhel [-_]? 4 \.? 0/msx ) {
                $label = "/dev/$phys";
            }
        }

        my @fs_line = ( $label, $mountpoint, $fstype, $mountopts );
        push @fstab, \@fs_line;
    }

    # we're done configuring partitions / file systems
    #
    # try to populate reasonable values for swraid /boot | /
    $self->try_md_configs unless $self->win;

    # we need to mark the root or boot partitions as 'boot'
    my $fs = $self->{fs}{'/boot'} || $self->{fs}{'/'};
    if ($fs) {
        my ( $disk, $part_nr ) = ( $fs->{disk}, $fs->{part_nr} );
        run_local("parted -s /dev/$disk set $part_nr boot on")
            unless $options{only_reconfigure};
    }

    $self->{fstab} = \@fstab;
}

sub mount_fs {
    my $self  = shift;
    my $fstab = $self->{fstab};

    # sorted by mountpoint so / is mounted before /foo
    for my $fs_fields ( sort { $a->[1] cmp $b->[1] } @$fstab ) {
        my ( $dev, $mountpoint, $fstype, $mountopts ) = @$fs_fields;

        $mountopts = "" if $mountopts eq "defaults";
        if ( $fstype ne "swap" ) {
            $mountopts = " -o $mountopts" if $mountopts;
            run_local("mkdir -p /mnt$mountpoint");
            run_local("mount -t $fstype $mountopts $dev /mnt$mountpoint");
        }
        else {
            run_local("swapon $mountopts $dev");
        }
    }

    # for special filesystems
    mkdir "/mnt/dev";
    mkdir "/mnt/proc";
    mkdir "/mnt/sys";
    run_local("mount --bind /dev /mnt/dev") unless $self->esx;
    run_local("mount --bind /proc /mnt/proc");
    run_local("mount --bind /sys /mnt/sys");
}

sub generate_fstab {
    my $self  = shift;
    my $fstab = $self->{fstab};
    mkdir "/mnt/etc";
    open my $fh, ">", "/mnt/etc/fstab"
        or fatal_error("Can't write to /mnt/etc/fstab: $!");
    for my $fs_fields ( sort { $a->[1] cmp $b->[1] } @$fstab ) {
        my ( $dev, $mountpoint, $fstype, $mountopts ) = @$fs_fields;
        my $line = sprintf( "%-20s %-20s %-8s %-10s   0 0\n",
            $dev, $mountpoint, $fstype, $mountopts );

        print $fh $line;
    }
    print $fh <<EOT;
devpts              /dev/pts                devpts  gid=5,mode=620  0 0
tmpfs               /dev/shm                tmpfs   defaults        0 0
proc                /proc                   proc    defaults        0 0
EOT
    my $uts_release = ( POSIX::uname() )[2];
    unless ( $uts_release =~ /\A 2\.4 /msx ) {
        print $fh "sysfs   /sys      sysfs   defaults        0 0\n";
    }

    close $fh;
    system("cp /mnt/etc/fstab /tmp");
}

sub try_md_configs {
    my $self    = shift;
    my $fs      = $self->{fs};
    my $boot_fs = $fs->{'/boot'} || $fs->{'/'};
    return if $boot_fs->{disk};    # not sw raid, or already configured
    
    # probably a swraid setup
    my $phys = $boot_fs->{phys};
    fatal_error("Can't find physical device for boot partition") unless $phys;

    my $dev = first_device_in_md( $phys, "/tmp/mdadm.conf" );
    my ( $disk, $part_nr ) = disk_part_from_dev($dev);

    $boot_fs->{disk}    = $disk;
    $boot_fs->{part_nr} = $part_nr;
}

sub disk_part_from_dev {
    my $dev = shift;
    my ( $disk, $part_nr );
    if ( $dev =~ m{\A([\w/]+?)p?(\d+)\z}msx ) {
        $disk    = $1;
        $part_nr = $2;
    }
    return ( $disk, $part_nr );
}

sub first_device_in_md {
    my ( $md, $file ) = @_;
    my $result;
    open my $fh, "<", $file or fatal_error("Can't open $file");
    while (<$fh>) {
        next
            unless
            m{\A \s* ARRAY \s+ /dev/$md [^\n]+ devices=/dev/([\w/]+) }msx;
        $result = $1;
        last;
    }
    close $fh;
    return $result;
}

sub create_md_devices {
    my $self = shift;
    my $count= shift;

    my $first_dev = 4; # start device creation at /dev/md4

    for ( my $i = $first_dev; $i <= $count+$first_dev; $i++ ) {
        if( ! -e "/dev/md$i" ) {
            system("/bin/mknod /dev/md$i b 9 $i");
        }
    }
}

1;
