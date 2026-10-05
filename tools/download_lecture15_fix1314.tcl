# Volatile SRAM programming for the lecture-13/14/15 acceptance build.
# Includes the thumbnail read-request refresh-window fix and the 32-bit
# parameter-menu debounce counters. This does not program Flash.
set fix_root [file normalize [file join [file dirname [info script]] ..]]
set fix_bit [file join $fix_root prj lecture15_td_Runs VinylFPGA_lecture15_fix13_14.bit]
if {![file exists $fix_bit]} {
    error "Fix13/14 bitstream missing: $fix_bit"
}
connect_cable -open -auto_start
set fix_device [read_device_id -level 1]
puts "FIX1314_DEVICE $fix_device"
if {![string match *EG4S20BG256* $fix_device]} {
    error "Unexpected or absent JTAG target; not programming"
}
if {[catch {download -mode jtag -bit $fix_bit} fix_error]} {
    puts "FIX1314_DOWNLOAD_FAIL $fix_error"
    exit 2
}
puts "FIX1314_DOWNLOAD_COMPLETE"
exit
