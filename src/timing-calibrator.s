; MC-10 field-timing calibrator.
;
; The stock MC-10 does not expose the MC6847 FS signal to the CPU, so this
; program cannot decide which phase produces the smallest visible tear by
; itself. It emits a P2.0 marker at every MC6803 output compare for external
; measurement, and provides one operator-facing calibration witness plus two
; advanced diagnostics:
;
;   default: a full-width CG3 band moves with W/S as the candidate phase is
;            changed. Moving the band beyond the visible raster marks a phase
;            candidate for the render-safe interval.
;   M mode 2: a CG3 rectangle advances once per compare. A period error makes
;             the update phase drift relative to the display raster.
;   M mode 3: the compare phase is swept across one field while a rectangle
;             moves through the display. P pauses and resumes the sweep so the
;             operator can inspect the least-disrupted phase. While paused,
;             A/D changes the rectangle height and W/S moves its vertical bias.
;
; The visual modes are deliberately diagnostic, not a claim that the program
; has read FS. Use P2.0 and MC6847 FS as the two channels of a scope or logic
; analyzer when an absolute phase measurement is required.

        NAM     MC10-FS-CALIBRATOR
        CPU     6803
        OUTPUT  HEX

SCREEN          EQU     $4000
VIDEO_MODE      EQU     $BFFF
CG3_GYBR        EQU     $24
TIMER_CSR       EQU     $0008
TIMER_COUNTER   EQU     $0009
TIMER_COMPARE   EQU     $000B
TIMER_DDR2      EQU     $0001
TIMER_PORT2     EQU     $0003
TIMER_OCF_VECTOR EQU    $4206
KEYBOARD_ROWS   EQU     $BFFF
CAL_DEFAULT_PERIOD EQU  $3A56
CAL_DEFAULT_PHASE  EQU  $0000
BACKGROUND_BYTE EQU     $AA             ; CG3 GYBR blue, two bits 10

; CG3 visual witness geometry. All X coordinates are multiples of four so a
; rectangle is written as complete packed CG3 bytes.
CAL_RECT_BYTES  EQU     $04             ; 16 pixels
CAL_RECT_HEIGHT EQU     $08
CAL_SWEEP_HEIGHT_MIN EQU $04
CAL_SWEEP_HEIGHT_MAX EQU $30
CAL_SWEEP_OFFSET_MIN EQU $A0         ; -$60 rows, permits a fully offscreen box
CAL_SWEEP_OFFSET_MAX EQU $60         ; +$60 rows, permits a fully offscreen box
CAL_RECT_SKIP   EQU     $001C           ; 32-byte line minus four bytes
CAL_DRIFT_STEP  EQU     $04
CAL_BAND_HEIGHT EQU     $04             ; full-width manual calibration band
CAL_MANUAL_PHASE_STEP EQU $0270         ; about 1/24 field per W/S press
CAL_MANUAL_TOP_OFFSCREEN EQU $FC        ; -4, one band height above row 0
CAL_MANUAL_BOTTOM_OFFSCREEN EQU $60     ; row 96, immediately below surface
CAL_SWEEP_STEP  EQU     $0040
CAL_SWEEP_HOLD_FRAMES EQU $08
CAL_SWEEP_START EQU     $E2D5           ; -$1D2B, half a modeled field
CAL_SWEEP_END   EQU     $1D2B

; Direct-page state. The stack remains below $00DF.
CAL_PERIOD_H    EQU     $00E0
CAL_PERIOD_L    EQU     $00E1
CAL_PHASE_H     EQU     $00E2       ; signed two's-complement E-clock offset
CAL_PHASE_L     EQU     $00E3
CAL_EVENTS_H    EQU     $00E4
CAL_EVENTS_L    EQU     $00E5
CAL_MARKER      EQU     $00E6
CAL_KEY_LATCH   EQU     $00E7       ; A,D,W,S,R,Space,M,P edge latches
CAL_DIRTY       EQU     $00E8
CAL_TEMP        EQU     $00E9
CAL_TEMP2       EQU     $00EA
CAL_TEXT_H      EQU     $00EB
CAL_TEXT_L      EQU     $00EC
CAL_SCREEN_H    EQU     $00ED
CAL_SCREEN_L    EQU     $00EE
CAL_VALUE_H     EQU     $00EF
CAL_VALUE_L     EQU     $00F0
CAL_MODE        EQU     $00F1       ; 0=manual band, 1=alpha, 2=drift, 3=sweep
CAL_RECT_X      EQU     $00F2
CAL_RECT_Y      EQU     $00F3
CAL_RECT_OLD_X  EQU     $00F4
CAL_RECT_OLD_Y  EQU     $00F5
CAL_RECT_BYTE   EQU     $00F6
CAL_SWEEP_ACTIVE EQU    $00F7
CAL_SWEEP_HOLD  EQU     $00F8
CAL_SWEEP_DIR   EQU     $00F9       ; 1=phase increasing, 0=decreasing
CAL_SWEEP_Y     EQU     $00FA
CAL_SWEEP_HEIGHT_STATE EQU $00FB     ; sweep rectangle height in CG3 rows
CAL_SWEEP_OFFSET EQU $00FC         ; signed vertical bias, -$60..+$60

        *       = $5000

