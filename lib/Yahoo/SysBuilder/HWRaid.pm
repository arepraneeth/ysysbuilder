package Yahoo::SysBuilder::HWRaid;

use strict;
use warnings 'all';
use Yahoo::SysBuilder::Utils qw(fatal_error);
use YAML qw();

my %module_type = (
    '3w-xxxx'      => '3ware',
    '3w-9xxx'      => '3ware',
    'mptsas'       => 'LSI',
    'mptscsih'     => 'LSI',
    'megaraid_sas' => 'Megacli',
    'cciss'        => 'Cciss',
);

sub new {
    my ( $class, %params ) = @_;
    my $mod_fname = $params{module_fname} || "/sysbuilder/etc/modules.yaml";
    my $storage_mods = YAML::LoadFile($mod_fname)->{scsi};

    return bless { mods => $storage_mods, cfg => $params{cfg} }, $class;
}

sub jbod {
    my $self = shift;
    $self->load_hw_raid_module;

    # delegate to the actual module
    $self->{hwraid}->jbod;
}
sub list_disks {
    my $self = shift;
    $self->load_hw_raid_module;
    return $self->{hwraid}->list_disks;
}

sub load_hw_raid_module {
    my $self = shift;
    return if $self->{hwraid};

    my $raidtype = $self->raidtype;
    return unless $raidtype;

    # load module type, propagate exceptions to the caller
    my $hw_raid_file = "/sysbuilder/lib/Yahoo/SysBuilder/HWRaid/$raidtype.pm";

    eval { require $hw_raid_file; };
    if ($@) {
        fatal_error("Unable to load HWRaid/$raidtype.pm");
    }

    my $hw_raid = "Yahoo::SysBuilder::HWRaid::$raidtype"
        ->new( modules => $self->{mods} );
    $self->{hwraid} = $hw_raid;
}

sub setup_raid {
    my $self = shift;
    my $cfg  = $self->{cfg};
    $self->load_hw_raid_module;
    my $hw_raid = $self->{hwraid};
    unless ($hw_raid) {
        print STDERR "WARNING: Unable to identify HW Raid module";
        return;
    }
    $hw_raid->setup($cfg);
}

sub raidtype {
    my $self = shift;

    # assume they have a single type for now
    my $mods = $self->{mods};
    for my $mod (@$mods) {
        return $module_type{$mod} if exists $module_type{$mod};
    }
    return;    # undef means doesn't exist or we don't know it
}

1;
