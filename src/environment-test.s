; Space Invaders for the Tandy MC-10.
;
; This is the first platform smoke test and playable text-mode game loop.
; It is deliberately self-contained:
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
MCX_MAP_STOCK   EQU     $02
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

; Internal RAM is safe for this standalone diagnostic. Keep the stack below
; the game state bytes, which occupy $00E0-$00FA.
TIMER_EVENTS    EQU     $00E0
TIMER_RESULT    EQU     $00E1
TIMER_MARKER    EQU     $00E2
TIMER_MODE      EQU     $00E3       ; 0=diagnostic, 1=game loop
GAME_PENDING    EQU     $00E4       ; queued frame updates
GAME_FRAME_LO   EQU     $00E5
GAME_FRAME_HI   EQU     $00E6
GAME_SCORE_LO   EQU     $00E7
GAME_SCORE_HI   EQU     $00E8
GAME_LIVES      EQU     $00E9
GAME_PLAYER_X   EQU     $00EA
GAME_BULLET_X   EQU     $00EB
GAME_BULLET_Y   EQU     $00EC       ; playfield-relative row, 0..7
GAME_BULLET_ACTIVE EQU  $00ED
GAME_ALIVE_TOP  EQU     $00EE       ; five-bit formation mask
GAME_ALIVE_BOTTOM EQU   $00EF       ; five-bit formation mask
GAME_INVADER_X  EQU     $00F0       ; leftmost formation column
GAME_INVADER_ROW EQU    $00F1       ; playfield-relative top row
GAME_INVADER_DIR EQU     $00F2       ; 1=right, 0=left
GAME_INVADER_TICK EQU    $00F3       ; movement divider
GAME_RENDER_MASK EQU     $00F4
GAME_RENDER_COLUMN EQU   $00F5
GAME_RENDER_X   EQU     $00F6
GAME_RENDER_TEMP EQU     $00F7
GAME_COLLISION_MASK EQU  $00F8
GAME_COLLISION_X EQU     $00F9
GAME_FIRE_LATCH EQU      $00FA

PORT1_DDR      EQU      $0000
PORT2_DDR      EQU      $0001
PORT1          EQU      $0002
PORT2          EQU      $0003
KEYBOARD_ROWS  EQU      $BFFF

        *       = $5000

start = *
        SEI
        LDS     #$00DF

        ; MC-10 alpha mode: GNA=0, GM2..GM0=0, CSS=0. The MC-10 VDG
        ; control port uses D5 as the active-low GNA input.
        LDAA    #$00
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

        ; Restore the stock-ROM map before normal runtime code. This keeps the
        ; loaded program at $5000 in expansion RAM while exposing the internal
        ; MC-10 ROM in the upper ROM window. A bare MC-10 ignores these writes.
        LDAA    #MCX_MAP_STOCK
        STAA    MCX_MAP
        CLRA
        STAA    MCX_BANK

        ; Fixed-width title and status rows. MC-10 alpha screen codes use
        ; bits 0-5 for the glyph and bit 6 as the inverse attribute.
        LDX     #SCREEN+32
        LDAA    #$13
        STAA    0,X
        LDAA    #$10
        STAA    1,X
        LDAA    #$01
        STAA    2,X
        LDAA    #$03
        STAA    3,X
        LDAA    #$05
        STAA    4,X
        LDAA    #$20
        STAA    5,X
        LDAA    #$09
        STAA    6,X
        LDAA    #$0E
        STAA    7,X
        LDAA    #$16
        STAA    8,X
        LDAA    #$01
        STAA    9,X
        LDAA    #$04
        STAA    10,X
        LDAA    #$05
        STAA    11,X
        LDAA    #$12
        STAA    12,X
        LDAA    #$13
        STAA    13,X

        LDX     #SCREEN+64
        LDAA    #$0D
        STAA    0,X
        LDAA    #$03
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
        LDAA    #$14
        STAA    11,X
        LDAA    #$05
        STAA    12,X
        LDAA    #$13
        STAA    13,X
        LDAA    #$14
        STAA    14,X

        LDX     #SCREEN+96
        LDAA    #$0D
        STAA    0,X
        LDAA    #$03
        STAA    1,X
        LDAA    #$18
        STAA    2,X
        LDAA    #$31
        STAA    3,X
        LDAA    #$32
        STAA    4,X
        LDAA    #$38
        STAA    5,X
        LDAA    #$20
        STAA    6,X
        LDAA    #$12
        STAA    7,X
        LDAA    #$01
        STAA    8,X
        LDAA    #$0D
        STAA    9,X
        LDAA    #$3A
        STAA    10,X
        LDAA    #$20
        STAA    11,X
        LDAA    #$0F
        STAA    12,X
        LDAA    #$0B
        STAA    13,X

        ; Seed the HUD before the timer diagnostic. game_initialize replaces
        ; this row after the timer cadence test succeeds.
        LDX     #SCREEN+160
        LDAA    #$06                    ; F
        STAA    0,X
        LDAA    #$12                    ; R
        STAA    1,X
        LDAA    #$01                    ; A
        STAA    2,X
        LDAA    #$0D                    ; M
        STAA    3,X
        LDAA    #$05                    ; E
        STAA    4,X
        LDAA    #$3A                    ; :
        STAA    5,X
        LDAA    #$20                    ; space
        STAA    6,X
        LDAA    #$30                    ; 0
        STAA    7,X
        STAA    8,X
        STAA    9,X
        STAA    10,X

        ; Run the timer/field-cadence diagnostic before entering the game loop.
        JSR     timer_compare_test

        ; Only start the game loop after the cadence diagnostic succeeds.
        LDAA    TIMER_RESULT
        CMPA    #$01
        BNE     main_loop
        JSR     game_loop_start

