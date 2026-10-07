connect_cable -open -allink
set verified_device [read_device_id -level 1]
puts "VERIFIED_DEVICE $verified_device"
if {![string match *EG4S20BG256* $verified_device]} {error "Unexpected JTAG target"}
if {[catch {download -mode jtag -bit {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/O8_r2_20261007/VinylFPGA_optimized.bit}} verified_error]} {puts "VERIFIED_DOWNLOAD_FAILED $verified_error"; exit 2}
puts VERIFIED_SRAM_DOWNLOAD_COMPLETE
exit
