# Volatile SRAM programming for the lecture-13/14/15 repaired build.
# Source bitstream: prj/resource_opt_20261005/seed3/VinylFPGA_resource_opt.bit
# This does not program Flash, so the existing power-on image is preserved.
set fix_root [file normalize [file join [file dirname [info script]] ..]]
set fix_bit [file join $fix_root prj resource_opt_20261005 seed3 VinylFPGA_resource_opt.bit]
if {![file exists $fix_bit]} {
    error "Fix13/14/15 bitstream missing: $fix_bit"
}
connect_cable -open -auto_start
set fix_device [read_device_id -level 1]
puts "FIX1315_DEVICE $fix_device"
if {![string match *EG4S20BG256* $fix_device]} {
    error "Unexpected or absent JTAG target; not programming"
}
if {[catch {download -mode jtag -bit $fix_bit} fix_error]} {
    puts "FIX1315_DOWNLOAD_FAIL $fix_error"
    exit 2
}
puts "FIX1315_DOWNLOAD_COMPLETE"
exit
