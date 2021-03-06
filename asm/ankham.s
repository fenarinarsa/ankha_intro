
* ANKHA Intro ATari Mega STE NOVA ET4000
* Copyright (C) 2021 fenarinarsa (Cyril Lambin)
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <https://www.gnu.org/licenses/>.

* Any complain of badly written "it looks like 30 years old" code can be sent to
* Code is shit because it's all patched from my previous Bad Apple player
* and I had to develop directly on my Mega STE since there is no VGA support
* in ST emulators. So a lot of comments are obsolete
*
* Twitter @fenarinarsa
* Mastodon @fenarinarsa@shelter.moe
* Web fenarinarsa.com

	;opt d+

; The demo must be ran in 320x240x256c 60Hz
; Compatible with ET4000 on NOVA adapter only
; framebuffer located at $C00000 (Mega STE)
; registers located at $DC0000 (Mega STE)

; note: adding $FE000000 to VME addresses
; should them TT compatible without breaking
; things on Mega STE... I think?
SCREEN	EQU	$FEC00000
DAC_PEL	EQU	$FEDC03C6
DAC_IR	EQU	$FEDC03C7
DAC_IW	EQU	$FEDC03C8
DAC_D	EQU	$FEDC03C9
CRTC_I	EQU	$FEDC03D4
CRTC_D	EQU	$FEDC03D5
INSTATUS1	EQU	$FEDC03DA
LStartH	EQU	$33
LStartM	EQU	$C
LStartL	EQU	$D

emu	EQU	0	; 1=emulate HDD access timings by adding NOPs
ram_limit	EQU	1024*1024	; 0=no limit, other=malloc size
blitter	EQU	1	; 1=use blitter 0=emulate blitter (not complete, for debug purpose only)
minimum_load EQU	128*1000	; minimum size of a disk read (to optimize FREADs)
loop_play	EQU	1
monochrome EQU 0

line_length EQU 	160
horz_shift	 EQU	1
intro_shift EQU	0
nb_frames	EQU	2332	; number of frames in file
loop_frame EQU	111

linewidth	EQU	320	; 640 for 640x480 and 320 for 320x240
vidwidth	EQU	linewidth/4

SWITCH_FRAMES EQU	880	; nb of frames between pictures swap 

DMASNDST	MACRO
	move.l	\1,d0
	swap	d0
	move.b	d0,$ffff8903.w
	swap	d0
	move.w	d0,d1
	lsr.w	#8,d0
	move.b	d0,$ffff8905.w
	move.b	d1,$ffff8907.w
	ENDM

DMASNDED	MACRO
	move.l	\1,d0
	swap	d0
	move.b	d0,$ffff890F.w
	swap	d0
	move.w	d0,d1
	lsr.w	#8,d0
	move.b	d0,$ffff8911.w
	move.b	d1,$ffff8913.w
	ENDM

emu_hdd_lag MACRO
	IFNE	emu
	move.l	d6,d5
.wait_emu	nop
	nop
	nop
	dbra.s	d5,.wait_emu
	ENDC
	ENDM


color_debug MACRO
	
	tst.w	debug_color
	beq.s	.\@
	IFEQ	monochrome
	move.w	#\1,$ffff8240.w
	ELSE
	not.w	$ffff8240.w
	ENDC
.\@
	ENDM
	
vga_debug	MACRO
	;move.b	#0,DAC_IW
	;move.b	#\1,DAC_D	; write R
	;move.b	#\2,DAC_D	; write G
	;move.b	#\3,DAC_D	; write B
	ENDM

	*** Mshrink
	movea.l   4(sp),a5
	move.l    12(a5),d0
	add.l     20(a5),d0
	add.l     28(a5),d0
	addi.l    #$1100,d0
	move.l    d0,d1
	add.l     a5,d1
	andi.l    #-2,d1
	movea.l   d1,sp
	move.l    d0,-(sp)
	move.l    a5,-(sp)
	clr.w     -(sp)
	move.w    #$4a,-(sp)
	trap      #1
	lea       12(a7),a7

	*** SUPER
	clr.l	-(sp)
	move.w	#$20,-(sp)		; super
	trap	#1
	addq.w	#6,sp

	*** get the biggest available block in memory for the file buffer
	move.l	#-1,-(sp)
	move.w	#$48,-(sp)		; malloc
	trap	#1
	addq.l	#6,sp
	cmp.l	#500*1024,d0	; needs at least 500MB of free RAM
	blt	buyram		; stop if not enough memory
	IFNE	ram_limit
	move.l	#ram_limit,d0	; limit used RAM (debug)
	ENDC
	move.l	d0,vid_buffer_end
	move.l	d0,-(sp)
	move.w	#$48,-(sp)		; malloc
	trap	#1
	addq.l	#6,sp
	tst.l	d0
	ble	end		; error while doing malloc
	move.l	d0,vid_buffer
	add.l	d0,vid_buffer_end
	move.l	d0,play_ptr
	move.l	d0,aplay_ptr
	addq	#2,d0
	move.l	d0,load_ptr	; add 2 to load_ptr because it must be >play_ptr, else it means the buffer is full

	*** Open index file
	move.w	#0,-(sp)		; open index
	pea	s_idx_filename
	move.w	#$3D,-(sp)
	trap	#1
	addq.l	#8,sp
	tst.w	d0
	ble	file_error	; index not found

	move.w	d0,file_handle

	*** Read index
	pea	vid_index
	move.l	#(nb_frames*2),-(sp)		; read index
	move.w	file_handle,-(sp)
	move.w	#$3F,-(sp)
	trap	#1
	add.l	#12,sp
	cmp.w	#4,d0		; error file too short
	ble	file_error

	*** Close index file
	move.w	file_handle,-(sp)	; close index
	move.w	#$3e,-(sp)		
	addq.l	#4,sp
	
	*** Open runtime file
	move.w	#0,-(sp)		; open video
	pea	s_vid_filename
	move.w	#$3D,-(sp)
	trap	#1
	addq.l	#8,sp
	tst.w	d0
	ble	file_error		; video not found

	move.w	d0,file_handle

	move.w	#2,-(sp)		; physaddr
	trap	#14
	move.l	d0,old_screen



