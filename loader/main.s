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

; Import the load address
.import __LOAD_ADDR__

; Include the constants and macros
.include "constants.inc"
.include "macros.inc"

.ifdef RAM_TAPE_BUF
.out "Building version using cassette buffer as RAM"
.else
.out "Building version using program space as RAM"
.endif

.ifndef ROM_VERSION
; Stored the load address of the program, which turns the binary into a PRG
; file.
.segment "LOAD"

.word __LOAD_ADDR__
.endif

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

; Install our IRQ handler.
install_irq_handler:
    JSR init_ram            ; Initialize RAM

    SEI                     ; Disable interrupts

    JSR install_irq_int     ; Install our IRQ handler

    CLI                     ; Enable interrupts

    RTS                     ; Return to BASIC

; Initialize RAM
;
; We only bother initialize the RAM which will be read before storing values.
init_ram:
    ; Set the default device ID
    LDA #DEFAULT_DEVICE_ID
    STA DEVICE_ID

    ; Clear number of bytes processed
    LDA #$00
    STA BYTES_PROCESSED

; Actually install the interrupt handler
;
; Must (and can be) called with interrupts disabled
install_irq_int:
    PRINT_CHAR $13, CGLOBAL ; Print S(etup) on the screen

    ; Save original IRQ vector (in ORIG_IRQ)
    LDA SYSTEM_IRQ
    STA ORIG_IRQ
    LDA SYSTEM_IRQ+1
    STA ORIG_IRQ+1
    
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
    LDA ORIG_IRQ
    STA SYSTEM_IRQ
    LDA ORIG_IRQ+1
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
    
    JMP (ORIG_IRQ)          ; Jump to original handler

@atn:
    PRINT_CHAR $01, CGLOBAL ; Top left of screen now becomes A(TN)
    TSX
    TXA
    PRINT_A CSTACKP1        ; Print stack pointer on entry

    ; Note that A has already been pushed to the stack

    ; We have to get NRFD pulled low just as quickly as we can, as once we're
    ; holding it low we can take our time, before raising it showing we're
    ; ready for data.  If we don't do this quickly, another device on the bus
    ; May get it low, and then high again, before we get the chance to pull it
    ; low, and then we will miss the data.
    ;
    ; The xum1541 gives us slightly more than 90us to get NRFD low, after
    ; pulling ATN low.  This code, including the time for the CPU to service
    ; the interrupt, takes slightly under that - around 80-85us.
    ;
    ; We don't use a subroutine to do this, to optimise speed.
    ;
    ; We could speed up further by settins NRFD_OUT to output in the
    ; initialization routine, but we can't guarantee it won't have been changed
    ; since then.
    ;
    ; ~NRFD_OUT is PB1 of UB15
    LDA UB15_PORT_B_DDR
    STA TEMP_UB15_PORT_B_DDR ; Save original value
    ORA #$02                ; Set bit 1
    STA UB15_PORT_B_DDR     ; Set NRFD_OUT to output
    LDA UB15_PORT_B         ; Read the port
    STA TEMP_UB15_PORT_B    ; Save original value
    AND #$FD                ; Clear bit 1
    STA UB15_PORT_B         ; Set NRFD low (not ready for data)

    ; Now we've pulled NRFD low we can take more time about things.

    ; Ideally at this point we'd check if ATN is still low or has gone high.
    ; We can't do this as CA1 state can't be read directly.  We could
    ; reconfigure interrupts to trigger on a positive transition, but that
    ; leaves a window condition.  So, we have to proceed under the assumption
    ; that ATN is still low.  We will handle this, within receive_ieee_byte, by
    ; dealing running timers, so we don't end up in an infinite loop.

    ; Initialize the rest of the IEEE-488 lines
    JSR setup_ieee

    ; Clear the interrupt - do this after setting up the IEEE-488 lines as it
    ; disables the ATN interrupt.  It'll get re-enabled later.
    CLEAR_IRQ_ATN_IN

    ; Clear first 16 bytes of the (40-col) screen
    LDX #$0F
    JSR clear_screen_area

    ; Put I on top left of screen to show we're in the interrupt handler
    PRINT_CHAR $09, CGLOBAL ; Top left of screen now becomes I(nterrupt)
    PRINT_CHAR $2D, CCMD    ; Command becomes -

    ; Calculate what the first byte should be to be a LISTEN for us
    LDA DEVICE_ID       ; Get the configured device ID (default 30)
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

