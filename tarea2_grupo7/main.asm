;-------------------------------------------------------------------------------
; Cronometro Multibase
; [Descripcion]
;
; Autores: Ariel J Santos, ...
; 29 de mayo de 2026
;-------------------------------------------------------------------------------
            .cdecls C,LIST,"msp430.h"       	; Include device header file

;-------------------------------------------------------------------------------
            .def    RESET                   	; Export program entry-point to
                                            	; make it known to linker.
;-------------------------------------------------------------------------------
            .text                           	; Assemble into program memory.
            .retain                         	; Override ELF conditional linking
                                            	; and retain current section.
            .retainrefs                     	; And retain any sections that have
                                            	; references to current section.

pos			.byte	9, 5, 3, 18, 14, 7			; Offsets de las posiciones de los numeros en el LCD
numidx  	.byte	0, 6, 7						; Digitos mostrados en la pantalla para el conteo regresivo

			.align
half		.byte	0							; Valor booleano que representa si ya ha pasado un numero impar
												; de interrupts en el timer. Se usa para duplicar el delay
												; (e.g. de 0.5s a 1.0s)

; Array de numeros utilizados para traducir un valor decimal a la combinacion de bits utilizada para mostrar los
; numeros en el LCD
; Numeros			0		1		2		3		4		5		6		7		8		9
numsH		.byte 	0xFC,	0x00,	0xDB,	0xF3,	0x67,	0xB7,	0xBF,	0xE0,	0xFF, 	0xF7
numsL		.byte 	0x00,	0x50,  	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00,	0x00

; Abecedario		F		R		E		Q		H		Z
abcH		.byte	0x8F,	0xCF,	0x9F,	0xE7,	0x6F,	0x90
abcL		.byte	0x00,	0x02,	0x00, 	0x00,	0x00,	0x28
;-------------------------------------------------------------------------------

RESET       mov.w   #__STACK_END,SP         ; Inicializar 'stackpointer'
StopWDT     mov.w   #WDTPW|WDTHOLD,&WDTCTL  ; Detener 'watchdog timer'

;-------------------------------------------------------------------------------
; Setup
;-------------------------------------------------------------------------------


SetupButtons:
	        bic.b   #0xFF,&P1SEL0           ; Set PxSel0 y PxSel1 para 'digital I/O'
	        bic.b   #0xFF,&P1SEL1

	        mov.b   #11111001B,&P1DIR       ; Set P1.1 y P1.2 para 'input' y todos los
	                                        ; demas pins de P1 para 'output'

	        mov.b   #00000110B,&P1REN       ; Activa los resistores de 'pull-up/pull-down'para
	        								; P1.1 y P1.2 y desactiva para los demas
	        bis.b   #00000110B,&P1OUT       ; Set resistores para P1.1 y P1.2 como 'pull-up'

; Inicializar segmentos del LCD 0 - 21; 26 - 43
SetupLCD:
			mov.w   #0xFFFF,&LCDCPCTL0
			mov.w   #0xfc3f,&LCDCPCTL1
  		    mov.w   #0x0fff,&LCDCPCTL2

			;Initialize LCD_C
  		    ;ACLK, Divider = 1, Pre-divider = 16; 4-pin MUX
			mov.w   #0x041e,&LCDCCTL0

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
; Subrutinas
;-------------------------------------------------------------------------------


; Objetivo: Comenzar la cuenta regresiva en el display LCD del MSP430 del numero
;			seleccionado en el menu del conteo.
; Parametros: R6 = 0: Se utiliza como indice interno para navegar por los tres digitos
;					  en el LCD.
; 			  R5: digito en la posicion de centenas (e.g. 123, R8 = 1)
; 			  R7: digito en la posicion de decenas (e.g. 123, R7 = 2)
;			  R8: digito en la posicion de unidades (e.g. 123, R8 = 3)
;			  R9: frecuencia a la que deberia operar el contador (1 Hz o 10 Hz)
; Pre-condiciones: Se asume que el LCD esta encendido, y que la frecuencia ya fue configurada.
; Post-condiciones: Comenzara el conteo regresivo con la frecuencia seleccionada hasta llegar a 000.
;					Una vez llegue a 0, se podria salir utilizando el boton S2. Mientras se ejecuta
;					el conteo, se puede pausar el mismo con el boton S1, y reanudar con este mismo.
downCounter:

			call	#displayNums			; Llama a la subrutina que se encarga de aparecer los numeros
											; en la pantalla
			cmp.b	#10, R9					; Revisa si la frecuencia seleccionada es de 10 Hz, y si lo es
			jz		changeTo10Hz			; salta a 'changeTo10Hz'. Por defecto sera de 1 Hz.

