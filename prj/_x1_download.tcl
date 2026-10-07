import_device eagle_s20.db -package EG4S20BG256
import_db {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/X1_r2_20261007/routed.db}
connect_cable -open -auto_start
set verified_device [read_device_id -level 1]
puts "VERIFIED_DEVICE $verified_device"
if {![string match *EG4S20BG256* $verified_device]} {error "Unexpected JTAG target"}
if {[catch {download -mode jtag -bit {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/X1_r2_20261007/VinylFPGA.bit}} verified_error]} {
    puts "X1_DOWNLOAD_FAILED $verified_error"
    exit 2
}
puts X1_SRAM_DOWNLOAD_COMPLETE
exit