main_loop = *
        ; The OCF ISR queues one tick per predicted field. Keep the main loop
        ; responsible for game work so the interrupt remains short and phase
        ; stable. Pending ticks are retained if an update takes longer than a
        ; field.
        LDAA    GAME_PENDING
        BEQ     main_loop
        SEI
        DEC     GAME_PENDING
        CLI
        JSR     game_update
        BRA     main_loop

mcx_failure = *
        LDAA    #MCX_MAP_STOCK
        STAA    MCX_MAP
        CLRA
        STAA    MCX_BANK
        LDX     #SCREEN+96
        LDAA    #$0D
        STAA    0,X
        LDAA    #$03
        STAA    1,X
        LDAA    #$18
        STAA    2,X
        LDAA    #$31
        STAA    3,X
        LDAA    #$32
        STAA    4,X
        LDAA    #$38
        STAA    5,X
        LDAA    #$20
        STAA    6,X
        LDAA    #$05
        STAA    7,X
        LDAA    #$12
        STAA    8,X
        LDAA    #$12
        STAA    9,X
        LDAA    #$0F
        STAA    10,X
        LDAA    #$12
        STAA    11,X
        LDAA    #$20
        STAA    12,X
        LDAA    #$21
        STAA    13,X

        ; Keep the MCX failure visible, but continue with the timer diagnostic
        ; so the stock-machine control can validate cassette execution and
        ; timer cadence independently of MCX hardware.
        JSR     timer_compare_test
        LDAA    TIMER_RESULT
        CMPA    #$01
        BNE     main_loop
        JSR     game_loop_start
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
        ; RTI at $4206, so this claims the private vector for the diagnostic
        ; and the timer-driven game loop.
        LDAA    #$7E                    ; JMP extended
        STAA    TIMER_OCF_VECTOR
        LDX     #timer_compare_isr
        STX     TIMER_OCF_VECTOR+1

        CLRA
        STAA    TIMER_EVENTS
        STAA    TIMER_RESULT
        STAA    TIMER_MARKER
        STAA    TIMER_MODE

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

        LDAA    TIMER_MODE
        BNE     timer_game_tick
        INC     TIMER_EVENTS
        LDAA    TIMER_EVENTS
        CMPA    #TIMER_SAMPLES
        BNE     timer_isr_done
        LDAA    #$01
        STAA    TIMER_RESULT
        BRA     timer_isr_done
