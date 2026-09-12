; Space Invaders for the Tandy MC-10.
;
; CG3 game target. The previous environment and MCX diagnostic is retained in
; src/environment-test.s and is built with the utility target.
;
; CG3 is 128x96, four-color, two bits per pixel, using 3 KiB at $4000-$4BFF.
; $BFFF=$24 selects CG3 with the MC6847 GYBR color set.

        NAM     SPACE-INVADERS-CG3
        CPU     6803
        OUTPUT  HEX

SCREEN          EQU     $4000
VIDEO_MODE      EQU     $BFFF
CG3_GYBR        EQU     $24
SCREEN_BYTES    EQU     $0C00

; MC6803 timer and keyboard registers.
TIMER_CSR       EQU     $0008
TIMER_COUNTER   EQU     $0009
TIMER_COMPARE   EQU     $000B
TIMER_DDR2      EQU     $0001
TIMER_PORT2     EQU     $0003
TIMER_OCF_VECTOR EQU    $4206
TIMER_PERIOD    EQU     $3A56       ; 14,934 E clocks at 59.923 Hz
PORT1_DDR       EQU     $0000
PORT1           EQU     $0002
KEYBOARD_ROWS   EQU     $BFFF

; Direct-page game state. The stack is kept below the state at $00DF.
GAME_PENDING    EQU     $00E0
GAME_FRAME      EQU     $00E1
GAME_SCORE_0    EQU     $00E2       ; decimal thousands
GAME_SCORE_1    EQU     $00E3       ; decimal hundreds
GAME_SCORE_2    EQU     $00E4       ; decimal tens
GAME_SCORE_3    EQU     $00E5       ; decimal ones
GAME_LIVES      EQU     $00E6
GAME_OVER       EQU     $00E7
GAME_PLAYER_X   EQU     $00E8       ; byte coordinate, four pixels
GAME_BULLET_X   EQU     $00E9
GAME_BULLET_Y   EQU     $00EA
GAME_BULLET_ACTIVE EQU  $00EB
GAME_ALIEN_SHOT_X EQU    $00EC
GAME_ALIEN_SHOT_Y EQU    $00ED
GAME_ALIEN_SHOT_ACTIVE EQU $00EE
GAME_ALIEN_SHOT_TICK EQU  $00EF
GAME_INVADER_X  EQU     $00F0       ; leftmost byte coordinate, 1..8
GAME_INVADER_Y  EQU     $00F1       ; top pixel coordinate
GAME_INVADER_DIR EQU     $00F2       ; 1=right, 0=left
GAME_INVADER_TICK EQU   $00F3
GAME_ANIM       EQU     $00F4
GAME_BONUS_X    EQU     $00F5
GAME_BONUS_ACTIVE EQU   $00F6
GAME_BONUS_DIR  EQU     $00F7
GAME_BONUS_TICK EQU     $00F8
GAME_RNG        EQU     $00F9
GAME_FIRE_LATCH EQU     $00FA
GAME_SHIELDS_ACTIVE EQU $00FB
GAME_RENDER_MODE EQU    $00FC       ; 0=erase, 1=draw
GAME_TICK       EQU     $00FD       ; formation redraw pending
GAME_TEMP       EQU     $00FE
GAME_TEMP2      EQU     $00FF

; Extended working storage in unused MC-10 RAM.
ALIEN_LIVE      EQU     $0100       ; 5 rows x 11 columns, one byte each
WORK_SPRITE     EQU     $0138       ; 16-bit sprite pointer
WORK_ADDR       EQU     $013A       ; 16-bit current screen address
WORK_ROW_PTR    EQU     $013C       ; 16-bit live-array pointer
WORK_SHAPE      EQU     $013E
WORK_COLOR_BASE EQU     $013F
WORK_COLOR_RESULT EQU   $0140
WORK_WIDTH      EQU     $0141
WORK_HEIGHT     EQU     $0142
WORK_COL        EQU     $0143
WORK_ROW        EQU     $0144
WORK_XBYTE      EQU     $0145
WORK_Y         EQU      $0146
WORK_TYPE       EQU     $0147
WORK_DIGIT      EQU     $0148
WORK_TEMP       EQU      $0149
WORK_TEMP2      EQU     $014A
PLOT_X          EQU     $014B
PLOT_Y          EQU     $014C
PLOT_COLOR      EQU     $014D
PLOT_BYTE       EQU     $014E
PLOT_SHIFT      EQU     $014F
PLOT_MASK       EQU     $0150
PLOT_ENCODED    EQU     $0151
WORK_COLOR      EQU     $0152

        *       = $5000

start = *
        SEI
        LDS     #$00DF

        ; Select 128x96 four-color CG3 with the GYBR palette.
        LDAA    #CG3_GYBR
        STAA    VIDEO_MODE

        JSR     game_initialize

        ; The MC-10 has no verified VDG-to-CPU frame interrupt. Use the
        ; MC6803 output compare at the verified MC6847 field cadence.
        JSR     game_install_timer_vector
        CLRA
        STAA    GAME_PENDING
        STAA    GAME_FRAME
        LDAA    TIMER_CSR
        LDD     TIMER_COUNTER
        ADDD    #TIMER_PERIOD
        STD     TIMER_COMPARE
        LDAA    #$01
        STAA    TIMER_DDR2
        CLRA
        STAA    TIMER_PORT2
        LDAA    #$08
        STAA    TIMER_CSR
        CLI

game_main_loop = *
        LDAA    GAME_PENDING
        BEQ     game_main_loop
        SEI
        DEC     GAME_PENDING
        JSR     game_update
        ; CG3 displays the RAM containing the OCF vector. Reinstall the
        ; vector after all screen writes, while interrupts remain masked.
        JSR     game_install_timer_vector
        CLI
        BRA     game_main_loop