*** Hardware inits
hwinits
	moveq	#$12,d0
	jsr	ikbd		; turn off mouse
	moveq	#$15,d0
	jsr	ikbd		; turn off joysticks
	jsr	flush

	move.w	#$2700,sr

	movem.l	$ffff8240.w,d0-d7
	movem.l	d0-d7,old_palette

	;move.b	$ffff8260.w,old_rez
	;move.b	$ffff820a.w,old_hz
	moveq	#0,d5		; reset vbl counter

	lea	old_ints,a0
	move.l	$68.w,(a0)+
	move.l	$70.w,(a0)+
	move.l	$118.w,(a0)+
	move.l	$120.w,(a0)+
	move.b	$fffffa07.w,(a0)+
	move.b	$fffffa09.w,(a0)+
	move.b	$fffffa0f.w,(a0)+
	move.b	$fffffa11.w,(a0)+
	move.b	$fffffa13.w,(a0)+
	move.b	$fffffa15.w,(a0)+
	move.b	$fffffa17.w,(a0)+
	move.b	$fffffa1b.w,(a0)+
	move.b	$fffffa21.w,(a0)+

	sf	$fffffa19.w	; stop timer A
	sf	$fffffa1b.w	; stop timer B
	move.l	#dummy_rte,$70.w	; temporary vbl
	move.l	#dummy_rte,$68.w	; temporary hbl

	move.l	#vbl,$70.w
	move.l	#hbl,$68.w

	; Timer C should not be stopped because it's used by some HDD drivers
	move.b	#%00100001,$fffffa07.w	; timer a/b only
	and.b	#%11100000,$fffffa09.w	; all but timer C / ACIA / HDC controller
	or.b	#%01000000,$fffffa09.w	; enable ACIA
	move.b	#%00100001,$fffffa13.w	; timer a/b only
	and.b	#%11100000,$fffffa15.w	; all but timer C & ACIA / HDC controller
	or.b	#%01000000,$fffffa15.w	; enable ACIA
	bclr	#3,$fffffa17.w	; AEI

	; find the ST video address for debug purpose
	move.b	$ffff8201.w,screen_debug_ptr+1
	move.b	$ffff8203.w,screen_debug_ptr+2
	move.b	$ffff820d.w,screen_debug_ptr+3

	move.b     #%11,$FFFF8921.w	; 50kHz stereo
	;move.b     #%10000001,$FFFF8921.w	; 12kHz mono
	lea	buf_nothing,a0
	DMASNDST	a0
	lea 	buf_nothing_end,a0
	DMASNDED	a0
	move.b	#%11,$ffff8901.w	; start playing sound

	; enable Timer A
	move.l	#timer_a,$134.w
	move.b	#1,$fffffa1f.w
	move.b	#8,$fffffa19.w

	; prepare all palettes
	move.l	pal0,a0
	lea	vgapal0,a1
	move.w	#239,d0
	bsr	copy_palette
	move.l	pal1,a0
	lea	vgapal1,a1
	move.w	#239,d0
	bsr	copy_palette
	move.l	pal2,a0
	lea	vgapal2,a1
	move.w	#239,d0
	bsr	copy_palette	
	; add font palette to the background palette
	lea	fontpal,a0
	lea	vgapal0+4*240,a1
	moveq	#15,d0
	bsr	copy_palette
	lea	fontpal,a0
	lea	vgapal1+4*240,a1
	moveq	#15,d0
	bsr	copy_palette
	lea	fontpal,a0
	lea	vgapal2+4*240,a1
	moveq	#15,d0
	bsr	copy_palette
	; prepare palettes for ET4000's 6-bits DAC
	lea	vgapal0,a0
	move.l	a0,pal0
	move.w	#255,d0
	bsr	prepare_palette
	lea	vgapal1,a0
	move.l	a0,pal1
	move.w	#255,d0
	bsr	prepare_palette
	lea	vgapal2,a0
	move.l	a0,pal2
	move.w	#255,d0
	bsr	prepare_palette	

	; clear 3 screens
	move.w	#240*3,$ffff8a38.w ; y count
	move.w	#160,$ffff8a36.w  ; x word count
	move.w	#2,$ffff8a20.w   ; src x byte increment
	move.w	#2,$ffff8a22.w   ; src y byte increment
	move.w	#2,$ffff8a2e.w ; dst x increment
	move.w     #2+(linewidth-320),$ffff8a30.w ; dst y increment
	clr.b	$ffff8a3d.w    ; skew
	move.w	#-1,$ffff8a28.w ; endmask1
	move.w	#-1,$ffff8a2a.w ; endmask2
	move.w	#-1,$ffff8a2c.w ; endmask3
	move.w	#$0100,$ffff8a3a.w    ; HOP+OP: $0100=0fill
	move.l	#image0,$ffff8a24.w   ; src
	move.l	screen0_ptr,$ffff8a32.w   ; dest
	move.b	#%11000000,$ffff8a3c.w ; start HOG
	nop
	nop

	bsr	set_palette

	; copy image to video RAM with the blitter
	move.w	#214,$ffff8a38.w ; y count
	move.w	#160,$ffff8a36.w  ; x word count
	move.w	#$0203,$ffff8a3a.w    ; HOP+OP: $010F=1fill/$0203=copy
	move.l	#image0,$ffff8a24.w   ; src
	move.l	screen0_ptr,$ffff8a32.w   ; dest
	move.b	#%11000000,$ffff8a3c.w ; start HOG
	nop
	nop
	move.w	#214,$ffff8a38.w ; y count
	move.w	#160,$ffff8a36.w  ; x word count
	move.l	#image1,$ffff8a24.w   ; src
	move.l	screen1_ptr,$ffff8a32.w   ; dest
	move.b	#%11000000,$ffff8a3c.w ; start HOG
	nop
	nop
	move.w	#214,$ffff8a38.w ; y count
	move.w	#160,$ffff8a36.w  ; x word count
	move.l	#image2,$ffff8a24.w   ; src
	move.l	screen2_ptr,$ffff8a32.w   ; dest
	move.b	#%11000000,$ffff8a3c.w ; start HOG
	nop
	nop
	
	; shift the font colors by 240
	move.l	fontidx,a0
	move.w	#(25*1534)/2-1,d0