return:
    TSX
    TXA
    PRINT_A CSTACKP2        ; Print stack pointer on exit

    ; Rather than RTI directly, we now call the standard hardware interrupt
    ; handler, as something probably needs handling from while we were busy.
    JMP (ORIG_IRQ)

timed_out:
    PRINT_CHAR $94, CERROR  ; Error char now becomes T(imed out), reversed
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
    STA ADDRESS
    PRINT_A CADDRLO         ; Display on screen

    JSR receive_ieee_byte   ; Get address high byte
    BMI timed_out           ; If A negative, timed out.
    TXA                     ; Put received byte in A
    STA ADDRESS+1
    PRINT_A CADDRHI         ; Display on screen

    RTS

; Load handling routine
do_load:
    ; Put L on top left of screen
    PRINT_CHAR $0C, CCMD    ; Command now becomes L(oad)

    ; Get load address
    JSR get_address

    ; Set up routine in RAM to do the store
    .assert STORE_ROUTINE_LEN = 4, error, "STORE_ROUTINE_LEN incorrect"
    LDA #$8D                ; STA absolute opcode
    STA STORE_ROUTINE
    ; STORE_ROUTINE+1 and 2 will be set up by the load loop below
    LDA #$60                ; RTS opcode
    STA STORE_ROUTINE+3

    LDY #$00                ; Used as offset with indirect STA operation
@load_loop:
    ; Start of main read loop
    LDA ADDRESS             ; Get low byte of destination
    STA STORE_ROUTINE+1     ; Set dest address
    LDA ADDRESS+1           ; Get high byte of destination
    STA STORE_ROUTINE+2     ; Set dest address

    ; Receive byte and store it
    JSR receive_ieee_byte   ; Get the next byte to store
    BMI timed_out           ; If A negative, timed out.
    PHA                     ; Push A onto the stack for later EOI usage
    TXA                     ; Put received byte in A
    PRINT_A CLBYTE          ; Display it
@store:
    ; Store the byte
    JSR STORE_ROUTINE       ; Call the routine to store the byte

    ; Check if this was the last byte
    PLA                     ; Pull A from the stack
    ASL A                   ; Shift A left 1 bit so we can test EOI at bit 7
    BMI @load_done          ; EOI set, so we're done

    ; Not the last byte, so continue
    INC ADDRESS             ; Increment low byte of address
    INC SCREEN_RAM+CADDRLO  ; Increment on screen
    BNE @not_page           ; Didn't wrap, so skip high byte increment

    ; Low byte wrapped around, so increment high byte
    INC ADDRESS+1           ; Increment high byte of address
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
    ; Store the accumulator (which contains the command received)
    STA EXEC_TEMP

    ; Put X on top left of screen
    PRINT_CHAR $18, CCMD    ; Command becomes (e)X(ecute)

    ; Figure out if we're executing a BASIC program or machine code
    LDA EXEC_TEMP
    LSR A                   ; Shift right so bit 0 becomes carry bit
    BCS @basic              ; If carry set, we're executing BASIC

    ; We're executing machine code.  Get execute address.
    JSR get_address

    ; No address required or expected when running a BASIC program
@basic:
    ; Restore the IEEE lines
    JSR restore_ieee

    ; Restore original IRQ handler
    JSR restore_irq_int

    LDA EXEC_TEMP
    LSR A
    BCS @execute_basic      ; If carry set, we're executing BASIC

    ; Not basic

    ; Clear interrupts before executing
    CLI

@execute:
    ; Create code which will JSR to the address we were given, and then JMP
    ; back
    .assert EXEC_JSR_LEN = 6, error, "EXEC_JSR_LEN incorrect"
    LDA #$6C                ; JMP (indirect)
    STA EXEC_JSR
    LDA ADDRESS             ; Get low byte of address
    STA EXEC_JSR+1
    LDA ADDRESS+1           ; Get high byte of address
    STA EXEC_JSR+2
    LDA #$4C                ; JMP (direct)
    STA EXEC_JSR+3
    LDA #<@exec_rtn         ; Get low byte of return address
    STA EXEC_JSR+4
    LDA #>@exec_rtn         ; Get high byte of return address
    STA EXEC_JSR+5

    ; JMP to the code we created
    JMP EXEC_JSR
    
@exec_rtn:
    ; We can't guarantee the code we were told to execute will RTS, but if it
    ; does the code we created will JMP back here and we will now reset up our
    ; interrupt handler so we can handle more commands.

    ; Enter interrupt context
    SEI

    ; Set up our interrupt handler again
    JSR install_irq_int

    JMP return

