import_device eagle_s20.db -package EG4S20BG256
open_project {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/VinylFPGA.al}
puts "==BEFORE-LAUNCH-SYN-PARAMS=="
non_default_params -allParams -run syn_1
puts "==BEFORE-LAUNCH-PHY-PARAMS=="
non_default_params -allParams -run phy_1
reset_runs {syn_1 phy_1} -f
launch_runs {syn_1 phy_1} -jobs 2
wait_run syn_1 -quiet
wait_run phy_1 -quiet
puts LAUNCH_VERIFY_DONE
exit
