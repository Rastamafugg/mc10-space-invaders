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
MCX_BANK_P0     EQU     $01
MCX_BANK_P1     EQU     $02
MCX_MAP_ALL_RAM EQU     $03
MCX_FLAG        EQU     $0020
MCX_TEST_P0_LOW EQU     $1000
MCX_TEST_P0_HIGH EQU    $C000
MCX_TEST_P1_LOW EQU     $6000
MCX_TEST_P1_HIGH EQU    $8000
P1_TEST_ENTRY   EQU     $D000

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

        ; Enter all-RAM mode with both bank selectors clear.
        LDAA    #MCX_MAP_ALL_RAM
        STAA    MCX_MAP
        CLRA
        STAA    MCX_BANK

        ; P0 controls the low and high 16K windows. Use different signatures
        ; so an alias or failed selector is detected.
        LDAA    #$A0
        STAA    MCX_TEST_P0_LOW
        LDAA    #$A3
        STAA    MCX_TEST_P0_HIGH

        LDAA    #MCX_BANK_P0
        STAA    MCX_BANK
        LDAA    MCX_BANK
        CMPA    #MCX_BANK_P0
        BEQ     p0_bank_register_ok
        JMP     mcx_failure
p0_bank_register_ok = *
        LDAA    #$A4
        STAA    MCX_TEST_P0_LOW
        LDAA    #$A7
        STAA    MCX_TEST_P0_HIGH

        ; Re-select P0=0 and verify its two base windows survived the writes
        ; made through P0=1.
        CLRA
        STAA    MCX_BANK
        LDAA    MCX_TEST_P0_LOW
        CMPA    #$A0
        BEQ     p0_base_low_ok
        JMP     mcx_failure
p0_base_low_ok = *
        LDAA    MCX_TEST_P0_HIGH
        CMPA    #$A3
        BEQ     p0_base_high_ok
        JMP     mcx_failure
p0_base_high_ok = *

        ; Verify the alternate P0 windows.
        LDAA    #MCX_BANK_P0
        STAA    MCX_BANK
        LDAA    MCX_TEST_P0_LOW
        CMPA    #$A4
        BEQ     p0_alt_low_ok
        JMP     mcx_failure
p0_alt_low_ok = *
        LDAA    MCX_TEST_P0_HIGH
        CMPA    #$A7
        BEQ     p0_alt_high_ok
        JMP     mcx_failure
p0_alt_high_ok = *

        ; Restore P0=0 before copying the P1 test. The copy destination is
        ; $D000, so it does not overwrite the P0 test signature at $C000 or
        ; remap the code at $5000 while P1 is tested.
        CLRA
        STAA    MCX_BANK
        LDX     #p1_test_start
        LDAB    #p1_test_end-p1_test_start
p1_copy_loop = *
        LDAA    0,X
p1_copy_store = *
        STAA    P1_TEST_ENTRY
        INX
        INC     p1_copy_store+2
        DECB
        BNE     p1_copy_loop
        CLRA
        STAA    p1_copy_store+2
        JSR     P1_TEST_ENTRY
        LDAA    MCX_FLAG
        CMPA    #$FF
        BEQ     p1_banks_ok
        JMP     mcx_failure
p1_banks_ok = *

        ; Verify both P0 pairs again after the P1 routine has written its four
        ; windows. This also detects an unexpected alias between P0 and P1.
        CLRA
        STAA    MCX_BANK
        LDAA    MCX_TEST_P0_LOW
        CMPA    #$A0
        BEQ     p0_final_base_low_ok
        JMP     mcx_failure
p0_final_base_low_ok = *
        LDAA    MCX_TEST_P0_HIGH
        CMPA    #$A3
        BEQ     p0_final_base_high_ok
        JMP     mcx_failure
p0_final_base_high_ok = *
        LDAA    #MCX_BANK_P0
        STAA    MCX_BANK
        LDAA    MCX_TEST_P0_LOW
        CMPA    #$A4
        BEQ     p0_final_alt_low_ok
        JMP     mcx_failure
p0_final_alt_low_ok = *
        LDAA    MCX_TEST_P0_HIGH
        CMPA    #$A7
        BEQ     p0_final_alt_high_ok
        JMP     mcx_failure
p0_final_alt_high_ok = *
        CLRA
        STAA    MCX_BANK
all_banks_ok = *

        ; Restore the MCX-128 power-on map before normal runtime code.
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

p1_test_start = *
        ; This routine executes from Page 0 at $D000. P0 remains zero, so the
        ; routine is stable while P1 remaps the $4000-$BFFF window.
        CLRA
        STAA    MCX_FLAG

        ; P1=0 exposes the two base middle windows.
        LDAA    #$B1
        STAA    MCX_TEST_P1_LOW
        LDAA    #$B2
        STAA    MCX_TEST_P1_HIGH

        LDAA    #MCX_BANK_P1
        STAA    MCX_BANK
        LDAA    MCX_BANK
        CMPA    #MCX_BANK_P1
        BNE     p1_test_fail

        ; P1=1 exposes the two alternate middle windows.
        LDAA    #$B5
        STAA    MCX_TEST_P1_LOW
        LDAA    #$B6
        STAA    MCX_TEST_P1_HIGH

        ; Re-select P1=0 and verify the base windows survived.
        CLRA
        STAA    MCX_BANK
        LDAA    MCX_TEST_P1_LOW
        CMPA    #$B1
        BNE     p1_test_fail
        LDAA    MCX_TEST_P1_HIGH
        CMPA    #$B2
        BNE     p1_test_fail

        ; Verify the alternate middle windows.
        LDAA    #MCX_BANK_P1
        STAA    MCX_BANK
        LDAA    MCX_TEST_P1_LOW
        CMPA    #$B5
        BNE     p1_test_fail
        LDAA    MCX_TEST_P1_HIGH
        CMPA    #$B6
        BNE     p1_test_fail

        ; Leave all-RAM mode selected until execution returns to $5000. The
        ; copied routine occupies the $C000 RAM window while it runs.
        CLRA
        STAA    MCX_BANK
        LDAA    #$FF
        STAA    MCX_FLAG
        RTS

p1_test_fail = *
        CLRA
        STAA    MCX_BANK
        RTS
p1_test_end = *
