# Volatile SRAM programming. The known-good power-on Flash image is preserved.
set resource_opt_root [file normalize [file join [file dirname [info script]] ..]]
set resource_opt_bit [file join $resource_opt_root prj resource_opt_20261005 release VinylFPGA_resource_opt.bit]
if {![file exists $resource_opt_bit]} {error "Release bitstream missing"}
connect_cable -open -auto_start
set resource_opt_device [read_device_id -level 1]
puts "RESOURCE_OPT_DEVICE $resource_opt_device"
if {![string match *EG4S20BG256* $resource_opt_device]} {
    error "Unexpected or absent JTAG target; not programming"
}
if {[catch {download -mode jtag -bit $resource_opt_bit} resource_opt_error]} {
    puts "RESOURCE_OPT_DOWNLOAD_FAIL $resource_opt_error"
    exit 2
}
puts "RESOURCE_OPT_DOWNLOAD_COMPLETE"
exit