game_install_timer_vector = *
        LDAA    #$7E                    ; JMP extended
        STAA    TIMER_OCF_VECTOR
        LDX     #game_timer_isr
        STX     TIMER_OCF_VECTOR+1
        RTS

game_timer_isr = *
        LDAA    TIMER_CSR
        LDD     TIMER_COMPARE
        ADDD    #TIMER_PERIOD
        STD     TIMER_COMPARE
        LDAA    GAME_PENDING
        CMPA    #$FF
        BEQ     game_timer_done
        INCA
        STAA    GAME_PENDING
game_timer_done = *
        RTI

; Initialize CG3 memory and all game state.
game_initialize = *
        LDAA    #CG3_GYBR
        STAA    VIDEO_MODE

        ; Clear 12 pages, $4000-$4BFF.
        LDX     #SCREEN
        CLRA
        LDAA    #$0C
        STAA    WORK_TEMP
        CLRA
        LDAB    #$00
game_clear_screen_loop = *
        STAA    0,X
        INX
        INCB
        BNE     game_clear_screen_loop
        DEC     WORK_TEMP
        BNE     game_clear_screen_loop

        CLRA
        STAA    GAME_FRAME
        STAA    GAME_SCORE_0
        STAA    GAME_SCORE_1
        STAA    GAME_SCORE_2
        STAA    GAME_SCORE_3
        STAA    GAME_OVER
        STAA    GAME_BULLET_ACTIVE
        STAA    GAME_ALIEN_SHOT_ACTIVE
        STAA    GAME_BONUS_ACTIVE
        STAA    GAME_FIRE_LATCH
        STAA    GAME_INVADER_TICK
        STAA    GAME_ALIEN_SHOT_TICK
        STAA    GAME_BONUS_TICK
        STAA    GAME_ANIM
        STAA    GAME_TICK
        LDAA    #$03
        STAA    GAME_LIVES
        LDAA    #$0F
        STAA    GAME_PLAYER_X
        LDAA    #$01
        STAA    GAME_INVADER_X
        STAA    GAME_INVADER_DIR
        STAA    GAME_SHIELDS_ACTIVE
        LDAA    #$05                    ; keep scanline 16 clear for OCF vector
        STAA    GAME_INVADER_Y
        LDAA    #$5A
        STAA    GAME_RNG

        JSR     game_initialize_aliens
        LDAA    #$01
        STAA    GAME_TICK
        LDAA    #$01
        STAA    GAME_RENDER_MODE
        JSR     game_draw_shields
        JSR     game_draw_formation
        JSR     game_draw_player
        JSR     game_draw_score
        JSR     game_draw_lives
        RTS

game_initialize_aliens = *
        LDX     #ALIEN_LIVE
        LDAA    #$01
        LDAB    #$37                    ; 5 x 11
game_initialize_aliens_loop = *
        STAA    0,X
        INX
        DECB
        BNE     game_initialize_aliens_loop
        RTS

; One simulation update per compare event. Dynamic objects are erased using
; their previous positions, persistent shields retain damage in video RAM, and
; the current state is drawn over the black background.
game_update = *
        LDAA    GAME_OVER
        BNE     game_update_done

        ; The formation remains in video RAM between movement events. Erase
        ; its previous position only on the update that will move it. This
        ; keeps the CPU from spending most of every field redrawing 55 aliens.
        CLRA
        STAA    GAME_TICK
        LDAA    GAME_INVADER_TICK
        CMPA    #$0F
        BNE     game_update_no_formation_erase
        LDAA    #$01
        STAA    GAME_TICK
        CLRA
        STAA    GAME_RENDER_MODE
        JSR     game_draw_formation
game_update_no_formation_erase = *
        JSR     game_erase_dynamic
        JSR     game_keyboard
        JSR     game_player_bullet_update
        JSR     game_alien_shot_update
        JSR     game_bonus_update
        JSR     game_invader_update

        INC     GAME_FRAME
        LDAA    GAME_FRAME
        BITA    #$07
        BNE     game_update_draw
        LDAA    GAME_ANIM
        EORA    #$01
        STAA    GAME_ANIM
game_update_draw = *
        LDAA    GAME_TICK
        BEQ     game_update_no_formation_draw
        LDAA    #$01
        STAA    GAME_RENDER_MODE
        JSR     game_draw_formation
game_update_no_formation_draw = *
        JSR     game_draw_dynamic
        JSR     game_draw_score
        JSR     game_draw_lives
game_update_done = *
        RTS

; Keyboard scan for A/D and Space. Rows are active-low and one Port 1 column
; is selected at a time.
game_keyboard = *
        LDAA    #$FF
        STAA    PORT1_DDR

        LDAA    #$FD                    ; PB1/PA0: A
        STAA    PORT1
        LDAA    KEYBOARD_ROWS
        BITA    #$01
        BNE     game_keyboard_right
        LDAA    GAME_PLAYER_X
        BEQ     game_keyboard_right
        DECA
        STAA    GAME_PLAYER_X

game_keyboard_right = *
        LDAA    #$EF                    ; PB4/PA0: D
        STAA    PORT1
        LDAA    KEYBOARD_ROWS
        BITA    #$01
        BNE     game_keyboard_fire
        LDAA    GAME_PLAYER_X
        CMPA    #$1D                    ; player is three bytes wide
        BCC     game_keyboard_fire
        INCA
        STAA    GAME_PLAYER_X

game_keyboard_fire = *
        LDAA    #$7F                    ; PB7/PA3: Space
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
        INCA
        STAA    GAME_BULLET_X
        LDAA    #$4E                    ; above player, below shields
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

; Erase the old moving layer.
game_erase_dynamic = *
        CLRA
        STAA    GAME_RENDER_MODE
        JSR     game_draw_player
        LDAA    GAME_BULLET_ACTIVE
        BEQ     game_erase_no_bullet
        JSR     game_draw_bullet