start = *
        SEI
        LDS     #$00DF

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
        STAA    CAL_MODE                    ; manual band is the default workflow
        STAA    CAL_SWEEP_ACTIVE

        ; Start with the operator-facing manual band. The vector is installed
        ; only after screen initialization because it lives in screen RAM at
        ; $4206-$4208.
        JSR     cal_visual_initialize
        JSR     cal_install_vector
        JSR     cal_rearm_locked
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
        JSR     cal_rearm_locked
        CLI
        RTS

cal_rearm_locked = *
        LDAA    TIMER_CSR
        LDD     TIMER_COUNTER
        ADDD    CAL_PERIOD_H
        ADDD    CAL_PHASE_H
        STD     TIMER_COMPARE
        LDAA    #$08
        STAA    TIMER_CSR
        RTS

cal_install_vector = *
        LDAA    #$7E
        STAA    TIMER_OCF_VECTOR
        LDX     #cal_timer_isr
        STX     TIMER_OCF_VECTOR+1
        RTS

; One short output-compare handler. P2.0 is the external marker. The
; foreground loop performs all screen writes and phase-sweep work.
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

; A/D changes period by one E clock outside sweep mode. W/S changes phase by
; eight E clocks in the alpha and drift modes, and by one visual band step in
; manual mode. In sweep mode A/D changes the red box height and W/S changes
; its signed vertical bias. Pause with P before making geometry adjustments
; when inspecting one fixed candidate. R re-arms from the current counter.
; M cycles manual, alpha, drift, and sweep modes. P pauses or resumes the
; phase sweep in mode 3.
; Keys are edge-triggered; release a key before the next adjustment.
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
        LDAA    CAL_MODE
        CMPA    #$03
        BEQ     cal_key_a_sweep
        LDD     CAL_PERIOD_H
        SUBD    #$0001
        STD     CAL_PERIOD_H
        JSR     cal_adjusted
        BRA     cal_key_d
cal_key_a_sweep = *
        LDAA    CAL_SWEEP_HEIGHT_STATE
        CMPA    #CAL_SWEEP_HEIGHT_MIN
        BCS     cal_key_d
        BEQ     cal_key_d
        SUBA    #$04
        STAA    CAL_SWEEP_HEIGHT_STATE
        JSR     cal_sweep_redraw
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
        LDAA    CAL_MODE
        CMPA    #$03
        BEQ     cal_key_d_sweep
        LDD     CAL_PERIOD_H
        ADDD    #$0001
        STD     CAL_PERIOD_H
        JSR     cal_adjusted
        BRA     cal_key_w
cal_key_d_sweep = *
        LDAA    CAL_SWEEP_HEIGHT_STATE
        CMPA    #CAL_SWEEP_HEIGHT_MAX
        BCC     cal_key_w
        ADDA    #$04
        STAA    CAL_SWEEP_HEIGHT_STATE
        JSR     cal_sweep_redraw
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
        LDAA    CAL_MODE
        BEQ     cal_key_w_manual
        CMPA    #$03
        BEQ     cal_key_w_sweep
        LDD     CAL_PHASE_H
        SUBD    #$0008
        STD     CAL_PHASE_H
        JSR     cal_adjusted
        BRA     cal_key_s
cal_key_w_sweep = *
        LDAA    CAL_SWEEP_OFFSET
        SUBA    #$04
        CMPA    #CAL_SWEEP_OFFSET_MAX
        BCS     cal_key_w_sweep_store
        BEQ     cal_key_w_sweep_store
        CMPA    #CAL_SWEEP_OFFSET_MIN
        BCS     cal_key_w_sweep_clamp
        BRA     cal_key_w_sweep_store
