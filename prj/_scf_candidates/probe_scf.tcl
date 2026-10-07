import_device eagle_s20.db -package EG4S20BG256
open_project {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/resource_opt_verified_20261005/_probe_scf/VinylFPGA.al} -noanalyze
puts "==PARAMS-SYN=="
non_default_params -allParams -run syn_1
puts "==PARAMS-PHY=="
non_default_params -allParams -run phy_1
exit
