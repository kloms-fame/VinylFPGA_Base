import_device eagle_s20.db -package EG4S20BG256
open_project {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/VinylFPGA.al} -single_run
elaborate -top top
read_adc {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/constraints/pin.adc}
read_sdc {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/constraints/timing.sdc}
optimize_rtl
report_area -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/rtl.area}
export_db {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/rtl.db}
set_param gate map_mode area_prior
optimize_gate
legalize_phy_inst
read_sdc {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/constraints/timing.sdc}
update_timing
report_area -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/gate.area}
report_timing_summary -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/gate.timing}
report_qor -step gate -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/gate.qor}
export_db {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/gate.db}
write_verilog {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/native_gate.v}
set_param place seed 5
place
report_qor -step place -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/place.qor}
export_db {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/place.db}
route
fix_hold
update_timing -mode final
report_area -io_info -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/final.area}
report_area -verbose -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/final_verbose.area}
report_qor -step route -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/final.qor}
report_timing_summary -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/final.timing}
report_timing_exception -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/final.exceptions}
check_timing -verbose -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/final.constraints}
flow_status -file {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/route.status}
export_db {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/routed.db}
write_verilog {C:/Users/Renni/AppData/Local/Temp/vinylfpga_resource_N1_N2_20261011_170501/N2_after/prj/native_final.v}
help report_hfn
help report_analysis
puts NATIVE_ROUND_COMPLETE
exit
