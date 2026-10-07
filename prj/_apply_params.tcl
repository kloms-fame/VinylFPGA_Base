import_device eagle_s20.db -package EG4S20BG256
open_project {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/VinylFPGA.al} -noanalyze
set_user_params -run syn_1 -params {{gate map_mode area_prior}}
set_user_params -run phy_1 -params {{place seed 5}}
puts "==SYN=="
non_default_params -allParams -run syn_1
puts "==PHY=="
non_default_params -allParams -run phy_1
exit