cal_key_w_sweep_clamp = *
        LDAA    #CAL_SWEEP_OFFSET_MIN
cal_key_w_sweep_store = *
        STAA    CAL_SWEEP_OFFSET
        JSR     cal_sweep_redraw
        BRA     cal_key_s
cal_key_w_manual = *
        LDD     CAL_PHASE_H
        SUBD    #CAL_MANUAL_PHASE_STEP
        STD     CAL_PHASE_H
        LDAA    CAL_RECT_Y
        CMPA    #CAL_MANUAL_TOP_OFFSCREEN
        BEQ     cal_key_w_manual_wrap
        SUBA    #CAL_BAND_HEIGHT
        BRA     cal_key_w_manual_store
cal_key_w_manual_wrap = *
        LDAA    #CAL_MANUAL_BOTTOM_OFFSCREEN
cal_key_w_manual_store = *
        STAA    CAL_RECT_Y
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
        LDAA    CAL_MODE
        BEQ     cal_key_s_manual
        CMPA    #$03
        BEQ     cal_key_s_sweep
        LDD     CAL_PHASE_H
        ADDD    #$0008
        STD     CAL_PHASE_H
        JSR     cal_adjusted
        BRA     cal_key_r
cal_key_s_sweep = *
        LDAA    CAL_SWEEP_OFFSET
        ADDA    #$04
        CMPA    #CAL_SWEEP_OFFSET_MAX
        BCS     cal_key_s_sweep_store
        BEQ     cal_key_s_sweep_store
        CMPA    #CAL_SWEEP_OFFSET_MIN
        BCS     cal_key_s_sweep_clamp
        BRA     cal_key_s_sweep_store
cal_key_s_sweep_clamp = *
        LDAA    #CAL_SWEEP_OFFSET_MAX
cal_key_s_sweep_store = *
        STAA    CAL_SWEEP_OFFSET
        JSR     cal_sweep_redraw
        BRA     cal_key_r
cal_key_s_manual = *
        LDD     CAL_PHASE_H
        ADDD    #CAL_MANUAL_PHASE_STEP
        STD     CAL_PHASE_H
        LDAA    CAL_RECT_Y
        CMPA    #CAL_MANUAL_BOTTOM_OFFSCREEN
        BEQ     cal_key_s_manual_wrap
        ADDA    #CAL_BAND_HEIGHT
        BRA     cal_key_s_manual_store
cal_key_s_manual_wrap = *
        LDAA    #CAL_MANUAL_TOP_OFFSCREEN
cal_key_s_manual_store = *
        STAA    CAL_RECT_Y
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
        BNE     cal_key_m
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
        BRA     cal_key_m
cal_key_space_up = *
        LDAA    CAL_KEY_LATCH
        ANDA    #$DF
        STAA    CAL_KEY_LATCH
cal_key_m = *
        LDAA    #$DF                    ; M: PB5/PA1
        STAA    $0002
        LDAA    KEYBOARD_ROWS
        BITA    #$02
        BNE     cal_key_m_up
        LDAA    CAL_KEY_LATCH
        BITA    #$40
        BNE     cal_key_p
        ORAA    #$40
        STAA    CAL_KEY_LATCH
        JSR     cal_mode_cycle
        BRA     cal_key_p
cal_key_m_up = *
        LDAA    CAL_KEY_LATCH
        ANDA    #$BF
        STAA    CAL_KEY_LATCH
cal_key_p = *
        LDAA    #$FE                    ; P: PB0/PA2
        STAA    $0002
        LDAA    KEYBOARD_ROWS
        BITA    #$04
        BNE     cal_key_p_up
        LDAA    CAL_KEY_LATCH
        BITA    #$80
        BNE     cal_keyboard_done
        ORAA    #$80
        STAA    CAL_KEY_LATCH
        LDAA    CAL_MODE
        CMPA    #$03
        BNE     cal_key_p_done
        LDAA    CAL_SWEEP_ACTIVE
        EORA    #$01
        STAA    CAL_SWEEP_ACTIVE
        LDAA    #$01
        STAA    CAL_DIRTY
cal_key_p_done = *
        BRA     cal_keyboard_done
cal_key_p_up = *
        LDAA    CAL_KEY_LATCH
        ANDA    #$7F
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

