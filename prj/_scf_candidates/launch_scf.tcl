import_device eagle_s20.db -package EG4S20BG256
open_project {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/_probe_scf/VinylFPGA.al}
puts "==PARAMS-SYN=="
non_default_params -allParams -run syn_1
reset_runs {syn_1} -f
launch_runs {syn_1} -jobs 2 -step opt_gate
wait_run syn_1 -quiet
report_area -file {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/_probe_scf/scf_gate.area}
puts "==RUNLOG-TAIL=="
catch {exec cmd /c type {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/_probe_scf/VinylFPGA_Runs/syn_1/run.log}} r
puts [string range $r end-800 end]
exit