game_erase_no_bullet = *
        LDAA    GAME_ALIEN_SHOT_ACTIVE
        BEQ     game_erase_no_alien_shot
        JSR     game_draw_alien_shot
game_erase_no_alien_shot = *
        LDAA    GAME_BONUS_ACTIVE
        BEQ     game_erase_done
        JSR     game_draw_bonus
game_erase_done = *
        RTS

game_draw_dynamic = *
        LDAA    #$01
        STAA    GAME_RENDER_MODE
        JSR     game_draw_bullet
        JSR     game_draw_alien_shot
        JSR     game_draw_bonus
        LDAA    GAME_OVER
        BNE     game_draw_dynamic_done
        JSR     game_draw_player
game_draw_dynamic_done = *
        RTS

; Formation renderer: 11 columns by 5 rows, two bytes per alien. The arcade
; order is top octopus row, two crab rows, then two squid rows.
game_draw_formation = *
        LDX     #ALIEN_LIVE
        STX     WORK_ROW_PTR
        CLRA
        STAA    WORK_ROW
        LDAA    GAME_INVADER_Y
        STAA    WORK_Y
        LDAA    #$05
        STAA    GAME_TEMP
game_draw_formation_row = *
        JSR     game_set_row_type
        LDAA    GAME_INVADER_X
        STAA    WORK_XBYTE
        LDAA    #$0B
        STAA    GAME_TEMP2
game_draw_formation_col = *
        LDX     WORK_ROW_PTR
        LDAA    0,X
        BEQ     game_draw_formation_skip
        JSR     game_draw_alien
game_draw_formation_skip = *
        LDX     WORK_ROW_PTR
        INX
        STX     WORK_ROW_PTR
        LDAA    WORK_XBYTE
        ADDA    #$02
        STAA    WORK_XBYTE
        DEC     GAME_TEMP2
        BNE     game_draw_formation_col
        LDAA    WORK_Y
        ADDA    #$06
        STAA    WORK_Y
        INC     WORK_ROW
        DEC     GAME_TEMP
        BNE     game_draw_formation_row
        RTS

game_set_row_type = *
        LDAA    WORK_ROW
        BEQ     game_row_top
        CMPA    #$03
        BCS     game_row_middle
        LDAA    #$02                    ; squid
        STAA    WORK_TYPE
        LDAA    #$01                    ; yellow
        STAA    WORK_COLOR
        BRA     game_row_color_done
game_row_top = *
        CLRA
        STAA    WORK_TYPE              ; octopus
        LDAA    #$03                    ; red
        STAA    WORK_COLOR
        BRA     game_row_color_done
game_row_middle = *
        LDAA    #$01                    ; crab
        STAA    WORK_TYPE
        LDAA    #$02                    ; blue
        STAA    WORK_COLOR
game_row_color_done = *
        LDAA    GAME_RENDER_MODE
        BNE     game_row_type_done
        CLRA
        STAA    WORK_COLOR
game_row_type_done = *
        RTS

game_draw_alien = *
        LDAA    WORK_TYPE
        ASLA
        ADDA    GAME_ANIM
        ASLA
        TAB
        LDX     #alien_sprite_ptrs
        ABX
        LDD     0,X
        STD     WORK_SPRITE
        LDAA    #$02
        STAA    WORK_WIDTH
        LDAA    #$05
        STAA    WORK_HEIGHT
        JSR     game_set_draw_address
        JSR     game_draw_mask_sprite
        RTS

game_draw_player = *
        LDAA    GAME_PLAYER_X
        STAA    WORK_XBYTE
        LDAA    #$52
        STAA    WORK_Y
        LDAA    #$03                    ; red
        STAA    WORK_COLOR
        LDX     #player_sprite
        STX     WORK_SPRITE
        LDAA    #$03
        STAA    WORK_WIDTH
        LDAA    #$05
        STAA    WORK_HEIGHT
        JSR     game_set_draw_address
        JSR     game_draw_mask_sprite
        RTS

game_draw_bullet = *
        LDAA    GAME_BULLET_ACTIVE
        BEQ     game_draw_bullet_done
        LDAA    GAME_BULLET_X
        STAA    WORK_XBYTE
        LDAA    GAME_BULLET_Y
        STAA    WORK_Y
        LDAA    #$02                    ; blue
        STAA    WORK_COLOR
        LDX     #player_bullet_sprite
        STX     WORK_SPRITE
        LDAA    #$01
        STAA    WORK_WIDTH
        LDAA    #$03
        STAA    WORK_HEIGHT
        JSR     game_set_draw_address
        JSR     game_draw_mask_sprite
game_draw_bullet_done = *
        RTS

game_draw_alien_shot = *
        LDAA    GAME_ALIEN_SHOT_ACTIVE
        BEQ     game_draw_alien_shot_done
        LDAA    GAME_ALIEN_SHOT_X
        STAA    WORK_XBYTE
        LDAA    GAME_ALIEN_SHOT_Y
        STAA    WORK_Y
        LDAA    #$03                    ; red
        STAA    WORK_COLOR
        LDX     #alien_shot_sprite
        STX     WORK_SPRITE
        LDAA    #$01
        STAA    WORK_WIDTH
        LDAA    #$03
        STAA    WORK_HEIGHT
        JSR     game_set_draw_address
        JSR     game_draw_mask_sprite
game_draw_alien_shot_done = *
        RTS

game_draw_bonus = *
        LDAA    GAME_BONUS_ACTIVE
        BEQ     game_draw_bonus_done
        LDAA    GAME_BONUS_X
        STAA    WORK_XBYTE
        LDAA    #$02
        STAA    WORK_Y
        LDAA    #$01                    ; yellow
        STAA    WORK_COLOR
        LDX     #bonus_sprite
        STX     WORK_SPRITE
        LDAA    #$02
        STAA    WORK_WIDTH
        LDAA    #$03
        STAA    WORK_HEIGHT
        JSR     game_set_draw_address
        JSR     game_draw_mask_sprite
