# 固定已验证的物理实现参数；建议在独立源码快照中执行。
# VINYL_BUILD_DIR 指向含 VinylFPGA.al 的目录，默认使用主工程 prj。
if {[info exists env(VINYL_BUILD_DIR)]} {
    set build_dir [file normalize $env(VINYL_BUILD_DIR)]
} else {
    set build_dir [file normalize [file join [file dirname [info script]] .. prj]]
}
cd $build_dir
set project_file [open VinylFPGA.al r]
set project_text [read $project_file]
close $project_file
if {![regexp {Num="1" Init="7"} $project_text] ||
    ![regexp {<Seeds select="7">7 </Seeds>} $project_text]} {
    error "收尾构建要求单一 seed 7，请检查工程副本配置"
}
proc require_stage {directory stage} {
    if {![file exists [file join $directory .$stage.end.f]] ||
        [file exists [file join $directory .$stage.error.f]]} {
        error "构建阶段未完成: $directory/$stage"
    }
}
import_device eagle_s20.db -package EG4S20BG256
open_project VinylFPGA.al -noanalyze
reset_runs syn_1 -f
launch_runs syn_1 -step opt_gate -jobs 1
wait_run syn_1
foreach stage {read_design opt_rtl opt_gate} {
    require_stage VinylFPGA_Runs/syn_1 $stage
}
set_user_params -run phy_1 -params [list \
    [list place timing_driven_mode on] \
    [list place crit_path_opt on] \
    [list place post_place_opt high] \
    [list place logic_level_opt on] \
    [list place shifter_opt on] \
    [list place split_data_from_clock on] \
    [list place hfn_opt_effort high] \
    [list route post_route_opt high] \
    [list route postrt_opt_extra_round 4]]
reset_runs phy_1 -f
launch_runs phy_1 -step bitgen -jobs 1
wait_run phy_1
set result_dir VinylFPGA_Runs/phy_1/seed_7
foreach stage {opt_place opt_route bitgen} {
    require_stage $result_dir $stage
}
set timing_file [open [file join $result_dir VinylFPGA_phy.ts] r]
set timing [read $timing_file]
close $timing_file
foreach field {SWNS HWNS STNS HTNS} {
    if {![regexp [format {%s:\s*(-?\d+(?:\.\d+)?)ns} $field] $timing ignored value]} {
        error "缺少最终时序指标: $field"
    }
    if {([string match *WNS $field] && $value <= 0) ||
        ([string match *TNS $field] && $value != 0)} {
        error "最终时序未通过: $field=$value"
    }
}
close_project
puts CLOSEOUT_BUILD_TIMING_PASSED
exit
