; {symbol
REGS_FS_OFFSET equ (10*4)
REGS_ERR_CODE_OFFSET equ (11*4)
REGS_CS_OFFSET equ (13*4)
NEED_RESCHED_OFFSET equ  (1*4)
SIGPENDING_OFFSET equ (2*4)

LATCH equ 1193180/100
extern do_IRQ
extern oprintf
extern spin

global ret_from_sys_call
global page_fault,usr_func
global restore_all
global selector_room_plain
global selector_video
global selector_plain_c3,selector_plain_d3,selector_plain_c1,selector_plain_d1,selector_plain_c0,selector_plain_d0;
global sec_data
global tss
global i20h
global p3
global outofproc
global base_tss
; func_table entry
extern _k_show_chars,k_sleep,k_obuffer_shift,_k_show_var,k_open,k_read,k_write,k_close,k_watch,k_seek,k_getchar,sys_fork
extern wake_hs,do_page_fault
extern no_reenter
extern dump_sys
extern key_handler
extern init8253
extern kernel_c
extern init8259A
extern do_timer,schedule,ticks

;edi equ 7e00h
base_kernelStack equ 0fffeh ; kernel-stack range from  0fffeh to 7f00h,about 32kb

base_text equ base_kernel_reset+0xc0000000
base_tss  equ base_text + (tss -_start)
;}end symbol

%include "../include/pm.inc"
%include "../include/utils.inc"
%include "bootinfo.asm"

global _start
[section .text]
_start:

mov esp,0xc0300000
jmp _reallystart
;store some data
tss:
TSS1 selector_plain_d0,ring0_smallstack_bottom, 0, 0, 0, 0
len_tss equ $ - tss

_reallystart:
lgdt [gdtPtr]   ; switch gdt,selector for ds prepared during boot.bin
jmp selector_plain_c0:newcs ;update cs

newcs:nop
;{init
;push  65535;1193181/18
push  11931 ;1193180/100
;push 1193;1193180/1000
call init8253 ; init 8253


add esp,4
push 11111000b
call init8259A ; init 8259A
add esp,4
;init segment-regs
mov  ax, selector_plain_d0
mov  fs, ax
mov  ss, ax
mov  ds, ax
;mov esp, base_kernelStack   ; the stack start at 7f00h ERR be care for stack will boiled
mov  ax, selector_video
mov  gs, ax
mov  es, ax
;end

;set idt
cli
lidt [idtPtr]
mov ax,selector_tss
ltr ax
;done
;}

jmp kernel_c;
;}
;{exception handler
exception_handler:
divide_error:
	save
	jmp exception_handler_step1
len_divide_error equ $ - divide_error

single_step:
	push 0xffffffff
	push 1
	jmp exception_handler_step1
len_single_step equ $ - single_step

nmi:
	push 0xffffffff
	push 2
	jmp exception_handler_step1
len_nmi equ $ - nmi

breakPoint:
	save
	delay (1<<25)
	jmp $
	;recover
	iret
len_breakPoint equ $ - breakPoint

overflow:
	push 0xffffffff
	push 4
	jmp exception_handler_step1
len_overflow equ $ - overflow

bounds_check:
	push 0xffffffff
	push 5
	jmp exception_handler_step1

len_bounds_check equ $ - bounds_check

inval_opcode:
	push 0xffffffff
	push 6
	jmp exception_handler_step1
len_inval_opcode equ $ - inval_opcode

copr_not_avialable:
	push 0xffffffff
	push 7
	jmp exception_handler_step1
len_copr_not_avialable equ $ - copr_not_avialable

double_fault:
	push 8
	jmp exception_handler_step1
len_double_fault equ $ - double_fault

copr_seg_overrun:
	push 0xffffffff
	push 9
	jmp exception_handler_step1
len_copr_seg_overrun equ $ - copr_seg_overrun

inval_tss:
	push 10 
	jmp exception_handler_step1
len_inval_tss equ $ - inval_tss

segment_not_present:
	push 11 
	jmp exception_handler_step1
len_segment_not_present equ $ - segment_not_present

stack_error:
	push 12
	jmp exception_handler_step1
len_stack_error equ $ - stack_error

general_protection:
	push 13
	jmp exception_handler_step1
len_general_protection equ $ - general_protection

copr_error:
	push 0xffffffff
	push 16
	jmp exception_handler_step1
len_copr_error equ $ - copr_error

exception_handler_step1:
	jmp $			; don't want to handle these exception now, just bless they won't happen
	mov ax, [esp+4]
	cmp ax, 0ffffh
	je .no_error_code
	.output_error_code:
		jmp .cleanStack
	.no_error_code:
	.cleanStack:
		add esp, 8  ;have checked add esp,8  correct
;}
.endOfhandler:
	mov eax, [esp+8]
	call dump_sys
	jmp $
	iretd

; timer interrupt
i20h:
	push 0x20 - 256
	jmp common_interrupt

;	call do_timer	
;	mov al,0x20
;	out 0x20,al
;	call schedule
	;far away

