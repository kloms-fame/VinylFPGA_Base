# S2 开机 Logo 阶段：易失 SRAM 下载（不触碰已固化的上电 Flash 镜像）。
set s2_root [file normalize [file join [file dirname [info script]] ..]]
set s2_bit [file join $s2_root prj resource_opt_verified_20261005 S2_boot_v4 VinylFPGA_optimized.bit]
if {![file exists $s2_bit]} {error "S2 bitstream missing"}
connect_cable -open -auto_start
set s2_device [read_device_id -level 1]
puts "S2_DEVICE $s2_device"
if {![string match *EG4S20BG256* $s2_device]} {
    error "Unexpected or absent JTAG target; not programming"
}
if {[catch {download -mode jtag -bit $s2_bit} s2_error]} {
    puts "S2_DOWNLOAD_FAIL $s2_error"
    exit 2
}
puts "S2_SRAM_DOWNLOAD_COMPLETE"
exit