continueDownCounter:
			cmp.b	#0, R8					; Revisa si el digito en posicion de unidades es un 0. Si lo es,
			jz		resetOnes				; salta a 'resetOnes'.
			dec		R8						; Si no, decrementa el valor del digito, y
			jmp		finDownCounter			; finaliza el conteo de este segundo.

changeTo10Hz:
			cmp     #6250, &TA0CCR0			; Revisa si el numero de ciclos del timer corresponde al utilizado para
											; correr a 10 Hz.
			jz		finFreq					; Si lo es, se sale de la rutina.
			mov     #6250, &TA0CCR0         ; Si no lo es, se cambia el numero de ciclos para que el timer vaya a 10 Hz

finFreq:	jmp		continueDownCounter		; Se reanuda la subrutina de downCounter

resetOnes:
			cmp.b	#0, R7					; Revisa si el digito en posicion de decenas es un 0. Si lo es,
			jz		resetTenth				; salta a 'resetTenth'.
			dec		R7						; Si no, decrementa el valor del digito,
			mov.b	#9, R8					; pone un 9 en el digito de unidades, y
			jmp		finDownCounter			; finaliza el conteo de este segundo.
resetTenth:
			cmp.b	#0, R5					; Revisa si el digito en posicion de centenas es un 0. Si lo es,
			jz		reachedZero				; salta a 'reachedZero'.
			dec		R5						; Si no, decrementa el valor del digito, y
			mov.b	#9, R7					; pone un 9 en el digito de decenas,
			mov.b	#9, R8					; pone un 9 en el digito de unidades, y
			jmp 	finDownCounter			; finaliza el conteo de este segundo.

reachedZero:
			; TODO: Enable interrupt del boton S2
			jmp		$
			nop

finDownCounter:
			clr		R6						; Lleva R6 a 0 para utilizarlo como indice
			ret

; Objetivo: Mostrar en el LCD los numeros. TODO: Expand documantation
; Parametros: R6 = 0: Se utiliza como indice interno para navegar por los tres digitos
;					  en el LCD.
; 			  R5: digito en la posicion de centenas (e.g. 123, R8 = 1)
; 			  R7: digito en la posicion de decenas (e.g. 123, R7 = 2)
;			  R8: digito en la posicion de unidades (e.g. 123, R8 = 3)
;			  R9: frecuencia a la que deberia operar el contador (1 Hz o 10 Hz)
; Pre-condiciones:
; Post-condiciones:
displayNums:
			mov.w   #2,&LCDCMEMCTL       	; Limpia la memoria del LCD para no tener multiples numeros
											; uno encima del otro

			mov.b	pos(R6), R14			; Se guarda el 'offset' de la primera posicion en el LCD.
  		    mov.b   numsH(R5),0x0a20(R14)	; Muestra el 'highbyte' del digito en posicion de centenas en el LCD
	        mov.b   numsL(R5),0x0a21(R14)	; Muestra el 'lowbyte' del digito en posicion de centenas en el LCD
			inc		R6

			mov.b	pos(R6), R14			; Se guarda el 'offset' de la segunda posicion en el LCD.
  		    mov.b   numsH(R7),0x0a20(R14)	; Muestra el 'highbyte' del digito en posicion de decenas en el LCD
	        mov.b   numsL(R7),0x0a21(R14)	; Muestra el 'lowbyte' del digito en posicion de decenas en el LCD
			inc		R6

			mov.b	pos(R6), R14			; Se guarda el 'offset' de la primera posicion en el LCD.
  		    mov.b   numsH(R8),0x0a20(R14)	; Muestra el 'highbyte' del digito en posicion de unidades en el LCD
	        mov.b   numsL(R8),0x0a21(R14)	; Muestra el 'lowbyte' del digito en posicion de unidades en el LCD
			clr		R6

			ret

; Objetivo:
; Parametros: R9: frecuencia a la que deberia operar el contador (1 Hz o 10 Hz)
;				  Tambien se utiliza como 'enum' o 'flag' de 3 estados:
;				  0: La frecuencia no ha sido configurada
;				  2: La frecuencia actual es de 1 Hz pero no ha sido seleccionada
;				  3: La frecuencia acutal es de 10 Hz pero no ha sido seleccionada
; Pre-condiciones:
; Post-condiciones:
freqMenu:

		 	cmp		#0, R9					; Revisa si la frecuencia esta en 0 (lo cual significa que no ha sido configurada)
			jz		displayFreqString		; Si lo es, muestra "FREq" en el LCD

			cmp		#2, R9					; Revisa si la frecuencia esta en 2 (lo cual significa que estaba en 10 Hz)
			jz		display1Hz				; Si lo es, muestra "1 Hz" en el LCD

			cmp		#3, R9					; Revisa si la frecuencia esta en 3 (lo cual significa que estaba en 1 Hz)
			jz		display10Hz				; Si lo es, muestra "10Hz" en el LCD

			jmp		finFreqMenu

