if {[info exists env(TD_ROOT)]} {set td $env(TD_ROOT)} else {set td D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116}
if {![file exists work]} {vlib work}
vmap work work
onerror {quit -code 1 -f}
vlog -sv $td/sim_release/eg4/eg_phy_bram32k.v $td/sim_release/eg4/eg_phy_glbl.v
vlog -sv ../../src/display/ascii_font_rom.v ascii_font_ref.v tb_ascii_font_equiv.v
vsim -voptargs=+acc -wlf font32.wlf work.tb_ascii_font_equiv work.glbl
do wave.do
log -r /tb_ascii_font_equiv/*
run -all
quit -code 0 -f