ftloop	add.w	#$F0F0,(a0)+
	dbra	d0,ftloop

	; detect VGA Vsync
	; and setup Timer B faster than 60Hz (40000 MFP cycles)
	; VGA is around 60.15Hz (40 858 MFP cycles)
	; Timer B handler will then wait for vblank
	sf	$fffffa1b.w	; stop TB
	move.l	#tb_render,$120.w
	bsr	vsync
	move.b	#203,$fffffa21.w	; counter=200
	move.b	#7,$fffffa1b.w	; divider=200
	move.w	#$2300,sr




*** MAIN LOOP
* the main loop is where the loading takes place
* with a FIFO (cyclic) buffer
* meanwhile rendering takes place in the HBL interrupt

next_frame
	; read next frame from file
next_load	
	move.l	idx_load,a0
	tst.w	(a0)		; end of index
	bne.s	find_load_size

	IFEQ loop_play
	; we're done loading, force play
	move.l	#wait_for_play_end,-(sp)
	bra	enableplay
	ELSE
	; end of video, looping

	; loop video
	move.l	idx_loaded,a0	; set -1 at the end the loaded data ptr list
	move.l	#-1,(a0)
	move.l	#play_index,idx_loaded
	move.l	#vid_index,a0
	move.w	#loop_frame-1,d0
	; add intro's frame sizes to get the loop frame offset in file
	move.w	#0,a1
.findloopindex
	adda.w	(a0)+,a1
	dbra	d0,.findloopindex
	move.l	a0,idx_load
	; seek to start of file
	clr.w	-(sp)
	move.w	file_handle,-(sp)
	move.l	a1,-(sp)		; seek offset
	move.w	#66,-(sp)		; fseek
	trap	#1
	add.l	#10,sp
	move.l	idx_load,a0
	ENDC	

find_load_size
	moveq	#0,d5
	moveq	#0,d6		; d6 = size to load
	moveq	#-1,d7		; d7 = number of frames we are going to load
.checksize	move.w	(a0)+,d5
	beq	check_room		; nul => EOF
	add.l	d5,d6
	addq	#1,d7
	cmp.l	#minimum_load,d6	; try not to load less than 512b (HDC DMA lower limit)
	blt.s	.checksize

check_room	
	bsr	check_ikbd
	move.l	load_ptr,a0
	move.l	play_ptr,a1
	move.w	play_frm,d0
	cmp.w	aplay_frm,d0	; if (play_frm < aplay_frm) => a1=play_ptr
	blt.s	.oklimit
	move.l	aplay_ptr,a2
	cmp.l	#buf_nothing_end,a2
	ble.s	.oklimit
	move.l	a2,a1
.oklimit	move.l	vid_buffer_end,a2	; a2=upper limit (default=end of filebuffer)

	move.l	a0,a3
	add.l	d6,a3		; a3=end_load_ptr

	cmp.l	a1,a0		; if (load_ptr <= play_ptr) => .upper_is_play
	ble.s	.upper_is_play
	cmp.l	a2,a3		; if (end_load_ptr <= vid_buffer_end) => loading
	ble	loading

	move.l	vid_buffer,a0	; load_ptr = start of vid buffer (looping memory)
	move.l	a0,load_ptr	
	move.l	a0,a3
	add.l	d6,a3

.upper_is_play
	cmp.l	a1,a3		; if (end_load_ptr < play_ptr) => loading
	blt	loading

.bufferfull
	; not enough room to load anything (buffer full)
	tst.w	b_buffering_lock
	beq.s	check_room		; we're not in buffering mode, recheck now

	; exit buffering mode
	move.l	#check_room,-(sp)	; for the upcoming rts
	tst.w	b_first_refresh	; is it the first refresh ?
	beq	enableplay
	bsr	first_refresh

enableplay
	clr.w	b_buffering_lock	; enable play if previously disabled
	move.b	#%11,$ffff8901.w	; restart sound
	rts			; go to check_room or wait_for_play_end

first_refresh
	move.w	#-2,b_first_refresh	; not so bool after all
.wait	cmp.w	#60,vbl_count	; wait at least 30 frames you damn emulator
	blt.s	.wait
	; clear screen
	clr.w	b_first_refresh

	rts


