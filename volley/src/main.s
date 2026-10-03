; =============================================================================
; SUP VOLLEY - beach volley 1 contro 1 per SUP Game Box (NES / VT02, mapper 0)
; Assemblare con:  make   (richiede cc65 e python3)
; =============================================================================

PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
OAMADDR   = $2003
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007
OAMDMA    = $4014
JOY1      = $4016
JOY2      = $4017

BTN_A      = $80
BTN_B      = $40
BTN_SELECT = $20
BTN_START  = $10
BTN_UP     = $08
BTN_DOWN   = $04
BTN_LEFT   = $02
BTN_RIGHT  = $01

ST_TITLE = 0
ST_PLAY  = 1
ST_POINT = 2
ST_OVER  = 3

WIN_SCORE  = 15
GROUND_Y   = 160            ; player top when standing (feet at 200)
BALL_FLOOR = 184            ; ball top when touching the sand
NET_L      = 124
NET_R      = 131
NET_TOP    = 120

; physics, 8.8 fixed point
BALL_GRAV  = $18
BALL_MAXV  = $06
HIT_VY     = $FB80          ; -4.5 px/frame
PL_GRAV    = $30
JUMP_VY    = $FB00          ; -5 px/frame
PL_SPEED   = 2

.segment "HEADER"
    .byte "NES", $1A, 1, 1, $01, $00
    .res 8, 0

; =============================================================================
.segment "ZEROPAGE"
nmi_count:  .res 1
ppu_on:     .res 1
txt_lock:   .res 1
tmp:        .res 4
ptr:        .res 2
pad1:       .res 1
pad1_old:   .res 1
pad2:       .res 1
pad2_old:   .res 1
in_cur:     .res 2          ; per player: buttons held (pad or CPU)
in_new:     .res 2          ; per player: buttons just pressed
ai_btn_old: .res 1
state:      .res 1
timer:      .res 1
frame:      .res 1
paused:     .res 1
mode:       .res 1          ; 1 = vs CPU, 2 = two players
menu:       .res 1
score:      .res 2
server:     .res 1
winner:     .res 1
rng:        .res 1
; players (index 0 = Nonno, 1 = Toro)
pl_x:       .res 2
pl_y:       .res 2
pl_ys:      .res 2
pl_vyl:     .res 2
pl_vyh:     .res 2
pl_ground:  .res 2
pl_cd:      .res 2          ; frames before the player can touch the ball again
pl_spike:   .res 2          ; frames left in which a touch is a spike
pl_moving:  .res 2
; ball
b_xs:       .res 1
b_x:        .res 1
b_ys:       .res 1
b_y:        .res 1
b_vxl:      .res 1
b_vxh:      .res 1
b_vyl:      .res 1
b_vyh:      .res 1
; CPU player
ai_dirty:   .res 1
ai_land:    .res 1
ai_err:     .res 1
s_xs:       .res 1
s_x:        .res 1
s_ys:       .res 1
s_y:        .res 1
s_vxl:      .res 1
s_vxh:      .res 1
s_vyl:      .res 1
s_vyh:      .res 1
; sprites
spr_idx:    .res 1
ms_x:       .res 1
ms_y:       .res 1
ms_cnt:     .res 1

.segment "OAM"
oam:        .res 256

.segment "BSS"
txtq:       .res 96         ; queued nametable writes: hi, lo, count, bytes... 0
txtq_len:   .res 1

; =============================================================================
.segment "CODE"

reset:
    sei
    cld
    ldx #$40
    stx $4017
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
    sta $4015
    lda #$5A
    sta rng
    lda #$88                ; NMI on, sprites at $1000
    sta PPUCTRL
    jsr title_init

main_loop:
    jsr wait_frame
    jsr read_pads
    inc frame
    jsr rng_next
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
    .word st_title-1, st_play-1, st_point-1, st_over-1

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
    lda txt_lock
    bne @notext
    ldx #0
