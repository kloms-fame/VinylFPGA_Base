import_device eagle_s20.db -package EG4S20BG256
report_param -stage route -detail -all -file x1x2_route_parameters.txt
puts [get_param route fix_hold]
exit
