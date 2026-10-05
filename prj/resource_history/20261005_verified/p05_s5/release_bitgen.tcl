import_device eagle_s20.db -package EG4S20BG256
import_db {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/p05_s5/routed.db}
bitgen -bit {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/p05_s5/VinylFPGA_optimized.bit}
setup_debugger
export_bitgen_param -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/p05_s5/.bitgen_param.f}
puts VERIFIED_BITGEN_COMPLETE
exit
