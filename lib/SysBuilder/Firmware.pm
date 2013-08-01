######################################################################
# Copyright (c) 2012, Yahoo! Inc. All rights reserved.
#
# This program is free software. You may copy or redistribute it under
# the same terms as Perl itself. Please see the LICENSE.Artistic file 
# included with this project for the terms of the Artistic License
# under which this project is licensed. 
######################################################################

package SysBuilder::Firmware;

use strict;
use warnings 'all';
use SysBuilder::Utils qw(:all);
use YAML qw();
use Tie::File;


sub new {
    my $class = shift;
    my $self  = {
        hw_vendor  	 		=> undef,
        hw_model   	 		=> undef,
        base       	 		=> undef,
        firmwareconfig 		=> undef,
        dell_system_id 		=> undef,
        dell_host_bios_ver	=> undef,
        dell_hdr_file_ver	=> undef,
        new_bios_file		=> undef,
        conrep_xml          => undef,
        @_
    };
 
    bless $self, $class;

    $self->_get_base;
    $self->_set_path;
    $self->_get_hw_type;
    return $self;
}

sub _get_base {
	my $self = shift;
	$self->{base} = get_base();
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


sub _get_hw_type {
    my $self = shift;

   my $dmidecode = '/usr/sbin/dmidecode';
	open(DMI,"$dmidecode |") or die "couldn't run dmidecode";
	while(<DMI>) {
	        next unless /System Information/;
	        while(<DMI>) {
	            last if /^Handle/;
	            if ($_ =~ /Manufacturer:\ (.*)$/ || $_ =~ /Vendor:\ (.*)$/) {
	                $self->{hw_vendor} = $1;
						 $self->{hw_vendor} =~ s/\s+$//;
						 $self->{hw_vendor} =~ tr/' '/_/;
	            }
	            if ($_ =~ /Product\ Name:\ (.*)$/ || $_ =~ /Product:\ (.*)$/) {
	                $self->{hw_model} = $1;
						 $self->{hw_model} =~ s/\s+$//;
						 $self->{hw_model} =~ tr/' '/_/;
	            }
		}
	}
	close(DMI); 
}

sub get_firmwareconfig {
    my $self     = shift;
       
    my $base     = $self->{base};
    my $cmd
        = "wget -q $base/rsync/firmware/firmware.yaml -O - 2>/tmp/firmwareconfig.err";
    my $yaml = qx/$cmd/;
    if ($?) {
        my $extra_err = read_file("/tmp/firmwareconfig.err");
        print "ERROR: Can't get firmwareconfig\n$extra_err";
        optional_shell(30);
        exit;
    }

    my $yaml_config;
    eval { $yaml_config = YAML::Load($yaml); };
    if ($@) {
        print "ERROR: Firmwareconfig corrupted - $@\n";
        optional_shell(30);
        exit;
    }
    $self->{firmwareconfig} = $yaml_config;
    $self->{firmwareconfig}->{base} = $base;
    YAML::DumpFile( "/sysbuilder/etc/firmware.yaml", $self->{firmwareconfig} );
}

sub get_code {
	my $self 	        = shift;
	my %params          = @_;
	my $base		    = $self->{base};
	my $new_bios_file   = $self->{new_bios_file};
    my $yaml		    = $self->{firmwareconfig};
	my $hw_vendor       = $self->{hw_vendor};	
	my $hw_model        = $self->{hw_model};
	my $dell_sys_id     = $self->{dell_system_id};
	my $cmd			    = undef;

   if( $params{action} eq 'get_firmware_update' ) {
       
        system("mkdir /firmware");
        
        if($hw_vendor =~/Dell/) {
            if($yaml->{$hw_vendor}->{$dell_sys_id}->{BIOS_FILE}) {
         	   $self->{new_bios_file} = $yaml->{$hw_vendor}->{$dell_sys_id}->{BIOS_FILE};
         	   $cmd = "wget -q $base/rsync/firmware/$hw_vendor/$dell_sys_id/$self->{new_bios_file} -O /firmware/$self->{new_bios_file}  2>/tmp/firmwarecode.err";
             }else {
         	   $self->{new_bios_file} = "bios.hdr";
         	   $cmd = "wget -q $base/rsync/firmware/$hw_vendor/$dell_sys_id/bios.hdr -O /firmware/bios.hdr  2>/tmp/firmwarecode.err";
             }
        }elsif($yaml->{$hw_vendor}->{$hw_model}->{BIOS_FILE}) {
            $self->{new_bios_file} = $yaml->{$hw_vendor}->{$hw_model}->{BIOS_FILE};
         	$cmd = "wget -q $base/rsync/firmware/$hw_vendor/$hw_model/$self->{new_bios_file} -O /firmware/$self->{new_bios_file}  2>/tmp/firmwarecode.err";
        }else{
           	print "No BIOS update available\n";
             optional_shell(30);
         	exit;
        }
        
        if($cmd) {
         	my $code = qx/$cmd/;
            if ($?) {
         		my $extra_err = read_file("/tmp/firmwarecode.err");
         		print "ERROR: Can't get firmwarecode\n$extra_err";
         		optional_shell(30);
         		exit;
         	}
        }
    }

    if( $params{action} eq 'get_bios_update' ) {
        
        system("mkdir /bios");
        
        if($yaml->{$hw_vendor}->{$hw_model}->{CONREP_XML}) {
            $self->{conrep_xml} = $yaml->{$hw_vendor}->{$hw_model}->{CONREP_XML};
         	$cmd = "wget -q $base/rsync/firmware/$hw_vendor/$hw_model/$self->{conrep_xml} -O /bios/$self->{conrep_xml}  2>/tmp/bios_config.err";
        }else{
           	print "No BIOS config available\n";
         	exit;
        }
        
        if($cmd) {
         	my $code = qx/$cmd/;
            if ($?) {
         		my $extra_err = read_file("/tmp/bmc_config.err");
         		print "ERROR: Can't get bmc config\n$extra_err";
         		optional_shell(30);
         		exit;
         	}
        }
    } 
}

sub get_dell_host_info {
	my $self = shift;
	my $cmd = "/usr/sbin/getSystemId --logconfig=/etc/dell_log.cnf";
	
	#need to redo this
   open(OUT, "$cmd |") or die "could not run getSystemId";
	while (<OUT>) {
		if (/BIOS Version:(.*)/) {
		    $self->{dell_host_bios_ver} = $1;
		    $self->{dell_host_bios_ver} =~ s/^\s+//;
		}elsif (/System ID:(.*)/) {
		    $self->{dell_system_id} = lc($1);
		    $self->{dell_system_id} =~ s/^\s+//;
		 }
	}
	close(OUT);
}

sub do_dell_update {
	my $self 				= shift;
	my $yaml		   		= $self->{firmwareconfig};
	my $hw_vendor  			= $self->{hw_vendor};	
	my $hw_model   			= $self->{hw_model};
	my $dell_id    			= $self->{dell_system_id};
	my $dell_hdr_file_ver 	= $self->{dell_hdr_file_ver};
	my $bios_file 			= $self->{new_bios_file};
	
	my $cmd = "/usr/sbin/dellBiosUpdate-compat --hdr-info /firmware/bios.hdr";

   open(HDR_INFO, "$cmd |") or die "could not run dellBiosUpdate-compat --hdr-info";
	while (<HDR_INFO>) {
		if (/BIOS Version:(.*)/) {
		    $self->{dell_hdr_file} = $1;
		    $self->{dell_hdr_file} =~ s/^\s+//;
		 }
	}
   close(HDR_INFO);

	if($self->{dell_host_bios_ver} eq $self->{dell_hdr_file}) {
		print "$self->{dell_hdr_file} is already installed. No update is needed \n ";
		exit;
	}else {
		print "Running dell update: updating to $yaml->{$hw_vendor}->{$hw_model}->{BIOS_VERSION} ...";
		my $cmd = "/usr/sbin/dellBiosUpdate-compat --hdr=/firmware/$bios_file -u --test";
		my $bios_update = qx/$cmd/;
		print " Done \n";
	}
}

sub do_dell_ipmi {
    my $self = shift;
    #first load the IPMI drivers
    run_local( "modprobe ipmi_msghandler" );
    run_local( "modprobe ipmi_devintf" );
    run_local( "modprobe ipmi_si" );

    #Make bios change
    run_local( "ipmitool lan set 1 ipsrc dhcp" );
    run_local( "ipmitool lan set 1 access on" );
    run_local( "ipmitool sol set volatile-bit-rate 9.6 1" );
    run_local( "ipmitool sol set non-volatile-bit-rate 9.6 1" ); 
    run_local( "syscfg --extserial=rad" );
    
}


sub do_hp_update {
	my $self            = shift;
	my $yaml            = $self->{firmwareconfig};
	my $hw_vendor       = $self->{hw_vendor};
	my $hw_model        = $self->{hw_model};
	my $new_bios_file   = $self->{new_bios_file};
	my $hp_exe          = $yaml->{$hw_vendor}->{$hw_model}->{BIN_FILE};

    print "Running HP update file $new_bios_file\n";

	#make temp dir to unpack update package to
	system("mkdir /firmware/tmp");
	
	#unpack the archive
	system("sh /firmware/$new_bios_file --unpack=/firmware/tmp");
	if ( $? == -1 )
	{
	  print "Bios unpack failed: $!\n";
	  optional_shell(30);
	  exit;
	} 
   
    print "updating system";
	system("cd /firmware/tmp/ && ./$hp_exe -s -f");
	if ( $? == -1 )
	{
	  print "Bios update failed: $!\n";
	  optional_shell(30);
	  exit;
	}	
}

sub do_hp_ipmi {
    my $self        = shift;
    
    my $code;
    my $error_code = {
               0 => "Success",
               1 => "Bad XML File",
               2 => "Bad Data File",
               4 => "Admin Password set",
               5 => "No XML Tag",
     };
                   
    my $conrep_dump_cmd = "/bin/conrep -s -f /bios/bios_config.dat -x /bios/$self->{conrep_xml}";
    my $conrep_load_cmd = "/bin/conrep -l -f /bios/bios_config.dat -x /bios/$self->{conrep_xml}";
    my $lo100cfg_dump_cmd = "/bin/lo100cfg -o /bios/bmc.xml";
    my $lo100cfg_load_cmd = "/bin/lo100cfg -i /bios/bmc.xml";
    
    # Process the BIOS
    print "Getting current BIOS\n";
    $code = qx/$conrep_dump_cmd/;
    if ($?) {
 		print "ERROR: $error_code->{$?}";
 		optional_shell(30);
 		exit;
 	}
    
    print "Updating BIOS config file\n";
    tie my @bios_config, 'Tie::File', "/bios/bios_config.dat" or die "could not open bios config file: $!\n";
    for( @bios_config ) {
        s/<Section name=\"Serial_Port_Assignment\">.*<\/Section>/<Section name=\"Serial_Port_Assignment\">bmc<\/Section>/;
    }
    untie @bios_config;
    
    print "Loading updated BIOS config file\n";
    $code = qx/$conrep_load_cmd/;
    if ($?) {
 		print "ERROR: $error_code->{$?}";
 		optional_shell(30);
 		exit;
 	}
    
    # Process the BMC
    print "Getting current BMC\n";
    $code = qx/$lo100cfg_dump_cmd/;
    if ($?) {
 		print "ERROR: $?";
 		optional_shell(30);
 		exit;
 	}
 	
    print "Updating BMC config file\n";
    tie my @bmc_config, 'Tie::File', "/bios/bmc.xml" or die "could not open bmc config file: $!\n";
    for( @bmc_config ) {
        s/<nic mode=.* type=.*>/<nic mode=\"dhcp\" type=\"dedicated\">/;
    }
    untie @bmc_config;
    
    print "Loading updated BMC config file\n";
    $code = qx/$lo100cfg_load_cmd/;
    if ($?) {
 		print "ERROR: $?";
 		optional_shell(30);
 		exit;
 	}
}

sub get_mfg {
	my $self = shift;
	return $self->{hw_vendor};
}

1;
