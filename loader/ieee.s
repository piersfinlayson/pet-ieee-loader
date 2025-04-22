; PET IEEE Loader
; 
; Contains IEEE-4888 handling code

; Copyright (c) 2025 Piers Finlayson <piers@piers.rocks>
;
; Licensed under the MIT License.  See [LICENSE] for details.

; Export the IEEE-488 routines
.export setup_ieee, restore_ieee, receive_ieee_byte

; Include the constants and macros
.include "constants.inc"
.include "macros.inc"

; Temporary IEEE-488 storage
temp_ub12_ctrl_a:
    .byte $00
temp_ub15_port_b_ddr:
    .byte $00

; Setup the IEEE-488 port for handling incoming data
;
; - Set DO1-8 to inputs to avoid conflicting with DI lines
; - Set ~NRFD_OUT to output as normally an input
; - Set ~EOI_OUT to input to avoid conflicting with ~EOI_IN
;
; ~DAV_IN is an input by default - so no need to configure
; ~NDAC_OUT is an output by default - so no need to configure
setup_ieee:
    ; Set up DO1-8 to be inputs
    LDY #$00                ; Inputs
    JSR set_do_dir

    ; Set ~NRFD_OUT to output
    LDA UB15_PORT_B_DDR     ; Get current value
    STA temp_ub15_port_b_ddr ; Store for later
    ORA #BIT_MASK_NRFD_OUT  ; Set ~NRFD_OUT to output
    STA UB15_PORT_B_DDR     ; Update direction register

    ; Set ~EOI_OUT to input - set bits 3, 4 and 5 to 0
    LDA UB12_CTRL_A         ; Get current value
    STA temp_ub12_ctrl_a    ; Store for later
    AND #INV_MASK_EOI_OUT   ; Clear bits 3, 4 and 5
    STA UB12_CTRL_A         ; Update control register

    RTS

; Restore the original IEEE register configuration on the PET
;
; - Disables UB16 CA1 (~ATN_IN) interrupts
; - Restores DO1-8 to outputs
; - Restores ~NRFD_OUT to input
;
; No need to restore ~NDAC_OUT - we don't configure it in the first place
restore_ieee:
    ; Restore DO1-8 to outputs
    LDY #$FF            ; Outputs
    JSR set_do_dir

    ; Restore ~NRFD_OUT to input
    LDA temp_ub15_port_b_ddr    ; Get B direction to default
    STA UB15_PORT_B_DDR         ; Write to DDR

    ; Set ~EOI_OUT back to output
    LDA temp_ub12_ctrl_a    ; Get original value
    STA UB12_CTRL_A         ; Update control register

    RTS

; IEEE-488 receive byte routine
;
; Returns
; - A with the received byte
; - X with 0 if not last byte, 1 if last byte
;
; Y is not used or modified
receive_ieee_byte:
    ; All lines on the PET are inverted.  Comment refers to bus levels - so
    ; high is 0 (and with MASK) and low is 1 (OR with bit).

    ; Initialize X to 0
    LDX #$00

    ; Show receive_byte progress on screen - start with 0
    PRINT_CHAR $30, 4

    ; Set NRFD high (ready for data)
    LDA REG_NRFD_OUT        ; UB15_PORT_B ($E842)
    AND #INV_MASK_NRFD_OUT  ; Clear bit 1
    STA REG_NRFD_OUT

    INC_CHAR 4              ; 1

    ; Wait for DAV low (data available)
@wait_dav_low:
    LDA REG_DAV_IN          ; UB15_PORT_B ($E842)
    BPL @wait_dav_low       ; Loop if DAV high (1 on bus, 0 on pin)
                            ; Positive if pin is 0, DAV high, loop

    INC_CHAR 4              ; 2

    ; Set NRFD low (ready for data)
    LDA REG_NRFD_OUT        ; UB15_PORT_B ($E842)
    ORA #BIT_MASK_NRFD_OUT  ; Set bit 1
    STA REG_NRFD_OUT

    INC_CHAR 4              ; 3

    ; Read EOI
    LDA REG_EOI_IN          ; UB12_PORT_A ($E810)
    AND #BIT_MASK_EOI_IN    ; Mask for EOI (bit 3)
    BEQ @eoi_not_set        ; If EOI not set, skip

    LDX #$01                ; EOI set
    PRINT_CHAR $3A, 5       ; Show EOI as :

@eoi_not_set:

    INC_CHAR 4              ; 4

    ; Read data byte
    LDA REG_DATA_IN         ; UB16_PORT_A ($E820)
    EOR #$FF                ; Invert (IEEE-488 is inverted)
    PHA                     ; Save data byte

    INC_CHAR 4              ; 5

    ; Set NDAC high (data accepted)
    ; For PIA CA2 (UB16): Clear bit 3, set bit 4 for low output
    LDA REG_NDAC_OUT        ; UB16_CTRL_A ($E821)
    AND #INV_MASK_NDAC_OUT  ; Clear bit 3
    ORA #$10                ; Set bit 4 for mode control
    STA REG_NDAC_OUT
    
    INC_CHAR 4              ; 6

    ; Wait for DAV high (sender released)
@wait_dav_high:
    LDA REG_DAV_IN          ; UB15_PORT_B ($E842)
    BMI @wait_dav_high      ; Loop if DAV low (0 on bus, 1 on pin)
                            ; Negative if pin is 1, DAV low, loop
    
    INC_CHAR 4              ; 7

    ; Set NDAC low (ready for next byte)
    ; For PIA CA2 (UB16): Set bit 3, set bit 4 for high output
    LDA REG_NDAC_OUT        ; UB16_CTRL_A ($E821)
    ORA #(BIT_MASK_NDAC_OUT | $10) ; Set bit 3 and bit 4 for mode control
    STA REG_NDAC_OUT
    
    INC_CHAR 4              ; 8

    ; Return data byte and store it on screen
    PLA
    STA SCREEN_RAM+6
    RTS

; Sets direction of DO1-8 lines
;
; Sets direction register to value in Y
set_do_dir:
    LDX UB16_CTRL_B     ; Get current control register value
    TXA                 ; Put in accumulator
    ORA #$04            ; Select DDR mode for UB16_CTRL_A
    STA UB16_CTRL_B     ; Update control register

    STY UB16_PORT_B     ; Write to DDR

    STX UB16_CTRL_B     ; Restore ctrl register

    RTS
