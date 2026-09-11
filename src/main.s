; Space Invaders for the Tandy MC-10.
;
; This is the first platform smoke test. It is deliberately self-contained:
; it does not depend on BASIC variables or undocumented ROM entry points.
; The executable is loaded by CLOADM at $5000 and entered with EXEC.

        NAM     SPACE-INVADERS
        CPU     6803
        OUTPUT  HEX

SCREEN          EQU     $4000
VIDEO_MODE      EQU     $BFFF
MCX_BANK        EQU     $BF00
MCX_MAP         EQU     $BF01
MCX_TEST        EQU     $C000
MCX_BANK_P0     EQU     $01
MCX_BANK_P1     EQU     $02
MCX_MAP_ALL_RAM EQU     $03

        *       = $5000

start = *
        SEI
        LDS     #$00FF

        ; MC-10 alpha mode: GNA=1, GM2..GM0=0, CSS=0.
        LDAA    #$20
        STAA    VIDEO_MODE

        ; Clear both 256-byte halves of the 32x16 text screen.
        LDAA    #$20
        LDX     #SCREEN
        LDAB    #$00
clear_first_half = *
        STAA    0,X
        INX
        INCB
        BNE     clear_first_half
        LDAB    #$00
clear_second_half = *
        STAA    0,X
        INX
        INCB
        BNE     clear_second_half

        ; Confirm that the MCX-128 responds at its registers and that P0
        ; selects the alternate page-0 RAM at $C000. Code remains at $5000,
        ; which is page 1 with P1=0.
        LDAA    #MCX_BANK_P0
        STAA    MCX_BANK
        LDAA    MCX_BANK
        CMPA    #MCX_BANK_P0
        BEQ     bank_check_ok
        JMP     mcx_failure
bank_check_ok = *

        LDAA    #MCX_MAP_ALL_RAM
        STAA    MCX_MAP
        LDAA    #$A5
        STAA    MCX_TEST
        LDAA    MCX_TEST
        CMPA    #$A5
        BEQ     ram_check_ok
        JMP     mcx_failure
ram_check_ok = *

        ; Restore the MCX-128 power-on map before using ROM or returning to
        ; future runtime code.
        CLRA
        STAA    MCX_MAP
        STAA    MCX_BANK

        ; Fixed-width title and status rows. MC-10 alpha screen codes match
        ; printable ASCII for the uppercase characters used here.
        LDX     #SCREEN+32
        LDAA    #$53
        STAA    0,X
        LDAA    #$50
        STAA    1,X
        LDAA    #$41
        STAA    2,X
        LDAA    #$43
        STAA    3,X
        LDAA    #$45
        STAA    4,X
        LDAA    #$20
        STAA    5,X
        LDAA    #$49
        STAA    6,X
        LDAA    #$4E
        STAA    7,X
        LDAA    #$56
        STAA    8,X
        LDAA    #$41
        STAA    9,X
        LDAA    #$44
        STAA    10,X
        LDAA    #$45
        STAA    11,X
        LDAA    #$52
        STAA    12,X
        LDAA    #$53
        STAA    13,X

        LDX     #SCREEN+64
        LDAA    #$4D
        STAA    0,X
        LDAA    #$43
        STAA    1,X
        LDAA    #$2D
        STAA    2,X
        LDAA    #$31
        STAA    3,X
        LDAA    #$30
        STAA    4,X
        LDAA    #$20
        STAA    5,X
        LDAA    #$36
        STAA    6,X
        LDAA    #$38
        STAA    7,X
        LDAA    #$30
        STAA    8,X
        LDAA    #$33
        STAA    9,X
        LDAA    #$20
        STAA    10,X
        LDAA    #$54
        STAA    11,X
        LDAA    #$45
        STAA    12,X
        LDAA    #$53
        STAA    13,X
        LDAA    #$54
        STAA    14,X

        LDX     #SCREEN+96
        LDAA    #$4D
        STAA    0,X
        LDAA    #$43
        STAA    1,X
        LDAA    #$58
        STAA    2,X
        LDAA    #$31
        STAA    3,X
        LDAA    #$32
        STAA    4,X
        LDAA    #$38
        STAA    5,X
        LDAA    #$20
        STAA    6,X
        LDAA    #$52
        STAA    7,X
        LDAA    #$41
        STAA    8,X
        LDAA    #$4D
        STAA    9,X
        LDAA    #$3A
        STAA    10,X
        LDAA    #$20
        STAA    11,X
        LDAA    #$4F
        STAA    12,X
        LDAA    #$4B
        STAA    13,X

main_loop = *
        BRA     main_loop

mcx_failure = *
        CLRA
        STAA    MCX_MAP
        STAA    MCX_BANK
        LDX     #SCREEN+96
        LDAA    #$4D
        STAA    0,X
        LDAA    #$43
        STAA    1,X
        LDAA    #$58
        STAA    2,X
        LDAA    #$31
        STAA    3,X
        LDAA    #$32
        STAA    4,X
        LDAA    #$38
        STAA    5,X
        LDAA    #$20
        STAA    6,X
        LDAA    #$45
        STAA    7,X
        LDAA    #$52
        STAA    8,X
        LDAA    #$52
        STAA    9,X
        LDAA    #$4F
        STAA    10,X
        LDAA    #$52
        STAA    11,X
        LDAA    #$20
        STAA    12,X
        LDAA    #$21
        STAA    13,X
        BRA     main_loop
