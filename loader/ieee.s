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
temp_ub16_ctrl_a:
    .byte $00
temp_ub16_ctrl_b:
    .byte $00
temp_receive:
    .byte $00
bytes_processed:
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
    DISABLE_IRQ_ATN_IN

    ; Set up DO1-8 to be inputs
    LDY #$00                ; Inputs
    JSR set_do_dir

    ; Set ~DAV_OUT to input
    LDA UB16_CTRL_B         ; Get current control register value
    STA temp_ub16_ctrl_b    ; Store for later
    AND #INV_MASK_DAV_OUT   ; Clear bits 3, 4 and 5
    STA UB16_CTRL_B         ; Update control register

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

    ; Store UB16_CTRL_A - used by NDAC
    LDA UB16_CTRL_A         ; Get current value
    STA temp_ub16_ctrl_a    ; Store for later

    ; Set NDAC low (ready for next byte)
    ; For PIA CA2 (UB16): Set bit 3, set bit 4 for high output
    LDA REG_NDAC_OUT        ; UB16_CTRL_A ($E821)
    ORA #$30                ; Bit 5 for output, 4-3 10 for low
    AND #INV_MASK_NDAC_OUT  ; Clear bit 3
    STA REG_NDAC_OUT

    ; Pull NRFD low (not ready for data)
    LDA REG_NRFD_OUT        ; UB15_PORT_B ($E842)
    AND #INV_MASK_NRFD_OUT  ; Clear bit 1
    STA REG_NRFD_OUT

    RTS

; Restore the original IEEE register configuration on the PET
;
; - Disables UB16 CA1 (~ATN_IN) interrupts
; - Restores DO1-8 to outputs
; - Restores ~NRFD_OUT to input
;
; No need to restore ~NDAC_OUT - we don't configure it in the first place
restore_ieee:
    ; Set NDAC high (released)
    ; For PIA CA2 (UB16): Clear bit 3, set bit 4 for low output
    LDA REG_NDAC_OUT        ; UB16_CTRL_A ($E821)
    ORA #(BIT_MASK_NDAC_OUT | $10)  ; Set bit 3 (and 4 for mode control)
    STA REG_NDAC_OUT
    
    ; Restore DO1-8 to outputs
    LDY #$FF            ; Outputs
    JSR set_do_dir

    ; Restore ~DAV_OUT to output
    LDA temp_ub16_ctrl_b    ; Get original value
    STA UB16_CTRL_B         ; Update control register

    ; Restore ~NRFD_OUT to input
    LDA temp_ub15_port_b_ddr    ; Get B direction to default
    STA UB15_PORT_B_DDR         ; Write to DDR

    ; Set ~EOI_OUT back to output
    LDA temp_ub12_ctrl_a    ; Get original value
    STA UB12_CTRL_A         ; Update control register

    ; Restore UB16_CTRL_A
    LDA temp_ub16_ctrl_a    ; Get original value
    STA UB16_CTRL_A         ; Update control register

    ENABLE_IRQ_ATN_IN

    RTS

; IEEE-488 receive byte routine
;
; Returns
; - A with the received byte
; - X with 0 if not last byte, non-zero if last byte
;
; Y is not used or modified
receive_ieee_byte:
    ; On the PET, all IEEE-488 are the same polarity as on the bus - not
    ; inverted.  Hence the only lines we need to invert to get the appropriate
    ; value are the Data lines, as the meaning in IEEE-488 is high=0 and
    ; low=1.

    ; Initialize X to 0 - default to not last byte
    LDX #$00

    ; Show receive_byte progress on screen - start with 0
    PRINT_CHAR $30, 4

    ; Set NRFD high (ready for data)
    LDA REG_NRFD_OUT        ; UB15_PORT_B ($E842)
    ORA #BIT_MASK_NRFD_OUT  ; Set bit 1
    STA REG_NRFD_OUT

    INC_CHAR 4              ; 1

    ; Wait for DAV low (data available)
@wait_dav_low:
    LDA REG_DAV_IN          ; UB15_PORT_B ($E842)
    BMI @wait_dav_low       ; Loop if DAV high (1 on bus)

    INC_CHAR 4              ; 2

    ; Set NRFD low (not ready for data)
    LDA REG_NRFD_OUT        ; UB15_PORT_B ($E842)
    AND #INV_MASK_NRFD_OUT  ; Clear bit 1
    STA REG_NRFD_OUT

    INC_CHAR 4              ; 3

    ; Set up UB12 port A (EOI_IN) to read value
    LDA UB12_CTRL_A         ; Get current value
    STA temp_receive
    ORA #$04                ; Set bit 2 for read mode

    ; Read EOI
    LDA REG_EOI_IN          ; UB12_PORT_A ($E810)
    ORA #INV_MASK_EOI_IN    ; Set all other bits to 1
    EOR #$FF                ; Invert - if EOI was 1 it is now 0 and vice versa
    TAX                     ; Store in X - non-zero now means EOI set
    PRINT_A 5               ; Show EOI as - (graphics) or @ (non-set)

    ; Return UB12 port A to original state
    LDA temp_receive
    STA UB12_CTRL_A         ; Restore UB12 port A

    INC_CHAR 4              ; 4

    ; Set up UB16 port A (data in) for read
    LDA UB16_CTRL_A         ; Set UB16 to read mode
    STA temp_receive
    ORA #$04                ; Set bit 2 for read mode   

    ; Read data byte
    LDA REG_DATA_IN         ; UB16_PORT_A ($E820)
    EOR #$FF                ; Invert (IEEE-488 is inverted)
    PRINT_A 6               ; Store it on the screen

    ; Now restore it how it was
    LDA temp_receive
    STA UB16_CTRL_A         ; Restore UB16 port A

    INC_CHAR 4              ; 5

    ; Set NDAC high (data accepted)
    ; For PIA CA2 (UB16): Clear bit 3, set bit 4 for low output
    LDA REG_NDAC_OUT        ; UB16_CTRL_A ($E821)
    ORA #(BIT_MASK_NDAC_OUT | $10)  ; Set bit 3 (and 4 for mode control)
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
    AND #INV_MASK_NDAC_OUT  ; Clear bit 3
    ORA #$10                ; Set bit 3 bit 4 for mode control
    STA REG_NDAC_OUT
    
    ; Increment bytes processed
    INC bytes_processed
    LDA bytes_processed
    STA SCREEN_RAM+15

    ; Return data byte
    LDA SCREEN_RAM+6
    RTS

; Sets direction of DO1-8 lines
;
; Sets direction register to value in Y
set_do_dir:
    LDX UB16_CTRL_B     ; Get current control register value
    TXA                 ; Put in accumulator
    AND #$FB            ; Select DDR mode for UB16_CTRL_A
    STA UB16_CTRL_B     ; Update control register

    STY UB16_PORT_B     ; Write to DDR

    STX UB16_CTRL_B     ; Restore ctrl register

    RTS