; Cycle manual band -> alpha -> drift -> phase sweep -> manual band. The screen initialization is
; performed with interrupts disabled because CG3 writes can overlap $4206-$4208.
cal_mode_cycle = *
        SEI
        LDAA    CAL_MODE
        INCA
        CMPA    #$04
        BCS     cal_mode_store
        CLRA
cal_mode_store = *
        STAA    CAL_MODE
        CLRA
        STAA    CAL_EVENTS_H
        STAA    CAL_EVENTS_L
        STAA    CAL_MARKER
        STAA    TIMER_PORT2
        LDAA    CAL_MODE
        CMPA    #$01
        BEQ     cal_mode_alpha_screen
        JSR     cal_visual_initialize
        BRA     cal_mode_finish
cal_mode_alpha_screen = *
        JSR     cal_alpha_initialize
cal_mode_finish = *
        JSR     cal_install_vector
        JSR     cal_rearm_locked
        LDAA    #$01
        STAA    CAL_DIRTY
        CLI
        RTS

; Initialize the 32x16 alpha screen and redraw the readable control panel.
cal_alpha_initialize = *
        CLRA
        STAA    VIDEO_MODE
        LDX     #SCREEN
        LDAA    #$20
        LDAB    #$00
cal_clear_alpha_first = *
        STAA    0,X
        INX
        INCB
        BNE     cal_clear_alpha_first
        LDAB    #$00
cal_clear_alpha_second = *
        STAA    0,X
        INX
        INCB
        BNE     cal_clear_alpha_second
        CLRA
        STAA    CAL_SWEEP_ACTIVE
        JSR     cal_write_static
        JSR     cal_update_alpha
        RTS

; Initialize a blue CG3 surface and the current visual witness.
cal_visual_initialize = *
        LDAA    #CG3_GYBR
        STAA    VIDEO_MODE
        JSR     cal_clear_cg3
        LDAA    #CAL_RECT_HEIGHT
        STAA    CAL_SWEEP_HEIGHT_STATE
        CLRA
        STAA    CAL_SWEEP_OFFSET
        LDAA    CAL_MODE
        CMPA    #$03
        BEQ     cal_visual_sweep_init

        CMPA    #$02
        BEQ     cal_visual_drift_init

        ; Manual mode starts with an upper-edge, full-width green band. W/S moves
        ; it four scan rows and changes the candidate phase by about 1/24 field.
        LDAA    #$08
        STAA    CAL_RECT_Y
        STAA    CAL_RECT_OLD_Y
        CLRA
        STAA    CAL_RECT_BYTE
        JSR     cal_draw_band
        RTS

cal_visual_drift_init = *
        LDAA    #CAL_RECT_HEIGHT
        STAA    CAL_SWEEP_HEIGHT_STATE
        LDAA    #$08
        STAA    CAL_RECT_X
        STAA    CAL_RECT_OLD_X
        LDAA    #$2C                    ; center-height drift marker
        STAA    CAL_RECT_Y
        STAA    CAL_RECT_OLD_Y
        CLRA                            ; CG3 green
        STAA    CAL_RECT_BYTE
        CLRA
        STAA    CAL_SWEEP_ACTIVE
        JSR     cal_draw_rect
        RTS

cal_visual_sweep_init = *
        LDAA    #CAL_RECT_HEIGHT
        STAA    CAL_SWEEP_HEIGHT_STATE
        CLRA
        STAA    CAL_SWEEP_OFFSET
        LDD     #CAL_SWEEP_START
        STD     CAL_PHASE_H
        LDAA    #$01
        STAA    CAL_SWEEP_ACTIVE
        STAA    CAL_SWEEP_DIR
        LDAA    #CAL_SWEEP_HOLD_FRAMES
        STAA    CAL_SWEEP_HOLD
        LDAA    #$08
        STAA    CAL_SWEEP_Y
        LDAA    #$38                    ; fixed center X
        STAA    CAL_RECT_X
        STAA    CAL_RECT_OLD_X
        LDAA    CAL_SWEEP_Y
        STAA    CAL_RECT_Y
        STAA    CAL_RECT_OLD_Y
        LDAA    #$FF                    ; CG3 red
        STAA    CAL_RECT_BYTE
        JSR     cal_draw_rect
        RTS

cal_clear_cg3 = *
        LDX     #SCREEN
        LDAA    #BACKGROUND_BYTE
        LDAB    #$00
cal_clear_cg3_page = *
        STAA    0,X
        INX
        INCB
        BNE     cal_clear_cg3_page
        LDAA    #$0C
        STAA    CAL_TEMP
