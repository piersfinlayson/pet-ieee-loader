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

; Import the IEEE-488 routines and storage
.import setup_ieee, restore_ieee, receive_ieee_byte, reset_ieee_var
.import temp_ub15_port_b, temp_ub15_port_b_ddr
.import do_test_routine

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

test_routine:
    ; Test routine which can be used to verify behavior by instructing the
    ; program to execute code at code_start+10
    .assert test_routine - code_start = 10, error, "Test routine not at expected offset"
    JMP do_test_routine

orig_irq:
    ; Original IRQ vector storage
    .byte $00, $00
address:
    ; Address to use for load/execute commands.  Although we also display on
    ; screen, we can't rely on that as storage, as it may get overwritten or
    ; cleared.
    .word $0000
irq_stack:
    ; Storage to use to save registers the main IRQ handler pushed to the
    ; stack, when we modify what's under it, in order to execute the code
    ; we're told to load.
    .byte $00, $00, $00

; Install our IRQ handler.
install_irq_handler:
    ; Disable interrupts
    SEI                     ; Disable interrupts

    JSR install_irq_int

    CLI                     ; Enable interrupts

    RTS                     ; Return to BASIC

; Actually install the interrupt handler
;
; Must (and can be) called with interrupts disabled
install_irq_int:
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
    LDX #$01
    JSR clear_screen_area
    PRINT_CHAR $2A, CGLOBAL ; Asterisk

    RTS

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

    ; Restore IEEE-488 stack variables
    JSR reset_ieee_var

    ; Clear whatever bits of the screen the IRQ handler uses
    LDX #$0F
    JSR clear_screen_area

    ; Put ! on top left of screen to show we're disabled
    PRINT_CHAR $21, CGLOBAL ; Exclamation mark

    RTS

; ATN Interrupt Handler - Entry point when ATN line goes active
; 
; As we get called from the main interrupt handler (by changing the address at
; $0090), we don't need to store registers on the stack.
irq_handler:
    ; Test if ATN caused the interrupt
    LDA UB16_CTRL_A         ; CA1 caused interrupt is top bit of this register
    BMI @atn                ; Check if ATN interrupt flag is set
    
    JMP (orig_irq)          ; Jump to original handler

@atn:
    PRINT_CHAR $01, CGLOBAL ; Top left of screen now becomes A(TN)

    ; Note that A has already been pushed to the stack

    ; We have to get NRFD pulled low just as quickly as we can, as once we're
    ; holding it low we can take our time, before raising it showing we're
    ; ready for data.  If we don't do this quickly, another device on the bus
    ; May get it low, and then high again, before we get the chance to pull it
    ; low, and then we will miss the data.
    ;
    ; Note we can only use the Accumulator at this stage
    ;
    ; We don't JSR to a routine to handle this in order to optimise speed.
    ;
    ; - This sequence takes 6+6+2+6+6+6+2+6 = 40 cycles.
    ; - The irq_handler takes 2+6+3 = 11 cycles.
    ; - The CPU probably takes 10-20 cycles to get into the interrupt handler.
    ;
    ; This totals around 60-70 cycles/us.
    ;
    ; ~NRFD_OUT is PB1 of UB15
    LDA UB15_PORT_B_DDR
    STA temp_ub15_port_b_ddr ; Save original value
    ORA #$02                ; Set bit 1
    STA UB15_PORT_B_DDR     ; Set NRFD_OUT to output
    LDA UB15_PORT_B         ; Read the port
    STA temp_ub15_port_b    ; Save original value
    AND #$FD                ; Clear bit 1
    STA UB15_PORT_B         ; Set NRFD low (not ready for data)

    ; Now we've pulled NRFD low we can take our time.

    ; Clear the interrupt by reading the data port
    LDA UB16_PORT_A     ; Read data port (clears CA1 interrupt flag)

    ; Initialize the rest of the IEEE-488 lines
    JSR setup_ieee

    ; Clear first 16 bytes of the (40-col) screen
    LDX #$0F
    JSR clear_screen_area

    ; Put I on top left of screen to show we're in the interrupt handler
    PRINT_CHAR $09, CGLOBAL ; Top left of screen now becomes I(nterrupt)
    PRINT_CHAR $2D, CCMD    ; Command becomes -

    ; Calculate what the first byte should be to be a LISTEN for us
    LDA device_id       ; Get the configured device ID (default 30)
    ORA #$20            ; OR with $20 to get the LISTEN byte
    PRINT_A CDLISTEN     ; Store the LISEN byte in the screen RAM

    ; Read the first byte from the IEEE-488 port
    JSR receive_ieee_byte   ; Get the first byte - and check it's a LISTEN
    BMI timed_out       ; If A negative, timed out.
    TXA                 ; Put received byte in A
    STA SCREEN_RAM+CRLISTEN ; Store received byte in the screen RAM
    CMP SCREEN_RAM+CDLISTEN ; Compare with the LISTEN byte
    BNE atn_exit        ; It wasn't a LISTEN, for us, so exit

    ; Is was a LISTEN for us, so continue.
    PRINT_CHAR $08, CGLOBAL ; Top left of screen now becomes "H"earing

    ; Get the secondary address byte
    JSR receive_ieee_byte
    BMI timed_out       ; If A negative, timed out.
    ; For now, accept any secondary channel byte.  We should probably have
    ; checked that ATN was still low - as its only a secondary address byte if
    ; so.  But we'll assume it is.

    ; Get command byte and perform dispatch - loads A with command so M and V
    ; bits are set on return
    JSR receive_ieee_byte
    BMI timed_out       ; If A negative, timed out.
    TXA                 ; Put received byte in A

    ; Check for execute command (bit 7)
    BMI handle_execute
    
    ; Check for load command (bit 6)
    ASL A               ; Shift left so bit 6 becomes bit 7
    BMI handle_load     ; Now test bit 7
    
