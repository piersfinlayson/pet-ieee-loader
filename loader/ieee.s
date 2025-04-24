; PET IEEE Loader
; 
; Contains IEEE-4888 handling code

; Copyright (c) 2025 Piers Finlayson <piers@piers.rocks>
;
; Licensed under the MIT License.  See [LICENSE] for details.

; Export the IEEE-488 routines and storage
.export setup_ieee, restore_ieee, receive_ieee_byte
.export temp_ub15_port_b, temp_ub15_port_b_ddr

; Include the constants and macros
.include "constants.inc"
.include "macros.inc"

; Temporary IEEE-488 storage
temp_ub12_ctrl_a:
    .byte $00
temp_ub15_port_b:
    .byte $00
temp_ub15_port_b_ddr:
    .byte $00
temp_ub16_ctrl_a:
    .byte $00
temp_ub16_ctrl_b:
    .byte $00
temp_ub16_ddr_b:
    .byte $00
temp_receive:
    .byte $00
bytes_processed:
    .byte $00

; Setup the IEEE-488 port for handling incoming data
;
; Set required ports to inputs/outputs and the correct levelc
; - ~DAV_IN is an input by default - so no need to configure
setup_ieee:
    DISABLE_IRQ_ATN_IN

    ; Set up DO1-8 to be inputs
    LDA UB16_CTRL_B     ; Get current control register value
    PHA                 ; Save it
    AND #$FB            ; Select DDR mode for UB16_CTRL_A - clear bit 2
    STA UB16_CTRL_B     ; Update control register

    LDA UB16_PORT_B     ; Get current port value
    STA temp_ub16_ddr_b ; Save it
    LDA #$00            ; Inputs
    STA UB16_PORT_B     ; Write to DDR
    
    PLA                 ; Get control register value
    STX UB16_CTRL_B     ; Restore ctrl register

    ; Set ports which might be in output mode to inputs

    ; ~DAV_OUT
    ; - ~DAV_OUT is UB16 CB2.
    ; - For input we want bits 5-3 to be 000
    LDA UB16_CTRL_B         ; Get current control register value
    STA temp_ub16_ctrl_b    ; Save it
    AND #$C7                ; Clear bits 3, 4 and 5
    STA UB16_CTRL_B         ; Update control register

    ; ~EOI_OUT to input
    ; - ~EOI_OUT is UB12 CA2.
    ; - To set to input we bits 5-3 to 000
    LDA UB12_CTRL_A         ; Get current value
    STA temp_ub12_ctrl_a    ; Save it
    AND #$C7                ; Clear bits 3, 4 and 5
    STA UB12_CTRL_A         ; Update control register

    ; Set ~NDAC_OUT low (ready for first byte)
    ; - ~NDAC_OUT is UB16 CA2.
    ; - To set to low output we want bits 5-3 to be 110
    LDA UB16_CTRL_A         ; UB16_CTRL_A ($E821)
    STA temp_ub16_ctrl_a    ; Save it
    ORA #$30                ; Set bits 5/4
    AND #$F7                ; Clear bit 3
    STA UB16_CTRL_A

    RTS