check_ikbd	cmp.b	#$1+$80,$fffffc02.w	; ESC depressed
	bne	.no_esc
	addq	#4,sp
	bra	video_end
.no_esc	clr.w	debug_color
;	cmp.b	#$4e+$80,$fffffc02.w  ; + depressed
;	bne.s	.noplus
;	move.w	#-1,debug_info
;	bsr	.endcheck
;.noplus	cmp.b	#$4a+$80,$fffffc02.w  ; - depressed
;	bne.s	.nominus
;	clr.w	debug_info
;	bsr	.endcheck
.nominus	cmp.b	#$2a,$fffffc02.w	; Left-shift pressed
	bne.s	.endcheck
	move.w	#-1,debug_color
.endcheck	rts

	

loading	move.w	#-1,b_loading
	move.l	load_ptr,-(sp)
	move.l	d6,-(sp)
	move.w	file_handle,-(sp)
	move.w	#$3F,-(sp)		; fread
	;color_debug $400	; faint red
	emu_hdd_lag
	trap	#1
	;color_debug $000	; black
	add.l	#12,sp
	clr.w	b_loading

	; filling idx_loaded with updated play pointers
	; idx_load: 16 bits frame size list, from original ".idx" file
	; load_ptr: ptr to the data that has just been loaded
	; idx_loaded: 32 bits ptr list generated from idx_load and load_ptr
	moveq	#0,d0
	move.l	idx_loaded,a0
	move.l	idx_load,a1
	move.l	load_ptr,a2
.idxloop	move.l	a2,(a0)+
	move.w	(a1)+,d0
	add.l	d0,a2
	dbra	d7,.idxloop
	move.l	a2,load_ptr
	move.l	a1,idx_load
	move.l	a0,idx_loaded

	cmp.l	#buf_nothing,a0	; assert (idx_loaded) < buf_nothing
	ble.s	.okaydebug
	illegal
.okaydebug

	; purple
	;move.w	#$707,d0
	;moveq	#15,d1
	;bsr	debug

	bra	next_load

	IFEQ	loop_play
wait_for_play_end
	move.l	idx_loaded,a0	; set -1 at the end the loaded data ptr list
	move.l	#-1,(a0)
.wait	bsr	check_ikbd
	move.l	idx_play,a0	; if -1 we reached the end of the loaded frames
	tst.l	(a0)
	bge.s	.wait
	ENDC

*** END

video_end	
	*** Close audio file
	move.w	file_handle,-(sp)
	move.w	#$3e,-(sp)
	addq.l	#4,sp

	*** Hardware restore
	move.w	#$2700,sr

	clr.w	$ffff8900.w	; stop playing sound

	sf	$fffffa19.w	; stop timer A
	sf	$fffffa1b.w	; stop timer B
	move.l	#dummy_rte,$70.w	; temporary vbl
	move.l	#dummy_rte,$68.w	; temporary hbl
	move.w	#$2300,sr		; wait for vbl
	movem.l	old_palette,d0-d7
	movem.l	d0-d7,$ffff8240.w
	;move.b	old_rez,$ffff8260.w
	;move.b	old_hz,$ffff820a.w
	move.l	old_screen,vid0_ptr
	bsr	set_videoaddr

	lea	old_ints,a0
	move.l	(a0)+,$68.w
	move.l	(a0)+,$70.w
	move.l	(a0)+,$118.w
	move.l	(a0)+,$120.w
	move.b	(a0)+,$fffffa07.w
	move.b	(a0)+,$fffffa09.w
	move.b	(a0)+,$fffffa0f.w
	move.b	(a0)+,$fffffa11.w
	move.b	(a0)+,$fffffa13.w
	move.b	(a0)+,$fffffa15.w
	move.b	(a0)+,$fffffa17.w
	move.b	(a0)+,$fffffa1b.w
	move.b	(a0)+,$fffffa21.w
	move.b	#$c0,$fffffa23.w	; fix key repeat

	; at least reset VGA color #0 to white
	move.l	pal0,a0
	move.b	#$FF,(a0)+
	move.b	#$FF,(a0)+
	move.b	#$FF,(a0)
	bsr	set_palette

	move.w	#$2300,sr

	moveq	#$8,d0
	jsr	ikbd		; turn on mouse
	jsr	flush

	clr.l	-(sp)
	move.w	#$20,-(sp)		; super
	trap	#1
	addq.w	#6,sp

end	; PTERM
	clr.w	-(sp)
	trap #1


*** GRAPHIC AND SOUND RENDER
* Audio is played from loaded raw data
* Frame is rendered by running the generated code + blitter data loaded from file
* VBL only prints debug data

vbl	;addq.w	#1,vbl_count
	rte
	
vbl_debug	move.w	$ffff8240.w,-(sp)
	color_debug $555

	movem.l	d0-a6,-(sp)


	bsr	.print_debug

	movem.l	(sp)+,d0-a6
	move.w	(sp)+,$ffff8240.w
	rte

.print_debug
	; print debug info
	move.l	screen_debug_ptr,a1

	; "LOAD"
	lea	s_nothing,a0
	tst.w	b_loading
	beq.s	.printload
	lea	s_debug_load,a0
.printload	moveq	#-1,d6
	bsr	textprint

	; "PLAY"
	lea	s_nothing,a0
	tst.w	b_buffering_lock
	bne.s	.printplay
	lea	s_debug_play,a0