; keyboard interrupt
i21h:
	;push sec_data.keyboard
	;call spin
	iret
	push 0	;no err_code
	save
	mov al,0x20
	out 0x20,al
	call key_handler;
	;far away
i2fh:
	;push sec_data.IDE0
	;call spin
	push 0x2f - 256
	jmp common_interrupt
	

i30h:
	jmp $
	save
	mov esp,[kernel_esp]

; page fault
page_fault:
	;有出错码的！不要push了
	push do_page_fault	;这个push位置本该是fs。
	SAVE_ALL_EXCEPT_FS	

	SET_PREG

	jmp error_code

len_page_fault equ  $ - page_fault

; system call
i80:
	push 0	;no err_code
	SAVE_ALL	;寄存器入栈顺序约定了
	SET_PREG
	call dword [eax*4+func_table]
	jmp ret_from_sys_call
i81:	;an I-gate for kernel thread to submit their time slice.
	OPRINTF sec_data.spin
	jmp $
	push 0	;no err_code
	save
	;save current esp to 'current->pregs'
	mov esi,esp	
	and esi,0xffffe000
	mov [esi],esp

	call schedule
	;far away
error_code:
	;fs还没有保存，要保存它，先把对应位置上的function　address取出来。
	GET_CURRENT(ebx)
	mov edi, [esp + REGS_FS_OFFSET]
	mov eax, fs
	mov [esp + REGS_FS_OFFSET], eax	;done

	;寄存器都保护好了，现在根据传递过来的函数地址，呼叫对应的服务例程
	;服务例程都需要两个参数，preg, err_code
	mov eax, esp		;esp现在就是preg，先存起来
	push dword [eax + REGS_ERR_CODE_OFFSET]
	push eax
	call edi
	;------------已经进入到服务例程里了--------------
	
	add esp, 8
	jmp ret_from_exception	;run away
	


common_interrupt:
	SAVE_ALL
	SET_PREG

	push ret_from_intr
	jmp do_IRQ
	
ret_from_exception:
	;do possible soft irq
ret_from_intr:
	GET_CURRENT(ebx)
	mov ecx, [ebx]	;get pregs
	;若中断前夕是内核态，直接restore
	mov eax, [ecx + REGS_CS_OFFSET]
	and eax, 0x3
	cmp eax,0
	je restore_all	;前夕是内核态。 发生在内核态的中断不会引起调度。
	jmp ret_with_reschedule		;中断前夕是用户态

ret_from_sys_call:
	GET_CURRENT(ebx)
	nop		;do softirp in future version

ret_with_reschedule:
	GET_CURRENT(ebx)
	cmp dword [ebx + NEED_RESCHED_OFFSET], 1	;需要rechedule吗
	je reschedule
	cmp dword [ebx + SIGPENDING_OFFSET], 1		;有信号需要处理吗
	je signal_return

restore_all:
	GET_CURRENT(ebx)
	mov esp, [ebx]	;对papaya内核，这是必要的，因为stackframe的位置不固定。
	RESTORE_ALL
	

reschedule:
	call schedule
	jmp ret_from_sys_call

signal_return:
	jmp restore_all
		
usr_func:
	;push 1
	;mov eax,[esp]
	jmp usr_func

[section .data]
sec_data:
.str1:  db 'h',0
.str2:  db 'hello world->wws',0
.str3:  dd 0,1,2,3,4,5,6,7,8,9
.spin:  db 'spin',0
.keyboard: db 'keyboard IRQ', 0
.IDE0: db 'IDE IRQ 2f' , 0
msg:db 'spin',0

;sys_call table,store address of function
func_table:
    dd _k_show_chars ;0 _k_show_chars
    dd sys_fork	;1
    dd 0 ;2		k_obuffer_shift
    dd 0 ;3		_k_show_var
    dd k_open ;4		k_open
    dd k_read ;5		k_read
    dd k_write ;6		k_write
    dd k_close ;7		k_close
    dd 0 ;8		k_watch
    dd k_seek ;9		k_seek
	dd k_getchar	;10
outofproc:
    dd 1
kernel_esp:
    dd 0
ring0_smallstack_top:
.errcode: dd 0
ring0_smallstack_iretd:
.eip   : dd 0
.cs    : dd 0
.eflags: dd 0
.esp   : dd 0
.ss    : dd 0
ring0_smallstack_bottom:

; new gdt
gdt:
.desc_empty: Descriptor 0,0,0
.desc_plain_c0  :Descriptor 0, 0fffffh, DA_32 | DA_C | DA_LIMIT_4K
.desc_plain_d0  :Descriptor 0, 0fffffh, DA_DRW | DA_LIMIT_4K+DA_32
.desc_plain_c1  :Descriptor 0, 0fffffh, DA_32 | DA_C | DA_LIMIT_4K+DA_DPL1
.desc_plain_d1  :Descriptor 0, 0fffffh, DA_32 | DA_DRW | DA_LIMIT_4K+DA_DPL1
.desc_plain_c3  :Descriptor 0, 0fffffh, DA_C | DA_LIMIT_4K + DA_DPL3 + DA_32
.desc_plain_d3  :Descriptor 0, 0fffffh, DA_DRW | DA_LIMIT_4K + DA_DPL3 + DA_32

