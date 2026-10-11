import_device eagle_s20.db -package EG4S20BG256
open_project {C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b/before/prj/VinylFPGA.al} -single_run
elaborate -top top
read_adc {C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b/before/constraints/pin.adc}
read_sdc {C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b/before/constraints/timing.sdc}
optimize_rtl
report_area -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b/before/prj/rtl.area}
export_db {C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b/before/prj/rtl.db}
set_param gate map_mode area_prior
optimize_gate
legalize_phy_inst
read_sdc {C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b/before/constraints/timing.sdc}
update_timing
report_area -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b/before/prj/gate.area}
report_timing_summary -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b/before/prj/gate.timing}
flow_status -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b/before/prj/gate.status}
export_db {C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b/before/prj/gate.db}
set_param place seed 5
place
export_db {C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b/before/prj/place.db}
route
fix_hold
update_timing -mode final
report_area -io_info -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b/before/prj/final.area}
report_qor -step route -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b/before/prj/final.qor}
report_timing_summary -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b/before/prj/final.timing}
report_timing_exception -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b/before/prj/final.exceptions}
check_timing -verbose -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b/before/prj/final.constraints}
flow_status -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b/before/prj/route.status}
export_db {C:/Users/Renni/AppData/Local/Temp/vinylfpga_optE_20261011b/before/prj/routed.db}
puts NATIVE_ROUND_COMPLETE
exit
