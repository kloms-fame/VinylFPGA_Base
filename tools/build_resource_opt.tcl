# TD 6.2.1 native flow for a reproducible physical seed and saved databases.
# Invoke through build_resource_opt.ps1 with a copied absolute-path .al.
set resource_opt_root [file normalize [file join [file dirname [info script]] ..]]
set resource_opt_dir [pwd]
source [file join $resource_opt_dir build_settings.tcl]
import_device eagle_s20.db -package EG4S20BG256
if {$resource_opt_gate_file ne ""} {
    import_db $resource_opt_gate_file
} else {
    open_project [file join $resource_opt_dir VinylFPGA.al] -single_run
    elaborate -top top
    read_adc [file join $resource_opt_root constraints pin.adc]
    read_sdc [file join $resource_opt_root constraints timing.sdc]
    optimize_rtl
    optimize_gate
    legalize_phy_inst
}
read_sdc [file join $resource_opt_root constraints timing.sdc]
export_db [file join $resource_opt_dir VinylFPGA_gate.db]
set_param place seed $resource_opt_seed
place
export_db [file join $resource_opt_dir VinylFPGA_place.db]
route
update_timing -mode final
report_qor -step route -file [file join $resource_opt_dir final.qor]
report_area -io_info -file [file join $resource_opt_dir final.area]
report_timing_summary -file [file join $resource_opt_dir final.timing]
check_timing -verbose -file [file join $resource_opt_dir constraints_check.rpt]
flow_status -file [file join $resource_opt_dir route_flow.status]
export_db [file join $resource_opt_dir VinylFPGA_pr.db]
set channel [open [file join $resource_opt_dir final.qor] r]
set qor [read $channel]
close $channel
if {![regexp {Setup WNS\s*\|\s*(-?[0-9]+)} $qor unused setup] ||
    ![regexp {Hold WNS\s*\|\s*(-?[0-9]+)} $qor unused hold]} {
    error "Cannot parse timing signoff"
}
if {$setup < 0 || $hold < 0} {
    puts "RESOURCE_OPT_TIMING_FAIL setup=$setup hold=$hold"
    exit 2
}
bitgen -bit [file join $resource_opt_dir VinylFPGA_resource_opt.bit]
setup_debugger
export_bitgen_param -file [file join $resource_opt_dir .bitgen_param.f]
puts "RESOURCE_OPT_BUILD_PASS setup=$setup hold=$hold"
exit
