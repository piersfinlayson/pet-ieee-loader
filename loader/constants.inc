; PET IEEE Loader
; 
; Contains constants and register addresses for the PET IEEE Loader

; Copyright (c) 2025 Piers Finlayson <piers@piers.rocks>
;
; Licensed under the MIT License.  See [LICENSE] for details.

;
; Configuration
;
DEFAULT_DEVICE_ID = 30 ; Default device ID for this device

;
; Zero page addresses
;
SYSTEM_IRQ = $90        ; Hardware IRQ handler, which we will subvert
SYSTEM_NMI = $94        ; Warm restarts basic, we call after we execute code

;
; Memory locations
;
TAPE_BUF_1 = $27A
TAPE_BUF_2 = $33A
TAPE_BUF_LEN = $C0
BASIC_START = $0401     ; Start of BASIC program area
SCREEN_RAM = $8000

;
; RAM variable locations
;

.ifdef RAM_TAPE_BUF
RAM_START = TAPE_BUF_1
.assert RAM_END <= (TAPE_BUF_1+TAPE_BUF_LEN), error, "RAM variable section is too large"
.else
; Put the RAM variables at the end of the program space.
.import __RAM_VAR_ADDR__
RAM_START = __RAM_VAR_ADDR__
.endif

; Device ID for this device
;
; - If using the tape buffer (the ROM variant), `POKE 634,8` is used to set
;   the device ID.
; - If using the $7C00 RAM variant with RAM located in the program space, use
;   `POKE 32720,8` to set the device ID (location $7FD0).
;
; It can be set at any time, but this value is only read when processing a
; LISTEN, so will be ignored until the next LISTEN command.
;
; On initialization, the device ID is set to DEFAULT_DEVICE_ID, so if the
; value is changed before initialization, it will be changed on initialization.
DEVICE_ID = RAM_START 

; Original IRQ vector storage
ORIG_IRQ = DEVICE_ID + 1
ORIG_IRQ_LEN = 2

; Address to use for load/execute commands.  Although we also display on
; screen, we can't rely on that as storage, as it may get overwritten or
; cleared.
ADDRESS = ORIG_IRQ + ORIG_IRQ_LEN
ADDRESS_LEN = 2

; Addresses used by the IEEE-488 routines.
; - TEMP_* are only valid for the duration of the interrupt handler
; - BYTES_PROCESSED is used to store the number of bytes received across all
;   interrupts, and only reset when the interrupt handler is initialized
TEMP_UB12_CTRL_A = ADDRESS + ADDRESS_LEN
TEMP_UB15_PORT_B =      TEMP_UB12_CTRL_A + 1
TEMP_UB15_PORT_B_DDR =  TEMP_UB12_CTRL_A + 2
TEMP_UB16_CTRL_A =      TEMP_UB12_CTRL_A + 3
TEMP_UB16_CTRL_B =      TEMP_UB12_CTRL_A + 4
TEMP_UB16_DDR_A =       TEMP_UB12_CTRL_A + 5
TEMP_UB16_DDR_B =       TEMP_UB12_CTRL_A + 6
TEMP_RECEIVE =          TEMP_UB12_CTRL_A + 7
BYTES_PROCESSED =       TEMP_UB12_CTRL_A + 8

; Store address - holds pointer to byte to be stored
STORE_ADDR = BYTES_PROCESSED + 1

; Stores instructions to JSR to the code to be executed, and then JMPs back to
; continue processing.
EXEC_JSR = STORE_ADDR + 1
EXEC_JSR_LEN = 6

STORE_ROUTINE = EXEC_JSR + EXEC_JSR_LEN
STORE_ROUTINE_LEN = 4

EXEC_TEMP = STORE_ROUTINE + STORE_ROUTINE_LEN

RAM_END = EXEC_TEMP + 1

;
; ROM locations
;
BASIC_LINKPRG = $B4B6
BASIC_STXPT = $B622
BASIC_NEWSTT = $B74A
ROM_CLALL = $FFE7

;
; Zeropage Locations
;
ZP_PRINT_FLAGS = $0D
ZP_ACTIVE_IO = $10
ZP_BASIC_START = $28
ZP_VAR_START = $2A
ZP_ARRAY_START = $2C
ZP_VAR_END = $2E
ZP_STRING_START = $30
ZP_BASIC_END = $34
ZP_PTR = $5C

;
; Register addresses
;

; UB12 is 6520 PIA 1
; Mostly handles keyboard, also EOI IN/OUT
; http://www.zimmers.net/anonftp/pub/cbm/schematics/computers/pet/8032/8032029-03.gif
UB12_PORT_A = $E810     ; 59408
UB12_CTRL_A = $E811     ; 59409
UB12_PORT_B = $E812     ; 59410
UB12_CTRL_B = $E813     ; 59411

; UB16 is 6520 PIA 2
; Primarily handles IEEE-488 data lines, also a few control lines
; http://www.zimmers.net/anonftp/pub/cbm/schematics/computers/pet/8032/8032029-02.gif
UB16_PORT_A = $E820     ; 59424
UB16_CTRL_A = $E821     ; 59425
UB16_PORT_B = $E822     ; 59426
UB16_CTRL_B = $E823     ; 59427

; UB15 is 6522 VIA
; Handles user port, cassette and IEEE-488 control lines
; http://www.zimmers.net/anonftp/pub/cbm/schematics/computers/pet/8032/8032029-03.gif
UB15_PORT_B = $E840     ; 59456
UB15_PORT_A = $E841     ; 59457
UB15_PORT_B_DDR = $E842 ; 59458
UB15_PORT_A_DDR = $E843 ; 59459

; IEEE-488 data lines
; - Data input lines (DI) are ports A of UB16 6520
; - Data output lines (DI) are ports B of UB16 6520

; IEEE-488 control lines
; - ~ATN_IN is CA1 of UB16 6520
; - ~NDAC_OUT is CA2 of UB16 6520
; - ~DAV_OUT is CB2 of UB16 6520
; - ~NDAC_IN is PB0 of UB15 6522
; - ~NRFD_OUT is PB1 of UB15 6522
; - ~NRFD_IN is PB6 of UB15 6522
; - ~DAV_IN is PB7 of UB15 6522
; - ~EOI_OUT is CA2 of UB12 6520
; - ~EOI_IN is PA6 of UB12 6520

;
; Screen character locations
;
; Offset from the top left of the screen
CGLOBAL = $00       ; Global status location
CCMD = $01          ; Command being executed
CERROR = $02        ; Error code
CDLISTEN = $04      ; Byte combining LISTEN ($20) with our device ID
CRLISTEN = $05      ; Received command byte to check against our listen byte
CADDRLO = $07       ; Low byte of address to load to or execute
CADDRHI = $08       ; High byte of address to load to or execute
CLBYTE   = $0A      ; Byte being stored to the load address 
CRSTEP = $0C        ; Receive byte step
CRBYTE = $0D        ; Received byte
CREOI = $0E         ; EOI status
CCMD2 = $24         ; Final command executed
CSTACKP1 = $25      ; Stack pointer on entry to IRQ handler
CSTACKP2 = $26      ; Stack pointer on exit from IRQ handler
CCOUNT = $27        ; Number of bytes successfully received
