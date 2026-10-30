# Read the selected routed database and independently recheck final timing.
# This does not place, route, generate a bitstream, or program hardware.
if {[info exists env(VINYL_BUILD_DIR)]} {
    set build_dir [file normalize $env(VINYL_BUILD_DIR)]
} else {
    set build_dir [file normalize [file join [file dirname [info script]] .. prj]]
}
set ch [open [file join $build_dir VinylFPGA.al] r]
set project_text [read $ch]
close $ch
if {![regexp {<Seeds select="(\d+)">} $project_text ignored seed]} {
    error "Missing selected seed in project"
}
set phy_dir [file join $build_dir VinylFPGA_Runs phy_1]
set result_dir [file join $phy_dir seed_$seed]
foreach name {.opt_route.end.f .bitgen.end.f VinylFPGA_pr.db VinylFPGA_phy.ts} {
    if {![file isfile [file join $result_dir $name]]} {error "Missing completed artifact: $name"}
}
if {[llength [glob -nocomplain -directory $result_dir .*.error.f]]} {
    error "Selected run contains error markers"
}
cd $phy_dir
import_device eagle_s20.db -package EG4S20BG256
open_project VinylFPGA.prj -noanalyze
cd $result_dir
import_db VinylFPGA_pr.db
update_timing -mode final
report_timing_status -file VinylFPGA_audit.ts
report_timing_summary -file VinylFPGA_audit.timing
check_timing -verbose
flow_status -file route_flow.status
if {[llength [info commands export_bitgen_param]]} {
    export_bitgen_param -file .bitgen_param.f
} else {
    puts "BITGEN_PARAM_EXPORT_UNAVAILABLE_IN_THIS_TD_VERSION"
}
close_project
set ch [open VinylFPGA_audit.ts r]
set timing [read $ch]
close $ch
foreach field {SWNS HWNS STNS HTNS} {
    if {![regexp [format {%s:\s*(-?\d+(?:\.\d+)?)ns} $field] $timing ignored value] ||
        ([string match *WNS $field] && $value <= 0) ||
        ([string match *TNS $field] && $value != 0)} {
        error "Independent final timing failed: $field"
    }
}
puts "INDEPENDENT_TIMING_PASSED; inspect top_route.check_timing for coverage and warnings"
exit
