# Configure TD's supported GUI Multi-Seed flow, using one deterministic seed.
# Store the seed in MultiSeed rather than private PlaceProperty: GUI Revert
# would reset a private seed to 0. MultiSeed.tcl also explicitly calls fix_hold.
set vinyl_optimized_project_dir [file normalize [file join [file dirname [info script]] .. prj]]
set vinyl_optimized_project_file [file join $vinyl_optimized_project_dir VinylFPGA.al]
cd $vinyl_optimized_project_dir
import_device eagle_s20.db -package EG4S20BG256
puts "CONFIGURE_PROJECT $vinyl_optimized_project_file"
open_project $vinyl_optimized_project_file -noanalyze
set_param gate map_mode area_prior -run syn_1
set_param place seed 0 -run phy_1
set_seed_param -num 1 -init 5 -step 1 -jobs 1 -save 1 -genBit on -endStep bitgen -random off -filter off
non_default_params -run syn_1
non_default_params -run phy_1
report_seed_param
close_project
puts OPTIMIZED_PROJECT_CONFIGURED
exit
