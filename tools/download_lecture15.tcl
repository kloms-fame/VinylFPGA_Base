# Volatile SRAM programming for the lecture-15 thumbnail interaction build.
# This only loads the FPGA SRAM; the known-good power-on Flash image is untouched.
set lecture15_root [file normalize [file join [file dirname [info script]] ..]]
set lecture15_bit [file join $lecture15_root prj resource_opt_20261005 seed6 VinylFPGA_resource_opt.bit]
if {![file exists $lecture15_bit]} {
    error "Lecture-15 bitstream missing: $lecture15_bit"
}
connect_cable -open -auto_start
set lecture15_device [read_device_id -level 1]
puts "LECTURE15_DEVICE $lecture15_device"
if {![string match *EG4S20BG256* $lecture15_device]} {
    error "Unexpected or absent JTAG target; not programming"
}
if {[catch {download -mode jtag -bit $lecture15_bit} lecture15_error]} {
    puts "LECTURE15_DOWNLOAD_FAIL $lecture15_error"
    exit 2
}
puts "LECTURE15_DOWNLOAD_COMPLETE"
exit