@entry:
    lda txtq,x
    beq @textdone
    bit PPUSTATUS
    sta PPUADDR
    inx
    lda txtq,x
    sta PPUADDR
    inx
    ldy txtq,x
    inx
@ch:
    lda txtq,x
    sta PPUDATA
    inx
    dey
    bne @ch
    jmp @entry
@textdone:
    lda #0
    sta txtq
    sta txtq_len
@notext:
    lda #$88
    sta PPUCTRL
    bit PPUSTATUS
    lda #0
    sta PPUSCROLL
    sta PPUSCROLL
    lda #%00011110
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

read_pads:
    lda pad1
    sta pad1_old
    lda pad2
    sta pad2_old
    lda #1
    sta JOY1
    lda #0
    sta JOY1
    ldx #8
@l:
    lda JOY1
    and #%00000011
    cmp #1
    rol pad1
    lda JOY2
    and #%00000011
    cmp #1
    rol pad2
    dex
    bne @l
    rts

rng_next:                   ; 8-bit Galois LFSR
    lda rng
    lsr a
    bcc :+
    eor #$B8
:   sta rng
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

; ptr = 1024-byte nametable image
load_nametable:
    bit PPUSTATUS
    lda #$20
    sta PPUADDR
    lda #$00
    sta PPUADDR
    ldx #4
    ldy #0
@l:
    lda (ptr),y
    sta PPUDATA
    iny
    bne @l
    inc ptr+1
    dex
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
    rts

; queue a text: ptr -> [addr hi, addr lo, chars..., 0]
queue_text:
    inc txt_lock
    ldx txtq_len
    ldy #0
    lda (ptr),y
    sta txtq,x
    inx
    iny
    lda (ptr),y
    sta txtq,x
    inx
    stx tmp                 ; where the count goes
    inx
    iny
@l:
    lda (ptr),y
    beq @end
    sta txtq,x
    inx
    iny
    bne @l
@end:
    txa
    sec
    sbc tmp
    sbc #1
    ldy tmp
    sta txtq,y
    lda #0
    sta txtq,x
    stx txtq_len
    dec txt_lock
    rts

; A = text index in msg_lo/msg_hi
queue_msg:
    tax
    lda msg_lo,x
    sta ptr
    lda msg_hi,x
    sta ptr+1
    jmp queue_text

; writes both scores into the nametable
queue_scores:
    inc txt_lock
    ldx txtq_len
    lda #$20
    sta txtq,x
    lda #$28
    sta txtq+1,x
    lda #2
    sta txtq+2,x
    lda score
    jsr two_digits
    sta txtq+4,x
    tya
    sta txtq+3,x
    lda #$20
    sta txtq+5,x
    lda #$3C
    sta txtq+6,x
    lda #2
    sta txtq+7,x
    lda score+1
    jsr two_digits
    sta txtq+9,x
    tya
    sta txtq+8,x
    lda #0
    sta txtq+10,x
    txa
    clc
    adc #10
    sta txtq_len
    dec txt_lock
    rts

; A = 0..99 -> Y = tens char, A = ones char
two_digits:
    ldy #'0'
@t:
    cmp #10
    bcc @o
    sbc #10
    iny
    bne @t
@o:
    clc
    adc #'0'
    rts

; ================================================================ title
title_init:
    jsr ppu_off
    lda #<title_nam
    sta ptr
    lda #>title_nam
    sta ptr+1
    jsr load_nametable
    jsr load_palette
    jsr clear_oam
    lda #0
    sta txtq
    sta txtq_len
    sta menu
    lda #ST_TITLE
    sta state
    jmp ppu_enable

st_title:
    lda pad1
    eor pad1_old
    and pad1
    sta tmp
    and #BTN_UP|BTN_DOWN|BTN_SELECT
    beq @nomove
    lda menu
    eor #1
    sta menu
    jsr sfx_tick
@nomove:
    lda tmp
    and #BTN_START
    beq @draw
    ldx menu
    inx
    stx mode
    jmp game_init
