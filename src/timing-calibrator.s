; MC-10 field-timing calibrator.
;
; This is an external-instrument helper. The stock MC-10 does not expose the
; MC6847 FS signal to the CPU, so the program cannot decide which phase is
; correct by itself. It emits a P2.0 marker at every MC6803 output compare;
; use that marker and the MC6847 FS pin on a two-channel scope or logic
; analyzer, then adjust the period and phase while this program runs.

        NAM     MC10-FS-CALIBRATOR
        CPU     6803
        OUTPUT  HEX

SCREEN          EQU     $4000
VIDEO_MODE      EQU     $BFFF
TIMER_CSR       EQU     $0008
TIMER_COUNTER   EQU     $0009
TIMER_COMPARE   EQU     $000B
TIMER_DDR2      EQU     $0001
TIMER_PORT2    EQU      $0003
TIMER_OCF_VECTOR EQU    $4206
KEYBOARD_ROWS   EQU     $BFFF
CAL_DEFAULT_PERIOD EQU  $3A56
CAL_DEFAULT_PHASE  EQU  $0000

; Direct-page state. The stack remains below $00DF.
CAL_PERIOD_H    EQU     $00E0
CAL_PERIOD_L    EQU     $00E1
CAL_PHASE_H     EQU     $00E2       ; signed two's-complement E-clock offset
CAL_PHASE_L     EQU     $00E3
CAL_EVENTS_H    EQU     $00E4
CAL_EVENTS_L    EQU     $00E5
CAL_MARKER      EQU     $00E6
CAL_KEY_LATCH   EQU     $00E7
CAL_DIRTY       EQU     $00E8
CAL_TEMP        EQU     $00E9
CAL_TEMP2       EQU     $00EA
CAL_TEXT_H      EQU     $00EB
CAL_TEXT_L      EQU     $00EC
CAL_SCREEN_H    EQU     $00ED
CAL_SCREEN_L    EQU     $00EE
CAL_VALUE_H     EQU     $00EF
CAL_VALUE_L     EQU     $00F0

        *       = $5000

start = *
        SEI
        LDS     #$00DF
        CLRA
        STAA    VIDEO_MODE

        ; Clear the 32x16 alpha screen.
        LDX     #SCREEN
        LDAA    #$20
        LDAB    #$00
cal_clear_first = *
        STAA    0,X
        INX
        INCB
        BNE     cal_clear_first
        LDAB    #$00
cal_clear_second = *
        STAA    0,X
        INX
        INCB
        BNE     cal_clear_second

        LDD     #CAL_DEFAULT_PERIOD
        STD     CAL_PERIOD_H
        LDD     #CAL_DEFAULT_PHASE
        STD     CAL_PHASE_H
        CLRA
        STAA    CAL_EVENTS_H
        STAA    CAL_EVENTS_L
        STAA    CAL_MARKER
        STAA    CAL_KEY_LATCH
        STAA    CAL_DIRTY

        ; Claim the RAM-resident output-compare vector.
        LDAA    #$7E
        STAA    TIMER_OCF_VECTOR
        LDX     #cal_timer_isr
        STX     TIMER_OCF_VECTOR+1

        LDAA    #$01
        STAA    TIMER_DDR2
        CLRA
        STAA    TIMER_PORT2

        JSR     cal_write_static
        JSR     cal_update_display
        JSR     cal_rearm
        CLI

cal_main_loop = *
        JSR     cal_keyboard
        LDAA    CAL_DIRTY
        BEQ     cal_main_loop
        CLRA
        STAA    CAL_DIRTY
        JSR     cal_update_display
        BRA     cal_main_loop

; Re-anchor the next compare to the current timer plus period plus signed
; phase. Subsequent ISR compares are chained from the previous compare.
cal_rearm = *
        SEI
        LDAA    TIMER_CSR
        LDD     TIMER_COUNTER
        ADDD    CAL_PERIOD_H
        ADDD    CAL_PHASE_H
        STD     TIMER_COMPARE
        LDAA    #$08
        STAA    TIMER_CSR
        CLI
        RTS

; One short output-compare handler. P2.0 is the external marker.
cal_timer_isr = *
        LDAA    TIMER_CSR
        LDD     TIMER_COMPARE
        ADDD    CAL_PERIOD_H
        STD     TIMER_COMPARE
        LDAA    CAL_MARKER
        EORA    #$01
        STAA    CAL_MARKER
        STAA    TIMER_PORT2
        INC     CAL_EVENTS_L
        BNE     cal_timer_done
        INC     CAL_EVENTS_H
cal_timer_done = *
        LDAA    #$01
        STAA    CAL_DIRTY
        RTI