.printplay	moveq	#-1,d6
	bsr	textprint

	; load ptr
	lea	s_hex,a6
	move.l	a6,a0
	move.l	load_ptr,d0
	bsr	itoahex
	move.l	a6,a0
	addq.l	#2,a0
	moveq	#7,d6
	bsr	textprint

	; play ptr
	lea	s_hex,a6
	move.l	a6,a0
	move.l	play_ptr,d0
	bsr	itoahex
	move.l	a6,a0
	addq.l	#2,a0
	moveq	#7,d6
	bsr	textprint
	rts
	

* Timer A

timer_a	move.b	#1,$fffffa1f.w
	;color_debug $700
	;vga_debug	$ff,$00,$00

	movem.l	d0-d1/a0-a1,-(sp)

	tst.w	b_buffering_lock
	bne	endrender

	move.l	idx_play,a1	; current frame
	move.l	(a1),d0
	ble	enter_buffering	; null ptr = not loaded yet

	; set the new DMA audio buffer
	; will be used when DMA loops automatically
	; note that it would be ideally in 1 (mono) or 2 (color) vbls and then be in sync with the video
	; there is many ways to achieve that but in this version it relies on the first audio frame
	; to be smaller so the DMA loop happens just before this 'render' function is called
	move.l	d0,a1
	move.l	a1,play_ptr
	add.w	#1,play_frm
	move.l	d0,a0
	move.l	(a0)+,d0		; pcm length
	move.l	a0,a1
	add.l	d0,a1		; pcm end
	DMASNDED	a1
	DMASNDST	a0

	;temporary hack to avoid emulation audio cracks
	moveq	#0,d0
	lea	$ffff8907.w,a0
	movep.l	(a0),d0
	and.l	#$00ffffff,d0
	move.l	d0,aplay_ptr
	add.w	#1,aplay_frm

	; empty graphics, skip render
	;addq	#2,a1  ; 0 = audio only

	IFNE	loop_play	
	; clear the idx playlist in case the video loops and inc idx_play+4
	move.l	idx_play,a0
	move.l	a0,a1
	addq	#4,a0
	cmp.l	#-1,(a0)
	bne	.noloop1
	move.l	#play_index,a0
.noloop1	move.l	a0,idx_play
	clr.l	(a1)
	ELSE
	add.l	#4,idx_play
	ENDC
	bra.s	endrender

enter_buffering
	move.b	#%00,$ffff8901.w	; stop sound
	move.w	#-1,b_buffering_lock

endrender	
	movem.l	(sp)+,d0-d1/a0-a1
	;color_debug $000
	;vga_debug $00,$00,$00
dummy_rte	rte

* RENDER is triggered by Timer B
* to be in sync with the card's vsync
* VBL is of no use here


tb_render	sub.w	#1,framecount
	addq	#1,vbl_count
	;vga_debug	$00,$ff,$ff

	;bsr	set_videoaddr	; must be done BEFORE vsync

	; wait for vsync
	btst	#3,INSTATUS1
	bne.s	.invsync
.waitvsync
	btst	#3,INSTATUS1
	beq.s	.waitvsync

.invsync	sf	$fffffa1b.w	; stop TB
	move.b	#203,$fffffa21.w	; counter=200
	move.b	#7,$fffffa1b.w	; divider=200

	tst.w	b_lock_render
	bne.s	.locked		; don't enable HBL if a render is already in progress
	and.w	#$f0ff,(sp)
	or.w	#$0100,(sp)	; enable HBL after rte
.locked	rte

b_lock_render
	dc.w	0

hbl	move.w	$ffff8240.w,-(sp)
	; green
	color_debug $070
	vga_debug $00,$FF,$00

	tst.w	b_lock_render
	bne	endhbl		; render already in progress (actually should not happen)
	move.w	#-1,b_lock_render

	movem.l	d0-a6,-(sp)

	tst.w	framecount
	bne.s	.noframezero

	; frame zero: changing the vid ptr at next vsync
	move.l	vid0_ptr,a0
	move.l	vid1_ptr,vid0_ptr
	move.l	vid2_ptr,vid1_ptr
	move.l	a0,vid2_ptr
	
	bsr	set_videoaddr

	bra.s	.noswitch
	
.noframezero
	bpl.s	.noswitch
	; switch screens
	move.l	screen0_ptr,a0
	move.l	screen1_ptr,screen0_ptr
	move.l	screen2_ptr,screen1_ptr
	move.l	a0,screen2_ptr
	
	; switch palettes
	move.l	pal1,a0
	move.l	pal2,pal1
	move.l	pal0,pal2
	move.l	a0,pal0
	
	;jsr	set_videoaddr
	;bsr	copy_palette
	bsr	set_palette
	move.w	#SWITCH_FRAMES,framecount

.noswitch	tst.w	b_buffering_lock
	bne	nohblrender

	bsr	scrolltext

	;add.w	#1,rendered_frame 	; for debug purpose only

	; check if unchanged frame
	; apply to frame N-2 so we need to save this
;	tst.w	swap_buffers
;	beq	nohblrender

	; swap video buffers
	; so next vbl we're gonna see the frame rendered 2 vbls ago
	;move.l	screen_render_ptr,a0
	;move.l	screen_display_ptr,screen_render_ptr
	;move.l	a0,screen_display_ptr

nohblrender
	bsr	set_screen
	movem.l	(sp)+,d0-a6
	
	clr.w	b_lock_render
endhbl	move.w	(sp)+,$ffff8240.w
	vga_debug $00,00,$ff
	and.w	#$f0ff,(sp)
	or.w	#$0300,(sp)	; disable HBL after rte (should not work on 68030+)
	rte