@draw:
    jsr clear_oam
    lda #72                 ; cursor
    sta ms_x
    lda menu
    beq :+
    lda #16
:   clc
    adc #175
    ldx spr_idx
    sta oam,x
    lda #TILE_CURSOR
    sta oam+1,x
    lda #0
    sta oam+2,x
    lda ms_x
    sta oam+3,x
    inx
    inx
    inx
    inx
    stx spr_idx
    ; bouncing ball: y = 72 + |((frame & 63) - 32)|
    lda frame
    and #63
    sec
    sbc #32
    bpl :+
    eor #$FF
    clc
    adc #1
:   clc
    adc #56
    sta ms_y
    lda #120
    sta ms_x
    lda #<ms_ball0
    sta ptr
    lda #>ms_ball0
    sta ptr+1
    jsr draw_ms
    lda #40
    ldx #0
    ldy #0
    jsr draw_char_at
    lda #192
    ldx #3
    ldy #0
    jmp draw_char_at

; A = x, X = character pose index, Y unused (y = GROUND_Y)
draw_char_at:
    sta ms_x
    lda #GROUND_Y
    sta ms_y
    lda char_ms_lo,x
    sta ptr
    lda char_ms_hi,x
    sta ptr+1
    jmp draw_ms

; ================================================================ match
game_init:
    jsr ppu_off
    lda #<game_nam
    sta ptr
    lda #>game_nam
    sta ptr+1
    jsr load_nametable
    jsr clear_oam
    lda #0
    sta score
    sta score+1
    sta server
    sta paused
    sta txtq
    sta txtq_len
    jsr reset_rally
    lda #ST_PLAY
    sta state
    jmp ppu_enable

reset_rally:
    lda #48
    sta pl_x
    lda #184
    sta pl_x+1
    ldx #1
@p:
    lda #GROUND_Y
    sta pl_y,x
    lda #0
    sta pl_ys,x
    sta pl_vyl,x
    sta pl_vyh,x
    sta pl_cd,x
    sta pl_spike,x
    sta pl_moving,x
    lda #1
    sta pl_ground,x
    dex
    bpl @p
    ; the ball drops onto the server's head
    ldx server
    lda pl_x,x
    clc
    adc #4
    sta b_x
    lda #24
    sta b_y
    lda #0
    sta b_xs
    sta b_ys
    sta b_vxl
    sta b_vxh
    sta b_vyl
    sta b_vyh
    lda #1
    sta ai_dirty
    jmp sfx_whistle

st_play:
    lda pad1
    eor pad1_old
    and pad1
    and #BTN_START
    beq @nopause
    lda paused
    eor #1
    sta paused
    beq @resume
    lda #MSG_PAUSE
    jmp queue_msg
@resume:
    lda #MSG_CLEAR
    jmp queue_msg
@nopause:
    lda paused
    beq @run
    rts
@run:
    jsr get_inputs
    ldx #0
    jsr update_player
    ldx #1
    jsr update_player
    jsr update_ball
    jmp draw_game

st_point:
    jsr draw_game
    dec timer
    bne @rts
    lda #MSG_CLEAR
    jsr queue_msg
    ldx winner
    lda score,x
    cmp #WIN_SCORE
    bcs @over
    jsr reset_rally
    lda #ST_PLAY
    sta state
@rts:
    rts
@over:
    lda #ST_OVER
    sta state
    lda winner
    clc
    adc #MSG_WIN_NONNO
    jsr queue_msg
    lda #MSG_REMATCH
    jsr queue_msg
    jmp sfx_point

st_over:
    ; the winner hops for joy
    ldx winner
    lda pl_ground,x
    beq :+
    lda #<JUMP_VY
    sta pl_vyl,x
    lda #>JUMP_VY
    sta pl_vyh,x
    lda #0
    sta pl_ground,x
