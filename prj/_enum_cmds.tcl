import_device eagle_s20.db -package EG4S20BG256
set f [open {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/_enum_cmds.txt} w]
puts $f "==INFO_COMMANDS=="
foreach c [lsort [info commands]] { puts $f $c }
puts $f "==MATCH_STRATEGY=="
foreach c [lsort [info commands]] { if {[string match -nocase *strat* $c] || [string match -nocase *scf* $c]} { puts $f $c } }
puts $f "==MATCH_PARAM=="
foreach c [lsort [info commands]] { if {[string match -nocase *param* $c]} { puts $f $c } }
puts $f "==MATCH_SAVE_EXPORT=="
foreach c [lsort [info commands]] { if {[string match -nocase *save* $c] || [string match -nocase *export* $c]} { puts $f $c } }
puts $f "==INFO_PROCS=="
foreach c [lsort [info procs]] { puts $f $c }
puts $f "==GLOBALS_MATCH=="
foreach c [lsort [info globals]] { if {[string match -nocase *strat* $c] || [string match -nocase *scf* $c] || [string match -nocase *param* $c]} { puts $f $c } }
close $f
exit