; A/D changes period by one E clock. W/S changes phase by eight E clocks.
; R re-arms from the current counter. Keys are edge-triggered; release a key
; before the next adjustment.
cal_keyboard = *
        LDAA    #$FF
        STAA    $0000

        LDAA    #$FD                    ; A: PB1/PA0
        STAA    $0002
        LDAA    KEYBOARD_ROWS
        BITA    #$01
        BNE     cal_key_a_up
        LDAA    CAL_KEY_LATCH
        BITA    #$01
        BNE     cal_key_d
        ORAA    #$01
        STAA    CAL_KEY_LATCH
        LDD     CAL_PERIOD_H
        SUBD    #$0001
        STD     CAL_PERIOD_H
        JSR     cal_adjusted
        BRA     cal_key_d
cal_key_a_up = *
        LDAA    CAL_KEY_LATCH
        ANDA    #$FE
        STAA    CAL_KEY_LATCH
cal_key_d = *
        LDAA    #$EF                    ; D: PB4/PA0
        STAA    $0002
        LDAA    KEYBOARD_ROWS
        BITA    #$01
        BNE     cal_key_d_up
        LDAA    CAL_KEY_LATCH
        BITA    #$02
        BNE     cal_key_w
        ORAA    #$02
        STAA    CAL_KEY_LATCH
        LDD     CAL_PERIOD_H
        ADDD    #$0001
        STD     CAL_PERIOD_H
        JSR     cal_adjusted
        BRA     cal_key_w
cal_key_d_up = *
        LDAA    CAL_KEY_LATCH
        ANDA    #$FD
        STAA    CAL_KEY_LATCH
cal_key_w = *
        LDAA    #$7F                    ; W: PB7/PA2
        STAA    $0002
        LDAA    KEYBOARD_ROWS
        BITA    #$04
        BNE     cal_key_w_up
        LDAA    CAL_KEY_LATCH
        BITA    #$04
        BNE     cal_key_s
        ORAA    #$04
        STAA    CAL_KEY_LATCH
        LDD     CAL_PHASE_H
        SUBD    #$0008
        STD     CAL_PHASE_H
        JSR     cal_adjusted
        BRA     cal_key_s
cal_key_w_up = *
        LDAA    CAL_KEY_LATCH
        ANDA    #$FB
        STAA    CAL_KEY_LATCH
cal_key_s = *
        LDAA    #$F7                    ; S: PB3/PA2
        STAA    $0002
        LDAA    KEYBOARD_ROWS
        BITA    #$04
        BNE     cal_key_s_up
        LDAA    CAL_KEY_LATCH
        BITA    #$08
        BNE     cal_key_r
        ORAA    #$08
        STAA    CAL_KEY_LATCH
        LDD     CAL_PHASE_H
        ADDD    #$0008
        STD     CAL_PHASE_H
        JSR     cal_adjusted
        BRA     cal_key_r
cal_key_s_up = *
        LDAA    CAL_KEY_LATCH
        ANDA    #$F7
        STAA    CAL_KEY_LATCH
cal_key_r = *
        LDAA    #$FB                    ; R: PB2/PA2
        STAA    $0002
        LDAA    KEYBOARD_ROWS
        BITA    #$04
        BNE     cal_key_r_up
        LDAA    CAL_KEY_LATCH
        BITA    #$10
        BNE     cal_key_space
        ORAA    #$10
        STAA    CAL_KEY_LATCH
        JSR     cal_rearm
        LDAA    #$01
        STAA    CAL_DIRTY
        BRA     cal_key_space
cal_key_r_up = *
        LDAA    CAL_KEY_LATCH
        ANDA    #$EF
        STAA    CAL_KEY_LATCH
cal_key_space = *
        LDAA    #$7F                    ; Space: PB7/PA3
        STAA    $0002
        LDAA    KEYBOARD_ROWS
        BITA    #$08
        BNE     cal_key_space_up
        LDAA    CAL_KEY_LATCH
        BITA    #$20
        BNE     cal_keyboard_done
        ORAA    #$20
        STAA    CAL_KEY_LATCH
        SEI
        CLRA
        STAA    CAL_EVENTS_H
        STAA    CAL_EVENTS_L
        STAA    CAL_MARKER
        STAA    TIMER_PORT2
        CLI
        LDAA    #$01
        STAA    CAL_DIRTY
        BRA     cal_keyboard_done
cal_key_space_up = *
        LDAA    CAL_KEY_LATCH
        ANDA    #$DF
        STAA    CAL_KEY_LATCH
cal_keyboard_done = *
        LDAA    #$FF
        STAA    $0002
        RTS