game_draw_bonus_done = *
        RTS

game_set_draw_address = *
        LDAA    WORK_Y
        ASLA
        TAB
        LDX     #screen_row_ptrs
        ABX
        LDD     0,X
        STD     WORK_ADDR
        LDAB    WORK_XBYTE
        LDX     WORK_ADDR
        ABX
        STX     WORK_ADDR
        RTS

; Draw a byte mask with a selected GYBR color. The low nibble contains one
; bit per pixel in the four-pixel CG3 byte.
game_draw_mask_sprite = *
        ; All moving-object routines use the same renderer for erase and
        ; draw. Force the selected color to the CG3 background during erase.
        LDAA    GAME_RENDER_MODE
        BNE     game_draw_mask_color_ready
        CLRA
        STAA    WORK_COLOR
game_draw_mask_color_ready = *
        LDAA    WORK_HEIGHT
        STAA    WORK_TEMP
game_draw_mask_row = *
        LDAA    WORK_WIDTH
        STAA    WORK_COL
game_draw_mask_col = *
        LDX     WORK_SPRITE
        LDAA    0,X
        INX
        STX     WORK_SPRITE
        JSR     game_colorize_mask_byte
        LDX     WORK_ADDR
        STAA    0,X
        INX
        STX     WORK_ADDR
        DEC     WORK_COL
        BNE     game_draw_mask_col

        LDAA    WORK_WIDTH
        CMPA    #$01
        BEQ     game_draw_mask_step_1
        CMPA    #$02
        BEQ     game_draw_mask_step_2
        LDD     WORK_ADDR
        ADDD    #$001D
        BRA     game_draw_mask_step_done
game_draw_mask_step_1 = *
        LDD     WORK_ADDR
        ADDD    #$001F
        BRA     game_draw_mask_step_done
game_draw_mask_step_2 = *
        LDD     WORK_ADDR
        ADDD    #$001E
game_draw_mask_step_done = *
        STD     WORK_ADDR
        DEC     WORK_TEMP
        BNE     game_draw_mask_row
        RTS

game_colorize_mask_byte = *
        STAA    WORK_SHAPE
        LDAA    WORK_COLOR
        ASLA
        ASLA
        ASLA
        ASLA
        STAA    WORK_COLOR_BASE
        LDAA    WORK_SHAPE
        ANDA    #$0F
        ADDA    WORK_COLOR_BASE
        ; The table is organized as four 16-byte color rows.
        TAB
        LDX     #colorize_table
        ABX
        LDAA    0,X
        RTS

; Initial shield structures are persistent pixels in video RAM. Damage writes
; black pixels into them, producing the arcade-style burrowing holes.
game_draw_shields = *
        LDAA    #$01
        STAA    WORK_COLOR
        LDAA    #$03
        STAA    WORK_WIDTH
        LDAA    #$07
        STAA    WORK_HEIGHT
        LDAA    #$3C
        STAA    WORK_Y
        LDAA    #$04
        STAA    WORK_XBYTE
        LDAA    #$04
        STAA    WORK_TEMP2
game_draw_shields_loop = *
        LDX     #shield_sprite
        STX     WORK_SPRITE
        JSR     game_set_draw_address
        JSR     game_draw_mask_sprite
        LDAA    WORK_XBYTE
        ADDA    #$07
        STAA    WORK_XBYTE
        DEC     WORK_TEMP2
        BNE     game_draw_shields_loop
        RTS

game_clear_shields = *
        CLRA
        STAA    GAME_SHIELDS_ACTIVE
        LDAA    #$03
        STAA    WORK_XBYTE
        LDAA    #$3A
        STAA    WORK_Y
        LDAA    #$1C
        STAA    WORK_WIDTH
        LDAA    #$09
        STAA    WORK_HEIGHT
        JSR     game_clear_rect
        RTS

; Draw the four decimal score digits at the lower left.
game_draw_score = *
        CLRA
        STAA    WORK_XBYTE
        LDAA    #$5A
        STAA    WORK_Y
        LDAA    #$0B
        STAA    WORK_WIDTH
        LDAA    #$06
        STAA    WORK_HEIGHT
        JSR     game_clear_rect
        LDAA    #$01
        STAA    WORK_COLOR
        LDAA    #$5A
        STAA    WORK_Y
        LDAA    GAME_SCORE_0
        STAA    WORK_DIGIT
        LDAA    #$01
        STAA    WORK_XBYTE
        JSR     game_draw_digit
        LDAA    GAME_SCORE_1
        STAA    WORK_DIGIT
        LDAA    #$03
        STAA    WORK_XBYTE
        JSR     game_draw_digit
        LDAA    GAME_SCORE_2
        STAA    WORK_DIGIT
        LDAA    #$05
        STAA    WORK_XBYTE
        JSR     game_draw_digit
        LDAA    GAME_SCORE_3
        STAA    WORK_DIGIT
        LDAA    #$07
        STAA    WORK_XBYTE
        JSR     game_draw_digit
        RTS

game_draw_digit = *
        LDAA    WORK_DIGIT
        ASLA
        TAB
        LDX     #digit_ptrs
        ABX
        LDD     0,X
        STD     WORK_SPRITE
        LDAA    #$01
        STAA    WORK_WIDTH
        LDAA    #$05
        STAA    WORK_HEIGHT
        JSR     game_set_draw_address
        JSR     game_draw_mask_sprite
        RTS

; Draw one life icon for each remaining life at the lower right.
game_draw_lives = *
        LDAA    #$14
        STAA    WORK_XBYTE
        LDAA    #$5A
        STAA    WORK_Y
        LDAA    #$0C
        STAA    WORK_WIDTH
        LDAA    #$06
        STAA    WORK_HEIGHT
        JSR     game_clear_rect
        LDAA    GAME_LIVES
        STAA    WORK_TEMP2
        LDAA    #$01
        STAA    WORK_COLOR
        LDAA    #$5C
        STAA    WORK_Y
        LDAA    #$1D
        STAA    WORK_XBYTE