timer_game_tick = *
        INC     GAME_PENDING
timer_isr_done = *
        RTI

; Re-arm the same compare interval after the one-second diagnostic and enter
; the frame-driven game loop. The next compare is based on the current counter;
; subsequent compares are chained from the previous compare in the ISR.
game_loop_start = *
        CLRA
        STAA    TIMER_MODE
        STAA    GAME_PENDING
        STAA    GAME_FRAME_LO
        STAA    GAME_FRAME_HI
        JSR     game_initialize
        LDAA    TIMER_CSR
        LDD     TIMER_COUNTER
        ADDD    #TIMER_PERIOD
        STD     TIMER_COMPARE
        LDAA    #$01
        STAA    TIMER_MODE
        LDAA    #$08
        STAA    TIMER_CSR
        CLI
        RTS

; First playable text-mode game loop. Each queued timer event scans A/D and
; Space, advances one player shot, moves the formation, resolves collisions,
; and redraws the eight-row playfield.
game_update = *
        JSR     game_keyboard
        JSR     game_bullet_update
        JSR     game_invader_update
        JSR     game_render
        JSR     game_hud_update

        INC     GAME_FRAME_LO
        BNE     game_update_done
        INC     GAME_FRAME_HI
game_update_done = *
        RTS

; Scan the three keys used by the prototype. MC-10 keyboard rows are active
; low: A is PB1/PA0, D is PB4/PA0, and Space is PB7/PA3.
game_keyboard = *
        LDAA    #$FF
        STAA    PORT1_DDR

        LDAA    #$FD                    ; PB1: A
        STAA    PORT1
        LDAA    KEYBOARD_ROWS
        BITA    #$01
        BNE     game_key_right
        LDAA    GAME_PLAYER_X
        BEQ     game_key_right
        DECA
        STAA    GAME_PLAYER_X

game_key_right = *
        LDAA    #$EF                    ; PB4: D
        STAA    PORT1
        LDAA    KEYBOARD_ROWS
        BITA    #$01
        BNE     game_key_fire
        LDAA    GAME_PLAYER_X
        CMPA    #$1F
        BCC     game_key_fire
        INCA
        STAA    GAME_PLAYER_X

game_key_fire = *
        LDAA    #$7F                    ; PB7: Space
        STAA    PORT1
        LDAA    KEYBOARD_ROWS
        BITA    #$08
        BNE     game_fire_release
        LDAA    GAME_FIRE_LATCH
        BNE     game_keyboard_done
        LDAA    #$01
        STAA    GAME_FIRE_LATCH
        LDAA    GAME_BULLET_ACTIVE
        BNE     game_keyboard_done
        LDAA    GAME_PLAYER_X
        STAA    GAME_BULLET_X
        LDAA    #$06
        STAA    GAME_BULLET_Y
        LDAA    #$01
        STAA    GAME_BULLET_ACTIVE
        BRA     game_keyboard_done

game_fire_release = *
        CLRA
        STAA    GAME_FIRE_LATCH

game_keyboard_done = *
        LDAA    #$FF
        STAA    PORT1
        RTS

; Move the single shot one row per update. It is removed at the top of the
; playfield or immediately after a hit.
game_bullet_update = *
        LDAA    GAME_BULLET_ACTIVE
        BEQ     game_bullet_done
        LDAA    GAME_BULLET_Y
        BEQ     game_bullet_remove
        DECA
        STAA    GAME_BULLET_Y
        JSR     game_bullet_collision
        RTS

game_bullet_remove = *
        CLRA
        STAA    GAME_BULLET_ACTIVE
game_bullet_done = *
        RTS

; The five columns are four cells apart. The top and bottom rows use separate
; five-bit masks so every shot can remove one invader without a table scan.
game_bullet_collision = *
        LDAA    GAME_BULLET_Y
        CMPA    GAME_INVADER_ROW
        BEQ     game_collision_top
        LDAA    GAME_INVADER_ROW
        ADDA    #$02
        CMPA    GAME_BULLET_Y
        BEQ     game_collision_bottom
        RTS

