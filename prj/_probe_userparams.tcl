import_device eagle_s20.db -package EG4S20BG256
open_project {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/VinylFPGA.al} -noanalyze
foreach cmd {set_user_params get_user_params} {
    puts "==ARGS $cmd=="
    catch {info args $cmd} r
    puts $r
    puts "==BODY $cmd=="
    catch {info body $cmd} r
    puts $r
}
puts "==TRY noargs=="
catch {set_user_params} r
puts $r
puts "==TRY guess=="
catch {set_user_params gate map_mode area_prior -run syn_1} r
puts $r
exit
