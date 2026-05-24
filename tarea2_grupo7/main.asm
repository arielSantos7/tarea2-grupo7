;-------------------------------------------------------------------------------
; Interrupt Management Demostration
; Uses Timer_A0 to generate an interrupt every 0.5 seconds.  With this
; interrupt green LED status is toggle so that it will light on every 1 second.
; Button S1 generates an interrupt used to toggle CCIE in TA0CCTL0.  With this
; the interrupt generation from Timer_A0 can be enable and disable.
;
; Author: José Navarro
; November 1, 2023
;-------------------------------------------------------------------------------
            .cdecls C,LIST,"msp430.h"       ; Include device header file

;-------------------------------------------------------------------------------
            .def    RESET                   ; Export program entry-point to
                                            ; make it known to linker.
;-------------------------------------------------------------------------------
            .text                           ; Assemble into program memory.
            .retain                         ; Override ELF conditional linking
                                            ; and retain current section.
            .retainrefs                     ; And retain any sections that have
                                            ; references to current section.

pos			.byte	9, 5, 3, 18, 14, 7			; Positions on the LCD
numidx  	.byte	0, 1, 5						; The indices for the numbers on the LCD

			.align
half		.byte	0							; Flag to check if half a second has passed.
												; Used for duplicating a delay of 0.5s, to 1s

;Define high and low byte values to generate chars J, N, F
;Sprites			0		1		2		3		4		5		6		7		8		9
numsH		.byte 	0xFC,	0x00,	0xDB,	0xF3,	0x67,	0xB7,	0xBF,	0xE0,	0xFF, 	0xF7
numsL		.byte 	0x00,	0x50,  	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00
;-------------------------------------------------------------------------------
RESET       mov.w   #__STACK_END,SP         ; Initialize stackpointer
StopWDT     mov.w   #WDTPW|WDTHOLD,&WDTCTL  ; Stop watchdog timer

;-------------------------------------------------------------------------------
; Setup
;-------------------------------------------------------------------------------


SetupButtonsAndLEDs:

	        bic.b   #0xFF,&P1SEL0           ; Set PxSel0 and PxSel1 to digital I/O
	        bic.b   #0xFF,&P1SEL1           ; Digital I/O is the default
	        bic.b   #0xFF,&P9SEL0
	        bic.b   #0xFF,&P9SEL1

	        mov.b   #11111001B,&P1DIR       ; Set P1.1 and P1.2 for input and all
	                                        ; other P1 pins for output
	        bis.b   #0xFF,&P9DIR            ; Set all P9 pins for output

	        mov.b   #00000110B,&P1REN       ; Activate P1.1 and P1.2 programable
	                                        ; pull-up/pull-down resistors and deactivate
	                                        ; others.
	        bis.b   #00000110B,&P1OUT       ; Set resistors for P1.1 and P1.2 as
	                                        ; as pull-up
	        bic.b   #0x01,&P1OUT            ; Clear P1.0 and P9.7 output latch to
	        bic.b   #0x80,&P9OUT            ; start with both off

SetupLCD:		;Initialize LCD segments 0 - 21; 26 - 43
			MOV.W   #0xFFFF,&LCDCPCTL0
			MOV.W   #0xfc3f,&LCDCPCTL1
  		    MOV.W   #0x0fff,&LCDCPCTL2

			;Initialize LCD_C
  		    ;ACLK, Divider = 1, Pre-divider = 16; 4-pin MUX
			MOV.W   #0x041e,&LCDCCTL0

  		    ;VLCD generated internally,
  		    ;V2-V4 generated internally, v5 to ground
  		    ;Set VLCD voltage to 2.60v
  		    ;Enable charge pump and select internal reference for it
  		    MOV.W   #0x0208,&LCDCVCTL

			MOV.W   #0x8000,&LCDCCPCTL   	;Clock synchronization enabled

			MOV.W   #2,&LCDCMEMCTL       	;Clear LCD memory

UnlockGPIO:
			bic.w   #LOCKLPM5,&PM5CTL0      ; Disable the GPIO power-on default
                                            ; high-impedance mode to activate
                                            ; previously configured port setting

			jmp 	main

;-------------------------------------------------------------------------------
; Sub-rutinas
;-------------------------------------------------------------------------------

changeTo10Hz:
			cmp     #6250, &TA0CCR0
			jz		finFreq
			mov     #6250, &TA0CCR0        ; Set the timer capture compare register 0

finFreq:	jmp		continueDownCounter

; Objetivo: Comenzar la cuenta regresiva en el display LCD del MSP430 del numero
;			seleccionado en el menu del conteo.
; Parametros: R6 = 0: Se utiliza como indice interno para navegar por los tres digitos
;					  en el LCD.
; 			  R5: digito en la posicion de centenas (e.g. 123, R8 = 1)
; 			  R7: digito en la posicion de decenas (e.g. 123, R7 = 2)
;			  R8: digito en la posicion de unidades (e.g. 123, R8 = 3)
;			  R9: frecuencia a la que deberia operar el contador (1 Hz o 10 Hz)
; Pre-condiciones: Se asume que el LCD esta encendido, y que la frecuencia ya fue configurada.
; Post-condiciones:
downCounter:

			call	#displayNums			; Llama a la subrutina que se encarga de aparecer los numeros
											; en la pantalla

			cmp.b	#10, R9
			jz		changeTo10Hz

continueDownCounter:
			cmp.b	#0, R8					; Revisa si el digito en posicion de unidades es un 0. Si lo es,
			jz		resetOnes				; salta a 'resetOnes'.
			dec		R8						; Sino, decrementa el valor del digito en unidades, y
			jmp		finDownCounter			; finaliza el conteo de este segundo.


