import_device eagle_s20.db -package EG4S20BG256
import_db {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/X2_r12_20261007/routed.db}
fix_hold
update_timing -mode final
report_qor -step route -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/X2_r12_20261007/fixhold_test.qor}
report_timing_summary -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/X2_r12_20261007/fixhold_test.timing}
export_db {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/X2_r12_20261007/fixhold_test.db}
puts FIXHOLD_TEST_COMPLETE
exit
