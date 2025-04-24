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
UB12_PORT_B = $E812     ; 59410
UB12_CTRL_B = $E813     ; 59411

; UB16 is 6520 PIA 2
; Primarily handles IEEE-488 data lines, also a few control lines
; http://www.zimmers.net/anonftp/pub/cbm/schematics/computers/pet/8032/8032029-02.gif
UB16_PORT_A = $E820     ; 59424
UB16_CTRL_A = $E821     ; 59425
UB16_PORT_B = $E822     ; 59426
UB16_CTRL_B = $E823     ; 59427

; UB15 is 6522 VIA
; Handles user port, cassette and IEEE-488 control lines
; http://www.zimmers.net/anonftp/pub/cbm/schematics/computers/pet/8032/8032029-03.gif
UB15_PORT_B = $E840     ; 59456
UB15_PORT_A = $E841     ; 59457
UB15_PORT_B_DDR = $E842 ; 59458
UB15_PORT_A_DDR = $E843 ; 59459

; IEEE-488 data lines
; - Data input lines (DI) are ports A of UB16 6520
; - Data output lines (DI) are ports B of UB16 6520

; IEEE-488 control lines
; - ~ATN_IN is CA1 of UB16 6520
; - ~NDAC_OUT is CA2 of UB16 6520
; - ~DAV_OUT is CB2 of UB16 6520
; - ~NDAC_IN is PB0 of UB15 6522
; - ~NRFD_OUT is PB1 of UB15 6522
; - ~NRFD_IN is PB6 of UB15 6522
; - ~DAV_IN is PB7 of UB15 6522
; - ~EOI_OUT is CA2 of UB12 6520
; - ~EOI_IN is PA6 of UB12 6520