cal_clear_cg3_pages = *
        LDAA    #BACKGROUND_BYTE
        LDAB    #$00
cal_clear_cg3_page_again = *
        STAA    0,X
        INX
        INCB
        BNE     cal_clear_cg3_page_again
        DEC     CAL_TEMP
        BNE     cal_clear_cg3_pages
        RTS

; Draw a full-width horizontal band. CAL_RECT_Y is a wrapped manual visual
; coordinate: rows $00-$5F are visible, $60 is immediately below the 96-row
; surface, and $FC is one band height above row 0. Other offscreen values draw
; nothing. Manual movement explicitly wraps between $FC and $60.
cal_draw_band = *
        LDAA    CAL_RECT_Y
        CMPA    #$60
        BCS     cal_draw_band_visible
        RTS
cal_draw_band_visible = *
        LDAB    #$20
        MUL
        ADDD    #SCREEN
        STD     CAL_SCREEN_H
        LDAA    #CAL_BAND_HEIGHT
        STAA    CAL_TEMP
cal_draw_band_row = *
        LDX     CAL_SCREEN_H
        LDAA    CAL_RECT_BYTE
        LDAB    #$20
cal_draw_band_byte = *
        STAA    0,X
        INX
        DECB
        BNE     cal_draw_band_byte
        STX     CAL_SCREEN_H
        DEC     CAL_TEMP
        BNE     cal_draw_band_row
        RTS

; Draw a solid 16-pixel packed-CG3 rectangle at CAL_RECT_X/CAL_RECT_Y.
; CAL_RECT_Y is a signed top coordinate for sweep mode. Rows outside the
; 0..95 logical CG3 surface are clipped, allowing the witness to disappear
; above or below the visible picture without writing outside video RAM. The
; height is CAL_SWEEP_HEIGHT_STATE rows. This routine uses the foreground-only
; CAL_TEMP loop byte.
cal_draw_rect = *
        LDAA    CAL_RECT_Y
        BMI     cal_draw_rect_negative
        CMPA    #$60
        BCS     cal_draw_rect_positive
        RTS
cal_draw_rect_positive = *
        LDAB    #$20
        MUL
        ADDD    #SCREEN
        STD     CAL_SCREEN_H
        LDAA    #$60
        SUBA    CAL_RECT_Y
        CMPA    CAL_SWEEP_HEIGHT_STATE
        BCS     cal_draw_rect_positive_count
        LDAA    CAL_SWEEP_HEIGHT_STATE
cal_draw_rect_positive_count = *
        STAA    CAL_TEMP
        BRA     cal_draw_rect_address
cal_draw_rect_negative = *
        COMA
        INCA
        STAA    CAL_TEMP2
        CMPA    CAL_SWEEP_HEIGHT_STATE
        BCS     cal_draw_rect_negative_count
        BEQ     cal_draw_rect_done
        RTS
cal_draw_rect_negative_count = *
        LDAA    CAL_SWEEP_HEIGHT_STATE
        SUBA    CAL_TEMP2
        STAA    CAL_TEMP
        LDD     #SCREEN
        STD     CAL_SCREEN_H
cal_draw_rect_address = *
        LDAA    CAL_RECT_X
        LSRA
        LSRA
        TAB
        CLRA
        LDX     CAL_SCREEN_H
        ABX
        STX     CAL_SCREEN_H
cal_draw_rect_row = *
        LDX     CAL_SCREEN_H
        LDAA    CAL_RECT_BYTE
        LDAB    #CAL_RECT_BYTES
cal_draw_rect_bytes = *
        STAA    0,X
        INX
        DECB
        BNE     cal_draw_rect_bytes
        STX     CAL_SCREEN_H
        LDD     CAL_SCREEN_H
        ADDD    #CAL_RECT_SKIP
        STD     CAL_SCREEN_H
        DEC     CAL_TEMP
        BNE     cal_draw_rect_row
        RTS
cal_draw_rect_done = *
        RTS

; Alpha display updates remain separate from visual witness updates.
cal_update_display = *
        LDAA    CAL_MODE
        CMPA    #$01
        BEQ     cal_update_alpha
        JSR     cal_update_visual
        RTS

cal_update_alpha = *
        JSR     cal_update_mode
        JSR     cal_update_sweep_status
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

