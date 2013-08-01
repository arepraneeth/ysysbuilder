package Yahoo::SysBuilder::ValidateHW;

use strict;
use warnings 'all';
use Yahoo::SysBuilder::Utils qw(run_local fatal_error printbold);

sub new {
    my ( $class, $cfg ) = @_;
    my $self = bless { cfg => $cfg }, $class;
    return $self;
}

sub run_audit {
    my $self = shift;
    $self->check_mem;
    $self->check_cpus;
    #$self->check_ipmi;
}


sub safe_dmidecode {
    my $self = shift;
    return `dmidecode`;
}

sub check_ipmi {
    my $self = shift;
    my $ipmi = lc($self->{cfg}{ipmi_enabled});

    return 1 if $ipmi eq "*";
    my $dmi = $self->safe_dmidecode;
    return 1 unless $dmi;
    my $setting;
    if ($dmi =~ /Out-of-band Remote Access.*Inbound Connection:\s+(\w+)/msi) {
        $setting = lc($1);
    } else {
        print "WARNING: Unknown IPMI setting\n";
        return 1;
    }
    if ($setting eq "enabled" and $ipmi = "no") {
        fatal_error("IPMI enabled (profile says it shouldn't be.)");
    } elsif ($setting eq "disabled" and $ipmi = "yes") {
        fatal_error("IPMI disabled (profile says we want it enabled)");
    }
    return 1;
}

sub check_cpus {
    my $self = shift;
    
    $self->count_cpus or return 0;
    $self->check_hyperthreading or return 0;
    
    return 1;
}

sub count_cpus {
    my $self = shift;
    my $cfg = $self->{cfg};

    return 1 unless defined $cfg->{cpus};  

    my $should_have = $cfg->{cpus};
    return 1 if $should_have eq "*";

    my $have = $self->get_physical_cpus;
    if ($should_have != $have) {
        if ($should_have > $have) {
            
            fatal_error("ERROR: The current ybiip profile expects $should_have " .
              "CPUs but $have were detected.");
        } else {
            printbold("WARNING: The current ybiip profile expects $should_have " .
              "CPUs but $have were detected.\n");
            return 1; # this is OK
        }
    }
    
    return 1;
}

sub get_physical_cpus {
    my $self = shift;
    
    # caching
    return $self->{_pcpus} if defined $self->{_pcpus};

    local $_ = $self->safe_dmidecode;
    return 1 unless $_;

    # get the Version: string after a DMI type 4

    my @versions =
      map { s/\s+$//; $_ }
      /^Handle \s+ \w+ ,? \s+ # Handle #
        DMI \s type \s 4      # We're only interested in DMI type 4
        .*?                   # and let's skip things we don't care about
        \s+ Status: \sPopulated,\s       # now we're near the good stuff
        ([^\n]+)              # our version
        /gsmx;

    my %cpus;
    my $total_cpus = 0;
    for (@versions) {
        next if /^0+$/;
        next if /^\s*$/;
        $cpus{$_}++;
        $total_cpus++;
    }

    $self->{_pcpus} = $total_cpus;
    return $total_cpus;
}

sub check_hyperthreading {
    my $self = shift;
    my $cfg = $self->{cfg};
   
    return 1 unless defined $cfg->{hyperthreading}; 

    my $ht = lc($cfg->{hyperthreading});
    return 1 if $ht eq "*";

    $ht = ($ht eq "1") || ($ht eq "enabled") || 
        ($ht eq "on") || ($ht eq "yes");
    my $logical_cpus  = $self->get_logical_cpus();
    my $physical_cpus = $self->get_physical_cpus();

    my $error = 0;
    my $expected_logical_cpus = ( 1 + $ht ) * $physical_cpus;
    if ( $logical_cpus < $expected_logical_cpus ) {
        fatal_error("ERROR: please enable hyperthreading");
    } elsif ( $logical_cpus > $expected_logical_cpus ) {
        fatal_error("ERROR: please disable hyperthreading");
    }

    return 1;
}

sub get_mem {
    my $memory = `free|sed -n 2p`;
    if ($memory =~ /Mem:\s+(\d+)/) {
        $memory = $1;
    } else {
        warn "Memory: $memory\n";
        return;
    }
    $memory /= 1000 * 1000.0;
    return sprintf( "%.0fG", $memory );
}

sub check_mem {
    my $self = shift;
    my $cfg = $self->{cfg};
    
    return 1 unless defined $cfg->{memory};  

    my $have = get_mem();
    my $should_have = $cfg->{memory};
    for ($have, $should_have) {
        s/G$//;
    }
   
    if ($have < $should_have) {
        fatal_error("ERROR:  Wrong amount of memory (RAM) for the selected profile. Found $have GB but expected $should_have GB");
    } elsif ( $have gt $should_have ) {
        printbold( "WARNING: Wrong amount of memory (RAM) for the selected profile. Found $have GB but expected $should_have GB\n");
        sleep(1);
    }
    
    return 1;
}

sub get_logical_cpus {
    my $self = shift;
    
    # caching
    return $self->{_lcpus} if defined $self->{_lcpus};

    open my $cpuinfo, "<", "/proc/cpuinfo" or die "/proc/cpuinfo: $!";
    my $result = grep { /processor\s+:\s*\d+\s*$/ } <$cpuinfo>;
    close $cpuinfo;

    $self->{_lcpus} = $result;
    return $result;
}

1;
