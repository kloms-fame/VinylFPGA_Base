import_device eagle_s20.db -package EG4S20BG256
import_db {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/O12345_r4_20261007/routed.db}
bitgen -bit {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/O12345_r4_20261007/VinylFPGA_optimized.bit}
setup_debugger
export_bitgen_param -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/O12345_r4_20261007/.bitgen_param.f}
puts VERIFIED_BITGEN_COMPLETE
exit