; Process one compare event in a visual mode. The vector is restored after
; every CG3 update because it occupies visible CG3 RAM at $4206-$4208.
cal_update_visual = *
        SEI
        LDAA    CAL_MODE
        BEQ     cal_update_manual
        CMPA    #$02
        BEQ     cal_update_drift
        JSR     cal_sweep_tick
        BRA     cal_update_visual_done
cal_update_manual = *
        JSR     cal_manual_tick
        BRA     cal_update_visual_done
cal_update_drift = *
        JSR     cal_drift_tick
cal_update_visual_done = *
        JSR     cal_install_vector
        CLI
        RTS

; Draw the manual band at its current phase-selected position and erase the
; old position only when it changed. Drawing the new band first avoids a blank
; frame at the old position and leaves the initial band untouched on compares
; where the operator has not moved it.
cal_manual_tick = *
        LDAA    CAL_RECT_Y
        STAA    CAL_TEMP2
        LDAA    CAL_RECT_OLD_Y
        CMPA    CAL_TEMP2
        BEQ     cal_manual_tick_done
        LDAA    CAL_TEMP2
        STAA    CAL_RECT_Y
        CLRA
        STAA    CAL_RECT_BYTE
        JSR     cal_draw_band
        LDAA    CAL_RECT_OLD_Y
        STAA    CAL_RECT_Y
        LDAA    #BACKGROUND_BYTE
        STAA    CAL_RECT_BYTE
        JSR     cal_draw_band
        LDAA    CAL_TEMP2
        STAA    CAL_RECT_Y
        LDAA    CAL_RECT_Y
        STAA    CAL_RECT_OLD_Y
cal_manual_tick_done = *
        RTS

; Move the green marker one packed-pixel column per compare. The old marker
; is erased before the new position is drawn. A period mismatch causes this
; update boundary to walk through the continuously refreshed raster.
cal_drift_tick = *
        LDAA    CAL_RECT_X
        STAA    CAL_RECT_OLD_X
        LDAA    CAL_RECT_Y
        STAA    CAL_RECT_OLD_Y
        LDAA    #BACKGROUND_BYTE
        STAA    CAL_RECT_BYTE
        JSR     cal_draw_rect

        LDAA    CAL_RECT_OLD_X
        ADDA    #CAL_DRIFT_STEP
        CMPA    #$70                    ; 112 + 16 reaches the right edge
        BCS     cal_drift_store_x
        LDAA    #$08
cal_drift_store_x = *
        STAA    CAL_RECT_X
        LDAA    #$00                    ; CG3 green
        STAA    CAL_RECT_BYTE
        JSR     cal_draw_rect
        LDAA    CAL_RECT_X
        STAA    CAL_RECT_OLD_X
        LDAA    CAL_RECT_Y
        STAA    CAL_RECT_OLD_Y
        RTS

; Sweep phase candidates over approximately one modeled field. The timer
; compare is re-anchored at each candidate so the visible rectangle tests both
; the candidate phase and the update boundary. The program can scan but cannot
; measure visible tear, so P pauses the current candidate for inspection.
cal_sweep_tick = *
        LDAA    CAL_SWEEP_ACTIVE
        BNE     cal_sweep_active_body
        JMP     cal_sweep_paused
cal_sweep_active_body = *
        LDAA    CAL_RECT_X
        STAA    CAL_RECT_OLD_X
        LDAA    CAL_RECT_Y
        STAA    CAL_RECT_OLD_Y
        LDAA    #BACKGROUND_BYTE
        STAA    CAL_RECT_BYTE
        JSR     cal_draw_rect

        DEC     CAL_SWEEP_HOLD
        BNE     cal_sweep_draw
        LDAA    #CAL_SWEEP_HOLD_FRAMES
        STAA    CAL_SWEEP_HOLD
        LDAA    CAL_SWEEP_DIR
        BEQ     cal_sweep_decrease

        LDD     CAL_PHASE_H
        ADDD    #CAL_SWEEP_STEP
        STD     CAL_PHASE_H
        LDAA    CAL_PHASE_H
        CMPA    #$1D
        BCS     cal_sweep_increase_y
        BNE     cal_sweep_high_end
        LDAA    CAL_PHASE_L
        CMPA    #$2B
        BCS     cal_sweep_increase_y
cal_sweep_high_end = *
        LDD     #CAL_SWEEP_END
        STD     CAL_PHASE_H
        CLRA
        STAA    CAL_SWEEP_DIR
        LDAA    #$50
        STAA    CAL_SWEEP_Y
        JSR     cal_rearm_locked
        BRA     cal_sweep_draw

