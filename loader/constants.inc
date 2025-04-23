; PET IEEE Loader
; 
; Contains constants and register addresses for the PET IEEE Loader

; Copyright (c) 2025 Piers Finlayson <piers@piers.rocks>
;
; Licensed under the MIT License.  See [LICENSE] for details.

;
; Zero page addresses
;
SYSTEM_IRQ = $90

;
; Memory locations
;
SCREEN_RAM = $8000

;
; Register addresses
;

; UB12 is 6520 PIA 1
; Mostly handles keyboard, also EOI IN/OUT
; http://www.zimmers.net/anonftp/pub/cbm/schematics/computers/pet/8032/8032029-03.gif
UB12_PORT_A = $E810     ; 59408
UB12_CTRL_A = $E811     ; 59409
UB12_CTRL_A_DEF = $60   ; Bits 5 and 6 set to 1 - CA2, ~EOI_OUT output
UB12_PORT_B = $E812     ; 59410
UB12_CTRL_B = $E813     ; 59411
UB12_CTRL_B_DEF = $61   ; Bits 0, 5 and 6 set to 1 - Caassette related

; UB16 is 6520 PIA 2
; Primarily handles IEEE-488 data lines, also a few control lines
; http://www.zimmers.net/anonftp/pub/cbm/schematics/computers/pet/8032/8032029-02.gif
UB16_PORT_A = $E820     ; 59424
UB16_PORT_A_DDR_DEF = $00   ; All inputs, DI1-8
UB16_CTRL_A = $E821     ; 59425
UB16_CTRL_A_DEF = $60   ; Bits 5 and 6 set to 1 - CA2, ~NDAC_OUT output
UB16_PORT_B = $E822     ; 59426
UB16_PORT_B_DDR_DEF = $FF   ; All outpus, DO-1-8
UB16_CTRL_B = $E823     ; 59427
UB16_CTRL_B_DEF = $60   ; Bits 5 and 6 set to 1 - CB2, ~DAV_OUT output

; UB15 is 6522 VIA
; Handles user port, cassette and IEEE-488 control lines
; http://www.zimmers.net/anonftp/pub/cbm/schematics/computers/pet/8032/8032029-03.gif
UB15_PORT_B = $E840     ; 59456
UB15_PORT_A = $E841     ; 59457
UB15_PORT_B_DDR = $E842  ; 59458
UB15_PORT_B_DDR_DEF = $30   ; Bits 4 and 5 set to 1 - PB4, PB5 both cassette related
                            ; ~NRFD_OUT and ~ATN_OUT both set to inputs
UB15_PORT_A_DDR = $E843  ; 59459
UB15_PORT_A_DDR_DEF = $00   ; All inputs, all user port pins

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
BIT_MASK_ATN_IN = $80
BIT_NDAC_OUT = 3
BIT_MASK_NDAC_OUT = $08
INV_MASK_NDAC_OUT = $F7  ; NDAC out bit cleared (complement of $08)

; ~DAV_OUT is CB2 of UB16 6520
INV_MASK_DAV_OUT = $C7  ; Clear bits 3, 4 and 5

; ~NDAC_IN is PB0 of UB15 6522
REG_NDAC_IN = UB15_PORT_B
BIT_NDAC_IN = 0
BIT_MASK_NDAC_IN = $01

; ~NRFD_OUT is PB1 of UB15 6522
REG_NRFD_OUT = UB15_PORT_B
BIT_NRFD_OUT = 1
BIT_MASK_NRFD_OUT = $02
INV_MASK_NRFD_OUT = $FD  ; NRFD out bit cleared (complement of $02)

; ~NRFD_IN is PB6 of UB15 6522
REG_NRFD_IN = UB15_PORT_B
BIT_NRFD_IN = 6
BIT_MASK_NRFD_IN = $40

; ~DAV_IN is PB7 of UB15 6522
REG_DAV_IN = UB15_PORT_B
BIT_DAV_IN = 7
BIT_MASK_DAV_IN = $80
INV_MASK_DAV_IN = $7F  ; DAV in bit cleared (complement of $80)

; ~EOI_OUT is CA2 of UB12 6520
INV_MASK_EOI_OUT = $C7  ; Clear bits 3, 4 and 5

; ~EOI_IN is PA6 of UB12 6520
REG_EOI_IN = UB12_PORT_A
BIT_EOI_IN = 6
BIT_MASK_EOI_IN = $40
INV_MASK_EOI_IN = $BF  ; EOI in bit cleared (complement of $40)
