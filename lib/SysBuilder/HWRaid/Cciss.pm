######################################################################
# Copyright (c) 2012, Yahoo! Inc. All rights reserved.
#
# This program is free software. You may copy or redistribute it under
# the same terms as Perl itself. Please see the LICENSE.Artistic file 
# included with this project for the terms of the Artistic License
# under which this project is licensed. 
######################################################################

package SysBuilder::HWRaid::Cciss;
use strict;
use warnings 'all';
use SysBuilder::Utils qw(run_local fatal_error);
use SysBuilder::Proc;

use Data::Dumper;

sub new {
    my $class     = shift;
    my %params    = @_;
    my $modules   = $params{modules};
    my $binary    = $params{binary} || '/opt/compaq/hpacucli/bld/hpacucli';
    my $slot_arg  = $params{slot_arg} || 'ctrl all show';
    my $verbose   = $params{verbose};
    my $proc      = SysBuilder::Proc->new;

    my $self = bless {
        cli       => $binary,
        get_slot  => $slot_arg,
        modules   => $modules,
        verbose   => 1 || $verbose,
    }, $class;

    return $self;
}

sub jbod {
    my ($self) = @_;
    
    # seems that HP does not have a JBOD that bypasses the controller (or a pass through). 
    # To get a /dev/cciss/ device usable by the OS, each disk needs to be put into a RAID-0
    # 1) detect and destroy any existing RAID
    # 2) for each disk, add it to a new RAID-0
    my ($slots,$disk_array,$physical_disks) = $self->get_controller_config();
    my $cli = $self->{cli};
    foreach my $slot ( @$slots ) {
        foreach my $array (@$disk_array) {
            foreach my $key (reverse sort keys %$array ) {  
                if( $array->{$key} == $slot ) {
                    print "DEBUG: delete $key from slot $slot\n";
                    $self->system("$cli ctrl slot=$slot $key delete forced");
                }
            }
        }
        # Make raid-0 array for each physical disk
        foreach my $disk (@$physical_disks) {
            foreach my $key (keys %$disk) {
                if( $disk->{$key} = $slot ) {
                    $self->make_raid( "0", $slot, $key);
                }
            }
        }
    }
}

sub list_disks {
    my $self = shift;

    my @disks;
    my ($slots,$disk_array,$physical_disks) = $self->get_controller_config();
    my $ctrl_count = 0;
    my $disk_count = 0;
    
    foreach my $slot ( @$slots ) {
        foreach my $array (@$disk_array) {
            foreach my $key ( sort keys %$array ) {
                if($array->{$key} == $slot) {
                    my $disk = "cciss/c" . $ctrl_count . "d" . $disk_count;
                    push @disks, $disk;
                    $disk_count++;
                }
            }
        }
        $ctrl_count++;
    }
    return \@disks;
}


sub make_raid {
    my ( $self, $raid_type, $slot, $disks ) = @_;

    my $cli = $self->{cli};
    #ctrl slot=2 create type=ld drives=1I:1:2 raid=0
    $self->system("$cli ctrl slot=$slot create type=ld drives=$disks raid=$raid_type");
}
    
sub setup {
    my ( $self, $cciss ) = @_;

    fatal_error('usage $Cciss->setup(disk_config)')
        unless $cciss || ref($cciss) ne 'HASH';

    my $cli = $self->{cli};

    # Get controller info
    my (@slots,@disk_array) = $self->get_controller_config();
    
    if( scalar @disk_array == 0 ) {
        die "Nothing to do. No arrays were found to delete but HWCONFIG found that there were... Confused\n";
    }
    
    for my $adapter ( keys %$cciss ) {
        print "Configuring CCISS Adapter $adapter:\n" if $self->{verbose};
        my $config = $cciss->{$adapter}{config};
        if ( lc($config) eq 'jbod' ) {
            $self->jbod($adapter);
        }
    }
}

sub get_controller_config {
    my $self = shift;
    
    my @slots;
    my @disk_arrays;
    my @physical_disks;
    my $cmd_slot = "$self->{cli}"." $self->{get_slot}";
     
	
	#need to redo this
    #First get the slots for the RAID card(s)
    open(OUT, "$cmd_slot |") or die "$! could not run hpacucli";
	while (<OUT>) {
		if (/Slot\s(\d)/) {
		    push @slots, $1;
        }
    }
    close(OUT);
    
    #now get the arrays and physical disks for each slot
    foreach my $slot ( @slots ) {
        my %array;
        my %disk;
        my $cmd_array = "$self->{cli}" . " ctrl slot=$slot array all show";
        open(OUT, "$cmd_array |") or die "$! could not run hpacucli";
        while (<OUT>) {
		    if (/(array\s\w)/) {
		        $array{$1} = $slot;
		    }
		}
		push @disk_arrays, \%array;
	    close(OUT);
	    
	    my $cmd_disk = "$self->{cli} " . " ctrl slot=$slot physicaldrive all show";
	    open(OUT, "$cmd_disk |") or die "$! could not run hpacucli";
	    while (<OUT>) {
	        if ( /(\d\w?:\d:?\d?)/ ) {
	            $disk{$1} = $slot;
	        }
	    }
	    push @physical_disks, \%disk;
	    close(OUT);
	}
	return( \@slots, \@disk_arrays,\@physical_disks );
}

sub system {
    my ( $self, @args ) = @_;
    print "% @args\n" if $self->{verbose};
    run_local(@args);
}

1;
