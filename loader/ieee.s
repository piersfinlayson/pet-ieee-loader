; PET IEEE Loader
; 
; Contains IEEE-4888 handling code

; Copyright (c) 2025 Piers Finlayson <piers@piers.rocks>
;
; Licensed under the MIT License.  See [LICENSE] for details.

; Export the IEEE-488 routines and storage
.export setup_ieee, restore_ieee, receive_ieee_byte, reset_ieee_var
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
temp_ub16_ddr_a:
    .byte $00
temp_ub16_ddr_b:
    .byte $00
temp_receive:
    .byte $00
bytes_processed:
    .byte $00

; Reset IEEE-488 variables
;
; We don't need to reset the temporary variables - only those that are valid
; beyond the context of a single interrupt
reset_ieee_var:
    LDA #$00
    STA bytes_processed
    RTS

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

    ; Set up DI1-8 to be inputs
    LDA UB16_CTRL_A     ; Get current control register value
    PHA                 ; Save it
    AND #$FB            ; Select DDR mode for UB16_CTRL_A - clear bit 2
    STA UB16_CTRL_A     ; Update control register

    LDA UB16_PORT_A     ; Get current port value
    STA temp_ub16_ddr_a ; Save it
    LDA #$00            ; Inputs
    STA UB16_PORT_A     ; Write to DDR
    
    PLA                 ; Get control register value
    STX UB16_CTRL_A     ; Restore ctrl register

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
;
; A is modified, X and Y are untouched
restore_ieee:
    ; Put ~NRFD_OUT back to its original state, but set it to high in case it's
    ; an output.  We originally reconfigured ~NRFD_OUT in main directly, not
    ; setup_ieee for performance reasons.
    ;
    ; Also set ~ATN_OUT to high at the same time.
    LDA temp_ub15_port_b_ddr ; Get original value
    STA UB15_PORT_B_DDR     ; Update DDR
    LDA temp_ub15_port_b    ; Get original value
    ORA #$06                ; Set bits PB1 and PB2
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
    AND #$FB            ; Select DDR mode for UB16_CTRL_B - clear bit 2
    STA UB16_CTRL_B     ; Update control register

    LDA temp_ub16_ddr_b ; Restore old value
    STA UB16_PORT_B     ; Write to DDR

    PLA                 ; Get control register value
    STA UB16_CTRL_B     ; Restore ctrl register

    ; Restore DI1-8 to their previous state
    LDA UB16_CTRL_A     ; Get current control register value
    PHA                 ; Save it
    AND #$FB            ; Select DDR mode for UB16_CTRL_A - clear bit 2
    STA UB16_CTRL_A     ; Update control register

    LDA temp_ub16_ddr_a ; Restore old value
    STA UB16_PORT_A     ; Write to DDR

    PLA                 ; Get control register value
    STA UB16_CTRL_A     ; Restore ctrl register

    ENABLE_IRQ_ATN_IN

    RTS

; IEEE-488 receive byte routine
;
; Returns
; - A indicates:
;   - Bit 6 (overflow bit) high if last byte (EOI set)
;   - Bit 7 (minus bit) high if timed out
; - X with the received byte (if A positive - no timeout)
;
; Y is not used or modified
receive_ieee_byte:
    ; On the PET, all IEEE-488 are the same polarity as on the bus - not
    ; inverted.  Hence the only lines we need to invert to get the appropriate
    ; value are the Data lines, as the meaning in IEEE-488 is high=0 and
    ; low=1.

    ; Show receive_byte progress on screen - start with 0
    PRINT_CHAR $30, CRSTEP

    ; Set NRFD high (ready for data)
    LDA UB15_PORT_B         ; UB15 PB1
    ORA #$02                ; Set bit 1
    STA UB15_PORT_B

    INC_CHAR CRSTEP         ; 1

    ; Wait for DAV low (data available).
    ;
    ; We need to be able to cope with the controller issuing a reset on ~IFC.
    ; ~IFC is not connected to anything we can read, as the PET never expected
    ; to be a device.
    ;
    ; Testing shows that the ATMEGA based xum1541 normally takes about 6.2us to
    ; assert ~DAV after ~NRFD is de-asserted.  However, I've seen it take 80us.
    ;
    ; Loading the UB15 register takes 6 clock cycles
    ; BMI on the value takes 3 when branch is taken (loop continues)
    ; A DEX takes 2 clock cycles.
    ; And a BEQ takes 2 clock cycles to test.
    ; Hence this whole loop should take 6+3+2+2 a single time around = 13 clock
    ; cycles.  This is 13us.
    ;
    ; We will try this loop ten times which is around 130us.