cal_adjusted = *
        LDAA    #$01
        STAA    CAL_DIRTY
        JSR     cal_rearm
        RTS

; Static explanatory text. MC-10 alpha codes use A=1..Z=$1A, digits $30..$39.
cal_write_static = *
        LDX     #cal_title
        LDAA    #$00
        LDAB    #$14
        JSR     cal_write_line
        LDX     #cal_period_text
        LDAA    #$02
        LDAB    #$08
        JSR     cal_write_line
        LDX     #cal_phase_text
        LDAA    #$03
        LDAB    #$08
        JSR     cal_write_line
        LDX     #cal_events_text
        LDAA    #$04
        LDAB    #$08
        JSR     cal_write_line
        LDX     #cal_controls_1
        LDAA    #$06
        LDAB    #$16
        JSR     cal_write_line
        LDX     #cal_controls_2
        LDAA    #$07
        LDAB    #$14
        JSR     cal_write_line
        RTS

; Write X text bytes to alpha row A, B bytes long.
cal_write_line = *
        STX     CAL_TEXT_H
        STAB    CAL_TEMP2
        ASLA
        TAB
        LDX     #cal_row_ptrs
        ABX
        LDD     0,X
        STD     CAL_SCREEN_H
        LDX     CAL_TEXT_H
        LDAB    CAL_TEMP2
cal_write_line_loop = *
        LDX     CAL_TEXT_H
        LDAA    0,X
        INX
        STX     CAL_TEXT_H
        LDX     CAL_SCREEN_H
        STAA    0,X
        INX
        STX     CAL_SCREEN_H
        LDAB    CAL_TEMP2
        DECB
        STAB    CAL_TEMP2
        BNE     cal_write_line_loop
        RTS

; Refresh the three four-digit hexadecimal values.
cal_update_display = *
        LDD     CAL_PERIOD_H
        LDX     #SCREEN+$48
        STX     CAL_SCREEN_H
        JSR     cal_write_word
        LDD     CAL_PHASE_H
        LDX     #SCREEN+$68
        STX     CAL_SCREEN_H
        JSR     cal_write_word
        LDD     CAL_EVENTS_H
        LDX     #SCREEN+$88
        STX     CAL_SCREEN_H
        JSR     cal_write_word
        RTS

cal_write_word = *
        STD     CAL_VALUE_H
        LDAA    CAL_VALUE_H
        LSRA
        LSRA
        LSRA
        LSRA
        JSR     cal_hex_nibble
        JSR     cal_write_char
        LDAA    CAL_VALUE_H
        JSR     cal_hex_nibble
        JSR     cal_write_char
        LDAA    CAL_VALUE_L
        LSRA
        LSRA
        LSRA
        LSRA
        JSR     cal_hex_nibble
        JSR     cal_write_char
        LDAA    CAL_VALUE_L
        JSR     cal_hex_nibble
        JSR     cal_write_char
        RTS

cal_hex_nibble = *
        ANDA    #$0F
        CMPA    #$0A
        BCS     cal_hex_digit
        SUBA    #$09
        RTS
cal_hex_digit = *
        ADDA    #$30
        RTS

cal_write_char = *
        LDX     CAL_SCREEN_H
        STAA    0,X
        INX
        STX     CAL_SCREEN_H
        RTS

cal_title = *
        DB      $06,$13,$20,$14,$09,$0D,$09,$0E,$07,$20,$03,$01,$0C,$09,$02,$12,$01,$14,$0F,$12
cal_period_text = *
        DB      $10,$05,$12,$09,$0F,$04,$3A,$20
cal_phase_text = *
        DB      $10,$08,$01,$13,$05,$3A,$20,$20
cal_events_text = *
        DB      $05,$16,$05,$0E,$14,$13,$3A,$20
cal_controls_1 = *
        DB      $01,$2F,$04,$20,$10,$05,$12,$09,$0F,$04,$20,$20,$17,$2F,$13,$20,$10,$08,$01,$13,$05,$20
cal_controls_2 = *
        DB      $12,$20,$12,$05,$01,$12,$0D,$20,$20,$13,$10,$01,$03,$05,$20,$12,$05,$13,$05,$14

cal_row_ptrs = *
        DW      SCREEN,SCREEN+$20,SCREEN+$40,SCREEN+$60
        DW      SCREEN+$80,SCREEN+$A0,SCREEN+$C0,SCREEN+$E0
        DW      SCREEN+$100,SCREEN+$120,SCREEN+$140,SCREEN+$160
        DW      SCREEN+$180,SCREEN+$1A0,SCREEN+$1C0,SCREEN+$1E0
