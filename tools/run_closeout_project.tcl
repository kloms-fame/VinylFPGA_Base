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
set required_params {
    {set_param place timing_driven_mode on}
    {set_param place crit_path_opt on}
    {set_param place post_place_opt high}
    {set_param place shifter_opt on}
    {set_param place split_data_from_clock on}
    {set_param place hfn_opt_effort high}
    {set_param route postrt_opt_extra_round 4}
}
foreach param $required_params {
    if {[string first "<param>$param</param>" $project_text] < 0} {
        error "工程文件未持久化候选实现参数: $param"
    }
}
foreach property {logic_level_opt post_route_opt} {
    if {[string first $property $project_text] >= 0} {
        error "GUI 工程配置不应持久化私有参数: $property"
    }
}
proc require_stage {directory stage} {
    if {![file exists [file join $directory .$stage.end.f]] ||
        [file exists [file join $directory .$stage.error.f]]} {
        error "构建阶段未完成: $directory/$stage"
    }
}
set project_open 0
try {
    import_device eagle_s20.db -package EG4S20BG256
    open_project VinylFPGA.al -noanalyze
    set project_open 1
    reset_runs syn_1 -f
    launch_runs syn_1 -step opt_gate -jobs 1
    wait_run syn_1
    foreach stage {read_design opt_rtl opt_gate} {
        require_stage VinylFPGA_Runs/syn_1 $stage
    }
    reset_runs phy_1 -f
    set_user_params -run phy_1 -params [list \
        [list place timing_driven_mode on] \
        [list place crit_path_opt on] \
        [list place post_place_opt high] \
        [list place shifter_opt on] \
        [list place split_data_from_clock on] \
        [list place hfn_opt_effort high] \
        [list route postrt_opt_extra_round 4] \
        [list place logic_level_opt on] \
        [list route post_route_opt high]]
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
    set qor_file [open [file join $result_dir route.qor] r]
    set qor [read $qor_file]
    close $qor_file
    foreach field {{Num of violated S-EP} {Num of violated H-EP}} {
        if {![regexp [format {%s\s*\|\s*(\d+)} $field] $qor ignored value]} {
            error "route QoR 缺少违例计数: $field"
        }
        if {$value != 0} {
            error "route 存在时序端点违例: $field=$value"
        }
    }
    close_project
    set project_open 0
} finally {
    if {$project_open} {
        catch {close_project}
    }
    set project_file [open VinylFPGA.al w]
    puts -nonewline $project_file $project_text
    close $project_file
}
puts CLOSEOUT_BUILD_TIMING_PASSED
exit