.ifdef new
    ; Changed 10 to 80 - to wait a ms - as xum1541/application may take too
    ; long.  In fact we should handle ATN being pulled low again during this
    ; loop and exit (re-enter our handling code) if it happens.
.endif
    LDX #$50                ; Check DAV this many times
@wait_dav_low:
    LDA UB15_PORT_B         ; UB15 PB7
    BPL @dav_low            ; If DAV low, break out of loop and continue
    DEX
    BNE @wait_dav_low       ; Try again if not zero
    BEQ @start_timed_out    ; If zero, timed out

@dav_low:
    INC_CHAR CRSTEP         ; 2

    ; Set NRFD low (not ready for data)
    LDA UB15_PORT_B         ; UB15 PB1
    AND #$FD                ; Clear bit 1
    STA UB15_PORT_B

    INC_CHAR CRSTEP         ; 3

    ; Initialize X to 0 - default to not last byte
    LDX #$00

    ; Set up UB12 port A (EOI_IN) to read value
    LDA UB12_CTRL_A         ; Get current value
    STA temp_receive
    ORA #$04                ; Set bit 2 for reading pins state

    ; Read EOI
    LDA UB12_PORT_A         ; UB12 PA6
    ORA #$BF                ; Set all other bits other than bit 6
    EOR #$FF                ; Invert - if EOI was 1 (unset) it is now 0 and
                            ; if it was 0 (set) it is now 1
    TAX                     ; Store in X - non-zero now means EOI set (bit
                            ; 6/overflow)
    PRINT_A CREOI           ; Show EOI as "-" (graphic char) or "@" (non-set)

    ; Return UB12 port A to original state
    LDA temp_receive
    STA UB12_CTRL_A         ; Restore UB12 port A

    INC_CHAR CRSTEP         ; 4

    ; Set up UB16 port A (data in) for read
    LDA UB16_CTRL_A         ; Get current value of control register
    STA temp_receive        ; Save it
    ORA #$04                ; Set bit 2 for read mode   
    STA UB16_CTRL_A         ; Set UB16 port A to read mode

    ; Read data byte
    LDA UB16_PORT_A
    EOR #$FF                ; Invert (IEEE-488 is inverted)
    PRINT_A CRBYTE          ; Store it on the screen

    ; Now restore the port read mode to how it was - and set ~NDAC_OUT high at
    ; the same time to save us some bytes and instructions
    LDA temp_receive
    ORA #$38                ; Set bits 5-3 to 111 to make ~NDAC high.
    STA UB16_CTRL_A         ; Restore UB16 port A

    INC_CHAR CRSTEP         ; 5

    ; Wait for DAV high (sender released)
    ;
    ; Testing shows xum1541 takes around 5us to raise ~DAV after ~NDAC is
    ; de-asserted.  Like @wait_dav_low we will loop 3 times.
    LDX #$0A                ; Check DAV this many times
@wait_dav_high:
    LDA UB15_PORT_B         ; UB15 PB7
    BMI @dav_high           ; If DAV high, break out of loop and continue
    DEX
    BNE @wait_dav_high      ; Try again if not zero
    BEQ @end_timed_out      ; If zero, timed out
    
@dav_high:
    INC_CHAR CRSTEP         ; 6

    ; Set ~NDAC low (ready for next byte) - we want bits 5-3 110 for output low
    LDA UB16_CTRL_A         ; UB16 CA2
    AND #$F7                ; Clear bit 3
    ORA #$20                ; Set bits 5-4
    STA UB16_CTRL_A
    
    ; Increment bytes processed
    INC bytes_processed
    LDA bytes_processed
    STA SCREEN_RAM+CCOUNT

    ; Return data byte
    LDX SCREEN_RAM+CRBYTE   ; Return data byte as X
    LDA SCREEN_RAM+CREOI    ; Return EOI value as A
    RTS

    ; If @end_timed_out, EOI value was stored in temp_receive
@end_timed_out:
    LDA SCREEN_RAM+CREOI    ; Get EOI value
    BNE @common_timed_out   ; If EOI set, branch to common timeout

    ; If EOI byte is 0, then we can just fall through and do the same as
    ; @start_timed_out, because X will be 0 (as used for loop counter).  Not
    ; JMPing saves us a byte
    
@start_timed_out:
    TXA                     ; Counter reached zero, so X is  aleady 0 - use it

@common_timed_out:
    ORA #$80                ; Set bit 7 (minus bit) to indicate timeout
    RTS