cal_sweep_increase_y = *
        LDAA    CAL_SWEEP_Y
        ADDA    #$04
        CMPA    #$50
        BCS     cal_sweep_store_y_up
        LDAA    #$50
cal_sweep_store_y_up = *
        STAA    CAL_SWEEP_Y
        JSR     cal_rearm_locked
        BRA     cal_sweep_draw

cal_sweep_decrease = *
        LDD     CAL_PHASE_H
        SUBD    #CAL_SWEEP_STEP
        STD     CAL_PHASE_H
        LDAA    CAL_PHASE_H
        CMPA    #$E2
        BCS     cal_sweep_low_end
        BNE     cal_sweep_decrease_y
        LDAA    CAL_PHASE_L
        CMPA    #$D5
        BCS     cal_sweep_low_end
        BNE     cal_sweep_decrease_y
cal_sweep_low_end = *
        LDD     #CAL_SWEEP_START
        STD     CAL_PHASE_H
        LDAA    #$01
        STAA    CAL_SWEEP_DIR
        LDAA    #$08
        STAA    CAL_SWEEP_Y
        JSR     cal_rearm_locked
        BRA     cal_sweep_draw

cal_sweep_decrease_y = *
        LDAA    CAL_SWEEP_Y
        SUBA    #$04
        CMPA    #$08
        BCS     cal_sweep_store_y_down
        BEQ     cal_sweep_store_y_down
        BRA     cal_sweep_rearm
cal_sweep_store_y_down = *
        LDAA    #$08
        STAA    CAL_SWEEP_Y
cal_sweep_rearm = *
        JSR     cal_rearm_locked

cal_sweep_draw = *
        JSR     cal_sweep_actual_y
        LDAA    #$FF                    ; CG3 red
        STAA    CAL_RECT_BYTE
        JSR     cal_draw_rect
        LDAA    CAL_RECT_X
        STAA    CAL_RECT_OLD_X
        LDAA    CAL_RECT_Y
        STAA    CAL_RECT_OLD_Y
        RTS
; Convert the automatic sweep row plus signed operator bias to a signed
; rectangle origin. The result is deliberately not clamped to the visible
; surface; cal_draw_rect clips the rows so the operator can move the box fully
; offscreen. Positive coordinates are limited to $7F so the high bit remains
; reserved for negative two's-complement coordinates. CAL_TEMP2 is the
; absolute value of a negative bias.
cal_sweep_actual_y = *
        LDAA    CAL_SWEEP_OFFSET
        BPL     cal_sweep_offset_positive
        COMA
        INCA
        STAA    CAL_TEMP2
        LDAA    CAL_SWEEP_Y
        CMPA    CAL_TEMP2
        BCS     cal_sweep_actual_negative
        BEQ     cal_sweep_actual_zero
        SUBA    CAL_TEMP2
        BRA     cal_sweep_actual_store
cal_sweep_actual_negative = *
        LDAA    CAL_TEMP2
        SUBA    CAL_SWEEP_Y
        COMA
        INCA
        BRA     cal_sweep_actual_store
cal_sweep_offset_positive = *
        ADDA    CAL_SWEEP_Y
        BCS     cal_sweep_actual_bottom
        CMPA    #$80
        BCS     cal_sweep_actual_store
cal_sweep_actual_bottom = *
        LDAA    #$7F
        BRA     cal_sweep_actual_store
cal_sweep_actual_zero = *
        CLRA
cal_sweep_actual_store = *
        STAA    CAL_RECT_Y
        RTS

; Redraw the current sweep witness after a height or vertical-bias change.
; The complete CG3 surface is cleared so a larger previous rectangle cannot
; leave stale red rows behind. This is diagnostic-only work, not the game's
; frame renderer.
cal_sweep_redraw = *
        SEI
        JSR     cal_clear_cg3
        JSR     cal_sweep_draw
        JSR     cal_install_vector
        CLI
        LDAA    #$01
        STAA    CAL_DIRTY
        RTS
cal_sweep_paused = *
        ; Keep the current red witness on screen while P is paused. Erasing
        ; before testing CAL_SWEEP_ACTIVE would make pause appear blank.
        RTS

; Static explanatory text. MC-10 alpha codes use A=1..Z=$1A, digits $30..$39.
cal_write_static = *
        LDX     #cal_title
        LDAA    #$00
        LDAB    #$14
        JSR     cal_write_line
        LDX     #cal_manual_help
        LDAA    #$05
        LDAB    #$0F
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

