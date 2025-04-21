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
; After loading the user calls `SYS 661` to install the interrupt handler.
;
; The user can then call `SYS 634` later to reset the interrupt handler to the
; original one.  However, this is not required if an execute command is
; received - this re-installs the original handler automatically before
; execution.
;
; By default the PET's device ID is 30.  This can be changed by `POKE`ing a
; different value into address 660.  For example, to set as device ID 8:
;   POKE 660,8
;
; This is the device ID that the program will respond to when it received a
; LISTEN command.  This allows other devices to reside on the bus, and the PET
; to ignore communicaations for them.

; This assert checks the locations haven't changed.
.assert restore_irq = 634, error, "SYS commands have changed"
.assert install_irq_handler = 661, error, "SYS commands have changed"
.assert (install_irq_handler - restore_irq) + 634 = 661, error, "SYS commands have changed"
.assert device_id = 660, error, "Device ID address has changed"

; Load address of the program - the beginning of the buffer.  Points to the
; start of the cassette buffer, which is what is set in the linker config file
; as the CODE segment start address.
.segment "LOAD"
.word $27A

.segment "CODE"

; Restore original IRQ vector
restore_irq:
    ; Disable interrupts
    SEI

    ; Load the old IRQ vector back to where it came from
    LDA old_irq
    STA $0090
    LDA old_irq+1
    STA $0091

    ; At this point we could clear out the stored IRQ vector, but that's
    ; unecessary

    ; De-configure UB16 PIA for ATN interrupts - just clear bit 7
    ; - Set bit 7 (1): Enable CA1 interrupts
    LDA UB16_PORT_A         ; Clear any outstanding interrupt
    LDA UB16_CTRL_A         ; Get current control register value
    AND #$7F                ; Clear top bit
    STA UB16_CTRL_A         ; Update control register

    ; Re-enable interrupts
    CLI

    RTS
    
old_irq:
    .word $0000         ; Original IRQ vector storage

device_id:
    .byte $1E           ; Default device ID - 30
                        ; Can be changed using `POKE`

; Entry point
install_irq_handler:
    ; Save original IRQ vector (in old_irq)
    LDA $0090
    STA old_irq
    LDA $0091
    STA old_irq+1
    
    ; Install our IRQ vector
    SEI                     ; Disable interrupts
    LDA #<atn_irq_handler
    STA $0090
    LDA #>atn_irq_handler
    STA $0091

    ; Don't bother settings UB16_PORT_A to 0xFF - this sets DI pins to inputs.
    ; This is done by the KERNAL on boot, so already set.

    ; Clear the interrupt by reading the data port
    LDA UB16_PORT_A         ; Read data port (clears CA1 interrupt flag)

    ; Configure UB16 PIA for ATN interrupts - preserve other bits
    ; - Set bit 7 (1): Enable CA1 interrupts
    ; - Set bit 1 (1): CA1 negative edge triggering (since ATN is active low)
    ; - Set bit 0 (1): Access data register (not direction register)
    LDA UB16_CTRL_A         ; Get current value
    ORA #$83                ; Set bits 0, 1, and 7
    STA UB16_CTRL_A         ; Update control register

    CLI                     ; Enable interrupts
    RTS                     ; Return to BASIC

; ATN Interrupt Handler - Entry point when ATN line goes active
atn_irq_handler:
    ; Save accumulator
    PHA

    ; Test if ATN caused the interrupt
    LDA REG_ATN_IN      ; Read control register A
    AND #MASK_ATN_IN    ; Mask for ATN interrupt flag (bit 7)
    BNE atn             ; If bit is high, ATN caused interrupt
    
    PLA                 ; Restore accumulator
    JMP (old_irq)       ; Jump to original handler

atn:
    ; Note that A has already been pushed to the stack

    ; Clear the interrupt by reading the data port
    LDA UB16_PORT_A     ; Read data port (clears CA1 interrupt flag)

    ; Save other registers
    TXA
    PHA
    TYA
    PHA

    ; Ensure exit_vector is RTI - we may have modified it when executing a
    ; command previously.  We could wait until after we know this is a listen
    ; for us, but this saves us needing different code paths for different exit
    ; cases - saving us some bytes.  It's a little more processor intensive if
    ; there's a lot of unrelated bus activity, but that's unlikely to be the
    ; use-case for this program. 
    LDA #$40            ; RTI opcode
    STA exit_vector

    ; Get the first byte and check it's a LISTEN, for us.
    LDA device_id       ; Construct the expected LISTEN command
    ORA #$20            
    STA listen
    JSR receive_byte    ; Get the first byte - and check it's a LISTEN
    CMP listen
    BNE atn_exit        ; It wasn't a LISTEN, for us, so exit

    ; Is was a LISTEN for us, so continue.  We are now "LISTENing".

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
    STA jump_addr       ; Modify jump address
    JSR receive_byte    ; Get address high byte
    STA jump_addr+1     ; Modify jump address
    
    ; Restore original IRQ handler
    JSR restore_irq

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

jump_addr:
.byte $00, $00          ; Placeholder for execute jump address

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