game_draw_lives_loop = *
        LDAA    WORK_TEMP2
        BEQ     game_draw_lives_done
        LDX     #life_sprite
        STX     WORK_SPRITE
        LDAA    #$03
        STAA    WORK_WIDTH
        LDAA    #$03
        STAA    WORK_HEIGHT
        JSR     game_set_draw_address
        JSR     game_draw_mask_sprite
        LDAA    WORK_XBYTE
        DECA
        DECA
        DECA
        DECA
        STAA    WORK_XBYTE
        DEC     WORK_TEMP2
        BRA     game_draw_lives_loop
game_draw_lives_done = *
        RTS

game_clear_rect = *
        JSR     game_set_draw_address
        LDAA    WORK_HEIGHT
        STAA    WORK_TEMP
game_clear_rect_row = *
        LDAA    WORK_WIDTH
        STAA    WORK_COL
        CLRA
        LDX     WORK_ADDR
game_clear_rect_col = *
        STAA    0,X
        INX
        DEC     WORK_COL
        BNE     game_clear_rect_col
        LDD     WORK_ADDR
        ADDD    #$0020
        STD     WORK_ADDR
        DEC     WORK_TEMP
        BNE     game_clear_rect_row
        RTS

; Player projectile update and collisions.
game_player_bullet_update = *
        LDAA    GAME_BULLET_ACTIVE
        BEQ     game_player_bullet_done
        LDAA    GAME_BULLET_Y
        BEQ     game_player_bullet_remove
        DECA
        STAA    GAME_BULLET_Y
        JSR     game_bullet_hit_bonus
        LDAA    GAME_BULLET_ACTIVE
        BEQ     game_player_bullet_done
        JSR     game_bullet_hit_alien
        LDAA    GAME_BULLET_ACTIVE
        BEQ     game_player_bullet_done
        LDAA    GAME_BULLET_Y
        CMPA    #$3A
        BCS     game_player_bullet_done
        JSR     game_prepare_bullet_plot
        LDAA    GAME_SHIELDS_ACTIVE
        BEQ     game_player_bullet_done
        JSR     game_get_pixel
        TSTA
        BEQ     game_player_bullet_done
        JSR     game_damage_shield
        CLRA
        STAA    GAME_BULLET_ACTIVE
        RTS
game_player_bullet_remove = *
        CLRA
        STAA    GAME_BULLET_ACTIVE
game_player_bullet_done = *
        RTS

game_bullet_hit_bonus = *
        LDAA    GAME_BONUS_ACTIVE
        BEQ     game_bullet_bonus_done
        LDAA    GAME_BULLET_Y
        CMPA    #$06
        BCC     game_bullet_bonus_done
        LDAA    GAME_BULLET_X
        CMPA    GAME_BONUS_X
        BCC     game_bullet_bonus_x_high
        RTS
game_bullet_bonus_x_high = *
        LDAA    GAME_BONUS_X
        ADDA    #$02
        CMPA    GAME_BULLET_X
        BLS     game_bullet_bonus_done
        CLRA
        STAA    GAME_BONUS_ACTIVE
        STAA    GAME_BULLET_ACTIVE
        JSR     game_add_score_50
game_bullet_bonus_done = *
        RTS

; Find the lowest live invader under the bullet and remove it.
game_bullet_hit_alien = *
        LDAA    #$04
        STAA    WORK_ROW
        LDAA    GAME_INVADER_Y
        ADDA    #$18
        STAA    WORK_Y
game_bullet_alien_row = *
        JSR     game_select_row_pointer
        LDAA    GAME_BULLET_Y
        CMPA    WORK_Y
        BCS     game_bullet_alien_row_next
        LDAA    WORK_Y
        ADDA    #$05
        CMPA    GAME_BULLET_Y
        BLS     game_bullet_alien_row_next
        LDAA    GAME_INVADER_X
        STAA    WORK_XBYTE
        LDAA    #$0B
        STAA    WORK_COL
game_bullet_alien_col = *
        LDX     WORK_ROW_PTR
        LDAA    0,X
        BEQ     game_bullet_alien_col_next
        LDAA    GAME_BULLET_X
        CMPA    WORK_XBYTE
        BEQ     game_bullet_alien_hit
        LDAA    WORK_XBYTE
        INCA
        CMPA    GAME_BULLET_X
        BEQ     game_bullet_alien_hit
game_bullet_alien_col_next = *
        LDX     WORK_ROW_PTR
        INX
        STX     WORK_ROW_PTR
        LDAA    WORK_XBYTE
        ADDA    #$02
        STAA    WORK_XBYTE
        DEC     WORK_COL
        BNE     game_bullet_alien_col
        RTS
game_bullet_alien_hit = *
        LDX     WORK_ROW_PTR
        CLRA
        STAA    0,X
        LDAA    WORK_ROW
        TAB
        LDX     #formation_row_offsets
        ABX
        LDAA    0,X
        ADDA    GAME_INVADER_Y
        STAA    WORK_Y
        CLRA
        STAA    GAME_RENDER_MODE
        JSR     game_set_row_type
        JSR     game_draw_alien
        JSR     game_add_score_for_row
        CLRA
        STAA    GAME_BULLET_ACTIVE
        JSR     game_check_wave
        RTS
game_bullet_alien_row_next = *
        DEC     WORK_ROW
        BEQ     game_bullet_alien_done
        LDAA    WORK_Y
        SUBA    #$06
        STAA    WORK_Y
        JMP     game_bullet_alien_row
game_bullet_alien_done = *
        RTS

