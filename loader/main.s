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

; Import the IEEE-488 routines
.import setup_ieee, restore_ieee, receive_ieee_byte

; Import the load address
.import __LOAD_ADDR__

; Include the constants and macros
.include "constants.inc"
.include "macros.inc"

; Stored the load address of the program, which turns the binary into a PRG
; file.
.segment "LOAD"

.word __LOAD_ADDR__

;
; CODE - start of the program
;
.segment "CODE"
code_start:

;
; Convience JMPs to the key entry points.  
;

; Allows the SYS commands to be:
; - Setup IRQ:   SYS __LOAD__ADDR__
; - Disable IRQ: SYS __LOAD__ADDR__+3
setup_irq:
    .assert setup_irq - code_start = 0, error, "setup_irq not at expected offset"
    JMP install_irq_handler
disable_irq:
    .assert disable_irq - code_start = 3, error, "disable_irq not at expected offset"
    JMP restore_irq_sys
handle_irq:
    .assert handle_irq - code_start = 6, error, "handle_irq not at expected offset"
    JMP irq_handler

;
; Memory used by the program
;
device_id:
    ; To configure the device ID, use POKE __LOAD_ADDR__+9, device_id.  E.g.
    ;   POKE __LOAD_ADDR__+9,8
    .assert device_id - code_start = 9, error, "Device ID not at expected offset"
    .byte 30            ; Device ID (0-30, default 30)

orig_irq:
    ; Original IRQ vector storage
    .byte $00, $00

; Install our IRQ handler.
install_irq_handler:
    ; Disable interrupts
    SEI                     ; Disable interrupts

    ; Save original IRQ vector (in orig_irq)
    LDA SYSTEM_IRQ
    STA orig_irq
    LDA SYSTEM_IRQ+1
    STA orig_irq+1
    
    ; Install our IRQ vector
    LDA #<irq_handler
    STA $0090
    LDA #>irq_handler
    STA $0091

    ; Enable ~ATN_IN interrupts
    ENABLE_IRQ_ATN_IN

    ; Clear first 2 bytes of screen and put * on top left
    LDX #$02
    JSR clear_screen_area
    PRINT_CHAR $2A, 0   ; Asterisk

    CLI                     ; Enable interrupts
    RTS                     ; Return to BASIC

; Restore original IRQ handler - called by SYS <address>.
;
; Disables interrupts before calling internal routine the restores before
; returning.
restore_irq_sys:
    ; Disable interrupts
    SEI

    JSR restore_irq_int

    ; Re-enable interrupts
    CLI

    RTS

; Restore original IRQ vector
;
; Only to be called internally once interrupts have been disabled - or from
; within an interrupt handler context.
restore_irq_int:
    ; Load the old IRQ vector back to where it came from
    LDA orig_irq
    STA SYSTEM_IRQ
    LDA orig_irq+1
    STA SYSTEM_IRQ+1

    ; At this point we could clear out the stored IRQ vector, but that's
    ; unecessary

    ; Disable ~ATN_IN interrupts
    DISABLE_IRQ_ATN_IN

    ; Put ! on top left of screen to show we're disabled
    PRINT_CHAR $21, 0       ; Exclamation mark

    RTS

; ATN Interrupt Handler - Entry point when ATN line goes active
irq_handler:
    ; Save accumulator
    PHA

    ; Test if ATN caused the interrupt
    LDA REG_ATN_IN          ; Read control register A
    AND #BIT_MASK_ATN_IN    ; Mask for ATN interrupt flag (bit 7)
    BNE atn                 ; If bit is high, ATN caused interrupt
    
    PLA                     ; Restore accumulator
    JMP (orig_irq)           ; Jump to original handler

