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

; MC6803 timer and the stock ROM's RAM-resident OCF vector.
TIMER_CSR       EQU     $0008
TIMER_COUNTER   EQU     $0009
TIMER_COMPARE   EQU     $000B
TIMER_DDR2      EQU     $0001
TIMER_PORT2     EQU     $0003
TIMER_OCF_VECTOR EQU    $4206
TIMER_PERIOD    EQU     $3A56       ; 14,934 E clocks: 262 * 228 / 4
TIMER_SAMPLES   EQU     $003C       ; 60 predicted fields

; Internal RAM is safe for this standalone diagnostic while the stack remains
; at the top of the $0080-$00FF region.
TIMER_EVENTS    EQU     $00E0
TIMER_RESULT    EQU     $00E1
TIMER_MARKER    EQU     $00E2

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

        ; Run the timer/field-cadence diagnostic before entering the idle loop.
        JSR     timer_compare_test

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

; ---------------------------------------------------------------------------
; MC6803 timer compare / MC6847 field-cadence diagnostic
;
; The MC6847 FS output is not available as a verified CPU interrupt input on
; the stock MC-10. This test therefore schedules OCF interrupts at the
; derived NTSC field interval. Each OCF toggles P2.0, which is the cassette /
; RS-232 output line. A scope can compare that marker with the MC6847 FS pin.
; The screen result proves that the timer interrupt completed 60 events; it
; cannot by itself measure FS phase because FS is not CPU-readable here.
; ---------------------------------------------------------------------------
timer_compare_test = *
        ; Show a visible wait state before enabling interrupts.
        LDX     #timer_wait_text
        JSR     write_timer_status

        ; Install a RAM jump at the stock OCF vector. The ROM normally puts an
        ; RTI at $4206, so this changes only the diagnostic's private vector.
        LDAA    #$7E                    ; JMP extended
        STAA    TIMER_OCF_VECTOR
        LDX     #timer_compare_isr
        STX     TIMER_OCF_VECTOR+1

        CLRA
        STAA    TIMER_EVENTS
        STAA    TIMER_RESULT
        STAA    TIMER_MARKER

        ; Keep P2.1 as a keyboard input. Only P2.0 is driven by this test.
        LDAA    #$01
        STAA    TIMER_DDR2
        CLRA
        STAA    TIMER_PORT2

        ; Read TCSR before writing OCR so a stale OCF is cleared by the OCR
        ; write. The compare is anchored to the current free-running counter.
        LDAA    TIMER_CSR
        LDD     TIMER_COUNTER
        ADDD    #TIMER_PERIOD
        STD     TIMER_COMPARE

        ; TCSR bit 3 enables the output-compare interrupt.
        LDAA    #$08
        STAA    TIMER_CSR
        CLI

        ; A timeout prevents a bad vector or unsupported timer from hanging
        ; the diagnostic indefinitely. This allows roughly eleven seconds.
        LDAB    #$10
timer_timeout_outer = *
        LDX     #$FFFF
timer_timeout_inner = *
        LDAA    TIMER_RESULT
        BNE     timer_test_finished
        DEX
        BNE     timer_timeout_inner
        DECB
        BNE     timer_timeout_outer

        SEI
        CLRA
        STAA    TIMER_CSR
        LDAA    #$02
        STAA    TIMER_RESULT

timer_test_finished = *
        SEI
        CLRA
        STAA    TIMER_CSR
        LDAA    #$01
        STAA    TIMER_PORT2

        LDAA    TIMER_RESULT
        CMPA    #$01
        BEQ     timer_test_ok
        LDX     #timer_fail_text
        JSR     write_timer_status
        RTS

timer_test_ok = *
        LDX     #timer_ok_text
        JSR     write_timer_status
        RTS

; OCF handler. Reading TCSR followed by writing OCR clears OCF. Adding the
; period to the previous compare value preserves the phase of the schedule,
; including across the 16-bit counter wrap.
timer_compare_isr = *
        LDAA    TIMER_CSR
        LDD     TIMER_COMPARE
        ADDD    #TIMER_PERIOD
        STD     TIMER_COMPARE

        LDAA    TIMER_MARKER
        EORA    #$01
        STAA    TIMER_MARKER
        STAA    TIMER_PORT2

        INC     TIMER_EVENTS
        LDAA    TIMER_EVENTS
        CMPA    #TIMER_SAMPLES
        BNE     timer_isr_done
        LDAA    #$01
        STAA    TIMER_RESULT
timer_isr_done = *
        RTI

; Copy one fixed-width status string to row 4. The self-modified low byte is
; reset to $80 after each call so repeated status updates are deterministic.
write_timer_status = *
        LDAB    #$0C
timer_status_loop = *
        LDAA    0,X
timer_status_store = *
        STAA    SCREEN+128
        INX
        INC     timer_status_store+2
        DECB
        BNE     timer_status_loop
        LDAA    #$80
        STAA    timer_status_store+2
        RTS

timer_wait_text = *
        DB      $54,$49,$4D,$45,$52,$3A,$20,$57,$41,$49,$54,$20
timer_ok_text = *
        DB      $54,$49,$4D,$45,$52,$3A,$20,$4F,$4B,$20,$20,$20
timer_fail_text = *
        DB      $54,$49,$4D,$45,$52,$3A,$20,$46,$41,$49,$4C,$20