game_collision_top = *
        LDAA    GAME_INVADER_X
        STAA    GAME_COLLISION_X
        LDAA    #$01
        STAA    GAME_COLLISION_MASK
        LDAB    #$05
game_collision_top_loop = *
        LDAA    GAME_COLLISION_X
        CMPA    GAME_BULLET_X
        BNE     game_collision_top_next
        LDAA    GAME_ALIVE_TOP
        ANDA    GAME_COLLISION_MASK
        BEQ     game_collision_top_next
        LDAA    GAME_ALIVE_TOP
        EORA    GAME_COLLISION_MASK
        STAA    GAME_ALIVE_TOP
        JSR     game_add_score
        CLRA
        STAA    GAME_BULLET_ACTIVE
        JSR     game_check_round
        RTS
game_collision_top_next = *
        LDAA    GAME_COLLISION_X
        ADDA    #$04
        STAA    GAME_COLLISION_X
        LDAA    GAME_COLLISION_MASK
        ASLA
        STAA    GAME_COLLISION_MASK
        DECB
        BNE     game_collision_top_loop
        RTS

game_collision_bottom = *
        LDAA    GAME_INVADER_X
        STAA    GAME_COLLISION_X
        LDAA    #$01
        STAA    GAME_COLLISION_MASK
        LDAB    #$05
game_collision_bottom_loop = *
        LDAA    GAME_COLLISION_X
        CMPA    GAME_BULLET_X
        BNE     game_collision_bottom_next
        LDAA    GAME_ALIVE_BOTTOM
        ANDA    GAME_COLLISION_MASK
        BEQ     game_collision_bottom_next
        LDAA    GAME_ALIVE_BOTTOM
        EORA    GAME_COLLISION_MASK
        STAA    GAME_ALIVE_BOTTOM
        JSR     game_add_score
        CLRA
        STAA    GAME_BULLET_ACTIVE
        JSR     game_check_round
        RTS
game_collision_bottom_next = *
        LDAA    GAME_COLLISION_X
        ADDA    #$04
        STAA    GAME_COLLISION_X
        LDAA    GAME_COLLISION_MASK
        ASLA
        STAA    GAME_COLLISION_MASK
        DECB
        BNE     game_collision_bottom_loop
        RTS

game_add_score = *
        LDAA    GAME_SCORE_LO
        ADDA    #$0A
        STAA    GAME_SCORE_LO
        BCC     game_add_score_done
        INC     GAME_SCORE_HI
game_add_score_done = *
        RTS

game_check_round = *
        LDAA    GAME_ALIVE_TOP
        ORAA    GAME_ALIVE_BOTTOM
        BNE     game_check_round_done
        JSR     game_reset_formation
game_check_round_done = *
        RTS

; Move the formation every sixteen timer events. At either horizontal edge it
; descends one row and reverses direction. Reaching the player costs a life
; and restarts the formation, keeping the prototype continuously playable.
game_invader_update = *
        INC     GAME_INVADER_TICK
        LDAA    GAME_INVADER_TICK
        CMPA    #$10
        BCS     game_invader_done
        CLRA
        STAA    GAME_INVADER_TICK

        LDAA    GAME_INVADER_DIR
        BEQ     game_invader_left
        LDAA    GAME_INVADER_X
        CMPA    #$0E
        BCC     game_invader_edge_right
        INCA
        STAA    GAME_INVADER_X
        RTS
game_invader_edge_right = *
        CLRA
        STAA    GAME_INVADER_DIR
        JSR     game_invader_descend
        RTS

game_invader_left = *
        LDAA    GAME_INVADER_X
        BEQ     game_invader_edge_left
        DECA
        STAA    GAME_INVADER_X
        RTS
game_invader_edge_left = *
        LDAA    #$01
        STAA    GAME_INVADER_DIR
        JSR     game_invader_descend
game_invader_done = *
        RTS

game_invader_descend = *
        INC     GAME_INVADER_ROW
        LDAA    GAME_INVADER_ROW
        CMPA    #$05
        BCS     game_invader_descend_done
        JSR     game_lose_life