@temp_basic:
    .byte $00, $00, $00, $00

@execute_basic:
    ; Fix BASIC in case a program has been loaded by us
    JSR fix_basic

    ; BASIC doesn't return to us when done - and our interrupt handler has been
    ; unloaded.  The user will have to reload afterwards if they want to use us
    ; again.

    LDX #$F8                ; Reset stack to what BASIC expects
    TXS
    TXA
    PRINT_A CSTACKP2        ; Print stack pointer on exit

    PRINT_CHAR $23, CGLOBAL ; Change top left of screen to # to show we're done
    PRINT_CHAR $02, CCMD2

    ; Execute program
    JMP BASIC_NEWSTT        ; Start execution

; Fixes BASIC pointers and relinks any BASIC program, ready to run it
;
; In the RAM version (where we are located at $7C00 by default), we need to 
; modify the end of BASIC to avoid overwriting it or confusing the BASIC
; interpreter.  We don't need to do this in the ROM version as we don't touch
; BASIC's RAM (we use a small amount of RAM below BASIC - in the first
; cassette buffer).
;
; In both RAM andd ROM versions we also need to relink the program, so that the
; line pointers are correct.  We also need to set up the variable and array
; pointers, to start immediately following the program, and finally initialize
; a few state variables so BASIC is ready to run the program.
fix_basic:
    ; We don't need to fix the BASIC end point if we're in the ROM version.
.ifndef ROM_VERSION
    ; Set top of memory based on where our machine code lives, and also the
    ; beginning of the string area which starts at the same place (and grows
    ; downwards).
    LDA #<__LOAD_ADDR__
    STA ZP_BASIC_END
    STA ZP_STRING_START
    LDA #>__LOAD_ADDR__
    STA ZP_BASIC_END+1
    STA ZP_STRING_START+1
    
    ; Fix program pointers - this probably isn't required even in the RAM
    ; version, as we don't touch the start of BASIC, but belt and braces.
    LDA #<BASIC_START
    STA ZP_BASIC_START
    LDA #>BASIC_START
    STA ZP_BASIC_START+1
.endif

    ; Relink program.  This sets up the line pointers (to the next line) within
    ; the program, in case they are broken - or the PRG file was created for a
    ; different basic start location.
    JSR BASIC_LINKPRG
    
    ; Find end of program so we can set up the variable space immediately
    ; following it.
    LDA ZP_BASIC_START
    LDY ZP_BASIC_START+1
    
    ; Load each BASIC program line link in turn, jumping from one to the next,
    ; until we find one which is $0000.  This is the end of the program.
@findend:
    STA ZP_PTR          ; Store current pointer
    STY ZP_PTR+1        ; Store current pointer
    LDY #$00
    LDA (ZP_PTR),Y      ; Get link low byte
    TAX                 ; Save it
    INY
    LDA (ZP_PTR),Y      ; Get link high byte
    TAY                 ; Y = high byte
    TXA                 ; A = low byte
    BNE @findend        ; Continue if we're not at $0000
    CPY #$00
    BNE @findend        ; Continue if we're not at $0000
    
    ; Set variable and array start, and also end, after program.  The end is
    ; the same as the start, as it will be filled up during BASIC program
    ; execution.
    CLC
    LDA ZP_PTR
    ADC #$02            ; Skip past the link
    STA ZP_VAR_START
    STA ZP_ARRAY_START
    STA ZP_VAR_END
    LDA ZP_PTR+1
    ADC #$00            ; 16-bit arithmetic - includes any carry byte
    STA ZP_VAR_START+1
    STA ZP_ARRAY_START+1
    STA ZP_VAR_END+1
    
    ; Close all I/O channels and files
    JSR ROM_CLALL
    LDA #$00
    STA ZP_ACTIVE_IO
    STA ZP_PRINT_FLAGS
    
    ; Reset TXTPTR - essentially BASIC's instruction pointer - so BASIC is
    ; ready to execute the program.  We need to do this as we will be launching
    ; the program directly rather than by entering `RUN` within the BASIC
    ; interpreter.
    JSR BASIC_STXPT
    
    RTS

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

.ifndef RAM_TAPE_BUF
; We have to define this segment somewhere, so the linker finds it and checks
; that the code isn't going to overlap with it.
.segment "RAM_VAR"
.endif
