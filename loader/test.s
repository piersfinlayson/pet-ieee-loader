; A test routine which can be loaded and executed using this loader.

; Copyright (c) 2025 Piers Finlayson <piers@piers.rocks>
;
; Licensed under the MIT License.  See [LICENSE] for details.

.export do_test_routine

SCREEN_RAM = $8000

; Prints a string to the 2nd line on the screen
do_test_routine:
    LDA #$10
    STA SCREEN_RAM+40
    LDA #$09
    STA SCREEN_RAM+41
    LDA #$05
    STA SCREEN_RAM+42
    LDA #$12
    STA SCREEN_RAM+43
    LDA #$13
    STA SCREEN_RAM+44
    LDA #$2E
    STA SCREEN_RAM+45
    LDA #$12
    STA SCREEN_RAM+46
    LDA #$0F
    STA SCREEN_RAM+47
    LDA #$03
    STA SCREEN_RAM+48
    LDA #$0B
    STA SCREEN_RAM+49
    LDA #$13
    STA SCREEN_RAM+50
    RTS