:   lda #0
    sta in_cur
    sta in_cur+1
    sta in_new
    sta in_new+1
    ldx #0
    jsr update_player
    ldx #1
    jsr update_player
    jsr draw_game
    lda pad1
    eor pad1_old
    and pad1
    and #BTN_START
    beq @rts
    jmp title_init
@rts:
    rts

; X = player who scored
award_point:
    stx winner
    stx server
    inc score,x
    jsr queue_scores
    lda winner
    clc
    adc #MSG_POINT_NONNO
    jsr queue_msg
    lda #ST_POINT
    sta state
    lda #100
    sta timer
    jmp sfx_point

; ----------------------------------------------------------------- input
get_inputs:
    lda pad1
    sta in_cur
    eor pad1_old
    and pad1
    sta in_new
    lda mode
    cmp #2
    bne @cpu
    lda pad2
    sta in_cur+1
    eor pad2_old
    and pad2
    sta in_new+1
    rts
@cpu:
    jsr ai_think            ; A = buttons
    sta in_cur+1
    eor ai_btn_old
    and in_cur+1
    sta in_new+1
    lda in_cur+1
    sta ai_btn_old
    rts

; ----------------------------------------------------------------- players
update_player:
    lda #0
    sta pl_moving,x
    lda in_cur,x
    and #BTN_LEFT
    beq @noleft
    lda pl_x,x
    sec
    sbc #PL_SPEED
    bcc @minx
    cmp x_min,x
    bcs @setx
@minx:
    lda x_min,x
    jmp @setx
@noleft:
    lda in_cur,x
    and #BTN_RIGHT
    beq @hdone
    lda pl_x,x
    clc
    adc #PL_SPEED
    cmp x_max,x
    bcc @setx
    lda x_max,x
@setx:
    cmp pl_x,x
    beq @hdone
    sta pl_x,x
    inc pl_moving,x
@hdone:
    lda pl_cd,x
    beq :+
    dec pl_cd,x
:   lda pl_spike,x
    beq :+
    dec pl_spike,x
:   lda pl_ground,x
    beq @air
    lda in_new,x
    and #BTN_A
    beq @rts
    lda #<JUMP_VY
    sta pl_vyl,x
    lda #>JUMP_VY
    sta pl_vyh,x
    lda #0
    sta pl_ground,x
    jmp sfx_jump
@air:
    lda in_new,x
    and #BTN_B
    beq :+
    lda #14
    sta pl_spike,x
:   lda pl_vyl,x
    clc
    adc #PL_GRAV
    sta pl_vyl,x
    lda pl_vyh,x
    adc #0
    sta pl_vyh,x
    lda pl_ys,x
    clc
    adc pl_vyl,x
    sta pl_ys,x
    lda pl_y,x
    adc pl_vyh,x
    sta pl_y,x
    cmp #GROUND_Y
    bcc @rts
    lda pl_vyh,x
    bmi @rts
    lda #GROUND_Y
    sta pl_y,x
    lda #0
    sta pl_ys,x
    sta pl_vyl,x
    sta pl_vyh,x
    lda #1
    sta pl_ground,x
@rts:
    rts

; ----------------------------------------------------------------- ball
neg_vx:
    lda #0
    sec
    sbc b_vxl
    sta b_vxl
    lda #0
    sbc b_vxh
    sta b_vxh
    rts

neg_vy:
    lda #0
    sec
    sbc b_vyl
    sta b_vyl
    lda #0
    sbc b_vyh
    sta b_vyh
    rts

update_ball:
    ; gravity
    lda b_vyl
    clc
    adc #BALL_GRAV
    sta b_vyl
    lda b_vyh
    adc #0
    sta b_vyh
    bmi :+
    cmp #BALL_MAXV
    bcc :+
    lda #BALL_MAXV
    sta b_vyh
    lda #0
    sta b_vyl
:   ; horizontal move with wall bounces
    ldy #0
    lda b_vxh
    bpl :+
    dey