displayFreqString:
			mov.w   #2,&LCDCMEMCTL       	; Limpia la memoria del LCD

			clr 	R6
			mov.b	pos(R6), R14			; Se guarda el 'offset' de la primera posicion en el LCD.
  		    mov.b   abcH(R6),0x0a20(R14)	; Muestra el 'highbyte' de la letra 'F' en el LCD
	        mov.b   abcL(R6),0x0a21(R14)	; Muestra el 'lowbyte' de la letra 'F' en el LCD
			inc		R6

			mov.b	pos(R6), R14			; Se guarda el 'offset' de la segunda posicion en el LCD.
  		    mov.b   abcH(R6),0x0a20(R14)	; Muestra el 'highbyte' de la letra 'R' en el LCD
	        mov.b   abcL(R6),0x0a21(R14)	; Muestra el 'lowbyte' de la letra 'R' en el LCD
			inc		R6

			mov.b	pos(R6), R14			; Se guarda el 'offset' de la primera posicion en el LCD.
  		    mov.b   abcH(R6),0x0a20(R14)	; Muestra el 'highbyte' de la letra 'E' en el LCD
	        mov.b   abcL(R6),0x0a21(R14)	; Muestra el 'lowbyte' de la letra 'E' en el LCD
			inc		R6

			mov.b	pos(R6), R14			; Se guarda el 'offset' de la primera posicion en el LCD.
  		    mov.b   abcH(R6),0x0a20(R14)	; Muestra el 'highbyte' de la letra 'q' en el LCD
	        mov.b   abcL(R6),0x0a21(R14)	; Muestra el 'lowbyte' de la letra 'q' en el LCD
			clr		R6

			mov		#2, R9					; Utiliza 2 como flag para mostrar el menu
			jmp 	finFreqMenu

display1Hz:

	        bis.b   #04h, &P1IES            ; Causa la interrupcion del boton S2 en la transicion de 1 a 0
	        bis.b   #04h, &P1IE             ; Activa la interrupcion del puerto P1.2

			mov.w   #2,&LCDCMEMCTL       	; Limpia la memoria del LCD para no tener multiples numeros
											; uno encima del otro
			clr 	R6
			mov.b	#1, R10					; Se guarda 1 para mostrarse en el LCD
			mov.b	pos(R6), R14			; Se guarda el 'offset' de la primera posicion en el LCD.
  		    mov.b   numsH(R10),0x0a20(R14)	; Muestra el 'highbyte' de '1' en la primera posicion del LCD
	        mov.b   numsL(R10),0x0a21(R14)	; Muestra el 'lowbyte' de '1' en la primera posicion del LCD
			inc		R6						; Se incrementa R6 dos veces para dejar una posicion en el LCD en blanco
			inc		R6

			mov.b	#4, R10					; Se guarda el indice para la letra 'H';
			mov.b	pos(R6), R14			; Se guarda el 'offset' de la segunda posicion en el LCD.
  		    mov.b   abcH(R10),0x0a20(R14)	; Muestra el 'highbyte' de la letra 'H' en el LCD
	        mov.b   abcL(R10),0x0a21(R14)	; Muestra el 'lowbyte' de la letra 'E' en el LCD
			inc		R6

			inc		R10
			mov.b	pos(R6), R14			; Se guarda el 'offset' de la primera posicion en el LCD.
  		    mov.b   abcH(R10),0x0a20(R14)	; Muestra el 'highbyte' de la letra 'Z' en el LCD
	        mov.b   abcL(R10),0x0a21(R14)	; Muestra el 'lowbyte' de la letra 'Z' en el LCD
			clr		R6
			mov		#3, R9					; Se guarda '3' en R9 para indicar que la frecuencia mostrada es 1 Hz
			jmp		finFreqMenu

display10Hz:
			clr 	R6
			inc		R6

			mov.b	#0, R10
			mov.b	pos(R6), R14			; Se guarda el 'offset' de la primera posicion en el LCD.
  		    mov.b   numsH(R10),0x0a20(R14)	; Muestra el 'highbyte' de '0' en la segunda posicion del LCD
	        mov.b   numsL(R10),0x0a21(R14)	; Muestra el 'lowbyte' de '0' en la segunda posicion del LCD
			clr 	R6
			mov		#2, R9					; Se guarda '2' en R9 para indicar que la frecuencia mostrada es 10 Hz

