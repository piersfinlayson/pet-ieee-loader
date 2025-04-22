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
    ORA #$83                ; Set bits 0, 1, and 7
    STA UB16_CTRL_A         ; Update control register
.endmacro

.macro DISABLE_IRQ_ATN_IN
    ; De-configure UB16 PIA for ATN interrupts
    LDA UB16_PORT_A         ; Clear any outstanding interrupt
    LDA UB16_CTRL_A         ; Get current control register value
    AND #$7C                ; Clear bits 0, 1 and 7
    STA UB16_CTRL_A         ; Update control register
.endmacro

; Stores registers after the interrupt handler
.macro RESTORE_REGISTERS
    PLA
    TAY
    PLA
    TAX
    PLA
.endmacro