:   clc
    lda b_xs
    adc b_vxl
    sta b_xs
    lda b_x
    adc b_vxh
    sta b_x
    tya
    adc #0
    beq @noleft
    lda #0                  ; went past the left wall
    sta b_x
    jsr neg_vx
    jsr ball_bounced
@noleft:
    lda b_x
    cmp #241
    bcc @noright
    lda #240
    sta b_x
    lda b_vxh
    bmi @noright
    jsr neg_vx
    jsr ball_bounced
@noright:
    ; vertical move
    ldy #0
    lda b_vyh
    bpl :+
    dey
:   clc
    lda b_ys
    adc b_vyl
    sta b_ys
    lda b_y
    adc b_vyh
    sta b_y
    tya
    adc #0
    beq @notop
    lda #0                  ; hit the top of the screen
    sta b_y
    jsr neg_vy
    jsr ball_bounced
@notop:
    jsr ball_net
    ldx #0
    jsr ball_player
    ldx #1
    jsr ball_player
    ; touched the sand?
    lda b_y
    cmp #BALL_FLOOR
    bcc @rts
    lda b_vyh
    bmi @rts
    lda #BALL_FLOOR
    sta b_y
    lda state
    cmp #ST_PLAY
    bne @rts
    lda b_x
    clc
    adc #8
    cmp #128
    ldx #0                  ; landed on the right: Nonno scores
    bcs :+
    inx
:   jmp award_point
@rts:
    rts

ball_bounced:
    lda #1
    sta ai_dirty
    rts

ball_net:
    lda b_x
    clc
    adc #15
    cmp #NET_L
    bcc @rts
    lda b_x
    cmp #NET_R+1
    bcs @rts
    lda b_y
    clc
    adc #15
    cmp #NET_TOP
    bcc @rts
    ; on top of the tape, falling: bounce up
    cmp #NET_TOP+8
    bcs @side
    lda b_vyh
    bmi @side
    lda #NET_TOP-16
    sta b_y
    lda #$80
    sta b_vyl
    lda #$FD
    sta b_vyh
    lda b_x                 ; nudge it off the tape
    clc
    adc #8
    cmp #128
    lda #$C0
    ldy #$FF
    bcc :+
    lda #$40
    ldy #$00
:   clc
    adc b_vxl
    sta b_vxl
    tya
    adc b_vxh
    sta b_vxh
    jsr ball_bounced
    jmp sfx_net
@side:
    lda b_x
    clc
    adc #8
    cmp #128
    bcs @right
    lda #NET_L-16
    sta b_x
    lda b_vxh
    bmi @snd
    jsr neg_vx
    jmp @snd
@right:
    lda #NET_R+1
    sta b_x
    lda b_vxh
    bpl @snd
    jsr neg_vx
@snd:
    jsr ball_bounced
    jmp sfx_net
@rts:
    rts

; X = player. Touch when the ball centre is near the player's head/body.
ball_player:
    lda pl_cd,x
    bne @rts
    lda state
    cmp #ST_PLAY
    bne @rts
    ; dx = (ball x + 8) - (player x + 12), 16 bit
    lda b_x
    sec
    sbc pl_x,x
    sta tmp
    lda #0
    sbc #0
    sta tmp+1
    lda tmp
    sec
    sbc #4
    sta tmp
    lda tmp+1
    sbc #0
    bne @neg
    lda tmp
    cmp #18
    bcs @rts
    bcc @inx
@neg:
    cmp #$FF
    bne @rts
    lda tmp
    cmp #$EF
    bcc @rts