; Restore the original IEEE port state
;
; Undoes setup_ieee & also releases NRFD (which allows other devices to
; communicate on the bus, should they need to))
restore_ieee:
    ; Put ~NRFD_OUT back to its original state, but set it to high in case it's
    ; an output.  We originally reconfigured ~NRFD_OUT in main directly, not
    ; setup_ieee for performance reasons.
    LDA temp_ub15_port_b_ddr ; Get original value
    STA UB15_PORT_B_DDR     ; Update DDR
    LDA temp_ub15_port_b    ; Get original value
    AND #02                 ; Set bit PB1
    STA UB15_PORT_B

    ; Set ~NDAC_OUT high
    ; - ~NDAC_OUT is UB16 CA2.
    ; - To set high output we need want bits 5-3 to 111
    LDA temp_ub16_ctrl_a    ; Get original value
    ORA #$38                ; Set bits 5-3 to 111
    STA UB16_CTRL_A

    ; Restore UB12 control register A - but we don't really care what happens
    ; to ~EOI_OUT
    LDA temp_ub12_ctrl_a    ; Get original value
    STA UB12_CTRL_A         ; Update control register

    ; Restore UB16 control register B - but we don't really care what happens
    ; to ~DAV_OUT
    LDA temp_ub16_ctrl_b    ; Get original value
    STA UB16_CTRL_B         ; Update control register

    ; Restore DO1-8 to their previous state
    LDA UB16_CTRL_B     ; Get current control register value
    PHA                 ; Save it
    AND #$FB            ; Select DDR mode for UB16_CTRL_A - clear bit 2
    STA UB16_CTRL_B     ; Update control register

    LDA temp_ub16_ddr_b ; Restore old value
    STA UB16_PORT_B     ; Write to DDR

    PLA                 ; Get control register value
    STX UB16_CTRL_B     ; Restore ctrl register

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
    LDA UB15_PORT_B         ; UB15 PB1
    ORA #$02                ; Set bit 1
    STA UB15_PORT_B

    INC_CHAR 4              ; 1

    ; Wait for DAV low (data available)
@wait_dav_low:
    LDA UB15_PORT_B         ; UB15 PB7
    BMI @wait_dav_low       ; Loop if DAV high (1 on bus)

    INC_CHAR 4              ; 2

    ; Set NRFD low (not ready for data)
    LDA UB15_PORT_B         ; UB15 PB1
    AND #$FD                ; Clear bit 1
    STA UB15_PORT_B

    INC_CHAR 4              ; 3

    ; Set up UB12 port A (EOI_IN) to read value
    LDA UB12_CTRL_A         ; Get current value
    STA temp_receive
    ORA #$04                ; Set bit 2 for reading pins state

    ; Read EOI
    LDA UB12_PORT_A         ; UB12 PA6
    ORA #$BF                ; Set all other bits other than bit 6
    EOR #$FF                ; Invert - if EOI was 1 (unset) it is now 0 and
                            ; if it was 0 (set) it is now 1
    TAX                     ; Store in X - non-zero now means EOI set
    PRINT_A 5               ; Show EOI as "-" (graphic char) or "@" (non-set)

    ; Return UB12 port A to original state
    LDA temp_receive
    STA UB12_CTRL_A         ; Restore UB12 port A

    INC_CHAR 4              ; 4

    ; Set up UB16 port A (data in) for read
    LDA UB16_CTRL_A         ; Set UB16 to read mode
    STA temp_receive
    ORA #$04                ; Set bit 2 for read mode   

    ; Read data byte
    LDA UB16_PORT_A
    EOR #$FF                ; Invert (IEEE-488 is inverted)
    PRINT_A 6               ; Store it on the screen

    ; Now restore the port read mode to how it was
    LDA temp_receive
    STA UB16_CTRL_A         ; Restore UB16 port A

    INC_CHAR 4              ; 5

    ; Set NDAC high (data accepted)
    ; For PIA CA2 (UB16): Clear bit 3, set bit 4 for low output
    LDA UB16_CTRL_A         ; UB16 CA2
    ORA #38                 ; Set bits 5-3 as 111 for output high
    STA UB16_CTRL_A
    
    INC_CHAR 4              ; 6

    ; Wait for DAV high (sender released)
@wait_dav_high:
    LDA UB15_PORT_B         ; UB15 PB7
    BPL @wait_dav_high      ; Loop if DAV low - if low, it's positive
    
    INC_CHAR 4              ; 7

    ; Set NDAC low (ready for next byte) - we want bits 5-3 110 for output low
    LDA UB16_CTRL_A         ; UB16 CA2
    AND #$F7                ; Clear bit 3
    ORA #$20                ; Set bits 5-4
    STA UB16_CTRL_A
    
    ; Increment bytes processed
    INC bytes_processed
    LDA bytes_processed
    STA SCREEN_RAM+14

    ; Return data byte
    LDA SCREEN_RAM+6
    RTS