game_invader_descend_done = *
        RTS

game_lose_life = *
        LDAA    GAME_LIVES
        BEQ     game_lose_reset_lives
        DECA
        STAA    GAME_LIVES
        BNE     game_lose_reset_formation
game_lose_reset_lives = *
        LDAA    #$03
        STAA    GAME_LIVES
game_lose_reset_formation = *
        JSR     game_reset_formation
        RTS

game_reset_formation = *
        LDAA    #$1F
        STAA    GAME_ALIVE_TOP
        STAA    GAME_ALIVE_BOTTOM
        LDAA    #$04
        STAA    GAME_INVADER_X
        CLRA
        STAA    GAME_INVADER_ROW
        LDAA    #$01
        STAA    GAME_INVADER_DIR
        CLRA
        STAA    GAME_INVADER_TICK
        STAA    GAME_BULLET_ACTIVE
        RTS

; Clear and redraw only the eight-row playfield. The screen remains in the
; stock map, so the MC-10 VDG and CPU share the internal screen RAM normally.
game_render = *
        LDAA    #$20
        LDX     #SCREEN+192
        LDAB    #$00
game_render_clear = *
        STAA    0,X
        INX
        INCB
        BNE     game_render_clear

        LDAA    GAME_ALIVE_TOP
        STAA    GAME_RENDER_MASK
        CLRA
        STAA    GAME_RENDER_COLUMN
        LDAA    GAME_INVADER_X
        STAA    GAME_RENDER_X
        CLRA
        STAA    GAME_RENDER_TEMP
game_render_top_loop = *
        LDAA    GAME_RENDER_MASK
        BITA    #$01
        BEQ     game_render_top_next
        JSR     game_draw_invader
game_render_top_next = *
        LDAA    GAME_RENDER_MASK
        LSRA
        STAA    GAME_RENDER_MASK
        LDAA    GAME_RENDER_X
        ADDA    #$04
        STAA    GAME_RENDER_X
        LDAA    GAME_RENDER_COLUMN
        INCA
        STAA    GAME_RENDER_COLUMN
        CMPA    #$05
        BCS     game_render_top_loop

        LDAA    GAME_ALIVE_BOTTOM
        STAA    GAME_RENDER_MASK
        CLRA
        STAA    GAME_RENDER_COLUMN
        LDAA    GAME_INVADER_X
        STAA    GAME_RENDER_X
        LDAA    GAME_INVADER_ROW
        ADDA    #$02
        STAA    GAME_RENDER_TEMP
game_render_bottom_loop = *
        LDAA    GAME_RENDER_MASK
        BITA    #$01
        BEQ     game_render_bottom_next
        JSR     game_draw_invader
game_render_bottom_next = *
        LDAA    GAME_RENDER_MASK
        LSRA
        STAA    GAME_RENDER_MASK
        LDAA    GAME_RENDER_X
        ADDA    #$04
        STAA    GAME_RENDER_X
        LDAA    GAME_RENDER_COLUMN
        INCA
        STAA    GAME_RENDER_COLUMN
        CMPA    #$05
        BCS     game_render_bottom_loop

        JSR     game_draw_bullet
        JSR     game_draw_player
        RTS

game_draw_invader = *
        LDAA    GAME_RENDER_TEMP
        TAB
        LDX     #playfield_row_offsets
        ABX
        LDAB    0,X
        LDX     #SCREEN+192
        ABX
        LDAB    GAME_RENDER_X
        ABX
        LDAA    #$17                    ; W-shaped invader glyph
        STAA    0,X
        RTS

game_draw_bullet = *
        LDAA    GAME_BULLET_ACTIVE
        BEQ     game_draw_bullet_done
        LDAA    GAME_BULLET_Y
        TAB
        LDX     #playfield_row_offsets
        ABX
        LDAA    0,X
        STAA    GAME_RENDER_TEMP
        LDX     #SCREEN+192
        LDAB    GAME_RENDER_TEMP
        ABX
        LDAB    GAME_BULLET_X
        ABX
        LDAA    #$2A                    ; asterisk bullet
        STAA    0,X
