import_device eagle_s20.db -package EG4S20BG256
import_db {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/VinylFPGA_Runs/phy_1/VinylFPGA_pr.db}
update_timing -mode final
check_timing -verbose -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/stage4_original_al_20261013_r3/final_constraints.txt}
report_area -verbose -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/stage4_original_al_20261013_r3/final_area.txt}
report_timing_summary -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/stage4_original_al_20261013_r3/final_timing.txt}
puts STAGE4_FINAL_CHECK_COMPLETE
exit