@inx:
    ; vertical: ball bottom >= player top and ball top <= player top + 32
    lda b_y
    clc
    adc #16
    cmp pl_y,x
    bcc @rts
    lda pl_y,x
    clc
    adc #32
    cmp b_y
    bcc @rts
    ; touch!
    lda #12
    sta pl_cd,x
    jsr ball_bounced
    lda pl_ground,x
    bne @bump
    lda in_cur,x            ; spike: B held (or pressed just before) in the air...
    and #BTN_B
    ora pl_spike,x
    beq @bump
    lda b_y                 ; ...with the ball above the tape...
    cmp #NET_TOP-24
    bcs @bump
    lda pl_x,x              ; ...and close to the net
    sec
    sbc spike_zone,x
    cmp #40
    bcs @bump
    lda #0
    sta pl_spike,x
    lda spike_vxl,x
    sta b_vxl
    lda spike_vxh,x
    sta b_vxh
    lda #$00
    sta b_vyl
    lda #$02                ; +2 px/frame: steep but clears the tape
    sta b_vyh
    jmp sfx_spike
@rts:
    rts
@bump:
    ; vx = dx * 12 + push toward the other side (+/- input)
    lda tmp
    sta tmp+2
    lda #0
    ldy tmp
    bpl :+
    lda #$FF
:   sta tmp+3
    asl tmp+2
    rol tmp+3
    asl tmp+2
    rol tmp+3
    lda tmp+2
    sta tmp
    lda tmp+3
    sta tmp+1               ; dx * 4
    asl tmp+2
    rol tmp+3               ; dx * 8
    clc
    lda tmp+2
    adc tmp
    sta b_vxl
    lda tmp+3
    adc tmp+1
    sta b_vxh
    clc
    lda b_vxl
    adc bias_l,x
    sta b_vxl
    lda b_vxh
    adc bias_h,x
    sta b_vxh
    lda in_cur,x
    and toward_btn,x
    beq :+
    clc
    lda b_vxl
    adc push_l,x
    sta b_vxl
    lda b_vxh
    adc push_h,x
    sta b_vxh
:   lda in_cur,x
    and away_btn,x
    beq :+
    clc
    lda b_vxl
    adc pull_l,x
    sta b_vxl
    lda b_vxh
    adc pull_h,x
    sta b_vxh
:   lda #<HIT_VY
    sta b_vyl
    lda #>HIT_VY
    sta b_vyh
    jmp sfx_hit

; ----------------------------------------------------------------- CPU player (Toro)
; returns the buttons the CPU "presses" in A
ai_think:
    lda ai_dirty
    beq :+
    jsr ai_predict
    lda #0
    sta ai_dirty
:   ; where to stand
    lda ai_land
    cmp #128
    bcc @home
    sec
    sbc #6                  ; ball centre slightly left of Toro's centre: it goes left
    clc
    adc ai_err
    cmp #NET_R+1
    bcs :+
    lda #NET_R+1
:   cmp #233
    bcc @have
    lda #232
    bne @have
@home:
    lda #184
@have:
    sta tmp+2
    lda #0
    sta tmp+3               ; buttons
    lda pl_x+1
    sec
    sbc tmp+2
    beq @jump
    bcs @goleft
    cmp #$FE                ; within 2 px: stay
    bcs @jump
    lda #BTN_RIGHT
    sta tmp+3
    bne @jump
@goleft:
    cmp #3
    bcc @jump
    lda #BTN_LEFT
    sta tmp+3
@jump:
    ; near the net with the ball coming down in front: jump and spike
    lda b_x
    clc
    adc #8
    cmp #128
    bcc @done
    lda pl_ground+1
    beq @air
    lda pl_x+1
    cmp #NET_R+1+36
    bcs @done
    lda b_vyh
    bmi @done
    lda b_x
    sec
    sbc pl_x+1
    clc
    adc #24                 ; ball within ~24 px of Toro
    cmp #48
    bcs @done
    ; where will the ball be when Toro reaches the top of his jump (~22 frames)?
    ; y + 22 * vy + gravity term (~23 px), for a falling ball
    lda b_vyh
    bmi @done
    cmp #4
    bcs @done
    tay
    lda b_y
    clc
    adc mul22,y
    bcs @done
    adc #23
    bcs @done
    cmp #50
    bcc @done
    cmp #110
    bcs @done
    lda rng
    and #3
    beq @done               ; sometimes it just bumps
    lda tmp+3
    ora #BTN_A
    rts
