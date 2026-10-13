# Run the original project through TD's run manager, matching GUI Run All.
set vinyl_gui_project_dir [file normalize [file join [file dirname [info script]] .. prj]]
cd $vinyl_gui_project_dir
import_device eagle_s20.db -package EG4S20BG256
open_project VinylFPGA.al -noanalyze
report_seed_param
reset_runs syn_1 -f
launch_runs syn_1 -step opt_gate -jobs 1
wait_run syn_1
launch_runs phy_1 -step bitgen -jobs 1
wait_run phy_1
close_project
puts ORIGINAL_GUI_FLOW_COMPLETE
exit
