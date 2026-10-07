import_device eagle_s20.db -package EG4S20BG256
open_project {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/VinylFPGA.al} -noanalyze
set_param gate map_mode area_prior -run syn_1
set_param place seed 5 -run phy_1
non_default_params -allParams -run syn_1
non_default_params -allParams -run phy_1
close_project
puts X1X2_PROJECT_SAVED
exit
