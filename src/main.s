; =============================================================================
; BOX HERO - platform a scorrimento per SUP Game Box (NES / VT02, mapper 0)
; Assemblare con:  make   (richiede cc65 e python3)
; =============================================================================

; ----------------------------------------------------------------- hardware
PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
OAMADDR   = $2003
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007
OAMDMA    = $4014
JOY1      = $4016
APUFRAME  = $4017

BTN_A      = $80
BTN_B      = $40
BTN_SELECT = $20
BTN_START  = $10
BTN_UP     = $08
BTN_DOWN   = $04
BTN_LEFT   = $02
BTN_RIGHT  = $01

; ----------------------------------------------------------------- game states
ST_TITLE    = 0
ST_INTRO    = 1
ST_PLAY     = 2
ST_DYING    = 3
ST_CLEAR    = 4
ST_GAMEOVER = 5
ST_WIN      = 6

; ----------------------------------------------------------------- objects
MAXOBJ    = 8               ; must stay 8 (draw rotation uses AND #7)
T_NONE    = 0
T_COIN    = 1
T_WALKER  = 2
T_SPIKY   = 3
T_BOSS    = 4
T_SQUISH  = 5
T_BOSSDIE = 6

; ----------------------------------------------------------------- physics (8.8 fixed point)
ACCEL     = $18
FRICTION  = $10
WALK_MAX  = $0180
RUN_MAX   = $0260
JUMP_V    = $FBC0           ; -4.25 px/frame
GRAV      = $60
GRAV_HOLD = $28             ; lighter gravity while A is held and rising
MAX_FALL  = $0400

; ----------------------------------------------------------------- metatiles
MT_SKY    = 0
MT_GTOP   = 1
MT_GFILL  = 2
MT_BRICK  = 3
MT_CLOUDL = 4
MT_CLOUDR = 5

; ----------------------------------------------------------------- sprite tiles ($1000 table)
SPR_STAND  = $00
SPR_WALK1  = $04
SPR_WALK2  = $08
SPR_JUMP   = $0C
SPR_DEAD   = $10
SPR_WALKA  = $14
SPR_WALKB  = $18
SPR_SQUISH = $1C
SPR_SPIKYA = $60
SPR_SPIKYB = $64
SPR_COINA  = $68
SPR_COINB  = $6A
SPR_HEART  = $6C
SPR_COINI  = $6D
SPR_BOSSA  = $70
SPR_BOSSB  = $80

; =============================================================================
.segment "HEADER"
    .byte "NES", $1A
    .byte 1                 ; 1 x 16 KB PRG
    .byte 1                 ; 1 x 8 KB CHR
    .byte $01               ; mapper 0, vertical mirroring (horizontal scrolling)
    .byte $00
    .res 8, 0

; =============================================================================
.segment "ZEROPAGE"
nmi_count:   .res 1
ppu_on:      .res 1
ppu_ctrl:    .res 1
scroll_x:    .res 1
scroll_nt:   .res 1
col_pending: .res 1
col_addr:    .res 2
pad:         .res 1
pad_prev:    .res 1
pad_new:     .res 1
tmp:         .res 4
ptr:         .res 2
state:       .res 1
timer:       .res 1
frame:       .res 1
paused:      .res 1
level:       .res 1
lives:       .res 1
coins:       .res 1
cam_x:       .res 2
cam_col:     .res 1
lvl_cols:    .res 2
lvl_objs:    .res 2
lvl_width:   .res 1
lvl_maxcam:  .res 2
obj_next:    .res 1
boss_on:     .res 1
boss_hp:     .res 1
; player
px_sub:      .res 1
px:          .res 1
px_h:        .res 1
py_sub:      .res 1
py:          .res 1
vx_l:        .res 1
vx_h:        .res 1
vy_l:        .res 1
vy_h:        .res 1
on_ground:   .res 1
facing:      .res 1
anim:        .res 1
p_l:         .res 1
p_r:         .res 1
p_t:         .res 1
p_b:         .res 1
; tile collision
chk_x:       .res 2
chk_y:       .res 1
s_t0:        .res 1
s_t1:        .res 1
s_t2:        .res 1
; column builder
bc_col:      .res 1
bc_b:        .res 1
bc_top:      .res 1
bc_plat:     .res 1
bc_crow:     .res 1
bc_cmt:      .res 1
bc_row:      .res 1
; sprites
spr_idx:     .res 1
spr_full:    .res 1
ms_x:        .res 2
ms_y:        .res 1
ms_tile:     .res 1
ms_w:        .res 1
ms_h:        .res 1
ms_attr:     .res 1
ms_c:        .res 1
ms_r:        .res 1
ms_cx:       .res 2
ms_cy:       .res 1
ms_rowbase:  .res 1
hs_x:        .res 1
hs_y:        .res 1
hs_a:        .res 1
do_i:        .res 1
do_cnt:      .res 1
; current object
o_sx:        .res 2
o_l:         .res 1
o_r:         .res 1
o_t:         .res 1
o_b:         .res 1

.segment "OAM"
oam:         .res 256

.segment "BSS"
colbuf:      .res 60
obj_t:       .res MAXOBJ
obj_xl:      .res MAXOBJ
obj_xh:      .res MAXOBJ
obj_y:       .res MAXOBJ
obj_vy:      .res MAXOBJ
obj_dir:     .res MAXOBJ    ; 0 = right, 1 = left
obj_timer:   .res MAXOBJ
obj_hp:      .res MAXOBJ
obj_inv:     .res MAXOBJ

; =============================================================================
.segment "CODE"

reset:
    sei
    cld
    ldx #$40
    stx APUFRAME            ; no APU frame IRQ
    ldx #$FF
    txs
    inx
    stx PPUCTRL
    stx PPUMASK
    stx $4010
    bit PPUSTATUS
@vb1:
    bit PPUSTATUS
    bpl @vb1
@clr:
    lda #0
    sta $00,x
    sta $0100,x
    sta $0300,x
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    lda #$FF
    sta $0200,x
    inx
    bne @clr
@vb2:
    bit PPUSTATUS
    bpl @vb2

    lda #$0F
    sta $4015               ; enable pulse 1/2, triangle, noise
    lda #$88                ; NMI on, sprites from $1000, BG from $0000
    sta ppu_ctrl
    sta PPUCTRL
    jsr title_init

main_loop:
    jsr wait_frame
    jsr read_pad
    inc frame
    jsr run_state
    jmp main_loop

run_state:
    lda state
    asl a
    tax
    lda state_tbl+1,x
    pha
    lda state_tbl,x
    pha
    rts

state_tbl:
    .word st_title-1, st_intro-1, st_play-1, st_dying-1
    .word st_clear-1, st_gameover-1, st_win-1

; -----------------------------------------------------------------------------
nmi:
    pha
    txa
    pha
    tya
    pha
    lda ppu_on
    beq @skip
    lda #0
    sta OAMADDR
    lda #>oam
    sta OAMDMA
    lda col_pending
    beq @nocol
    jsr upload_column
    lda #0
    sta col_pending
@nocol:
    lda ppu_ctrl
    ora scroll_nt
    sta PPUCTRL
    bit PPUSTATUS
    lda scroll_x
    sta PPUSCROLL
    lda #0
    sta PPUSCROLL
    lda #%00011110          ; show BG and sprites, also in the leftmost 8 px
    sta PPUMASK
@skip:
    inc nmi_count
    pla
    tay
    pla
    tax
    pla
irq:
    rti

wait_frame:
    lda nmi_count
@w:
    cmp nmi_count
    beq @w
    rts

read_pad:
    lda pad
    sta pad_prev
    lda #1
    sta JOY1
    lda #0
    sta JOY1
    ldx #8
@l:
    lda JOY1
    and #%00000011          ; standard + Famicom expansion pads
    cmp #1
    rol pad
    dex
    bne @l
    lda pad_prev
    eor #$FF
    and pad
    sta pad_new
    rts

; ----------------------------------------------------------------- PPU helpers
ppu_off:
    jsr wait_frame
    lda #0
    sta ppu_on
    sta PPUMASK
    rts

ppu_enable:
    lda #1
    sta ppu_on
    jmp wait_frame

clear_nametables:
    bit PPUSTATUS
    lda #$20
    sta PPUADDR
    lda #$00
    sta PPUADDR
    ldy #8
    ldx #0
@l:
    sta PPUDATA
    inx
    bne @l
    dey
    bne @l
    rts

load_palette:
    bit PPUSTATUS
    lda #$3F
    sta PPUADDR
    lda #$00
    sta PPUADDR
    ldx #0
@l:
    lda palette,x
    sta PPUDATA
    inx
    cpx #32
    bne @l
    lda #$3F                ; per-level colour of boss and spiky enemies
    sta PPUADDR
    lda #$1D
    sta PPUADDR
    ldx level
    lda boss_color,x
    sta PPUDATA
    rts

clear_oam:
    lda #$FF
    ldx #0
@l:
    sta oam,x
    inx
    inx
    inx
    inx
    bne @l
    stx spr_idx
    stx spr_full
    rts

; ptr -> list of [addr hi, addr lo, text..., 0], terminated by $FF
print_list:
    ldy #0
@next:
    lda (ptr),y
    cmp #$FF
    beq @done
    bit PPUSTATUS
    sta PPUADDR
    iny
    lda (ptr),y
    sta PPUADDR
    iny
@ch:
    lda (ptr),y
    beq @end
    sta PPUDATA
    iny
    bne @ch
@end:
    iny
    bne @next
@done:
    rts

; draws the brick floor on the bottom four tile rows of nametable 0
draw_floor:
    lda #$23
    sta tmp+1
    lda #$40
    sta tmp
    ldy #0
@row:
    bit PPUSTATUS
    lda tmp+1
    sta PPUADDR
    lda tmp
    sta PPUADDR
    ldx #16
@pair:
    lda floor_tiles,y
    sta PPUDATA
    lda floor_tiles+1,y
    sta PPUDATA
    dex
    bne @pair
    iny
    iny
    lda tmp
    clc
    adc #32
    sta tmp
    cpy #8
    bne @row
    rts

; screen_begin: rendering off, clear, print the text list in ptr
screen_begin:
    jsr ppu_off
    lda #0
    sta col_pending
    jsr clear_nametables
    jsr print_list
    jsr draw_floor
    jmp load_palette

screen_end:
    lda #0
    sta scroll_x
    sta scroll_nt
    jsr clear_oam
    jmp ppu_enable

; A = digit, ptr = PPU address
put_digit:
    pha
    bit PPUSTATUS
    lda ptr+1
    sta PPUADDR
    lda ptr
    sta PPUADDR
    pla
    clc
    adc #'0'
    sta PPUDATA
    rts

; ================================================================ states
title_init:
    lda #<txt_title
    sta ptr
    lda #>txt_title
    sta ptr+1
    jsr screen_begin
    jsr screen_end
    lda #ST_TITLE
    sta state
    ; decorative hero and walker on the floor
    lda #96
    sta ms_x
    lda #0
    sta ms_x+1
    sta ms_attr
    lda #192
    sta ms_y
    lda #SPR_STAND
    sta ms_tile
    jsr draw_2x2
    lda #152
    sta ms_x
    lda #SPR_WALKA
    sta ms_tile
    lda #$41
    sta ms_attr
    jmp draw_2x2

st_title:
    lda pad_new
    and #BTN_START
    beq @rts
    lda #0
    sta level
    sta coins
    lda #3
    sta lives
    jmp intro_init
@rts:
    rts

intro_init:
    lda #<txt_intro
    sta ptr
    lda #>txt_intro
    sta ptr+1
    jsr screen_begin
    lda #$93
    sta ptr
    lda #$21
    sta ptr+1
    lda level
    clc
    adc #1
    jsr put_digit
    lda #$F3
    sta ptr
    lda lives
    jsr put_digit
    jsr screen_end
    lda #ST_INTRO
    sta state
    lda #120
    sta timer
    rts

st_intro:
    dec timer
    bne @rts
    jmp play_init
@rts:
    rts

gameover_init:
    lda #<txt_gameover
    sta ptr
    lda #>txt_gameover
    sta ptr+1
    jsr screen_begin
    jsr screen_end
    lda #ST_GAMEOVER
    sta state
    lda #240
    sta timer
    rts

st_gameover:
    lda pad_new
    and #BTN_START
    bne @done
    dec timer
    bne @rts
@done:
    jmp title_init
@rts:
    rts

win_init:
    lda #<txt_win
    sta ptr
    lda #>txt_win
    sta ptr+1
    jsr screen_begin
    jsr screen_end
    lda #ST_WIN
    sta state
    rts

st_win:
    lda pad_new
    and #BTN_START
    beq @rts
    jmp title_init
@rts:
    rts

; ----------------------------------------------------------------- level setup
play_init:
    jsr ppu_off
    lda #0
    sta col_pending
    ldx level
    lda level_cols_lo,x
    sta lvl_cols
    lda level_cols_hi,x
    sta lvl_cols+1
    lda level_objs_lo,x
    sta lvl_objs
    lda level_objs_hi,x
    sta lvl_objs+1
    lda level_width,x
    sta lvl_width
    ; maxcam = width * 16 - 256
    asl a
    asl a
    asl a
    asl a
    sta lvl_maxcam
    lda lvl_width
    lsr a
    lsr a
    lsr a
    lsr a
    sec
    sbc #1
    sta lvl_maxcam+1

    lda #0
    sta cam_x
    sta cam_x+1
    sta scroll_x
    sta scroll_nt
    sta obj_next
    sta boss_on
    sta boss_hp
    sta paused
    jsr clear_nametables

    lda #0
    sta cam_col
@col:
    lda cam_col
    jsr build_column
    jsr upload_column
    inc cam_col
    lda cam_col
    cmp #17
    bne @col
    dec cam_col             ; last column drawn

    ldx #MAXOBJ-1
    lda #0
@clrobj:
    sta obj_t,x
    dex
    bpl @clrobj
    jsr spawn_objects

    lda #0
    sta px_sub
    sta px_h
    sta py_sub
    sta vx_l
    sta vx_h
    sta vy_l
    sta vy_h
    sta facing
    sta anim
    sta on_ground
    lda #32
    sta px
    lda #160
    sta py

    jsr load_palette
    jsr clear_oam
    lda #ST_PLAY
    sta state
    jmp ppu_enable

; ----------------------------------------------------------------- play
st_play:
    lda pad_new
    and #BTN_START
    beq @nopause
    lda paused
    eor #1
    sta paused
    beq @nopause
    jmp draw_pause
@nopause:
    lda paused
    beq @run
    rts
@run:
    jsr update_player
    jsr update_camera
    jsr update_objects
    jmp draw_all

st_dying:
    dec timer
    beq @done
    lda timer
    cmp #90                 ; short freeze before the fall
    bcs @draw
    lda py
    cmp #240
    bcs @draw
    lda vy_l
    clc
    adc #$30
    sta vy_l
    lda vy_h
    adc #0
    sta vy_h
    clc
    lda py_sub
    adc vy_l
    sta py_sub
    lda py
    adc vy_h
    sta py
    ldy vy_h
    bpl @draw
    bcs @draw
    lda #0                  ; went above the screen top
    sta py
@draw:
    jmp draw_all
@done:
    dec lives
    beq @over
    jmp intro_init
@over:
    jmp gameover_init

st_clear:
    lda #0                  ; the player just lands, ignoring the pad
    sta pad
    sta pad_new
    jsr update_player
    jsr update_objects
    jsr draw_all
    dec timer
    bne @rts
    inc level
    lda level
    cmp #LEVEL_COUNT
    bcs @win
    jmp intro_init
@win:
    jmp win_init
@rts:
    rts

kill_player:
    lda state
    cmp #ST_PLAY
    bne @rts
    lda #ST_DYING
    sta state
    lda #120
    sta timer
    lda #$00
    sta vy_l
    lda #$FC
    sta vy_h
    jmp sfx_die
@rts:
    rts

player_bounce:
    lda #0
    sta on_ground
    lda pad
    and #BTN_A
    beq @low
    lda #$80
    sta vy_l
    lda #$FB
    sta vy_h
    rts
@low:
    lda #$00
    sta vy_l
    lda #$FD
    sta vy_h
    rts

add_life:
    lda lives
    cmp #9
    bcs @rts
    inc lives
@rts:
    rts

; ----------------------------------------------------------------- player
update_player:
    ; max speed: B runs
    lda pad
    and #BTN_B
    beq @walk
    lda #<RUN_MAX
    sta tmp
    lda #>RUN_MAX
    sta tmp+1
    jmp @gotmax
@walk:
    lda #<WALK_MAX
    sta tmp
    lda #>WALK_MAX
    sta tmp+1
@gotmax:
    lda pad
    and #BTN_RIGHT
    beq @notright
    lda #0
    sta facing
    lda vx_l
    clc
    adc #ACCEL
    sta vx_l
    lda vx_h
    adc #0
    sta vx_h
    bmi @to_hdone
    cmp tmp+1
    bcc @to_hdone
    bne @maxr
    lda vx_l
    cmp tmp
    bcc @to_hdone
    beq @to_hdone
@maxr:
    lda tmp
    sta vx_l
    lda tmp+1
    sta vx_h
@to_hdone:
    jmp @hdone
@notright:
    lda pad
    and #BTN_LEFT
    beq @friction
    lda #1
    sta facing
    lda vx_l
    sec
    sbc #ACCEL
    sta vx_l
    lda vx_h
    sbc #0
    sta vx_h
    bpl @hdone
    lda #0                  ; tmp+2/3 = -max
    sec
    sbc tmp
    sta tmp+2
    lda #0
    sbc tmp+1
    sta tmp+3
    lda vx_h
    cmp tmp+3
    bcc @maxl
    bne @hdone
    lda vx_l
    cmp tmp+2
    bcs @hdone
@maxl:
    lda tmp+2
    sta vx_l
    lda tmp+3
    sta vx_h
    jmp @hdone
@friction:
    lda vx_h
    bmi @fneg
    ora vx_l
    beq @hdone
    lda vx_l
    sec
    sbc #FRICTION
    sta vx_l
    lda vx_h
    sbc #0
    sta vx_h
    bpl @hdone
    lda #0
    sta vx_l
    sta vx_h
    jmp @hdone
@fneg:
    lda vx_l
    clc
    adc #FRICTION
    sta vx_l
    lda vx_h
    adc #0
    sta vx_h
    bmi @hdone
    lda #0
    sta vx_l
    sta vx_h
@hdone:
    ; x += vx (24 bit)
    ldy #0
    lda vx_h
    bpl :+
    dey
:   clc
    lda px_sub
    adc vx_l
    sta px_sub
    lda px
    adc vx_h
    sta px
    tya
    adc px_h
    sta px_h
    ; never left of the camera
    bmi @clampl
    lda px
    cmp cam_x
    lda px_h
    sbc cam_x+1
    bcs @hcol
@clampl:
    lda cam_x
    sta px
    lda cam_x+1
    sta px_h
    lda #0
    sta px_sub
    sta vx_l
    sta vx_h
@hcol:
    lda vx_h
    bmi @hleft
    ora vx_l
    beq @hcol_done
    lda px
    clc
    adc #13
    sta chk_x
    lda px_h
    adc #0
    sta chk_x+1
    jsr check_side
    bcc @hcol_done
    lda chk_x
    and #$F0
    sec
    sbc #14
    sta px
    lda chk_x+1
    sbc #0
    sta px_h
    jmp @hstop
@hleft:
    lda px
    clc
    adc #2
    sta chk_x
    lda px_h
    adc #0
    sta chk_x+1
    jsr check_side
    bcc @hcol_done
    lda chk_x
    and #$F0
    clc
    adc #14
    sta px
    lda chk_x+1
    adc #0
    sta px_h
@hstop:
    lda #0
    sta px_sub
    sta vx_l
    sta vx_h
@hcol_done:
    ; jump
    lda on_ground
    beq @nojump
    lda pad_new
    and #BTN_A
    beq @nojump
    lda #<JUMP_V
    sta vy_l
    lda #>JUMP_V
    sta vy_h
    lda #0
    sta on_ground
    jsr sfx_jump
@nojump:
    ; gravity
    lda vy_h
    bpl @gnorm
    lda pad
    and #BTN_A
    beq @gnorm
    lda #GRAV_HOLD
    bne @gadd
@gnorm:
    lda #GRAV
@gadd:
    clc
    adc vy_l
    sta vy_l
    lda vy_h
    adc #0
    sta vy_h
    bmi @capok
    cmp #>MAX_FALL
    bcc @capok
    lda #0
    sta vy_l
    lda #>MAX_FALL
    sta vy_h
@capok:
    clc
    lda py_sub
    adc vy_l
    sta py_sub
    lda py
    adc vy_h
    sta py
    ldy vy_h
    bpl @down
    bcs @up
    lda #0                  ; hit the top of the screen
    sta py
    sta vy_l
    sta vy_h
    jmp @vdone
@up:
    lda py
    sta chk_y
    jsr check_row
    bcc @vdone
    lda py
    and #$F0
    clc
    adc #16
    sta py
    lda #0
    sta py_sub
    sta vy_l
    sta vy_h
    jsr sfx_bump
    jmp @vdone
@down:
    lda py
    cmp #224
    bcc @dok
    jmp kill_player         ; fell into a pit
@dok:
    clc
    adc #16
    sta chk_y
    jsr check_row
    bcc @air
    lda chk_y
    and #$F0
    sec
    sbc #16
    sta py
    lda #0
    sta py_sub
    sta vy_l
    sta vy_h
    lda #1
    sta on_ground
    jmp @vdone
@air:
    lda #0
    sta on_ground
@vdone:
    lda on_ground
    beq @rts
    lda vx_h
    bpl :+
    eor #$FF
:   sec                     ; +1
    adc anim
    sta anim
@rts:
    rts

; solid at (chk_x, py+2) or (chk_x, py+13)?
check_side:
    lda py
    clc
    adc #2
    sta chk_y
    jsr is_solid
    bcs @r
    lda py
    clc
    adc #13
    sta chk_y
    jmp is_solid
@r:
    rts

; solid at (px+3, chk_y) or (px+12, chk_y)?
check_row:
    lda px
    clc
    adc #3
    sta chk_x
    lda px_h
    adc #0
    sta chk_x+1
    jsr is_solid
    bcs @r
    lda px
    clc
    adc #12
    sta chk_x
    lda px_h
    adc #0
    sta chk_x+1
    jmp is_solid
@r:
    rts

; in: chk_x (world px, 16 bit), chk_y (px). out: C=1 if solid. clobbers A, Y
is_solid:
    lda chk_y
    cmp #240
    bcs @no
    lda chk_x+1
    cmp #$10
    bcs @yes                ; beyond column 255
    sta s_t0
    lda chk_x
    lsr s_t0
    ror a
    lsr s_t0
    ror a
    lsr s_t0
    ror a
    lsr s_t0
    ror a
    cmp lvl_width
    bcs @yes                ; right edge of the level is a wall
    tay
    lda chk_y
    lsr a
    lsr a
    lsr a
    lsr a
    sta s_t1                ; row
    lda (lvl_cols),y
    sta s_t2
    and #$0F
    beq @plat
    clc                     ; ground: solid if row >= 15 - height
    adc s_t1
    cmp #15
    bcs @yes
@plat:
    lda s_t2
    lsr a
    lsr a
    lsr a
    lsr a
    beq @no
    cmp s_t1
    beq @yes
@no:
    clc
    rts
@yes:
    sec
    rts

; ----------------------------------------------------------------- camera
update_camera:
    lda px
    sec
    sbc #112
    sta tmp
    lda px_h
    sbc #0
    sta tmp+1
    bmi @scroll
    cmp cam_x+1
    bcc @scroll
    bne @set
    lda tmp
    cmp cam_x
    bcc @scroll
    beq @scroll
@set:
    lda tmp+1
    cmp lvl_maxcam+1
    bcc @ok
    bne @clamp
    lda tmp
    cmp lvl_maxcam
    bcc @ok
@clamp:
    lda lvl_maxcam
    sta tmp
    lda lvl_maxcam+1
    sta tmp+1
@ok:
    lda tmp
    sta cam_x
    lda tmp+1
    sta cam_x+1
@scroll:
    lda cam_x
    sta scroll_x
    lda cam_x+1
    and #1
    sta scroll_nt
    ; stream in column (cam_x >> 4) + 16
    lda cam_x+1
    sta tmp+1
    lda cam_x
    lsr tmp+1
    ror a
    lsr tmp+1
    ror a
    lsr tmp+1
    ror a
    lsr tmp+1
    ror a
    clc
    adc #16
    bcs @nocol
    cmp lvl_width
    bcs @nocol
    cmp cam_col
    beq @nocol
    bcc @nocol
    inc cam_col
    lda cam_col
    jsr build_column
    lda #1
    sta col_pending
@nocol:
    jmp spawn_objects

; ----------------------------------------------------------------- nametable columns
; A = level column. Fills colbuf (two tile columns) and col_addr.
build_column:
    sta bc_col
    and #$0F
    asl a
    sta col_addr
    lda #$20
    sta col_addr+1
    lda bc_col
    and #$10
    beq :+
    lda #$24
    sta col_addr+1
:   ldy bc_col
    lda (lvl_cols),y
    sta bc_b
    and #$0F
    sta bc_top
    lda #15
    sec
    sbc bc_top
    sta bc_top              ; first ground row (15 = none)
    lda bc_b
    lsr a
    lsr a
    lsr a
    lsr a
    sta bc_plat
    ; decorative clouds: 32 px wide, every 8 columns, on row 2 or 4
    lda #$FF
    sta bc_crow
    lda bc_col
    and #7
    cmp #2
    beq @cl
    cmp #3
    bne @rows
    lda #MT_CLOUDR
    bne @cset
@cl:
    lda #MT_CLOUDL
@cset:
    sta bc_cmt
    lda bc_col
    and #8
    lsr a
    lsr a
    clc
    adc #2
    sta bc_crow
@rows:
    ldx #0
    stx bc_row
@row:
    lda bc_row
    cmp bc_top
    bcc @notground
    beq @top
    lda #MT_GFILL
    bne @put
@top:
    lda #MT_GTOP
    bne @put
@notground:
    ldy bc_plat
    beq @noplat
    cmp bc_plat
    bne @noplat
    lda #MT_BRICK
    bne @put
@noplat:
    cmp bc_crow
    bne @sky
    lda bc_cmt
    jmp @put
@sky:
    lda #MT_SKY
@put:
    tay
    lda mt_tl,y
    sta colbuf,x
    lda mt_bl,y
    sta colbuf+1,x
    lda mt_tr,y
    sta colbuf+30,x
    lda mt_br,y
    sta colbuf+31,x
    inx
    inx
    inc bc_row
    lda bc_row
    cmp #15
    bne @row
    rts

; writes colbuf to col_addr (called from NMI, or directly with rendering off)
upload_column:
    lda ppu_ctrl
    ora #$04                ; VRAM increment 32 (vertical)
    sta PPUCTRL
    bit PPUSTATUS
    lda col_addr+1
    sta PPUADDR
    lda col_addr
    sta PPUADDR
    ldx #0
@a:
    lda colbuf,x
    sta PPUDATA
    inx
    cpx #30
    bne @a
    lda col_addr+1
    sta PPUADDR
    lda col_addr
    clc
    adc #1
    sta PPUADDR
@b:
    lda colbuf,x
    sta PPUDATA
    inx
    cpx #60
    bne @b
    lda ppu_ctrl
    sta PPUCTRL
    rts

; ----------------------------------------------------------------- objects
spawn_objects:
    lda cam_x+1
    sta tmp+1
    lda cam_x
    lsr tmp+1
    ror a
    lsr tmp+1
    ror a
    lsr tmp+1
    ror a
    lsr tmp+1
    ror a
    clc
    adc #17
    bcc :+
    lda #$FE
:   sta tmp+2               ; spawn everything up to this column
@loop:
    ldy obj_next
    lda (lvl_objs),y
    cmp #$FF
    beq @done
    cmp tmp+2
    beq @spawn
    bcs @done
@spawn:
    ldx #MAXOBJ-1
@find:
    lda obj_t,x
    beq @found
    dex
    bpl @find
@done:
    rts                     ; no free slot: retry next frame
@found:
    lda (lvl_objs),y
    asl a
    asl a
    asl a
    asl a
    sta obj_xl,x
    lda (lvl_objs),y
    lsr a
    lsr a
    lsr a
    lsr a
    sta obj_xh,x
    iny
    lda (lvl_objs),y
    asl a
    asl a
    asl a
    asl a
    sta obj_y,x
    iny
    lda (lvl_objs),y
    sta obj_t,x
    iny
    sty obj_next
    lda #0
    sta obj_vy,x
    sta obj_timer,x
    sta obj_inv,x
    lda #1
    sta obj_dir,x
    lda obj_t,x
    cmp #T_BOSS
    bne @loop
    ldy level
    lda boss_hp_tbl,y
    sta obj_hp,x
    sta boss_hp
    lda #60
    sta obj_timer,x
    lda #1
    sta boss_on
    jmp @loop

update_objects:
    lda px
    sec
    sbc cam_x
    tay
    clc
    adc #2
    sta p_l
    tya
    clc
    adc #13
    sta p_r
    lda py
    sta p_t
    clc
    adc #15
    sta p_b
    ldx #MAXOBJ-1
@loop:
    lda obj_t,x
    beq @next
    lda obj_xl,x
    sec
    sbc cam_x
    sta o_sx
    lda obj_xh,x
    sbc cam_x+1
    sta o_sx+1
    jsr obj_dispatch
@next:
    dex
    bpl @loop
    rts

obj_dispatch:
    lda obj_t,x
    asl a
    tay
    lda obj_tbl+1,y
    pha
    lda obj_tbl,y
    pha
    rts

obj_tbl:
    .word 0, o_coin-1, o_walker-1, o_walker-1, o_boss-1, o_squish-1, o_bossdie-1

; removes the object when it is more than 32 px left of the screen. C=1 if removed
check_despawn:
    lda o_sx+1
    bpl @keep
    cmp #$FF
    bne @kill
    lda o_sx
    cmp #$E0
    bcs @keep
@kill:
    lda #T_NONE
    sta obj_t,x
    sec
    rts
@keep:
    clc
    rts

; C=1 if the object overlaps the player (only while playing and on screen)
test_overlap:
    lda state
    cmp #ST_PLAY
    bne @no
    lda o_sx+1
    bne @no
    lda o_sx
    cmp #240
    bcs @no
    ldy obj_t,x
    lda o_sx
    clc
    adc box_l,y
    sta o_l
    lda o_sx
    clc
    adc box_r,y
    sta o_r
    lda obj_y,x
    clc
    adc box_t,y
    sta o_t
    lda obj_y,x
    clc
    adc box_b,y
    sta o_b
    lda o_r
    cmp p_l
    bcc @no
    lda p_r
    cmp o_l
    bcc @no
    lda o_b
    cmp p_t
    bcc @no
    lda p_b
    cmp o_t
    bcc @no
    sec
    rts
@no:
    clc
    rts

; C=1 if the player is falling onto the top part of the object
is_stomp:
    lda vy_h
    bmi @no
    ora vy_l
    beq @no
    lda o_t
    clc
    adc #8
    cmp p_b
    beq @no
    bcc @no
    sec
    rts
@no:
    clc
    rts

; gravity + ground snap. tmp+3 = object height, A = x offset of the foot probe.
; returns A=1 (Z=0) on ground, A=0 (Z=1) in the air
obj_gravity16:
    lda #16
    sta tmp+3
    lda #8
obj_gravity:
    clc
    adc obj_xl,x
    sta chk_x
    lda obj_xh,x
    adc #0
    sta chk_x+1
    lda obj_vy,x
    bmi @air
    lda obj_y,x
    clc
    adc tmp+3
    bcs @air
    sta chk_y
    jsr is_solid
    bcc @air
    lda chk_y
    and #$F0
    sec
    sbc tmp+3
    sta obj_y,x
    lda #0
    sta obj_vy,x
    lda #1
    rts
@air:
    lda frame
    and #1
    bne @nog
    lda obj_vy,x
    bmi @inc
    cmp #4
    bcs @nog
@inc:
    inc obj_vy,x
@nog:
    lda obj_y,x
    clc
    adc obj_vy,x
    sta obj_y,x
    lda #0
    rts

o_coin:
    jsr check_despawn
    bcs @rts
    jsr test_overlap
    bcc @rts
    lda #T_NONE
    sta obj_t,x
    inc coins
    lda coins
    cmp #100
    bcc :+
    lda #0
    sta coins
    jsr add_life
:   jmp sfx_coin
@rts:
    rts

o_squish:
    dec obj_timer,x
    bne @rts
    lda #T_NONE
    sta obj_t,x
@rts:
    rts

o_walker:
    jsr check_despawn
    bcs @rts
    lda state
    cmp #ST_PLAY
    bne @rts                ; freeze during level clear
    lda frame
    and #1
    beq @grav
    lda obj_dir,x
    bne @left
    lda obj_xl,x
    clc
    adc #16
    sta chk_x
    lda obj_xh,x
    adc #0
    sta chk_x+1
    jsr @wall
    bcs @turn
    inc obj_xl,x
    bne @grav
    inc obj_xh,x
    jmp @grav
@left:
    lda obj_xl,x
    sec
    sbc #1
    sta chk_x
    lda obj_xh,x
    sbc #0
    sta chk_x+1
    jsr @wall
    bcs @turn
    lda obj_xl,x
    bne :+
    dec obj_xh,x
:   dec obj_xl,x
    jmp @grav
@turn:
    lda obj_dir,x
    eor #1
    sta obj_dir,x
@grav:
    jsr obj_gravity16
    lda obj_y,x
    cmp #224
    bcc @alive
    lda #T_NONE             ; fell into a pit
    sta obj_t,x
@rts:
    rts
@alive:
    jsr test_overlap
    bcc @rts
    lda obj_t,x
    cmp #T_SPIKY
    beq @hurt
    jsr is_stomp
    bcc @hurt
    lda #T_SQUISH
    sta obj_t,x
    lda #30
    sta obj_timer,x
    jsr player_bounce
    jmp sfx_stomp
@hurt:
    jmp kill_player
@wall:
    lda obj_y,x
    clc
    adc #8
    sta chk_y
    jmp is_solid

o_boss:
    lda o_sx+1              ; never leave the arena on the left
    bpl :+
    lda cam_x
    sta obj_xl,x
    lda cam_x+1
    sta obj_xh,x
    lda #0
    sta o_sx
    sta o_sx+1
:   lda obj_hp,x
    sta boss_hp
    lda obj_inv,x
    beq :+
    dec obj_inv,x
:   lda obj_vy,x
    bne @move               ; keep direction while airborne
    lda px                  ; face the player
    sec
    sbc obj_xl,x
    sta tmp
    lda px_h
    sbc obj_xh,x
    sta tmp+1
    lda tmp
    sec
    sbc #8
    lda tmp+1
    sbc #0
    bmi @facel
    lda #0
    sta obj_dir,x
    beq @move
@facel:
    lda #1
    sta obj_dir,x
@move:
    ldy level
    lda frame
    and boss_mask,y
    bne @grav
    lda obj_dir,x
    bne @ml
    lda obj_xl,x
    clc
    adc #32
    sta chk_x
    lda obj_xh,x
    adc #0
    sta chk_x+1
    jsr @wall
    bcs @grav
    inc obj_xl,x
    bne @grav
    inc obj_xh,x
    jmp @grav
@ml:
    lda o_sx
    ora o_sx+1
    beq @grav
    lda obj_xl,x
    sec
    sbc #1
    sta chk_x
    lda obj_xh,x
    sbc #0
    sta chk_x+1
    jsr @wall
    bcs @grav
    lda obj_xl,x
    bne :+
    dec obj_xh,x
:   dec obj_xl,x
@grav:
    lda #32
    sta tmp+3
    lda #16
    jsr obj_gravity
    beq @inter
    dec obj_timer,x
    bne @inter
    ldy level
    lda boss_jump_t,y
    sta obj_timer,x
    lda boss_jump_v,y
    sta obj_vy,x
@inter:
    jsr test_overlap
    bcc @rts
    jsr is_stomp
    bcc @side
    jsr player_bounce
    lda obj_inv,x
    bne @rts
    lda #60
    sta obj_inv,x
    dec obj_hp,x
    lda obj_hp,x
    sta boss_hp
    bne @hit
    lda #T_BOSSDIE
    sta obj_t,x
    lda #$FB
    sta obj_vy,x
    lda #ST_CLEAR
    sta state
    lda #180
    sta timer
    jmp sfx_clear
@hit:
    jmp sfx_hit
@side:
    lda obj_inv,x
    bne @rts
    jmp kill_player
@rts:
    rts
@wall:
    lda obj_y,x
    clc
    adc #16
    sta chk_y
    jmp is_solid

o_bossdie:
    lda obj_y,x
    cmp #232
    bcs @rts
    lda frame
    and #1
    bne :+
    inc obj_vy,x
:   lda obj_y,x
    clc
    adc obj_vy,x
    sta obj_y,x
@rts:
    rts

; ----------------------------------------------------------------- drawing
draw_all:
    jsr clear_oam
    jsr draw_hud
    jsr draw_player
    jmp draw_objects

; put one 8x8 sprite: A = tile, at hs_x/hs_y with hs_a; advances hs_x by 8
put_spr:
    ldx spr_idx
    sta oam+1,x
    lda hs_y
    sta oam,x
    lda hs_a
    sta oam+2,x
    lda hs_x
    sta oam+3,x
    clc
    adc #8
    sta hs_x
    txa
    clc
    adc #4
    sta spr_idx
    rts

draw_hud:
    lda #14
    sta hs_y
    lda #16
    sta hs_x
    lda #0
    sta hs_a
    lda #SPR_HEART
    jsr put_spr
    lda #2
    sta hs_a
    lda #'X'
    jsr put_spr
    lda lives
    clc
    adc #'0'
    jsr put_spr
    lda #56
    sta hs_x
    lda #SPR_COINI
    jsr put_spr
    lda coins
    ldy #'0'
@tens:
    cmp #10
    bcc @ones
    sbc #10
    iny
    bne @tens
@ones:
    pha
    tya
    jsr put_spr
    pla
    clc
    adc #'0'
    jsr put_spr
    ; boss health on the second row
    lda boss_hp
    beq @rts
    sta tmp
    lda #24
    sta hs_y
    lda #200
    sta hs_x
    lda #0
    sta hs_a
@hp:
    lda #SPR_HEART
    jsr put_spr
    dec tmp
    bne @hp
@rts:
    rts

draw_player:
    lda py
    cmp #240
    bcs @rts
    lda px
    sec
    sbc cam_x
    sta ms_x
    lda px_h
    sbc cam_x+1
    sta ms_x+1
    lda py
    sta ms_y
    lda state
    cmp #ST_DYING
    bne @alive
    lda #0
    sta ms_attr
    lda #SPR_DEAD
    bne @set
@alive:
    lda facing
    beq :+
    lda #$40
:   sta ms_attr
    lda on_ground
    beq @jump
    lda vx_h
    ora vx_l
    beq @stand
    lda anim
    and #8
    beq @w1
    lda #SPR_WALK2
    bne @set
@w1:
    lda #SPR_WALK1
    bne @set
@stand:
    lda #SPR_STAND
    bne @set
@jump:
    lda #SPR_JUMP
@set:
    sta ms_tile
    jmp draw_2x2
@rts:
    rts

; rotates the starting slot every frame so overlapping sprites flicker
; instead of vanishing (max 8 sprites per scanline)
draw_objects:
    lda frame
    and #7
    sta do_i
    lda #MAXOBJ
    sta do_cnt
@loop:
    ldx do_i
    lda obj_t,x
    beq @next
    jsr draw_obj
@next:
    lda do_i
    clc
    adc #1
    and #7
    sta do_i
    dec do_cnt
    bne @loop
    rts

draw_obj:
    lda obj_xl,x
    sec
    sbc cam_x
    sta ms_x
    lda obj_xh,x
    sbc cam_x+1
    sta ms_x+1
    lda obj_y,x
    sta ms_y
    lda obj_t,x
    cmp #T_COIN
    beq @coin
    cmp #T_WALKER
    beq @walker
    cmp #T_SPIKY
    beq @spiky
    cmp #T_SQUISH
    beq @squish
    cmp #T_BOSS
    beq @boss
    ; T_BOSSDIE: upside down, falling off the screen
    lda obj_y,x
    cmp #232
    bcs @rts
    lda #SPR_BOSSA
    sta ms_tile
    lda #$83
    sta ms_attr
    jmp draw_4x4
@rts:
    rts
@coin:
    lda ms_x
    clc
    adc #4
    sta ms_x
    lda ms_x+1
    adc #0
    sta ms_x+1
    lda frame
    and #16
    beq :+
    lda #SPR_COINB-SPR_COINA
:   clc
    adc #SPR_COINA
    sta ms_tile
    lda #1
    sta ms_w
    lda #2
    sta ms_h
    sta ms_attr
    jmp draw_meta
@squish:
    lda #SPR_SQUISH
    sta ms_tile
    lda #1
    sta ms_attr
    jmp draw_2x2
@walker:
    lda #SPR_WALKA
    sta ms_tile
    lda #1
    bne @enemy
@spiky:
    lda #SPR_SPIKYA
    sta ms_tile
    lda #3
@enemy:
    ldy obj_dir,x           ; art faces right: flip when walking left
    beq :+
    ora #$40
:   sta ms_attr
    lda frame
    and #8
    beq :+
    lda ms_tile
    clc
    adc #4
    sta ms_tile
:   jmp draw_2x2
@boss:
    lda #SPR_BOSSA
    sta ms_tile
    lda frame
    and #16
    beq :+
    lda #SPR_BOSSB
    sta ms_tile
:   lda #3
    sta tmp
    lda obj_inv,x
    beq @noflash
    lda frame
    and #4
    beq @noflash
    lda #0                  ; flash while invulnerable
    sta tmp
@noflash:
    lda tmp
    ldy obj_dir,x
    beq :+
    ora #$40
:   sta ms_attr
    jmp draw_4x4

draw_2x2:
    lda #2
    sta ms_w
    sta ms_h
    jmp draw_meta

draw_4x4:
    lda #4
    sta ms_w
    sta ms_h
    ; fall through

; ms_x (16 bit, screen), ms_y, ms_tile, ms_w, ms_h, ms_attr ($40 hflip, $80 vflip)
; tiles are row-major; columns off screen are clipped
draw_meta:
    lda spr_full
    bne @rts
    lda #0
    sta ms_r
    lda ms_y
    sta ms_cy
@row:
    ; source row (reversed when vertically flipped) * width
    lda ms_r
    bit ms_attr
    bpl :+
    lda ms_h
    sec
    sbc #1
    sbc ms_r
:   tay
    lda #0
@mul:
    dey
    bmi :+
    clc
    adc ms_w
    jmp @mul
:   sta ms_rowbase
    lda #0
    sta ms_c
    lda ms_x
    sta ms_cx
    lda ms_x+1
    sta ms_cx+1
@col:
    lda ms_cx+1
    bne @skip
    lda ms_cy
    cmp #239
    bcs @skip
    lda ms_c
    bit ms_attr
    bvc :+
    lda ms_w
    sec
    sbc #1
    sbc ms_c
:   clc
    adc ms_rowbase
    adc ms_tile
    ldx spr_idx
    sta oam+1,x
    lda ms_cy
    sta oam,x
    lda ms_attr
    sta oam+2,x
    lda ms_cx
    sta oam+3,x
    txa
    clc
    adc #4
    sta spr_idx
    bne @skip
    lda #1
    sta spr_full
@rts:
    rts
@skip:
    lda ms_cx
    clc
    adc #8
    sta ms_cx
    bcc :+
    inc ms_cx+1
:   inc ms_c
    lda ms_c
    cmp ms_w
    bne @col
    lda ms_cy
    clc
    adc #8
    bcs @rts2               ; would wrap to the top of the screen
    sta ms_cy
    inc ms_r
    lda ms_r
    cmp ms_h
    beq @rts2
    jmp @row
@rts2:
    rts

draw_pause:
    lda #108
    sta hs_y
    lda #108
    sta hs_x
    lda #2
    sta hs_a
    ldy #0
@l:
    lda txt_pause,y
    beq @rts
    sty tmp
    jsr put_spr
    ldy tmp
    iny
    bne @l
@rts:
    rts

; ----------------------------------------------------------------- sound effects
sfx_jump:
    lda #$86
    sta $4000
    lda #$AB
    sta $4001
    lda #$C0
    sta $4002
    lda #$08
    sta $4003
    rts

sfx_bump:
    lda #$02
    sta $400C
    lda #$0C
    sta $400E
    lda #$08
    sta $400F
    rts

sfx_coin:
    lda #$83
    sta $4004
    lda #$00
    sta $4005
    lda #$50
    sta $4006
    lda #$08
    sta $4007
    rts

sfx_stomp:
    lda #$05
    sta $400C
    lda #$0A
    sta $400E
    lda #$08
    sta $400F
    rts

sfx_hit:
    lda #$08
    sta $400C
    lda #$04
    sta $400E
    lda #$08
    sta $400F
    rts

sfx_die:
    lda #$8F
    sta $4000
    lda #$B2
    sta $4001
    lda #$80
    sta $4002
    lda #$09
    sta $4003
    rts

sfx_clear:
    lda #$8F
    sta $4004
    lda #$AA
    sta $4005
    lda #$00
    sta $4006
    lda #$0A
    sta $4007
    rts

; =============================================================================
.segment "RODATA"

palette:
    .byte $22,$0F,$17,$30, $22,$0F,$17,$30, $22,$0F,$17,$30, $22,$0F,$17,$30
    .byte $22,$16,$37,$02, $22,$17,$37,$0F, $22,$28,$17,$30, $22,$1A,$30,$0F

; per level: boss/spiky colour, boss health, move mask, jump interval, jump speed
boss_color:  .byte $1A, $16, $14
boss_hp_tbl: .byte 3, 4, 5
boss_mask:   .byte 1, 0, 0
boss_jump_t: .byte 100, 80, 55
boss_jump_v: .byte $FA, $F9, $F8

; collision box per object type (offsets from the object's top-left)
box_l: .byte 0, 4, 2, 2, 3, 0, 0
box_r: .byte 0, 11, 13, 13, 28, 0, 0
box_t: .byte 0, 0, 4, 4, 6, 0, 0
box_b: .byte 0, 15, 15, 15, 31, 0, 0

; metatile -> tiles                sky  gtop gfill brick cloudL cloudR
mt_tl: .byte $00, $01, $05, $09, $0D, $11
mt_tr: .byte $00, $02, $06, $0A, $0E, $12
mt_bl: .byte $00, $03, $07, $0B, $0F, $13
mt_br: .byte $00, $04, $08, $0C, $10, $14

floor_tiles:
    .byte $01,$02, $03,$04, $05,$06, $07,$08

txt_title:
    .byte $21,$0C, "BOX HERO", 0
    .byte $21,$63, "UN GIOCO PER SUP GAME BOX", 0
    .byte $22,$0A, "PREMI START", 0
    .byte $22,$68, "A SALTA  B CORRI", 0
    .byte $FF
txt_intro:
    .byte $21,$8B, "LIVELLO", 0
    .byte $21,$EC, "VITE X", 0
    .byte $FF
txt_gameover:
    .byte $21,$CB, "GAME OVER", 0
    .byte $FF
txt_win:
    .byte $21,$8B, "HAI VINTO!", 0
    .byte $21,$E4, "GRAZIE PER AVER GIOCATO", 0
    .byte $22,$4A, "PREMI START", 0
    .byte $FF
txt_pause:
    .byte "PAUSA", 0

.include "levels.inc"

; =============================================================================
.segment "VECTORS"
    .word nmi, reset, irq

.segment "CHARS"
    .incbin "chr.bin"
