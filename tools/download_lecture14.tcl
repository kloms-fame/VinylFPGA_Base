# Volatile SRAM programming for the lecture-14 brightness/contrast build.
# This only loads the FPGA SRAM; the known-good power-on Flash image is untouched.
set lecture14_root [file normalize [file join [file dirname [info script]] ..]]
set lecture14_bit [file join $lecture14_root prj lecture14_td_Runs VinylFPGA_lecture14.bit]
if {![file exists $lecture14_bit]} {
    error "Lecture-14 bitstream missing: $lecture14_bit"
}
connect_cable -open -auto_start
set lecture14_device [read_device_id -level 1]
puts "LECTURE14_DEVICE $lecture14_device"
if {![string match *EG4S20BG256* $lecture14_device]} {
    error "Unexpected or absent JTAG target; not programming"
}
if {[catch {download -mode jtag -bit $lecture14_bit} lecture14_error]} {
    puts "LECTURE14_DOWNLOAD_FAIL $lecture14_error"
    exit 2
}
puts "LECTURE14_DOWNLOAD_COMPLETE"
exit