.desc_video     :Descriptor    0b8000h,      0ffffh, DA_DRW + DA_32 + DA_DPL3
.desc_pgTbl     :Descriptor  pgTblBase,        1023, DA_DRW | DA_LIMIT_4K + DA_32
.desc_pgDir     :Descriptor  pgDirBase,        4095, DA_DRW + DA_32
.desc_room_plain:Descriptor          0,     0fffffh, DA_DRW | DA_LIMIT_4K + DA_32 + DA_DPL3
.desc_tss       :Descriptor   base_tss, len_tss - 1, DA_386TSS
; end of new gdt
len_gdt equ $ - gdt

;{selector start
selector_plain_c0 equ gdt.desc_plain_c0 - gdt
selector_plain_d0 equ gdt.desc_plain_d0 - gdt
selector_plain_c1 equ gdt.desc_plain_c1 - gdt + SA_RPL1
selector_plain_d1 equ gdt.desc_plain_d1 - gdt + SA_RPL1
selector_plain_c3 equ gdt.desc_plain_c3 - gdt + SA_RPL3
selector_plain_d3 equ gdt.desc_plain_d3 - gdt + SA_RPL3

selector_video      equ gdt.desc_video - gdt
selector_pgTbl      equ gdt.desc_pgTbl - gdt
selector_pgDir      equ gdt.desc_pgDir - gdt
selector_room_plain equ gdt.desc_room_plain - gdt
selector_tss        equ gdt.desc_tss - gdt
;}selector end

gdtPtr:
	dw len_gdt-1
	dd gdt
	dw 0 ; padden to align on 8-bit

;{gate for idt
idt:
.gate_divide_error       : Gate selector_plain_c0, divide_error - _start + base_text,           0, DA_386IGate
.gate_single_step        : Gate selector_plain_c0, single_step - _start + base_text,            0, DA_386IGate 
.gate_nmi                : Gate selector_plain_c0, nmi - _start + base_text,                    0, DA_386IGate 
.gate_breakPoint         : Gate selector_plain_c0, breakPoint - _start + base_text,             0, DA_386IGate 
.gate_overflow           : Gate selector_plain_c0, overflow - _start + base_text,               0, DA_386IGate 
.gate_bounds_check       : Gate selector_plain_c0, bounds_check - _start + base_text,           0, DA_386IGate 
.gate_inval_opcode       : Gate selector_plain_c0, inval_opcode - _start + base_text,           0, DA_386IGate 
.gate_copr_not_avialable : Gate selector_plain_c0, copr_not_avialable - _start + base_text,     0, DA_386IGate 
.gate_double_fault       : Gate selector_plain_c0, double_fault - _start + base_text,           0, DA_386IGate 
.gate_copr_seg_overrun   : Gate selector_plain_c0, copr_seg_overrun - _start + base_text,       0, DA_386IGate 
.gate_inval_tss          : Gate selector_plain_c0, inval_tss - _start + base_text,              0, DA_386IGate 
.gate_segment_not_present: Gate selector_plain_c0, segment_not_present - _start + base_text,    0, DA_386IGate 
.gate_stack_error        : Gate selector_plain_c0, stack_error -_start + base_text,             0, DA_386IGate 
.gate_general_protection : Gate selector_plain_c0, general_protection - _start + base_text,     0, DA_386IGate 
.gate_page_fault         : Gate selector_plain_c0, page_fault - _start + base_text,             0, DA_386IGate 
.gate_copr_error         : Gate selector_plain_c0, copr_error - _start + base_text,             0, DA_386IGate 

%rep (0x20-16) ; 0-15,totally 16 gates,0-0x19,totally 0x20 gates,use (0x20-16)
Gate selector_plain_c0, i80 - _start + base_text, 0, DA_386IGate
%endrep

.gate_i20h:Gate selector_plain_c0,i20h - _start + base_text, 0, DA_386IGate + DA_DPL3 ;ERR dpl3
.gate_i21h:Gate selector_plain_c0,i21h - _start + base_text, 0, DA_386IGate

%rep (0x2f-0x22)
Gate selector_plain_c0, i2fh -_start + base_text, 0, DA_386IGate
%endrep

.gate_i2fh:Gate selector_plain_c0,i2fh - _start + base_text, 0, DA_386IGate
.gate_i30h:Gate selector_plain_c0,i30h - _start + base_text, 0, DA_386IGate

%rep (0x80-0x31) ;0-0x2f,totally 0x30 gates,0-0x79,totally 0x80 gates,use (0x80-0x22)
Gate selector_plain_c0, i80 -_start + base_text, 0, DA_386IGate
%endrep

.gate_i80h:Gate selector_plain_c0, i80 - _start + base_text, 0, DA_386IGate + DA_DPL3
.gate_i81h:Gate selector_plain_c0, i81 - _start + base_text, 0, DA_386IGate + DA_DPL0

len_idt equ $ - idt

idtPtr:
	dw len_idt-1
	dd idt
	dw 0
;end}	