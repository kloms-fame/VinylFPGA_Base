foreach c {set_user_params set_strategy save_project_as export_flow_script} {
 puts "API $c"
 catch {help $c} r
 puts $r
}
exit
