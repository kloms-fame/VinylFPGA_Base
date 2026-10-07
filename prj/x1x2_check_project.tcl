import_device eagle_s20.db -package EG4S20BG256
open_project {D:/Data_Backup/VinylFPGA_Workspace_Base/VinylFPGA/prj/VinylFPGA.al} -noanalyze
non_default_params -allParams -run syn_1
non_default_params -allParams -run phy_1
puts X1X2_PROJECT_PARAMETERS_CHECKED
exit