atn_exit:
    PRINT_CHAR $11, CGLOBAL ; Top left of screen now becomes Q(uitting)

    ; Unknown command, or we're finished, restore IEEE lines and return from
    ; the interrupt handler
    JSR restore_ieee

    PRINT_CHAR $04, CGLOBAL ; Top left of screen now becomes D(one)

    ; Rather than RTI directly, we now call the standard hardware interrupt
    ; handler, as something probably needs handling from while we were busy.
    JMP (orig_irq)

timed_out:
    PRINT_CHAR $14, CERROR; Second char now becomes T(imed out)
    JMP atn_exit        ; Jump to exit

handle_execute:
    JMP do_execute      ; Jump so nothing goes on stack, and we won't return
                        ; anyway

handle_load:
    JSR do_load
    JMP atn_exit
    
; Read next two bytes from the IEEE-488 bus and store in screen RAM
;
; If either byte receive times out, exit
get_address:
    ; Read next 2 IEEE-488 bytes, which are the destination address
    JSR receive_ieee_byte   ; Get address low byte
    BMI timed_out           ; If A negative, timed out.
    TXA                     ; Put received byte in A
    STA address
    PRINT_A CADDRLO         ; Display on screen

    JSR receive_ieee_byte   ; Get address high byte
    BMI timed_out           ; If A negative, timed out.
    TXA                     ; Put received byte in A
    STA address+1
    PRINT_A CADDRHI         ; Display on screen

    RTS

; Load handling routine
do_load:
    ; Put L on top left of screen
    PRINT_CHAR $0C, CCMD    ; Command now becomes L(oad)

    ; Get load address
    JSR get_address

@load_loop:
    ; Start of main read loop
    LDA address             ; Get low byte of destination
    STA @store+1            ; Modify store instruction to put the byte in the
                            ; correct place
    LDA address+1           ; Get high byte of destination
    STA @store+2            ; Modify store instruction to put the byte in the
                            ; correct place

    ; Receive byte and store it
    JSR receive_ieee_byte   ; Get the next byte to store
    BMI timed_out           ; If A negative, timed out.
    PHA                     ; Push A onto the stack for later EOI usage
    TXA                     ; Put received byte in A
    PRINT_A CLBYTE          ; Display it
@store:
    STA $FFFE               ; Store the byte - $FFFE is a dummy address which
                            ; has been replaced above

    ; Check if this was the last byte
    PLA                     ; Pull A from the stack
    ASL A                   ; Shift A left 1 bit so we can test EOI at bit 7
    BMI @load_done          ; EOI set, so we're done

    ; Not the last byte, so continue
    INC address             ; Increment low byte of address
    INC SCREEN_RAM+CADDRLO  ; Increment on screen
    BNE @not_page           ; Didn't wrap, so skip high byte increment

    ; Low byte wrapped around, so increment high byte
    INC address+1           ; Increment high byte of address
    INC SCREEN_RAM+CADDRHI  ; Increment on screen

@not_page:
    JMP @load_loop      ; Loop back to get the next byte
    
@load_done:
    RTS

; Execute the code at a given address
;
; Assumes the code we've been told to execute will RTS after its done.
;
; Operation:
; - Load the address from the IEEE-488 bus
; - Restore IEEE-488 lines to their usual state
; - Deregister our interrupt handler and replace with normal one
; - Modify our own routine so we'll JSR to the address given
; - Clear the interrupt context
; - JSR to the address given
; - Set interrupt context (disable interrupts)
; - Re-install our interrupt handler
; - Clear interrupt context
; - Reset the stack pointer to a known good state for BASIC
; - Warn restart BASIC without clearing RAM
;
; This leaves RAM in whatever state it was before we started (except for the
; address we modified in our own code), and bar any changes made by the code we
; were told to execute.  It also leaves this loader routine in a state where we
; can be called again, and will work as expected.
do_execute:
    ; Put X on top left of screen
    PRINT_CHAR $18, CCMD    ; Command becomes (e)X(ecute)

    ; Get execute address
    JSR get_address

.ifdef new
    ; We should really wait for an unlisten now - this would be cleanest.
.endif

    ; Restore the IEEE lines
    JSR restore_ieee

    ; Restore original IRQ handler
    JSR restore_irq_int

    ; Modify execute address below
    LDA address+1       ; Get high byte of address
    STA @execute+2
    LDA address         ; Get low byte of address
    STA @execute+1

    PRINT_CHAR $23, CGLOBAL ; Change top left of screen to # to show we're done

    ; Clear interrupts befor executing the code
    CLI

    ; Actually execute the code we're been instructed to.
@execute:
    JSR $FFFE

    ; Enter interrupt context
    SEI

    ; Set up our interrupt handler again
    JSR install_irq_int

    ; Clear interrupt context
    CLI

    ; Reset the stack pointer to known good state for BASIC.  This is done by
    ; the stock ROM boot initialization at $D3B6, called by $FD46 with the
    ; power on reset entry routine at $FD16.
    LDX #$FB            ; Standard BASIC stack pointer value
    TXS                 ; Reset stack without clearing memory
    
    ; Reinitialize just the screen editor
    JMP (SYSTEM_NMI)    ; Restart BASIC without clearing RAM - this is 

; Clears the first few bytes of the screen where we can show status
;
; Takes X as the number of bytes to clear
clear_screen_area:
    LDA #$20            ; Space
@loop:  ; 10 cycles per iteration = 10us.
    STA SCREEN_RAM,X    ; Clear a byte of screen, 5 cycles
    DEX                 ; 2 cycles
    BNE @loop           ; 3 cycles
    RTS

