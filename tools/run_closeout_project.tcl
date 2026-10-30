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
if {![regexp {<MultiSeed>(.*?)</MultiSeed>} $project_text ignored multi_text] ||
    ![regexp {<Property\s+([^>]+)>} $multi_text ignored properties] ||
    ![regexp {<Seeds select="(\d+)">([^<]+)</Seeds>} $multi_text ignored selected_seed seed_text]} {
    error "收尾构建要求有效的 MultiSeed 配置"
}
set seed_properties [dict create]
foreach {match key value} [regexp -all -inline {(\w+)="([^"]*)"} $properties] {
    dict set seed_properties $key $value
}
foreach {key value} {Enable true Random false GenBit true EndStep bitgen} {
    if {![dict exists $seed_properties $key] || [dict get $seed_properties $key] ne $value} {
        error "MultiSeed 配置错误: $key"
    }
}
set seed_list [regexp -all -inline {\d+} $seed_text]
foreach key {Num Init Step} {
    if {![dict exists $seed_properties $key] || ![string is integer -strict [dict get $seed_properties $key]]} {
        error "MultiSeed 数值配置错误: $key"
    }
}
if {[dict get $seed_properties Num] != [llength $seed_list] ||
    [llength $seed_list] < 1 || [dict get $seed_properties Step] < 1 ||
    [dict get $seed_properties Init] < 0 || [lsearch -exact $seed_list $selected_seed] < 0} {
    error "MultiSeed 种子数量或选中项不一致"
}
set index 0
foreach seed $seed_list {
    if {$seed != [dict get $seed_properties Init] + $index * [dict get $seed_properties Step]} {
        error "MultiSeed 种子列表与 Init/Step 不一致"
    }
    incr index
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
proc require_artifact {path} {
    if {![file isfile $path] || [file size $path] == 0} {
        error "构建产物缺失或为空: $path"
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
    require_artifact VinylFPGA_Runs/syn_1/VinylFPGA_gate.db
    reset_runs phy_1 -f
    launch_runs phy_1 -step bitgen -jobs 1
    wait_run phy_1
    require_stage VinylFPGA_Runs/phy_1 multiSeed
    set best_dir VinylFPGA_Runs/best_result
    set readme [open [file join $best_dir readMe.txt] r]
    set best_text [read $readme]
    close $readme
    if {![regexp {seed\s+(\d+)\M} $best_text ignored result_seed] ||
        [lsearch -exact $seed_list $result_seed] < 0} {
        error "best_result 未指向本轮配置的种子"
    }
    set result_dir VinylFPGA_Runs/phy_1/seed_$result_seed
    foreach stage {opt_place opt_route bitgen} {
        require_stage $result_dir $stage
    }
    foreach name {VinylFPGA_place.db VinylFPGA_pr.db VinylFPGA.bit VinylFPGA_phy.ts route.qor} {
        require_artifact [file join $result_dir $name]
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
    foreach {field pattern} {
        {Num of violated S-EP} {Num of violated S-EP\s*\|\s*(\d+)}
        {Num of violated H-EP} {Num of violated H-EP\s*\|\s*(\d+)}
    } {
        if {![regexp $pattern $qor ignored value]} {
            error "route QoR 缺少违例计数: $field"
        }
        if {$value != 0} {
            error "route 存在时序端点违例: $field=$value"
        }
    }
    foreach name {VinylFPGA.bit VinylFPGA_phy.ts} {
        set selected [open [file join $result_dir $name] rb]
        set selected_data [read $selected]
        close $selected
        set best [open [file join $best_dir $name] rb]
        set best_data [read $best]
        close $best
        if {$selected_data ne $best_data} {
            error "best_result 与 seed $result_seed 的构建产物不一致: $name"
        }
    }
    close_project
    set project_open 0
    # Preserve the reviewed strategy, with the actual passing GUI selection.
    regsub {<Seeds select="\d+">} $project_text "<Seeds select=\"$result_seed\">" project_text
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
