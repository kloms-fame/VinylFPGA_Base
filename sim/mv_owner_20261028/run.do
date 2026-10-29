onerror {quit -code 1 -f}
set case_dir [pwd]
cd $case_dir
set repo [file normalize ../..]
if {![file exists work]} {vlib work}
vmap work work
set sources [list src/SD/sd_card_top.v src/SD/sd_card_sec_read_write.v \
 src/SD/sd_card_cmd.v src/SD/sd_cmd18_reader.v src/SD/sd_sector_adapter.v \
 src/video/mv_sd_burst.v src/video/mv_stream_player.v \
 sim/mv_owner_20261028/fake_spi_card.v sim/mv_owner_20261028/tb_sd_owner.v \
 sim/mv_owner_20261028/tb_mv_shared_frame.v]
# The production packet RAM is an explicit EG_PHY_BRAM32K. Simulate the real
# primitive (TD release model) so the vendored block, not a behavioural
# stand-in, is what the playback test exercises.
if {[info exists env(TD_ROOT)]} { set td_root $env(TD_ROOT) } else { set td_root D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116 }
vlog -sv $td_root/sim_release/eg4/eg_phy_bram32k.v $td_root/sim_release/eg4/eg_phy_glbl.v
foreach source $sources {vlog -sv +define+FIXE +incdir+$repo/src $repo/$source}
set run_args {}
set wave_name shared_frame.wlf
if {[info exists env(MV_REALTIME)]} {
 set run_args {+REALTIME}
 set wave_name realtime_frame.wlf
}
eval vsim -voptargs=+acc -wlf $wave_name work.tb_mv_shared_frame work.glbl $run_args
do wave.do
log -r /tb_mv_shared_frame/dut/*
log -r /tb_mv_shared_frame/player/*
log -r /tb_mv_shared_frame/bridge/*
run -all
quit -code 0 -f
