# =============================================================================
# program_flash_s2_boot.tcl —— 把 S2 开机 Logo 位流写入板载配置 Flash（MSPI）
#
# 用 BitWizard（bw_commands_prompt.exe）执行：
#     bw_commands_prompt.exe tools/program_flash_s2_boot.tcl
#
# 为什么必须做这一步：
#   板载配置 Flash 是 W25Q16（JEDEC EF 40 15）。板子断电重上电时由它自动配置 FPGA。
#   只用 JTAG 下 SRAM（download -mode jtag）时，断电后仍旧运行 Flash 里的老镜像，
#   表现为"上电看不到 S2 Logo"。
#
# 流程（与 TD GUI 的 Tools->Download->External Flash 等价）：
#   1) connect_cable + read_device_id 认到 EG4S20BG256；
#   2) bit_to_vec 把 .bit 载入会话（这一步把"bit string"喂给后续命令）；
#   3) program_spi 擦写配置 Flash；
#   4) verify_spi 复核。
# =============================================================================
set s2_root  [file normalize [file join [file dirname [info script]] ..]]
set s2_bit   [file join $s2_root prj resource_opt_verified_20261005 S2_boot_v4 VinylFPGA_optimized.bit]
set s2_chip  "EG4S20BG256"
set s2_speed 8

if {![file exists $s2_bit]} { error "S2 bitstream missing: $s2_bit" }

connect_cable -open -auto_start
set s2_device [read_device_id -level 1]
puts "S2_FLASH_DEVICE $s2_device"
if {![string match *$s2_chip* $s2_device]} {
    error "Unexpected or absent JTAG target; not programming flash"
}

# 先确认配置 Flash 型号（Winbond=ef，W25Q16=40 15）
catch {get_flash_manufacturer} s2_mfg
puts "S2_FLASH_MFG $s2_mfg"

# 载入位流（program_spi 依赖这一步提供的 bit string）
bit_to_vec -chip $s2_chip -m jtag_burst -freq 3.000000 -bit $s2_bit

if {[catch {program_spi -cable 0 -chip $s2_chip -spd $s2_speed} s2_prog_err]} {
    puts "S2_FLASH_PROGRAM_FAIL $s2_prog_err"
    exit 2
}
puts "S2_FLASH_PROGRAM_COMPLETE"

# 复核（失败只告警，不回滚）
if {[catch {verify_spi -cable 0 -spd $s2_speed} s2_ver_err]} {
    puts "S2_FLASH_VERIFY_FAIL $s2_ver_err"
} else {
    puts "S2_FLASH_VERIFY_COMPLETE"
}
exit