@air:
    lda pl_y+1
    clc
    adc #8
    cmp b_y
    bcc @done
    lda tmp+3
    ora #BTN_B
    rts
@done:
    lda tmp+3
    rts

; simulates the ball (walls and net only) until it comes down to head height
ai_predict:
    lda b_xs
    sta s_xs
    lda b_x
    sta s_x
    lda b_ys
    sta s_ys
    lda b_y
    sta s_y
    lda b_vxl
    sta s_vxl
    lda b_vxh
    sta s_vxh
    lda b_vyl
    sta s_vyl
    lda b_vyh
    sta s_vyh
    ldx #160                ; max steps
@step:
    lda s_vyl
    clc
    adc #BALL_GRAV
    sta s_vyl
    lda s_vyh
    adc #0
    sta s_vyh
    clc
    lda s_ys
    adc s_vyl
    sta s_ys
    lda s_y
    adc s_vyh
    sta s_y
    ldy s_vyh
    bmi @up
    cmp #GROUND_Y-16        ; ball reaches head height
    bcs @found
    bcc @x
@up:
    bcs @x
    lda #0                  ; above the screen: stop rising
    sta s_y
    sta s_vyl
    sta s_vyh
@x:
    ldy #0
    lda s_vxh
    bpl :+
    dey
:   clc
    lda s_xs
    adc s_vxl
    sta s_xs
    lda s_x
    adc s_vxh
    sta s_x
    tya
    adc #0
    beq :+
    lda #0
    sta s_x
    jsr @negx
:   lda s_x
    cmp #241
    bcc :+
    lda #240
    sta s_x
    jsr @negx
:   dex
    bne @step
@found:
    lda s_x
    clc
    adc #8
    sta ai_land
    lda rng                 ; aiming error -8..+7 px
    and #15
    sec
    sbc #8
    sta ai_err
    rts
@negx:
    lda #0
    sec
    sbc s_vxl
    sta s_vxl
    lda #0
    sbc s_vxh
    sta s_vxh
    rts

; ----------------------------------------------------------------- drawing
; ptr -> [count, (dx, dy, tile, attr)...], at ms_x / ms_y
draw_ms:
    ldy #0
    lda (ptr),y
    sta ms_cnt
    iny
    ldx spr_idx
@l:
    lda (ptr),y
    clc
    adc ms_x
    sta oam+3,x
    iny
    lda (ptr),y
    clc
    adc ms_y
    sta oam,x
    iny
    lda (ptr),y
    sta oam+1,x
    iny
    lda (ptr),y
    sta oam+2,x
    iny
    inx
    inx
    inx
    inx
    dec ms_cnt
    bne @l
    stx spr_idx
    rts

draw_game:
    jsr clear_oam
    ; ball (drawn first so it wins sprite priority)
    lda b_x
    sta ms_x
    lda b_y
    sta ms_y
    lda frame
    and #8
    beq :+
    lda b_vxh
    ora b_vxl
    beq :+
    lda #<ms_ball1
    ldy #>ms_ball1
    bne :++
:   lda #<ms_ball0
    ldy #>ms_ball0
:   sta ptr
    sty ptr+1
    jsr draw_ms
    ; shadow on the sand while the ball is high (keeps <= 8 sprites per line)
    lda b_y
    cmp #160
    bcs :+
    lda b_x
    sta ms_x
    lda #196
    sta ms_y
    lda #<ms_shadow
    sta ptr
    lda #>ms_shadow
    sta ptr+1
    jsr draw_ms
:   ldx #0
    jsr draw_player
    ldx #1
    ; fall through

draw_player:
    lda pl_x,x
    sta ms_x
    lda pl_y,x
    sta ms_y
    txa                     ; pose index = player * 3 + pose
    sta tmp
    asl a
    adc tmp
    sta tmp
    lda pl_ground,x
    beq @jump
    lda pl_moving,x
    beq @have
    lda frame
    and #8
    beq @have
    inc tmp                 ; walk
    bne @have