set_screen
	tst.w	debug_info
	;beq.s	.noshift
	;move.b	screen_debug_ptr+1,$ffff8201.w
	;move.b	screen_debug_ptr+2,$ffff8203.w
	;move.b	screen_debug_ptr+3,$ffff820d.w
	;bra.s	.end
.noshift	;move.b	screen_display_ptr+1,$ffff8201.w
	;move.b	screen_display_ptr+2,$ffff8203.w
	;move.b	screen_display_ptr+3,$ffff820d.w
.end	rts


	; a0=palette source
	; a1=dest
	; d0=nb colors-1
copy_palette
.loop	move.b	(a0)+,(a1)+
	move.b	(a0)+,(a1)+
	move.b	(a0)+,(a1)+
	move.b	(a0)+,(a1)+
	dbra	d0,.loop
	rts

; 18-bits palette so each component must be >>2
; reorder the palette (RGB instead of BGRA)
; d0=nb of colors-2
; a0=palette address	
prepare_palette	
	move.l	a0,a1
.pal	move.b	(a0)+,d1
	move.b	(a0)+,d2
	move.b	(a0),d3
	addq	#2,a0
	lsr.b	#2,d1
	lsr.b	#2,d2
	lsr.b	#2,d3
	move.b	d3,(a1)+	; write R
	move.b	d2,(a1)+	; write G
	move.b	d1,(a1)+	; write B
	dbra	d0,.pal
	rts
	
set_palette	
	move.b	#$FF,DAC_PEL ; pixel mask
	move.w	#255,d0
	move.l	pal0,a0
	move.b	#0,DAC_IW	; start pal index #0
.pal	move.b	(a0)+,DAC_D
	move.b	(a0)+,DAC_D
	move.b	(a0)+,DAC_D
	dbra	d0,.pal
	rts

	; poll vsync bit
vsync	btst	#3,INSTATUS1
	bne.s	vsync
.vs	btst	#3,INSTATUS1
	beq.s	.vs
	rts

	; set screen base address
set_videoaddr
	move.b	#LStartL,CRTC_I
	move.b	vid0_ptr+3,CRTC_D
	move.b	#LStartM,CRTC_I
	move.b	vid0_ptr+2,CRTC_D
	move.b	#LStartH,CRTC_I
	move.b	vid0_ptr+1,CRTC_D
	rts
	
*** SCROLLTEXT
; 100% blitter
; each char is copied individually on screen
; a bit complex because the chars are 26px wide ToT

scrolltext
	;move.w	#22,textshift

	; setup static blitter registers
	move.w	#2,$ffff8a20.w   ; src x byte increment
	move.w	#2,$ffff8a2e.w ; dst x increment
	clr.b	$ffff8a3d.w    ; skew
	move.w	#-1,$ffff8a28.w ; endmask1
	move.w	#-1,$ffff8a2a.w ; endmask2
	move.w	#-1,$ffff8a2c.w ; endmask3
	move.w	#$0203,$ffff8a3a.w    ; HOP+OP: $010F=1fill/$0203=copy
	
	move.l	screen0_ptr,a6
	add.l	#(240-25)*linewidth,a6	; screen bottom
	move.l	textptr,a5
	lea	fontidx,a4
	moveq	#11,d7
	move.w	textshift,d6
	beq.s	.middle
	cmp.w	#18,d6
	bge.s	.firstchar
	moveq	#10,d7

.firstchar	
	; first char
	moveq	#0,d0
	move.b	(a5)+,d0
	cmp.b	#'#',d0
	bne.s	.ok1
	addq	#1,a5
	move.b	(a5)+,d0
.ok1	sub.w	#' ',d0
	lsl.w	#2,d0
	move.l	(a4,d0.w),a0	; char ptr	
	add.w	d6,a0	; add text shift

	moveq	#26,d1
	sub.w	d6,d1
	move.w	d1,d4
	move.w	#2+1536,d2
	sub.w	d1,d2	; src y byte increment
	move.w	#2+linewidth,d3
	sub.w	d1,d3	; dst y increment
	lsr.w	#1,d1	; x word count

	; copy 1 char to video RAM with the blitter
	move.w	#25,$ffff8a38.w ; y count
	move.w	d1,$ffff8a36.w  ; x word count
	move.w	d2,$ffff8a22.w   ; src y byte increment
	move.w	d3,$ffff8a30.w ; dst y increment
	move.l	a0,$ffff8a24.w   ; src
	move.l	a6,$ffff8a32.w   ; dest
	move.b	#%11000000,$ffff8a3c.w ; start HOG
	nop
	nop
	
	add.w	d4,a6	; next char on screen
	
	; 11 or 12  middle chars
.middle	
.loopchar	moveq	#0,d0
	move.b	(a5)+,d0
	cmp.b	#'#',d0
	bne.s	.ok2
	addq	#1,a5
	move.b	(a5)+,d0
.ok2	sub.w	#' ',d0
	lsl.w	#2,d0
	move.l	(a4,d0.w),a0	; char ptr

	; copy 1 char to video RAM with the blitter
	move.w	#25,$ffff8a38.w ; y count
	move.w	#13,$ffff8a36.w  ; x word count
	move.w	#2+1534-24,$ffff8a22.w   ; src y byte increment
	move.w	#2+linewidth-26,$ffff8a30.w ; dst y increment
	move.l	a0,$ffff8a24.w   ; src
	move.l	a6,$ffff8a32.w   ; dest
	move.b	#%11000000,$ffff8a3c.w ; start HOG
	nop
	nop
	
	add.w	#26,a6
	dbra	d7,.loopchar
	
	cmp.w	#18,d6
	beq.s	.shifttext
	
	; last char (if needed)
	moveq	#0,d0
	move.b	(a5)+,d0
	cmp.b	#'#',d0
	bne.s	.ok3
	addq	#1,a5
	move.b	(a5)+,d0
