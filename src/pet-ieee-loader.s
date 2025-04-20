; PET IEEE Loader
;
; This program allows programs to be loaded into and executed on the PET
; remotely from an external IEEE-488 controller.
;
; This can be another PET, a C64 with IEEE-488 interface cartridge, or a PC
; using an IEEE-488 xum1541/ZoomFloppy.  It is designed to make it very quick
; and easy to load programs into the PET and run test during a development/test
; process.
;
; The PET running this loader becomes an IEEE-488 device, rather than operating
; in its usual controller mode.

; Copyright (c) 2025 Piers Finlayson <piers@piers.rocks>
;
; Licensed under the MIT License.  See [LICENSE] for details.

.include "constants.inc"

; Location of binary
; $27A - 339 inclusive - cassette buffer 1
; $33A - 3F9 inclusive - cassette buffer 2
;
; The second cassette buffer was not free on the earliest PET models, but I 
; can't get this program down to 192 bytes.  Therefore we'll load to $27A and
; over-run into the 2nd cassette buffer.
;
; The program loads to $27A.
;
; After loading the user calls `SYS 649` to install the interrupt handler.
;
; The user can then call `SYS 634` later to reset the interrupt handler to the
; original one.
;
; This assert checks the SYS commands haven't changed.
.assert (init - exit) + 634 = 649, error, "SYS commands have changed"

; Load address of the program - the beginning of the buffer.  Points to the
; start of the cassette buffer, which is what is set in the linker config file
; as the CODE segment start address.
.segment "LOAD"
.word $27A

.segment "CODE"

; Exit point - restore original IRQ vector
exit:
    SEI
    LDA old_irq
    STA $0090
    LDA old_irq+1
    STA $0091
    CLI
    RTS
    
old_irq:
    .word $0000         ; Original IRQ vector storage

; Entry point
init:
    ; Save original IRQ vector
    LDA $0090
    STA old_irq
    LDA $0091
    STA old_irq+1
    
    ; Install our IRQ vector
    SEI                 ; Disable interrupts
    LDA #<atn_handler
    STA $0090
    LDA #>atn_handler
    STA $0091

    ; Don't bother settings UB16_PORT_A to 0xFF - this sets DI pins to inputs.
    ; This is done by the KERNAL on boot, so already set.

    ; Configure UB16 PIA for ATN interrupts - preserve other bits
    ; - Set bit 7 (1): Enable CA1 interrupts
    ; - Set bit 1 (1): CA1 negative edge triggering (since ATN is active low)
    ; - Set bit 0 (1): Access data register (not direction register)
    LDA UB16_CTRL_A    ; Get current value
    ORA #$83           ; Set bits 0, 1, and 7
    STA UB16_CTRL_A    ; Update control register
    
    CLI                 ; Enable interrupts
    RTS                 ; Return to BASIC

; ATN Interrupt Handler - Entry point when ATN line goes active
atn_handler:
    ; Save registers
    PHA
    TXA
    PHA
    TYA
    PHA

    ; Ensure exit_vector is RTI for this command - we may have modified it when
    ; executing a command previously
    LDA #$40            ; RTI opcode
    STA exit_vector
    
    ; Get command byte and perform dispatch - loads A with command so M and V
    ; bits are set on return
    JSR receive_byte
    
    ; Check for execute command (bit 7)
    BMI handle_execute  ; Will JMP to a specific address
    
    ; Check for load command (bit 6)
    BVS handle_load     ; Load a series of bytes
    
    ; Unknown command, just return
    BVC atn_exit        ; Always branches
    
; IEEE-488 receive byte routine
receive_byte:
    ; Set NRFD high (not ready)
    LDA REG_NRFD_OUT        ; UB15_PORT_B ($E842)
    ORA #MASK_NRFD_OUT      ; Set bit 1
    STA REG_NRFD_OUT

    ; Wait for DAV low (data available)
@wait_dav_low:
    LDA REG_DAV_IN          ; UB15_PORT_B ($E842)
    AND #MASK_DAV_IN        ; Test bit 7
    BNE @wait_dav_low       ; Loop if DAV high

    ; Set NRFD low (ready for data)
    LDA REG_NRFD_OUT        ; UB15_PORT_B ($E842)
    AND #MASK_NRFD_OUT_OFF  ; Clear bit 1
    STA REG_NRFD_OUT
    
    ; Read data byte
    LDA REG_DATA_IN         ; UB16_PORT_A ($E820)
    EOR #$FF                ; Invert (IEEE-488 is inverted)
    PHA                     ; Save data byte
    
    ; Set NDAC low (data accepted)
    ; For PIA CA2 (UB16): Clear bit 3, set bit 4 for low output
    LDA REG_NDAC_OUT        ; UB16_CTRL_A ($E821)
    AND #$F7                ; Clear bit 3
    ORA #$10                ; Set bit 4 for mode control
    STA REG_NDAC_OUT
    
    ; Wait for DAV high (sender released)
@wait_dav_high:
    LDA REG_DAV_IN          ; UB15_PORT_B ($E842)
    AND #MASK_DAV_IN        ; Test bit 7
    BEQ @wait_dav_high      ; Loop if DAV still low
    
    ; Set NDAC high (ready for next byte)
    ; For PIA CA2 (UB16): Set bit 3, set bit 4 for high output
    LDA REG_NDAC_OUT        ; UB16_CTRL_A ($E821)
    ORA #$18                ; Set bits 3 & 4
    STA REG_NDAC_OUT
    
    ; Return data byte
    PLA
    RTS

handle_execute:
    JSR receive_byte    ; Get address low byte
    STA exit_vector+1   ; Self-modify exit instruction
    JSR receive_byte    ; Get address high byte
    STA exit_vector+2   ; Self-modify exit instruction
    
    ; Change RTI to JMP
    LDA #$4C             ; JMP opcode
    STA exit_vector      ; Replace RTI with JMP
    ; Fall through to atn_exit (saves bytes)

; Combine 
atn_exit:
    ; Restore registers
    PLA
    TAY
    PLA
    TAX
    PLA

exit_vector:
    RTI                 ; Becomes JMP $xxxx in execute case
.byte $00, $00          ; Placeholder for exit vector

; Main load handling routine
handle_load:
    JSR receive_byte    ; Get address low byte
    STA dest_lo
    JSR receive_byte    ; Get address high byte
    STA dest_hi
    JSR receive_byte    ; Get count low byte
    STA count_lo
    JSR receive_byte    ; Get count high byte
    STA count_hi
    
    LDY #$00            ; Initialize index register
    
load_loop:
    JSR receive_byte    ; Get a data byte
    STA (dest_lo),Y     ; Store at destination address + Y
    
    INY                 ; Increment index
    BNE load_not_page   ; If Y didn't wrap to 0, skip high byte increment
    INC dest_hi         ; Y wrapped, so increment high byte of destination
    
load_not_page:
    ; Decrement 16-bit counter
    DEC count_lo        ; Decrement low byte of count
    LDA count_lo
    CMP #$FF            ; Did it wrap from 0 to 255?
    BNE load_check_done ; If not, skip high byte decrement
    DEC count_hi        ; Decrement high byte since low byte wrapped
    
load_check_done:
    LDA count_lo        ; Check if both bytes of count are zero
    ORA count_hi
    BNE load_loop       ; If not, continue loading
    
    ; Return when done by jumping to atn_exit
    BEQ atn_exit        ; Always true if here