game_draw_bullet_done = *
        RTS

game_draw_player = *
        LDAA    #$07                    ; bottom playfield row
        TAB
        LDX     #playfield_row_offsets
        ABX
        LDAA    0,X
        STAA    GAME_RENDER_TEMP
        LDX     #SCREEN+192
        LDAB    GAME_RENDER_TEMP
        ABX
        LDAB    GAME_PLAYER_X
        ABX
        LDAA    #$01                    ; A-shaped player ship
        STAA    0,X
        RTS

game_hud_update = *
        LDAA    GAME_SCORE_HI
        LSRA
        LSRA
        LSRA
        LSRA
        JSR     hex_ascii_nibble
        STAA    SCREEN+167
        LDAA    GAME_SCORE_HI
        JSR     hex_ascii_nibble
        STAA    SCREEN+168
        LDAA    GAME_SCORE_LO
        LSRA
        LSRA
        LSRA
        LSRA
        JSR     hex_ascii_nibble
        STAA    SCREEN+169
        LDAA    GAME_SCORE_LO
        JSR     hex_ascii_nibble
        STAA    SCREEN+170
        LDAA    GAME_LIVES
        ADDA    #$30
        STAA    SCREEN+179
        RTS

game_initialize = *
        CLRA
        STAA    GAME_SCORE_LO
        STAA    GAME_SCORE_HI
        LDAA    #$03
        STAA    GAME_LIVES
        LDAA    #$0F
        STAA    GAME_PLAYER_X
        CLRA
        STAA    GAME_BULLET_ACTIVE
        STAA    GAME_FIRE_LATCH
        JSR     game_reset_formation
        JSR     game_write_hud
        JSR     game_write_controls
        JSR     game_render
        RTS

; Convert the low nibble of A to an MC-10 alpha-mode hexadecimal character.
; Digits retain their screen codes; A-F use alpha codes 1-6.
hex_ascii_nibble = *
        ANDA    #$0F
        CMPA    #$0A
        BCS     hex_ascii_digit
        SUBA    #$09
        RTS
hex_ascii_digit = *
        ADDA    #$30
        RTS

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

; Write the static game HUD and controls. Runtime updates replace the score
; digits at SCREEN+167..170 and the lives digit at SCREEN+179.
game_write_hud = *
        LDX     #game_hud_text
        LDAB    #$14
game_hud_loop = *
        LDAA    0,X
game_hud_store = *
        STAA    SCREEN+160
        INX
        INC     game_hud_store+2
        DECB
        BNE     game_hud_loop
        LDAA    #$A0
        STAA    game_hud_store+2
        RTS

game_write_controls = *
        LDX     #game_controls_text
        LDAB    #$13
game_controls_loop = *
        LDAA    0,X
game_controls_store = *
        STAA    SCREEN+480
        INX
        INC     game_controls_store+2
        DECB
        BNE     game_controls_loop
        LDAA    #$E0
        STAA    game_controls_store+2
        RTS

timer_wait_text = *
        DB      $14,$09,$0D,$05,$12,$3A,$20,$17,$01,$09,$14,$20
timer_ok_text = *
        DB      $14,$09,$0D,$05,$12,$3A,$20,$0F,$0B,$20,$20,$20
timer_fail_text = *
        DB      $14,$09,$0D,$05,$12,$3A,$20,$06,$01,$09,$0C,$20

; Screen-row and formation-column offsets used by the indexed renderer.
playfield_row_offsets = *
        DB      $00,$20,$40,$60,$80,$A0,$C0,$E0

; "SCORE: 0000 LIVES: 3" and "A/D MOVE SPACE FIRE" in MC-10 alpha codes.
game_hud_text = *
        DB      $13,$03,$0F,$12,$05,$3A,$20,$30,$30,$30,$30,$20
        DB      $0C,$09,$16,$05,$13,$3A,$20,$33
game_controls_text = *
        DB      $01,$2F,$04,$20,$0D,$0F,$16,$05,$20,$13,$10,$01,$03,$05
        DB      $20,$06,$09,$12,$05