.ok3	sub.w	#' ',d0
	lsl.w	#2,d0
	move.l	(a4,d0.w),a0	; char ptr	

	moveq	#8,d1
	add.w	d6,d1
	cmp.w	#26,d1
	blt.s	.noovflow
	sub.w	#26,d1
.noovflow	move.w	#2+1536,d2
	sub.w	d1,d2	; src y byte increment
	move.w	#2+linewidth,d3
	sub.w	d1,d3	; dst y increment
	lsr.w	#1,d1	; x word count

	; copy 1 char to video RAM with the blitter
	move.w	#25,$ffff8a38.w ; y count
	move.w	d1,$ffff8a36.w  ; x word count
	move.w	d2,$ffff8a22.w   ; src y byte increment
	move.w	d3,$ffff8a30.w ; dst y increment
	move.l	a0,$ffff8a24.w   ; src
	move.l	a6,$ffff8a32.w   ; dest
	move.b	#%11000000,$ffff8a3c.w ; start HOG
	nop
	nop

.shifttext	
	move.b	(a5)+,d0
	cmp.b	#'#',d0
	bne.s	.nocmd
	; speed command A>M (2>26)
	move.b	(a5)+,d0
	sub.b	#'A'-1,d0
	lsl.b	#1,d0
	move.b	d0,textspeed+1	; change speed
	move.b	(a5)+,d0	
.nocmd	tst.b	d0
	beq.s	.wrap
	add.w	textspeed,d6	; scroll speed (must be even and <=26)
	cmp.w	#26,d6
	blt.s	.noinc
	sub.w	#26,d6
	add.l	#1,textptr
	move.l	textptr,a5
	move.b	(a5),d0
	cmp.b	#'#',d0
	bne.s	.noinc
	add.l	#2,textptr
	bra.s	.noinc
.wrap	move.l	#text,textptr
	moveq	#0,d6
.noinc	move.w	d6,textshift			
	rts
	


*** MISC

ikbd	lea	$fffffc00.w,a1
.l1	move.b	(a1),d1
	btst	#1,d1
	beq.s	.l1
	move.b	d0,2(a1)
	rts

flush	move.w	d0,-(sp)
.l1	btst.b	#0,$fffffc00.w
	beq.s	.s1
	move.b	$fffffc02.w,d0
	bra.s	.l1
.s1	move.w	(sp)+,d0
	rts

file_error
	pea	s_errfile
	bra.s	error_message
buyram	pea	s_errmemory
error_message
	move.w	#9,-(sp)
	trap	#1
	addq	#6,sp

	move.w	#8,-(sp)
	trap	#1
	addq	#2,sp

	jmp	end


*** STRING FUNCTIONS

	; a0 text to print
	; a1 destination address on screen
	; d6 max text length - 1

textprint_end
	rts

textprint	lea	smallfont(pc),a2
	lea	SmallTab(pc),a5
	;moveq	#3,d1		; nb bitplanes
.startline	move.l	a1,a6

.loop	moveq	#0,d2
	move.b	(a0)+,d2	; char
	beq	textprint_end
	cmp.b	#13,d2	; CR
	bne.s	.nocr
	
	; CR
	move.l	a6,a1
	add.w	#line_length*9,a1
	bra.s	.startline

.nocr	sub.b	#32,d2	; ASCII-32
	move.b	(a5,d2.w),d2	; offset to char
	lsl.w	#3,d2	; size of char = 8 bytes
	lea	(a2,d2.w),a3	; source

.print
	move.b	(a3)+,(a1)
	move.b	(a3)+,line_length(a1)
	move.b	(a3)+,line_length*2(a1)
	move.b	(a3)+,line_length*3(a1)
	move.b	(a3)+,line_length*4(a1)
	move.b	(a3)+,line_length*5(a1)
	move.b	(a3)+,line_length*6(a1)
	move.b	(a3),line_length*7(a1)
	addq	#8,a1

	IFEQ	monochrome
	move.l	a1,d5
	btst	#0,d5
	bne.s	.odd
	ENDC
	subq	#7,a1
	dbra	d6,.loop
	rts
.odd	subq	#1,a1
	dbra	d6,.loop
	rts
	

	; d0 value to convert
	; a0 textbuffer (8 bytes)
itoahex	lea	hexstr,a2
	lea	8(a0),a0
	moveq	#7,d3
	move.w	#$F,d2
.loop	move.w	d0,d1
	and.w	d2,d1
	move.b	(a2,d1.w),-(a0)
	lsr.l	#4,d0
	dbra	d3,.loop
	rts


hexstr	dc.b	'0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F'
	even


	section	data

	even

vbl_count	dc.w	0
b_loading	dc.w	0
b_buffering_lock
	dc.w	-1
b_first_refresh
	dc.w	-1
b_fileerror
	dc.w	0
screen0_ptr
	dc.l	SCREEN
screen1_ptr 
	dc.l	SCREEN+(linewidth*240)
screen2_ptr
	dc.l	SCREEN+(linewidth*480)
vid0_ptr	dc.l	SCREEN
vid1_ptr	dc.l	SCREEN+(vidwidth*240)
vid2_ptr	dc.l	SCREEN+(vidwidth*480)

