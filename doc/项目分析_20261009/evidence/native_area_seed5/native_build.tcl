import_device eagle_s20.db -package EG4S20BG256
open_project {C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2/VinylFPGA.al} -single_run
elaborate -top top
read_adc {C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2/constraints/pin.adc}
read_sdc {C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2/constraints/timing.sdc}
optimize_rtl
report_area -file {C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2/rtl.area}
export_db {C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2/rtl.db}
set_param gate map_mode area_prior
optimize_gate
legalize_phy_inst
read_sdc {C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2/constraints/timing.sdc}
update_timing
report_area -file {C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2/gate.area}
report_timing_summary -file {C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2/gate.timing}
flow_status -file {C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2/gate.status}
export_db {C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2/gate.db}
set_param place seed 5
place
export_db {C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2/place.db}
route
fix_hold
update_timing -mode final
report_area -io_info -file {C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2/final.area}
report_qor -step route -file {C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2/final.qor}
report_timing_summary -file {C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2/final.timing}
report_timing_exception -file {C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2/final.exceptions}
check_timing -verbose -file {C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2/final.constraints}
flow_status -file {C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2/route.status}
export_db {C:/Users/Renni/.codex/visualizations/2026/10/09/01a12039-9e5a-7aa2-9166-f308f4a6547a/baseline/prj/resource_opt_verified_20261005/audit_area_seed5_v2/routed.db}
puts VERIFIED_ROUND_COMPLETE
exit
