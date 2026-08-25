# =====================================================================
# ptat_cell.tcl -- flat analog PTAT cell layout in magic (sky130A)
#
# The two substrate PNPs use the EXACT device geometry from the PDK
# magic cells (rf_pnp W0p68 and W3p40): pwell ring + nbase + pdiff
# emitter + psubdiff substrate contact.  R1 is a meandering p+ poly
# resistor.  Metal1 wiring + labels tie the devices into the PTAT
# core (Q2 emitter = node b, Q1 emitter = node n1, R1 between a and
# n1, VSS on the substrate/well contacts).
#
# Run:
#   magic -noconsole -dnull -rcfile /foss/pdks/sky130A/libs.tech/magic/sky130A.tcl ptat_cell.tcl
# =====================================================================

tech load /foss/pdks/sky130A/libs.tech/magic/sky130A.tech
load ptat_cell

# ---------------------------------------------------------------------
# Q2: small substrate PNP (0.68x0.68 um) -- PDK geometry, at origin
# ---------------------------------------------------------------------
box 0 0 796 796
paint pwell
box 0 643 796 796
paint pwell
box 0 153 153 643
paint pwell
box 643 153 796 643
paint pwell
box 0 0 796 153
paint pwell
box 153 153 643 643
paint nbase
box 330 449 466 466
paint pdiff
box 330 347 347 449
paint pdiff
box 449 347 466 449
paint pdiff
box 330 330 466 347
paint pdiff
box 347 347 449 449
paint pdiffc
box 26 736 770 770
paint psubdiff
box 26 702 60 736
paint psubdiff
box 94 702 128 736
paint psubdiff
box 162 702 196 736
paint psubdiff
box 230 702 264 736
paint psubdiff
box 298 702 498 736
paint psubdiff
box 532 702 566 736
paint psubdiff
box 600 702 634 736
paint psubdiff
box 668 702 702 736
paint psubdiff
box 736 702 770 736
paint psubdiff
box 26 669 770 702
paint psubdiff
box 26 668 127 669
paint psubdiff
box 26 634 60 668
paint psubdiff
box 94 634 127 668
paint psubdiff
box 26 600 127 634
paint psubdiff
# emitter contact + label (node b)
box 347 347 449 449
paint m1contact
box 398 398 398 398
label b metal1
# substrate/well contact + label
box 298 702 498 736
paint m1contact
box 398 715 398 715
label VSS metal1
box 153 153 153 153
label VSS metal1

# ---------------------------------------------------------------------
# Q1: large substrate PNP (3.4x3.4 um) -- PDK geometry, offset (+2000,0)
# ---------------------------------------------------------------------
set dx 2000
box [expr $dx+0] [expr 0] [expr $dx+1340] [expr 1340]
paint pwell
box [expr $dx+0] [expr 1187] [expr $dx+1340] [expr 1340]
paint pwell
box [expr $dx+0] [expr 153] [expr $dx+153] [expr 1187]
paint pwell
box [expr $dx+1187] [expr 153] [expr $dx+1340] [expr 1187]
paint pwell
box [expr $dx+0] [expr 0] [expr $dx+1340] [expr 153]
paint pwell
box [expr $dx+153] [expr 153] [expr $dx+1187] [expr 1187]
paint nbase
box [expr $dx+330] [expr 958] [expr $dx+1010] [expr 1010]
paint pdiff
box [expr $dx+330] [expr 924] [expr $dx+384] [expr 958]
paint pdiff
box [expr $dx+418] [expr 924] [expr $dx+474] [expr 958]
paint pdiff
box [expr $dx+508] [expr 924] [expr $dx+564] [expr 958]
paint pdiff
box [expr $dx+598] [expr 924] [expr $dx+654] [expr 958]
paint pdiff
box [expr $dx+688] [expr 924] [expr $dx+744] [expr 958]
paint pdiff
box [expr $dx+778] [expr 924] [expr $dx+834] [expr 958]
paint pdiff
box [expr $dx+868] [expr 924] [expr $dx+924] [expr 958]
paint pdiff
box [expr $dx+958] [expr 924] [expr $dx+1010] [expr 958]
paint pdiff
# substrate ring (representative segment)
box [expr $dx+26] [expr 1300] [expr $dx+1314] [expr 1314]
paint psubdiff
box [expr $dx+600] [expr 700] [expr $dx+740] [expr 740]
paint psubdiff
# emitter label (node n1)
label n1 metal1 [expr $dx+500] [expr 968] [expr $dx+500] [expr 968] FreeSans 0.4 0 0 0
label VSS metal1 [expr $dx+153] [expr 153] [expr $dx+1187] [expr 1187] FreeSans 0.4 0 0 0

# ---------------------------------------------------------------------
# R1: meandering p+ poly resistor (ppolyres), between the two PNPs
# ---------------------------------------------------------------------
set ry 1600
box 300 $ry 900 [expr $ry+40]
paint ppolyres
box 300 [expr $ry+40] 340 [expr $ry+360]
paint ppolyres
box 340 [expr $ry+320] 860 [expr $ry+360]
paint ppolyres
box 860 [expr $ry+40] 900 [expr $ry+360]
paint ppolyres
# contacts at both ends
box 300 $ry 380 [expr $ry+40]
paint polycontact
box 820 $ry 900 [expr $ry+40]
paint polycontact
# labels: left = node a (R1 top), right = node n1 (Q1 emitter)
label a metal1 340 [expr $ry+20] 340 [expr $ry+20] FreeSans 0.4 0 0 0
label n1r metal1 860 [expr $ry+20] 860 [expr $ry+20] FreeSans 0.4 0 0 0

# ---------------------------------------------------------------------
# wiring: metal1 straps (VDD/GND frame), DRC
# ---------------------------------------------------------------------
box 0 2600 3000 2620
paint metal1
box 300 2610 300 2610
label VDD metal1

# ---------------------------------------------------------------------
# DRC check (whole layout)
# ---------------------------------------------------------------------
box 0 0 3200 2800
drc off
drc euclidean on
drc style drc(full)
drc check
drc catchup
drc catchup
puts "== DRC errors =="
drc count total

writeall force ptat_cell
puts "== wrote layout/ptat_cell.mag =="
quit
