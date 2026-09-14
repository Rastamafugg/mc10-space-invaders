; MC-10 IRQ1 sanity test.
;
; This is a cassette-loadable MC6803 diagnostic, not a programmable ROM image.
; It installs a handler at the MC-10's RAM IRQ1 vector, disables the internal
; timer interrupt enables, enables CPU interrupts, and waits long enough to
; cover many MC6847 fields. If IRQ1 is driven, the handler increments the
; counter and the screen reports ACTIVE. If the counter remains zero, the
; screen reports INACTIVE.

        NAM     MC10-IRQ1-SANITY
        CPU     6803
        OUTPUT  HEX

SCREEN          EQU     $4000
VIDEO_MODE      EQU     $BFFF
TIMER_CSR       EQU     $0008
IRQ1_VECTOR     EQU     $420C

; Direct-page state. These locations remain in the MC-10's internal RAM and
; are also readable by the MAME Lua regression harness.
IRQ1_COUNT      EQU     $00E0
IRQ1_DONE       EQU     $00E1
IRQ1_STATUS     EQU     $00E2       ; 0=wait, 1=inactive, 2=active
IRQ1_TEMP       EQU     $00E3
IRQ1_TEXT_PTR   EQU     $00E4
IRQ1_SCREEN_PTR EQU     $00E6
IRQ1_LENGTH     EQU     $00E8
IRQ1_ROW        EQU     $00E9

        *       = $5000

start = *
        SEI
        LDS     #$00DF

        ; Select stock MC-10 alphanumeric video mode.
        CLRA
        STAA    VIDEO_MODE

        ; Disable timer compare, input-capture, and overflow interrupt
        ; enables. The free-running counter is irrelevant to this test.
        STAA    TIMER_CSR

        ; Clear state before the observation window begins.
        STAA    IRQ1_COUNT
        STAA    IRQ1_DONE
        STAA    IRQ1_STATUS

        ; Clear the 32x16 alpha screen.
        LDAA    #$20
        LDX     #SCREEN
        LDAB    #$00
irq_clear_first = *
        STAA    0,X
        INX
        INCB
        BNE     irq_clear_first
        LDAB    #$00
irq_clear_second = *
        STAA    0,X
        INX
        INCB
        BNE     irq_clear_second

        ; Install a JMP at the MC-10 RAM IRQ1 vector. If the CPU sees an
        ; external IRQ1 assertion while interrupts are enabled, execution
        ; reaches irq1_handler and increments IRQ1_COUNT.
        LDAA    #$7E
        STAA    IRQ1_VECTOR
        LDX     #irq1_handler
        STX     IRQ1_VECTOR+1

        LDX     #irq_title
        LDAA    #$00
        LDAB    #$0F
        JSR     irq_write_line
        LDX     #irq_wait_text
        LDAA    #$02
        LDAB    #$0A
        JSR     irq_write_line
        LDX     #irq_count_text
        LDAA    #$04
        LDAB    #$0C
        JSR     irq_write_line
        JSR     irq_write_count

        ; Allow IRQ1 to be accepted. No timer source is enabled, so a count
        ; change during this loop is attributable to the external IRQ1 pin.
        CLI
        LDAB    #$04
irq_window_outer = *
        LDX     #$FFFF
irq_window_inner = *
        DEX
        BNE     irq_window_inner
        DECB
        BNE     irq_window_outer

        SEI
        LDAA    #$01
        STAA    IRQ1_DONE
        LDAA    IRQ1_COUNT
        BEQ     irq_window_inactive

        LDAA    #$02
        STAA    IRQ1_STATUS
        LDX     #irq_active_text
        LDAA    #$02
        LDAB    #$0E
        JSR     irq_write_line
        BRA     irq_show_count

irq_window_inactive = *
        LDAA    #$01
        STAA    IRQ1_STATUS
        LDX     #irq_inactive_text
        LDAA    #$02
        LDAB    #$0E
        JSR     irq_write_line

irq_show_count = *
        JSR     irq_write_count

        ; Leave the result stable for screen capture and direct memory reads.
irq_result_loop = *
        BRA     irq_result_loop

; IRQ1 handler. The MC6803 stacks the machine state before entering this
; routine, so only the diagnostic byte changes before RTI restores execution.
irq1_handler = *
        INC     IRQ1_COUNT
        RTI

; Write X text bytes to alpha row A. B contains the byte count.
irq_write_line = *
        STAB    IRQ1_LENGTH
        STAA    IRQ1_ROW
        STX     IRQ1_TEXT_PTR

        LDAA    IRQ1_ROW
        ASLA
        TAB
        LDX     #irq_row_ptrs
        ABX
        LDD     0,X
        STD     IRQ1_SCREEN_PTR
        LDX     IRQ1_TEXT_PTR

irq_write_line_loop = *
        LDAA    0,X
        INX
        STX     IRQ1_TEXT_PTR
        LDX     IRQ1_SCREEN_PTR
        STAA    0,X
        INX
        STX     IRQ1_SCREEN_PTR
        LDX     IRQ1_TEXT_PTR
        LDAB    IRQ1_LENGTH
        DECB
        STAB    IRQ1_LENGTH
        BNE     irq_write_line_loop
        RTS

; Display the one-byte handler count as two hexadecimal characters after the
; row-4 prefix. A zero count is the visible and machine-readable proof point.
irq_write_count = *
        LDAA    IRQ1_COUNT
        STAA    IRQ1_TEMP
        LSRA
        LSRA
        LSRA
        LSRA
        JSR     irq_hex_char
        LDX     #SCREEN+$8C
        STAA    0,X
        LDAA    IRQ1_TEMP
        JSR     irq_hex_char
        INX
        STAA    0,X
        RTS

; Convert the low nibble of A to the MC-10 alpha screen code.
irq_hex_char = *
        ANDA    #$0F
        CMPA    #$0A
        BCS     irq_hex_digit
        SUBA    #$09
        RTS
irq_hex_digit = *
        ADDA    #$30
        RTS

irq_title = *
        DB      $0D,$03,$2D,$31,$30,$20,$09,$12,$11,$31,$20,$14,$05,$13,$14
irq_wait_text = *
        DB      $09,$12,$11,$31,$3A,$20,$17,$01,$09,$14
irq_inactive_text = *
        DB      $09,$12,$11,$31,$3A,$20,$09,$0E,$01,$03,$14,$09,$16,$05
irq_active_text = *
        DB      $09,$12,$11,$31,$3A,$20,$01,$03,$14,$09,$16,$05,$20,$20
irq_count_text = *
        DB      $09,$12,$11,$31,$20,$03,$0F,$15,$0E,$14,$3A,$20

irq_row_ptrs = *
        DW      SCREEN,SCREEN+$20,SCREEN+$40,SCREEN+$60
        DW      SCREEN+$80,SCREEN+$A0,SCREEN+$C0,SCREEN+$E0
        DW      SCREEN+$100,SCREEN+$120,SCREEN+$140,SCREEN+$160
        DW      SCREEN+$180,SCREEN+$1A0,SCREEN+$1C0,SCREEN+$1E0
