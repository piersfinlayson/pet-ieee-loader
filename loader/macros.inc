; PET IEEE Loader
; 
; Contains macros for the PET IEEE Loader

; Copyright (c) 2025 Piers Finlayson <piers@piers.rocks>
;
; Licensed under the MIT License.  See [LICENSE] for details.

; Output a character to an offset from the beginning of the screen
.macro PRINT_CHAR char, offset
    LDA #char
    STA SCREEN_RAM + offset
.endmacro

.macro PRINT_A offset
    STA SCREEN_RAM + offset
.endmacro

.macro INC_CHAR offset
    INC SCREEN_RAM + offset
.endmacro

.macro ENABLE_IRQ_ATN_IN
    ; Clear any existing ~ATN_IN interrupt by reading the data port
    LDA UB16_PORT_A         ; Read data port (clears CA1 interrupt flag)

    ; Configure UB16 PIA for ATN interrupts - preserve other bits
    ; - Set bit 7 (1): Enable interrupt
    ; - Set bit 1 (1): CA1 negative edge triggering (since ATN is active low)
    ; - Set bit 0 (1): Enable interrupt
    LDA UB16_CTRL_A         ; Get current value

.ifdef new
    ; I changed this so top bit is no longer being set - not required?
    ; Bit 1 should be 0 for a negative edge trigger
    ; Bit 0 should be 1 to enable the interrupt
.endif
    AND #$FD                ; Clear bit 1
    ORA #$01                ; Set bit 0
    STA UB16_CTRL_A         ; Update control register
.endmacro

.macro DISABLE_IRQ_ATN_IN
    ; De-configure UB16 PIA for ATN interrupts
    LDA UB16_PORT_A         ; Clear any outstanding interrupt
    LDA UB16_CTRL_A         ; Get current control register value
    AND #$FE                ; Clear bit 0 (disable interrupt)
.ifdef new
    ; I changed AND #$7C to just clear bit 0 instead
.endif
    STA UB16_CTRL_A         ; Update control register
.endmacro

.macro CLEAR_IRQ_ATN_IN
    LDA UB16_CTRL_A     ; Get current control register value
    PHA                 ; Save it
    ORA #$04            ; Set bit 2 to enable ORA on PORT A
    STA UB16_CTRL_A     ; Update control register

    LDA UB16_PORT_A     ; Read data port (clears CA1 interrupt flag)

    PLA                 ; Restore control register
    STA UB16_CTRL_A
.endmacro