screen_debug_ptr
	dc.l	buf_nothing_end
file_handle
	dc.w	0
debug_color
	dc.w	0
debug_info	dc.w	0



idx_play	dc.l	play_index		; ptr to next frame to play
idx_load	dc.l	vid_index		; ptr to frame size 16bits list
idx_loaded	dc.l	play_index		; ptr to next frame to load
load_ptr	dc.l	0	; start at vid_buffer
play_ptr	dc.l	0	; video frame ptr
	dc.w	0	; 32b align
play_frm	dc.w	0	; video frame number
aplay_ptr	dc.l	0	; audio frame ptr
	dc.w	0	; 32b align
aplay_frm	dc.w	0	; audio frame number
play_offset
	dc.l	0
load_offset
	dc.l	0
size_toload
	dc.l	0
vid_buffer	dc.l	0
vid_buffer_end
	dc.l	0
framecount
	dc.w	SWITCH_FRAMES+322
swap_buffers
	dc.w	-1


s_vid_filename
	dc.b	"AUDIO.DAT",0
s_idx_filename
	dc.b	"AUDIO.IDX",0
s_debug_load
	dc.b	"LOAD ",0
s_debug_play
	dc.b	"PLAY ",0
s_hex	dc.b	"         ",0
s_nothing	dc.b	"     ",0



s_errmemory
	dc.b	"Not enough memory available T_T",10,13,10,13,"Please buy some RAM and try again.",10,13,0
s_errfile
	dc.b	"File error",10,13,0

text	dc.b	"             "
	dc.b	"VGA CARD DETECTED             "
	dc.b	"#A LOOKS LIKE YOU'RE THE LUCKY OWNER OF A MSTE WITH AN ET4000 CARD"
	dc.b	"      #C SO LET'S ENJOY SPEED AND COLORS WITH THIS SMALL INTRO! "
	dc.b	"      -CREDITS-       MUSIC DDAMAGE     GFX ZONE     CODE FENARINARSA"
	dc.b	"                "
	dc.b	" SORRY FOR THE VIDEO AND AUDIO BUGS. #DHERE'S A FULL EXPLANATION WHY:         #KGUESS WHAT NO BLOODY ST EMULATOR KNOWS WHAT"
	dc.b	" A VGA CARD IS SO NO CROSSDEV FOR ME AND BOY I DIDN'T MISS DEV ON REAL HARDWARE AND TIME IS RUNNING OUT"
	dc.b	" SO YES THERE'S AUDIO CRACKS AND SOME VIDEO GLITCHES, NOVA CARDS DON'T HAVE VSYNC INTERRUPT BECAUSE"
	dc.b	" BASIC VGA CARDS ARE SLOW SHIT                  #C"
	dc.b	" FOR SHORT IT'S A     #ASILLYVENTURE PARTY RELEASE #C         "
	dc.b	" THE MUSIC IS A 50KHZ STEREO PCM STREAMED FROM HDD. YEAH IT'S BIG BUT #B----I KNOW---- #CYOU ALL HAVE COSMOSEX OR ULTRASATAN WITH ---UNUSED DISK SPACE---"
	dc.b	"           THANKS TO JB FROM DDAMAGE FOR THE ORIGINAL TUNE BTW - MERCI MEC!                 "
	dc.b	"           I DIDN'T CHOOSE THE PICTURES RANDOMLY - THIS INTRO IS ALSO A TRAILER OF WHO'S COMING NEXT FOR YOUR --STANDARD SHIFTER-- STE"
	dc.b	"      FOLLOW ME #B  FENARINARSA ON TWITTER #C      IF YOU DON'T WANT TO MISS THE RELEASE. HOPEFULLY BEFORE CHRISTMAS!           LATER!      "
	dc.b	"             #B "
	dc.b	0
	even
textptr	dc.l	text
textshift	dc.w	0
textspeed	dc.w	4

	even

smallfont	dc.b	0,0,0,0,0,0,0,0
	incbin	"SMALL"
	dc.b	$ff,$ff,$ff,$ff,$ff,$ff,$ff,0
SmallTab	dc.b	0,38,0,48,0,0,0,42,43,44,0,46,41,45,47,0
	dc.b	1,2,3,4,5,6,7,8,9,10
	dc.b	39,40,0,0,0,37,0
	dc.b	11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27
	dc.b	28,29,30,31,32,33,34,35,36,37,38,39,40,41

	even
back0	incbin	"back0.bmp"
pal0	dc.l	back0+$36
image0	EQU	back0+1014 ;$3FB
	even
back1	incbin	"back1.bmp"
pal1	dc.l	back1+$36
image1	EQU	back1+1014 ;$3FB
	even
back2	incbin	"back2.bmp"
pal2	dc.l	back2+$36
image2	EQU	back2+1014 ;$3FB	even
	even
fontimg	incbin	"carebear.bmp"
fontpal	EQU	fontimg+$36
fontidx	
Xchar	SET	0
	REPT	59
	dc.l	fontimg+1070+Xchar
Xchar	SET	Xchar+26
	ENDR

	section	bss

	even
Save_Mfp	ds.l	16
Save_Vec	ds.l	17
old_screen
	ds.l	1
old_ints	ds.b	26
old_palette
	ds.w	16
vid_index	ds.w	nb_frames+1
play_index	ds.l	nb_frames+1
vgapal0	ds.l	256
vgapal1	ds.l	256
vgapal2	ds.l	256
buf_nothing
	ds.w	40
buf_nothing_end