resetOnes:
			cmp.b	#0, R7
			jz		resetTenth
			dec		R7
			mov.b	#9, R8
			jmp		finDownCounter
resetTenth:
			cmp.b	#0, R5
			jz		resetHundreth
			dec		R5
			mov.b	#9, R7
			mov.b	#9, R8
			jmp 	finDownCounter

resetHundreth:
			mov.b	#0, R7
			mov.b	#0, R8

finDownCounter:
			clr		R6
			mov.b	R5, numidx(R6)
			inc		R6
			mov.b	R7, numidx(R6)
			inc		R6
			mov.b	R8, numidx(R6)
			clr 	R6

			ret

displayNums:
			mov.w   #2,&LCDCMEMCTL       	; Clear LCD memory so that there aren't multiple nums on the screen

			mov.b	pos(R6), R14			; Stores the offset of the postion on the LCD.
  		    mov.b   numsH(R5),0x0a20(R14)	; Displays the highbyte on the LCD
	        mov.b   numsL(R5),0x0a21(R14)	; Displays the lowbyte on the LCD
			inc		R6

			mov.b	pos(R6), R14			; Stores the offset of the postion on the LCD.
  		    mov.b   numsH(R7),0x0a20(R14)	; Displays the highbyte on the LCD
	        mov.b   numsL(R7),0x0a21(R14)	; Displays the lowbyte on the LCD
			inc		R6

			mov.b	pos(R6), R14			; Stores the offset of the postion on the LCD.
  		    mov.b   numsH(R8),0x0a20(R14)	; Displays the highbyte on the LCD
	        mov.b   numsL(R8),0x0a21(R14)	; Displays the lowbyte on the LCD
			clr		R6

			ret
;-------------------------------------------------------------------------------
; Interrupt Service Routines (ISRs)
;-------------------------------------------------------------------------------

TIMER_A0_ISR:

			cmp.b	#1, &half				; Check if it already passed 0.5 seconds.
			jnz		fin						; If not, end the ISR and toggle the half flag.

			call 	#downCounter

fin:
			xor.b	#1, &half				; Toggles the half flag to indicate that
											; the number should not change yet.
      	  	reti

PORT1_ISR:
		    bic.b   #00000010b, &P1IFG  	; Reset interrupt flag
		   	nop
		    xor     #CCIE, &TA0CCTL0		; Desactiva las interrupciones del timer A si estan activadas,
		    								; si estan desactivadas, las activa.
		    nop

		    reti

;-------------------------------------------------------------------------------
; Main loop here
;-------------------------------------------------------------------------------
main:	   	NOP                             ; main program
	        MOV.W   #WDTPW+WDTHOLD,&WDTCTL  ; Stop watchdog timer

	        bis.b   #02h, &P1IES            ; Int generated on high to low transition
	        bis.b   #02h, &P1IE             ; Enable interrupt at P1.1

	        mov     #CCIE, &TA0CCTL0        ; Enable TACCR0 interrupt

	        mov     #TASSEL_2+MC_1+ID_3, &TA0CTL  ;Set timer according to next table
	   		nop
	        ; Uses SMCLK and up mode
	        ; TASSELx        MCx (mode control)                IDx (input divider)
	        ; 00 -> TACLK    00 -> Stop                        00 -> /1
	        ; 01 -> ACLK     01 -> Up mode (up to TACCR0)      01 -> /2
	        ; 10 -> SMCLK    10 -> Continuous (up to 0FFFFh)   10 -> /4
	        ; 11 -> INCLK    11 -> Up/down (top on TACCR0)     11 -> /8

	        ; period = cycles * divider / SMCLK
	        ; Assuming SMCLK = 1 MHz, divider = 8 and period = 0.5 seg
	        ; cycles = 62500.  With period = 0.5 LED turn on every 1 second
	        mov     #62500, &TA0CCR0        ; Set the timer capture compare register 0

	        bic.b   #0000010b, &P1IFG       ; To erase a flag raised before
	                                        ; activating the GIE. This help to
	                                        ; avoid responding to a push on button
	                                        ; previous to program start.

	        nop             ; required befor enabling interrupts

	        ;bis     #GIE+LPM0, SR           ; Enable interrupts and enter Low Power mode 0
	        bis		#GIE, SR				; that doesn't disable timers
	        nop                             ; Required after enabling interrupts

initPreconditions:
			clr		R6						; Reset R6 so it starts at 0
			mov.b	numidx(R6), R5			; Moving the first number (hundreth place) into R5
			inc		R6						; Increase R6
			mov.b	numidx(R6), R7			; Move the second number (tenth place) into R7
			inc		R6						; Increase R6
			mov.b	numidx(R6), R8			; Move the third number (oneth place) into R8
			clr 	R6						; Reset R6 to 0

			mov.b 	#10, R9					; Set frequency to 10

			bis.w   #1, &LCDCCTL0			; Turn on LCD

	        jmp $                           ; jump to current location '$'
	        nop                             ; (endless loop)


;-------------------------------------------------------------------------------
; Stack Pointer definition
;-------------------------------------------------------------------------------
            .global __STACK_END
            .sect   .stack

;-------------------------------------------------------------------------------
; Interrupt Vectors
;-------------------------------------------------------------------------------
            .sect   ".reset"                ; MSP430 RESET Vector
            .short  RESET
            .sect   ".int37"
            .short  PORT1_ISR
            .sect   ".int44"
            .short  TIMER_A0_ISR
            .END

