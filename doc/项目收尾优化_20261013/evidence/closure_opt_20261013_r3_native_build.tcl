import_device eagle_s20.db -package EG4S20BG256
open_project {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/VinylFPGA.al} -single_run
elaborate -top top
read_adc {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/constraints/pin.adc}
read_sdc {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/constraints/timing.sdc}
optimize_rtl
report_area -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/rtl.area}
export_db {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/rtl.db}
set_param gate map_mode area_prior
optimize_gate
legalize_phy_inst
read_sdc {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/constraints/timing.sdc}
update_timing
report_area -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/gate.area}
report_timing_summary -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/gate.timing}
flow_status -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/gate.status}
export_db {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/gate.db}
set_param place seed 5
place
export_db {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/place.db}
route
fix_hold
update_timing -mode final
report_area -io_info -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/final.area}
report_area -verbose -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/final_verbose.area}
report_qor -step route -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/final.qor}
report_timing_summary -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/final.timing}
report_timing_exception -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/final.exceptions}
check_timing -verbose -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/final.constraints}
flow_status -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/route.status}
export_db {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/closure_opt_20261013_r3/routed.db}
puts VERIFIED_ROUND_COMPLETE
exit