@jump:
    inc tmp
    inc tmp
@have:
    ldy tmp
    lda char_ms_lo,y
    sta ptr
    lda char_ms_hi,y
    sta ptr+1
    jmp draw_ms

; ----------------------------------------------------------------- sound effects
sfx_hit:
    lda #$84
    sta $4000
    lda #$00
    sta $4001
    lda #$A0
    sta $4002
    lda #$08
    sta $4003
    rts

sfx_spike:
    lda #$06
    sta $400C
    lda #$05
    sta $400E
    lda #$08
    sta $400F
    lda #$85
    sta $4000
    lda #$BA
    sta $4001
    lda #$40
    sta $4002
    lda #$08
    sta $4003
    rts

sfx_net:
    lda #$03
    sta $400C
    lda #$0C
    sta $400E
    lda #$08
    sta $400F
    rts

sfx_jump:
    lda #$82
    sta $4004
    lda #$AA
    sta $4005
    lda #$F0
    sta $4006
    lda #$08
    sta $4007
    rts

sfx_point:
    lda #$8C
    sta $4004
    lda #$00
    sta $4005
    lda #$60
    sta $4006
    lda #$08
    sta $4007
    rts

sfx_whistle:
    lda #$47
    sta $4000
    lda #$00
    sta $4001
    lda #$30
    sta $4002
    lda #$08
    sta $4003
    rts

sfx_tick:
    lda #$81
    sta $4004
    lda #$00
    sta $4005
    lda #$80
    sta $4006
    lda #$08
    sta $4007
    rts

; =============================================================================
.segment "RODATA"

; per player: 0 = Nonno (left), 1 = Toro (right)
x_min:      .byte 0, NET_R+1
x_max:      .byte NET_L-24, 232
bias_l:     .byte $00, $00      ; +1 / -1 px/frame toward the other court
bias_h:     .byte $01, $FF
push_l:     .byte $80, $80      ; holding toward the net: +/- 0.5
push_h:     .byte $00, $FF
pull_l:     .byte $80, $80      ; holding away from the net: -/+ 0.5
pull_h:     .byte $FF, $00
toward_btn: .byte BTN_RIGHT, BTN_LEFT
away_btn:   .byte BTN_LEFT, BTN_RIGHT
spike_vxl:  .byte $80, $80      ; +/- 3.5 px/frame
spike_vxh:  .byte $03, $FC
mul22:      .byte 0, 22, 44, 66
spike_zone: .byte NET_L-24-40, NET_R+1   ; x range (40 px wide) where a spike is allowed

MSG_CLEAR       = 0
MSG_PAUSE       = 1
MSG_POINT_NONNO = 2
MSG_POINT_TORO  = 3
MSG_WIN_NONNO   = 4
MSG_WIN_TORO    = 5
MSG_REMATCH     = 6
msg_lo: .byte <m_clear, <m_pause, <m_pnonno, <m_ptoro, <m_wnonno, <m_wtoro, <m_rematch
msg_hi: .byte >m_clear, >m_pause, >m_pnonno, >m_ptoro, >m_wnonno, >m_wtoro, >m_rematch
; row 9 / row 10 of the sky, columns 6..25
m_clear:   .byte $21,$26, "                    ", 0
m_pause:   .byte $21,$2D, "PAUSA", 0
m_pnonno:  .byte $21,$2A, "PUNTO NONNO!", 0
m_ptoro:   .byte $21,$2B, "PUNTO TORO!", 0
m_wnonno:  .byte $21,$29, "VINCE IL NONNO!", 0
m_wtoro:   .byte $21,$2A, "VINCE TORO!", 0
m_rematch: .byte $21,$48, "START: RIVINCITA", 0

.include "assets.inc"

title_nam: .incbin "title.nam"
game_nam:  .incbin "game.nam"

.segment "VECTORS"
    .word nmi, reset, irq

.segment "CHARS"
    .incbin "chr.bin"
