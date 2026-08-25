tech load /foss/pdks/sky130A/libs.tech/magic/sky130A.tech
load ptat_cell
box 0 0 3200 2800
gds write /foss/designs/temp-sensor-chip/layout/ptat_cell.gds
puts "GDS_WRITTEN"
quit