game_select_row_pointer = *
        LDAA    WORK_ROW
        ASLA
        TAB
        LDX     #alien_row_ptrs
        ABX
        LDD     0,X
        STD     WORK_ROW_PTR
        RTS

game_check_wave = *
        LDX     #ALIEN_LIVE
        LDAB    #$37
game_check_wave_loop = *
        LDAA    0,X
        BNE     game_check_wave_done
        INX
        DECB
        BNE     game_check_wave_loop
        JSR     game_initialize_aliens
        CLRA
        STAA    GAME_INVADER_TICK
        LDAA    #$01
        STAA    GAME_INVADER_X
        STAA    GAME_INVADER_DIR
        LDAA    #$05
        STAA    GAME_INVADER_Y
        LDAA    #$01
        STAA    GAME_TICK
game_check_wave_done = *
        RTS

game_add_score_for_row = *
        LDAA    WORK_ROW
        BEQ     game_add_score_30
        CMPA    #$03
        BCS     game_add_score_20
        BRA     game_add_score_10

game_add_score_10 = *
        INC     GAME_SCORE_2
        LDAA    GAME_SCORE_2
        CMPA    #$0A
        BCS     game_add_score_10_carry
        RTS
game_add_score_10_carry = *
        CLRA
        STAA    GAME_SCORE_2
        INC     GAME_SCORE_1
        LDAA    GAME_SCORE_1
        CMPA    #$0A
        BCS     game_add_score_10_hcarry
        RTS
game_add_score_10_hcarry = *
        CLRA
        STAA    GAME_SCORE_1
        INC     GAME_SCORE_0
        LDAA    GAME_SCORE_0
        CMPA    #$0A
        BCS     game_add_score_10_done
        CLRA
        STAA    GAME_SCORE_0
game_add_score_10_done = *
        RTS

game_add_score_20 = *
        JSR     game_add_score_10
        JSR     game_add_score_10
        RTS

game_add_score_30 = *
        JSR     game_add_score_10
        JSR     game_add_score_10
        JSR     game_add_score_10
        RTS

game_add_score_50 = *
        JSR     game_add_score_10
        JSR     game_add_score_10
        JSR     game_add_score_10
        JSR     game_add_score_10
        JSR     game_add_score_10
        RTS

; Alien projectile cadence, shield damage, and player collision.
game_alien_shot_update = *
        LDAA    GAME_ALIEN_SHOT_ACTIVE
        BNE     game_alien_shot_move
        INC     GAME_ALIEN_SHOT_TICK
        LDAA    GAME_ALIEN_SHOT_TICK
        CMPA    #$30
        BCS     game_alien_shot_done
        JSR     game_rng_next
        LDAA    GAME_RNG
        ANDA    #$0F
        CMPA    #$0B
        BCS     game_alien_shot_column
game_alien_shot_mod = *
        SUBA    #$0B
game_alien_shot_column = *
        ASLA
        ADDA    GAME_INVADER_X
        INCA
        STAA    GAME_ALIEN_SHOT_X
        LDAA    GAME_INVADER_Y
        ADDA    #$1E
        STAA    GAME_ALIEN_SHOT_Y
        CLRA
        STAA    GAME_ALIEN_SHOT_TICK
        LDAA    #$01
        STAA    GAME_ALIEN_SHOT_ACTIVE
        RTS

game_alien_shot_move = *
        INC     GAME_ALIEN_SHOT_TICK
        LDAA    GAME_ALIEN_SHOT_TICK
        CMPA    #$02
        BCS     game_alien_shot_done
        CLRA
        STAA    GAME_ALIEN_SHOT_TICK
        INC     GAME_ALIEN_SHOT_Y
        LDAA    GAME_ALIEN_SHOT_Y
        CMPA    #$3A
        BCS     game_alien_shot_player_check
        LDAA    GAME_SHIELDS_ACTIVE
        BEQ     game_alien_shot_player_check
        JSR     game_prepare_alien_shot_plot
        JSR     game_get_pixel
        TSTA
        BEQ     game_alien_shot_player_check
        JSR     game_damage_shield
        CLRA
        STAA    GAME_ALIEN_SHOT_ACTIVE
        RTS
game_alien_shot_player_check = *
        LDAA    GAME_ALIEN_SHOT_Y
        CMPA    #$52
        BCS     game_alien_shot_bottom_check
        LDAA    GAME_ALIEN_SHOT_X
        CMPA    GAME_PLAYER_X
        BCC     game_alien_shot_x_high
        BRA     game_alien_shot_bottom_check
game_alien_shot_x_high = *
        LDAA    GAME_PLAYER_X
        ADDA    #$03
        CMPA    GAME_ALIEN_SHOT_X
        BLS     game_alien_shot_bottom_check
        JSR     game_lose_life
        RTS
game_alien_shot_bottom_check = *
        LDAA    GAME_ALIEN_SHOT_Y
        CMPA    #$5E
        BCS     game_alien_shot_done
        CLRA
        STAA    GAME_ALIEN_SHOT_ACTIVE
game_alien_shot_done = *
        RTS

game_prepare_alien_shot_plot = *
        LDAA    GAME_ALIEN_SHOT_X
        ASLA
        ASLA
        ADDA    #$02
        STAA    PLOT_X
        LDAA    GAME_ALIEN_SHOT_Y
        STAA    PLOT_Y
        RTS

game_prepare_bullet_plot = *
        LDAA    GAME_BULLET_X
        ASLA
        ASLA
        ADDA    #$02
        STAA    PLOT_X
        LDAA    GAME_BULLET_Y
        STAA    PLOT_Y
        RTS

game_damage_shield = *
        LDAA    PLOT_X
        STAA    WORK_TEMP
        JSR     game_plot_black
        LDAA    WORK_TEMP
        INCA
        STAA    PLOT_X
        JSR     game_plot_black
        LDAA    WORK_TEMP
        DECA
        STAA    PLOT_X
        JSR     game_plot_black
        LDAA    WORK_TEMP
        STAA    PLOT_X
        LDAA    PLOT_Y
        INCA
        STAA    PLOT_Y
        JSR     game_plot_black
        RTS

