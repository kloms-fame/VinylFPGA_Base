# Configure TD's supported GUI Multi-Seed flow, using one deterministic seed.
# Store the seed in MultiSeed rather than private PlaceProperty: GUI Revert
# would reset a private seed to 0. MultiSeed.tcl also explicitly calls fix_hold.
set vinyl_optimized_project_dir [file normalize [file join [file dirname [info script]] .. prj]]
set vinyl_optimized_project_file [file join $vinyl_optimized_project_dir VinylFPGA.al]
cd $vinyl_optimized_project_dir
set vinyl_project_channel [open $vinyl_optimized_project_file r]
set vinyl_project_text [read $vinyl_project_channel]
close $vinyl_project_channel
set vinyl_seed_match [regexp {<Property Enable="true"[^>]* Init="([0-9]+)"} $vinyl_project_text -> vinyl_project_seed]
if {!$vinyl_seed_match} {
    error "Expected one deterministic MultiSeed configuration in VinylFPGA.al"
}
import_device eagle_s20.db -package EG4S20BG256
puts "CONFIGURE_PROJECT $vinyl_optimized_project_file SEED $vinyl_project_seed"
open_project $vinyl_optimized_project_file -noanalyze
set_param gate map_mode area_prior -run syn_1
set_param gate pack_effort high -run syn_1
set_param place opt_timing high -run phy_1
set_param route effort routability -run phy_1
set_seed_param -num 1 -init $vinyl_project_seed -step 1 -jobs 1 -save 1 -genBit on -endStep bitgen -random off -filter off
non_default_params -run syn_1
non_default_params -run phy_1
report_seed_param
close_project
set vinyl_project_channel [open $vinyl_optimized_project_file r]
set vinyl_saved_project [read $vinyl_project_channel]
close $vinyl_project_channel
set vinyl_saved_match [regexp {<Property Enable="true"[^>]* Init="([0-9]+)"} $vinyl_saved_project -> vinyl_saved_seed]
if {!$vinyl_saved_match || $vinyl_saved_seed != $vinyl_project_seed} {
    error "TD did not preserve the requested MultiSeed configuration"
}
foreach {vinyl_setting vinyl_expected} {
    map_mode area_prior pack_effort high opt_timing high effort routability
} {
    set vinyl_setting_pattern [format {<%s>\s*%s\s*</%s>} $vinyl_setting $vinyl_expected $vinyl_setting]
    if {![regexp $vinyl_setting_pattern $vinyl_saved_project]} {
        error "TD did not persist project strategy $vinyl_setting=$vinyl_expected"
    }
}
puts "CONFIGURED_SEED $vinyl_project_seed"
puts OPTIMIZED_PROJECT_CONFIGURED
exit