cal_update_mode = *
        LDAA    CAL_MODE
        BEQ     cal_mode_manual_text
        CMPA    #$01
        BEQ     cal_mode_alpha_text
        CMPA    #$02
        BEQ     cal_mode_drift_text
        LDX     #cal_mode_sweep
        BRA     cal_mode_write
cal_mode_manual_text = *
        LDX     #cal_mode_manual
        BRA     cal_mode_write
cal_mode_alpha_text = *
        LDX     #cal_mode_alpha_label
        BRA     cal_mode_write
cal_mode_drift_text = *
        LDX     #cal_mode_drift
cal_mode_write = *
        LDAA    #$01
        LDAB    #$0B
        JSR     cal_write_line
        RTS

cal_update_sweep_status = *
        LDAA    CAL_MODE
        BEQ     cal_manual_status_help
        CMPA    #$01
        BEQ     cal_alpha_status_help
        CMPA    #$03
        BNE     cal_sweep_status_help
        LDAA    CAL_SWEEP_ACTIVE
        BEQ     cal_sweep_status_stop
        LDX     #cal_sweep_run
        BRA     cal_sweep_status_write
cal_sweep_status_stop = *
        LDX     #cal_sweep_stop
        BRA     cal_sweep_status_write
cal_sweep_status_help = *
        LDX     #cal_sweep_help
        BRA     cal_sweep_status_write
cal_alpha_status_help = *
        LDX     #cal_alpha_help
        BRA     cal_sweep_status_write
cal_manual_status_help = *
        LDX     #cal_manual_help
cal_sweep_status_write = *
        LDAA    #$05
        LDAB    #$0F
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
cal_write_line_loop = *
        LDAA    0,X
        INX
        STX     CAL_TEXT_H
        LDX     CAL_SCREEN_H
        STAA    0,X
        INX
        STX     CAL_SCREEN_H
        LDX     CAL_TEXT_H
        LDAB    CAL_TEMP2
        DECB
        STAB    CAL_TEMP2
        BNE     cal_write_line_loop
        RTS

; Refresh a four-digit hexadecimal value.
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
cal_mode_manual = *
        DB      $0D,$0F,$04,$05,$3A,$20,$0D,$01,$0E,$15,$01
cal_mode_alpha_label = *
        DB      $0D,$0F,$04,$05,$3A,$20,$01,$0C,$10,$08,$01
cal_mode_drift = *
        DB      $0D,$0F,$04,$05,$3A,$20,$04,$12,$09,$06,$14
cal_mode_sweep = *
        DB      $0D,$0F,$04,$05,$3A,$20,$13,$17,$05,$05,$10
cal_manual_help = *
        DB      $17,$2F,$13,$20,$0D,$0F,$16,$05,$20,$0D,$20,$0D,$0F,$04,$05
cal_sweep_help = *
        DB      $01,$2F,$04,$20,$10,$05,$12,$09,$0F,$04,$20,$17,$2F,$13,$20
cal_alpha_help = *
        DB      $01,$2F,$04,$20,$10,$05,$12,$09,$0F,$04,$20,$17,$2F,$13,$20
cal_sweep_run = *
        DB      $10,$20,$10,$01,$21,$19,$05,$20,$01,$2F,$04,$20,$13,$26,$20
cal_sweep_stop = *
        DB      $10,$20,$12,$05,$19,$21,$13,$05,$20,$01,$2F,$04,$20,$13,$26
cal_controls_1 = *
        DB      $01,$2F,$04,$20,$10,$05,$12,$09,$0F,$04,$20,$20,$17,$2F,$13,$20,$01,$04,$10,$15,$13,$14
cal_controls_2 = *
        DB      $12,$20,$12,$05,$01,$12,$0D,$20,$20,$13,$10,$01,$03,$05,$20,$12,$05,$13,$05,$14

cal_row_ptrs = *
        DW      SCREEN,SCREEN+$20,SCREEN+$40,SCREEN+$60
        DW      SCREEN+$80,SCREEN+$A0,SCREEN+$C0,SCREEN+$E0
        DW      SCREEN+$100,SCREEN+$120,SCREEN+$140,SCREEN+$160
        DW      SCREEN+$180,SCREEN+$1A0,SCREEN+$1C0,SCREEN+$1E0