game_plot_black = *
        CLRA
        STAA    PLOT_COLOR
        JSR     game_plot_pixel
        RTS

; Return the two-bit CG3 color at PLOT_X/PLOT_Y.
game_get_pixel = *
        LDAA    PLOT_X
        TAB
        LSRA
        LSRA
        STAA    PLOT_BYTE
        ANDB    #$03
        STAB    PLOT_SHIFT
        LDAA    PLOT_Y
        ASLA
        TAB
        LDX     #screen_row_ptrs
        ABX
        LDD     0,X
        STD     WORK_ADDR
        LDAB    PLOT_BYTE
        LDX     WORK_ADDR
        ABX
        LDAA    0,X
        LDAB    PLOT_SHIFT
        LDX     #pixel_right_shifts
        ABX
        LDAB    0,X
game_get_pixel_shift = *
        TSTB
        BEQ     game_get_pixel_mask
        LSRA
        DECB
        BRA     game_get_pixel_shift
game_get_pixel_mask = *
        ANDA    #$03
        RTS

game_plot_pixel = *
        LDAA    PLOT_X
        TAB
        LSRA
        LSRA
        STAA    PLOT_BYTE
        ANDB    #$03
        STAB    PLOT_SHIFT
        LDAB    PLOT_SHIFT
        LDX     #pixel_clear_masks
        ABX
        LDAA    0,X
        STAA    PLOT_MASK
        LDAA    PLOT_SHIFT
        ASLA
        ASLA
        ADDA    PLOT_COLOR
        TAB
        LDX     #pixel_color_table
        ABX
        LDAA    0,X
        STAA    PLOT_ENCODED
        LDAA    PLOT_Y
        ASLA
        TAB
        LDX     #screen_row_ptrs
        ABX
        LDD     0,X
        STD     WORK_ADDR
        LDAB    PLOT_BYTE
        LDX     WORK_ADDR
        ABX
        LDAA    0,X
        ANDA    PLOT_MASK
        ORAA    PLOT_ENCODED
        STAA    0,X
        RTS

; Formation movement, descent, shield removal, and player collision.
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
        CMPA    #$08
        BCC     game_invader_right_edge
        INCA
        STAA    GAME_INVADER_X
        RTS
game_invader_right_edge = *
        CLRA
        STAA    GAME_INVADER_DIR
        JSR     game_invader_descend
        RTS
game_invader_left = *
        LDAA    GAME_INVADER_X
        CMPA    #$01
        BLS     game_invader_left_edge
        DECA
        STAA    GAME_INVADER_X
        RTS
game_invader_left_edge = *
        LDAA    #$01
        STAA    GAME_INVADER_DIR
        JSR     game_invader_descend
game_invader_done = *
        RTS

game_invader_descend = *
        LDAA    GAME_INVADER_Y
        ADDA    #$06
        STAA    GAME_INVADER_Y
        CMPA    #$20
        BCS     game_invader_player_level
        LDAA    GAME_SHIELDS_ACTIVE
        BEQ     game_invader_player_level
        JSR     game_clear_shields
game_invader_player_level = *
        LDAA    GAME_INVADER_Y
        CMPA    #$38
        BCS     game_invader_descend_done
        JSR     game_lose_life
game_invader_descend_done = *
        RTS

game_lose_life = *
        LDAA    GAME_LIVES
        BEQ     game_set_game_over
        DECA
        STAA    GAME_LIVES
        BEQ     game_set_game_over

        ; Remove the old formation before resetting its position. The new
        ; formation is drawn at the end of this update.
        CLRA
        STAA    GAME_RENDER_MODE
        JSR     game_draw_formation
        LDAA    #$01
        STAA    GAME_TICK
        LDAA    #$01
        STAA    GAME_INVADER_X
        STAA    GAME_INVADER_DIR
        CLRA
        STAA    GAME_INVADER_TICK
        STAA    GAME_BULLET_ACTIVE
        STAA    GAME_ALIEN_SHOT_ACTIVE
        LDAA    #$05
        STAA    GAME_INVADER_Y
        LDAA    #$0F
        STAA    GAME_PLAYER_X
        RTS
game_set_game_over = *
        LDAA    #$01
        STAA    GAME_OVER
        CLRA
        STAA    GAME_BULLET_ACTIVE
        STAA    GAME_ALIEN_SHOT_ACTIVE
        STAA    GAME_BONUS_ACTIVE
        RTS

game_rng_next = *
        LDAA    GAME_RNG
        LSRA
        BCC     game_rng_store
        EORA    #$B8
game_rng_store = *
        STAA    GAME_RNG
        RTS

; Bonus ship timer and horizontal flight.
game_bonus_update = *
        LDAA    GAME_BONUS_ACTIVE
        BEQ     game_bonus_wait
        INC     GAME_BONUS_TICK
        LDAA    GAME_BONUS_TICK
        BITA    #$01
        BNE     game_bonus_done
        LDAA    GAME_BONUS_DIR
        BEQ     game_bonus_left
        LDAA    GAME_BONUS_X
        CMPA    #$1E
        BCC     game_bonus_remove
        INCA
        STAA    GAME_BONUS_X
        RTS
game_bonus_left = *
        LDAA    GAME_BONUS_X
        BEQ     game_bonus_remove
        DECA
        STAA    GAME_BONUS_X
        RTS
game_bonus_remove = *
        CLRA
        STAA    GAME_BONUS_ACTIVE
game_bonus_done = *
        RTS
