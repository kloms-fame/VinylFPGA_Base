cd {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj}
import_device eagle_s20.db -package EG4S20BG256
open_project {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/VinylFPGA.al}
non_default_params -allParams -run syn_1
non_default_params -allParams -run phy_1
reset_runs {syn_1 phy_1} -f
launch_runs syn_1 -step opt_gate
wait_run syn_1 -quiet
if {[file exists {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/VinylFPGA_Runs/syn_1/.opt_gate.error.f}]} {error SYNTHESIS_FAILED}
launch_runs phy_1 -step bitgen
wait_run phy_1 -quiet
puts X1X2_REBUILD_FINISHED
exit