atn:
    ; Note that A has already been pushed to the stack

    ; Save other registers
    TXA
    PHA
    TYA
    PHA

    ; Clear first 16 bytes of the screen
    LDX #$10
    JSR clear_screen_area

    ; Put + on top left of screen to show we're processing
    PRINT_CHAR $2B, 0

    ; Clear the interrupt by reading the data port
    LDY UB16_PORT_A     ; Read data port (clears CA1 interrupt flag)

    ; Setup the IEEE-488 port for listening
    JSR setup_ieee

    ; Updated first byte on screen to show progress - now a ,
    INC_CHAR 0

    ; Calculate what the first byte should be to be a LISTEN for us
    LDA device_id       ; Get the configured device ID (default 30)
    ORA #$20            ; OR with $20 to get the LISTEN byte
    PRINT_A 2           ; Store the LISEN byte in the screen RAM

    ; Read the first byte from the IEEE-488 port
    JSR receive_ieee_byte    ; Get the first byte - and check it's a LISTEN
    CMP SCREEN_RAM+2    ; Compare with the byte we stored in screen RAM
    BNE @atn_exit       ; It wasn't a LISTEN, for us, so exit

    ; Is was a LISTEN for us, so continue.  We are now "LISTENing".
    INC_CHAR 0          ; Top left of screen now becomes -

    ; Get command byte and perform dispatch - loads A with command so M and V
    ; bits are set on return
    JSR receive_ieee_byte

    ; Check for execute command (bit 7)
    BMI @handle_execute
    
    ; Check for load command (bit 6)
    BVS @handle_load
    
@atn_exit:
    ; Unknown command, or we're finished, restore IEEE lines and return from
    ; the interrupt handler
    JSR restore_ieee

    RESTORE_REGISTERS
    RTI

@handle_execute:
    JMP do_execute      ; Jump so nothing goes on stack, and we won't return
                        ; anyway

@handle_load:
    JSR do_load
    JMP @atn_exit
    
do_execute:
    ; Put X on top left of screen
    PRINT_CHAR $18, 0

    ; Get execute address
    JSR receive_ieee_byte    ; Get address low byte
    PRINT_A 8           ; Store it in the screen RAM
    JSR receive_ieee_byte    ; Get address high byte
    PRINT_A 9           ; Store it in the screen RAM

    ; Restore the IEEE lines
    JSR restore_ieee

    ; Restore original IRQ handler
    JSR restore_irq_int

    ; Modify the stack so whe we RTI, the CPU will execute code at the required
    ; address.
    RESTORE_REGISTERS   ; Pull the registers we stored at the beginning of our
                        ; interrupt handler back off the stack (and throw them
                        ; away)
    PLA                 ; Pull the CPU flag register stored before IRQ call off
                        ; the stack (and throw it away)
    PLA                 ; Pull the interrupt return address off the stack
    PLA                 ; 2nd byte of return address

    ; Now push the new return address back on the stack
    LDA SCREEN_RAM+9    ; Get high byte of address
    PHA                 ; Push it on the stack
    LDA SCREEN_RAM+8    ; Get low byte of address
    PHA                 ; Push it on the stack
    LDA #$00            ; Push the new CPU flag register on the stack
    PHA                 ; Push it on the stack

    PRINT_CHAR $23, 0   ; Change top left of screen to # to show we're done

    RTI                 ; Return from interrupt handler

; Load handling routine
do_load:
    ; Put L on top left of screen
    PRINT_CHAR $0C, 0

    ; Read next 2 IEEE-488 bytes, which are the destination address
    JSR receive_ieee_byte   ; Get address low byte
    PRINT_A 8               ; Display on screen
    JSR receive_ieee_byte   ; Get address high byte
    PRINT_A 9               ; Display on screen

@load_loop:
    ; Start of main read loop
    LDA SCREEN_RAM+8        ; Get low byte of destination
    STA @store+1            ; Modify store instruction to put the byte in the
                            ; correct place
    LDA SCREEN_RAM+9        ; Get high byte of destination
    STA @store+2            ; Modify store instruction to put the byte in the
                            ; correct place

    ; Receive byte and store it
    JSR receive_ieee_byte   ; Get the next byte to store
    PRINT_A 11              ; Display it
@store:
    STA $FFFE               ; Store the byte - $FFFE is a dummy address which
                            ; has been replaced above

    ; Check if this was the last byte
    CPX #$00                
    BNE @load_done          ; If so, we're done

    ; Not the last byte, so continue
    INC SCREEN_RAM+8        ; Increment low byte of destination
    BNE @not_page           ; Didn't wrap, so skip high byte increment

    ; Low byte wrapped around, so increment high byte
    INC SCREEN_RAM+9

@not_page:
    JMP @load_loop      ; Loop back to get the next byte
    
@load_done:
    RTS

; Clears the first few bytes of the screen where we can show status
;
; Takes X as the number of bytes to clear
clear_screen_area:
    LDA #$20            ; Space
    LDX #$0F            ; Clear first 16 bytes
@loop:
    STA SCREEN_RAM,X    ; Clear a byte of screen
    DEX
    BNE @loop
RTS