game_bonus_wait = *
        INC     GAME_BONUS_TICK
        LDAA    GAME_BONUS_TICK
        CMPA    #$C0
        BCS     game_bonus_done
        JSR     game_rng_next
        LDAA    GAME_RNG
        BITA    #$01
        BEQ     game_bonus_start_right
        LDAA    #$1E
        STAA    GAME_BONUS_X
        CLRA
        STAA    GAME_BONUS_DIR
        BRA     game_bonus_start
game_bonus_start_right = *
        CLRA
        STAA    GAME_BONUS_X
        LDAA    #$01
        STAA    GAME_BONUS_DIR
game_bonus_start = *
        CLRA
        STAA    GAME_BONUS_TICK
        LDAA    #$01
        STAA    GAME_BONUS_ACTIVE
        RTS

; An alien row's vertical offsets and live-array row pointers.
formation_row_offsets = *
        DB      $00,$06,$0C,$12,$18
alien_row_ptrs = *
        DW      ALIEN_LIVE,ALIEN_LIVE+11,ALIEN_LIVE+22
        DW      ALIEN_LIVE+33,ALIEN_LIVE+44

alien_sprite_ptrs = *
        DW      alien_top_0,alien_top_1
        DW      alien_mid_0,alien_mid_1
        DW      alien_bottom_0,alien_bottom_1

; Sixteen-pixel-wide masks, two CG3 bytes per row, five rows per frame.
alien_top_0 = *
        DB      $03,$03,$07,$0E,$0F,$0F,$09,$09,$0A,$05
alien_top_1 = *
        DB      $06,$06,$0F,$0F,$0B,$0D,$07,$0E,$09,$06
alien_mid_0 = *
        DB      $0C,$03,$07,$0E,$0F,$0F,$0A,$05,$06,$06
alien_mid_1 = *
        DB      $0C,$03,$0F,$0F,$0B,$0D,$0F,$0F,$06,$06
alien_bottom_0 = *
        DB      $03,$03,$0F,$0F,$0A,$05,$07,$0E,$04,$02
alien_bottom_1 = *
        DB      $06,$06,$0F,$0F,$0B,$0D,$0F,$0F,$04,$02

shield_sprite = *
        DB      $0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F
        DB      $0F,$0F,$0F,$0F,$00,$0F,$0F,$00,$0F
        DB      $0F,$00,$0F
player_sprite = *
        DB      $04,$0F,$04,$00,$0F,$00,$04,$0F,$04
        DB      $0F,$0F,$0F,$0F,$0F,$0F
bonus_sprite = *
        DB      $0F,$0F,$0A,$0A,$05,$05
player_bullet_sprite = *
        DB      $0F,$0F,$0F
alien_shot_sprite = *
        DB      $0F,$0A,$0F
life_sprite = *
        DB      $04,$0F,$04,$0F,$0F,$0F,$0F,$0F,$0F

digit_ptrs = *
        DW      digit_0,digit_1,digit_2,digit_3,digit_4
        DW      digit_5,digit_6,digit_7,digit_8,digit_9
digit_0 = *
        DB      $0F,$09,$09,$09,$0F
digit_1 = *
        DB      $04,$0C,$04,$04,$0E
digit_2 = *
        DB      $0F,$01,$0F,$08,$0F
digit_3 = *
        DB      $0F,$01,$07,$01,$0F
digit_4 = *
        DB      $09,$09,$0F,$01,$01
digit_5 = *
        DB      $0F,$08,$0F,$01,$0F
digit_6 = *
        DB      $0F,$08,$0F,$09,$0F
digit_7 = *
        DB      $0F,$01,$02,$04,$04
digit_8 = *
        DB      $0F,$09,$0F,$09,$0F
digit_9 = *
        DB      $0F,$09,$0F,$01,$0F

pixel_clear_masks = *
        DB      $3F,$CF,$F3,$FC
pixel_right_shifts = *
        DB      $06,$04,$02,$00

colorize_table = *
        DB      $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        DB      $00,$01,$04,$05,$10,$11,$14,$15,$40,$41,$44,$45,$50,$51,$54,$55
        DB      $00,$02,$08,$0A,$20,$22,$28,$2A,$80,$82,$88,$8A,$A0,$A2,$A8,$AA
        DB      $00,$03,$0C,$0F,$30,$33,$3C,$3F,$C0,$C3,$CC,$CF,$F0,$F3,$FC,$FF

; Single-pixel encodings indexed by pixel position, then color.
pixel_color_table = *
        DB      $00,$40,$80,$C0
        DB      $00,$10,$20,$30
        DB      $00,$04,$08,$0C
        DB      $00,$01,$02,$03

; Each row is a 32-byte CG3 scanline. The table keeps address generation
; explicit and avoids relying on undocumented VDG page behavior.
screen_row_ptrs = *
        DW      $4000,$4020,$4040,$4060,$4080,$40A0,$40C0,$40E0
        DW      $4100,$4120,$4140,$4160,$4180,$41A0,$41C0,$41E0
        DW      $4200,$4220,$4240,$4260,$4280,$42A0,$42C0,$42E0
        DW      $4300,$4320,$4340,$4360,$4380,$43A0,$43C0,$43E0
        DW      $4400,$4420,$4440,$4460,$4480,$44A0,$44C0,$44E0
        DW      $4500,$4520,$4540,$4560,$4580,$45A0,$45C0,$45E0
        DW      $4600,$4620,$4640,$4660,$4680,$46A0,$46C0,$46E0
        DW      $4700,$4720,$4740,$4760,$4780,$47A0,$47C0,$47E0
        DW      $4800,$4820,$4840,$4860,$4880,$48A0,$48C0,$48E0
        DW      $4900,$4920,$4940,$4960,$4980,$49A0,$49C0,$49E0
        DW      $4A00,$4A20,$4A40,$4A60,$4A80,$4AA0,$4AC0,$4AE0
        DW      $4B00,$4B20,$4B40,$4B60,$4B80,$4BA0,$4BC0,$4BE0