finFreqMenu:
			ret

;-------------------------------------------------------------------------------
; Interrupt Service Routines (ISRs)
;-------------------------------------------------------------------------------

; Objetivo: Manejar las interrupciones causadas por el Timer A.
; Parametros: R6 = 0: Se utiliza como indice interno para navegar por los tres digitos
;					  en el LCD.
; 			  R5: digito en la posicion de centenas (e.g. 123, R8 = 1)
; 			  R7: digito en la posicion de decenas (e.g. 123, R7 = 2)
;			  R8: digito en la posicion de unidades (e.g. 123, R8 = 3)
;			  R9: frecuencia a la que deberia operar el contador (1 Hz o 10 Hz)
; Pre-condiciones:
; Post-condiciones:
TIMER_A0_ISR:

			cmp.b	#1, &half				; Revisa si ya paso un numero impar de interrupciones
			jnz		finTimerA0				; Si no, termina la ISR, y cambia half a 'true'.

			call 	#downCounter			; Si ya paso un numero impar de interrupciones, se llama a la subrutina para
											; contar un numero hacia abajo
finTimerA0:
			xor.b	#1, &half				; Cambia el valor 'booleano' half a su valor contrario.
      	  	reti

; Objetivo: Manejar las interrupciones provocadas por los botones S1 y S2
; Parametros: R9: frecuencia a la que deberia operar el contador (1 Hz o 10 Hz)
;				  Tambien se utiliza como 'enum' o 'flag' de 3 estados:
;				  0: La frecuencia no ha sido configurada
;				  2: La frecuencia actual es de 1 Hz pero no ha sido seleccionada
;				  3: La frecuencia acutal es de 10 Hz pero no ha sido seleccionada
; Pre-condiciones:
; Post-condiciones:
PORT1_ISR:
		    bic.b   #00000110b, &P1IFG  	; Resetea el 'flag' de interrupcion para que no se llame indefinidamente esta
		    nop								; ISR
			mov.b   &P1IN,R4                ; Copy into R4 P1IN's byte

delay:
			mov		#0xFFFF, R6				; Se anade un valor alto a R6 para hacer un delay para
next:										; resolver el 'bouncing'
			dec		R6						; Se decrementa R6 hasta llegar a 0
			jnz		next
			bic.b   #00000110b, &P1IFG  	; Resetea el 'flag' de interrupcion para que no se llame indefinidamente esta
		    nop								; ISR

			bit.b	#00000100b,R4			; Revisa si el boton S2 fue presionado.
			jz		S2pressed

S1pressed:
			cmp		#1, R9					; Revisa si la frecuencia ya fue configurada, y si lo fue
			jz		toggleTimer				; presionar el boton S1 causa que se detenga o continue la cuenta regresiva
			cmp		#10, R9
			jz		toggleTimer

			call	#freqMenu				; Si la frecuencia no ha sido configurada, se abre el menu para escoger la frecuencia
			reti

toggleTimer:
			xor     #CCIE, &TA0CCTL0        ; Activa las interrupciones del timer A0
			reti

S2pressed:
			call	#displayNums			; Muestra los numeros antes de comenzar la cuenta regresiva

			cmp		#2, R9					; Si la opcion mostrada es de 1 Hz,
			jz		setFreq10Hz				; selecciona 1 Hz como frecuencia
			cmp		#3, R9					; Si la opcion mostrada es de 10 Hz,
			jz		setFreq1Hz				; selecciona 10 Hz como frecuencia

setFreq10Hz:
			mov		#10, R9					; Selecciona 10 Hz como frecuencia
			mov     #CCIE, &TA0CCTL0        ; Activa las interrupciones del timer A0
			reti
setFreq1Hz:
			mov		#1, R9					; Selecciona 1 Hz como frecuencia
			mov     #CCIE, &TA0CCTL0        ; Activa las interrupciones del timer A0
			reti


;-------------------------------------------------------------------------------
; Main loop here
;-------------------------------------------------------------------------------
main:	   	NOP                             ; main program
	        MOV.W   #WDTPW+WDTHOLD,&WDTCTL  ; Stop watchdog timer

	        bis.b   #02h, &P1IES            ; Int generated on high to low transition
	        bis.b   #02h, &P1IE             ; Enable interrupt at P1.1

	        ;mov     #CCIE, &TA0CCTL0        ; Enable TACCR0 interrupt

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

			clr		R9						; Start R9 at 0 to use it as a flag

			bis.w   #1, &LCDCCTL0			; Turn on LCD

			call	#displayNums			; Display the numbers before starting

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

