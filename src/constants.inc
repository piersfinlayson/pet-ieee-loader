;
; Zero page variables
;

; This range is often free for temporary storage
listen      = $FB       ; Listen byte - used at different time to dest_lo
dest_lo     = $FB       ; Destination address low byte
dest_hi     = $FC       ; Destination address high byte
count_lo    = $FD       ; Count of bytes to transfer (low byte)
count_hi    = $FE       ; Count of bytes to transfer (high byte)

;
; Register addresses
;

; UB12 is 6520 PIA 1
; Mostly handles keyboard, also EOI IN/OUT
; http://www.zimmers.net/anonftp/pub/cbm/schematics/computers/pet/8032/8032029-03.gif
UB12_PORT_A = $E800
UB12_CTRL_A = $E811
UB12_PORT_B = $E812
UB12_CTRL_B = $E813

; UB16 is 6520 PIA 2
; Primarily handles IEEE-488 data lines, also a few control lines
; http://www.zimmers.net/anonftp/pub/cbm/schematics/computers/pet/8032/8032029-02.gif
UB16_PORT_A = $E820
UB16_CTRL_A = $E821
UB16_PORT_B = $E822 
UB16_CTRL_B = $E823

; UB15 is 6522 VIA
; Handles user port, cassette and IEEE-488 control lines
; http://www.zimmers.net/anonftp/pub/cbm/schematics/computers/pet/8032/8032029-03.gif
UB15_PORT_B = $E840
UB15_PORT_A = $E841
UB15_PORT_B_DDR = $E842
UB15_PORT_A_DDR = $E843

; IEEE-488 data lines

; Data input lines (DI) are ports A of UB16 6520
REG_DATA_IN = UB16_PORT_A
; Data output lines (DI) are ports B of UB16 6520
REG_DATA_OUT = UB16_PORT_B

; IEEE-488 control lines

; ~ATN_IN is CA1 of UB16 6520
; ~NDAC_OUT is CA2 of UB16 6520
REG_ATN_IN = UB16_CTRL_A
REG_NDAC_OUT = UB16_CTRL_A
BIT_ATN_IN = 7
MASK_ATN_IN = $80
BIT_NDAC_OUT = 3
MASK_NDAC_OUT = $08

; ~DAV_OUT is CB2 of UB16 6520
REG_DAV_OUT = UB16_CTRL_B
BIT_DAV_OUT = 3
MASK_DAV_OUT = $08

; ~NDAC_IN is PB0 of UB15 6522
; ~NRFD_OUT is PB1 of UB15 6522
; ~NRFD_IN is PB6 of UB15 6522
; ~DAV_IN is PB7 of UB15 6522
REG_NDAC_IN = UB15_PORT_B
REG_NRFD_OUT = UB15_PORT_B
REG_NRFD_IN = UB15_PORT_B
REG_DAV_IN = UB15_PORT_B
BIT_NDAC_IN = 0
BIT_NRFD_OUT = 1
BIT_NRFD_IN = 6
BIT_DAV_IN = 7
MASK_NDAC_IN = $01
MASK_NRFD_OUT = $02
MASK_NRFD_OUT_OFF = $FD  ; NRFD out bit cleared (complement of $02)
MASK_NRFD_IN = $40
MASK_DAV_IN = $80

; ~EOI_OUT is CA2 of UB12 6520
REG_EOI_OUT = UB12_CTRL_A
BIT_EOI_OUT = 3
MASK_EOI_OUT = $08

