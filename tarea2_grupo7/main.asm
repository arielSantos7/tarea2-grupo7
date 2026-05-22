; Interrupt Management Demostration
; Program Port 1 to generate an interrupt everytime the push button
; on the launchpad is pressed. The first time the red LED will be light on.
; The second time the green LED will be light on. Next times will cause no
; changes.
; *IMPORTANT: To find the correct INT# and address specific for your
; Micro/Launchpad open the msp430.h file and look into the file that
; includes the interrupt.  For this case I used msp430fr69891.h in
; C:\ti\ccs1011\ccs\ccs_base\msp430\include
;
; No error message if : is not used at the end of Interrupt Service
; routine name but if not used the ISR is not executed.
;
; Author: José Navarro
; March 20, 2021
; Updated: November 30, 2023

;-------------------------------------------------------------------------------
; MSP430 Assembler Code Template for use with TI Code Composer Studio
;
;
;-------------------------------------------------------------------------------
            .cdecls C,LIST,"msp430.h"       ; Include device header file
            
;-------------------------------------------------------------------------------
            .def    RESET                   ; Export program entry-point to
                                            ; make it known to linker.
;-------------------------------------------------------------------------------
            .text                           ; Assemble into program memory.
;            .retain                         ; Override ELF conditional linking
                                            ; and retain current section.
;            .retainrefs                     ; And retain any sections that have
                                            ; references to current section.


pushCount   .word 0


;-------------------------------------------------------------------------------
RESET       mov.w   #__STACK_END,SP         ; Initialize stackpointer
StopWDT     mov.w   #WDTPW|WDTHOLD,&WDTCTL  ; Stop watchdog timer


;-------------------------------------------------------------------------------
; Main loop here
;-------------------------------------------------------------------------------
            mov.b   #0FFh,&P2DIR            ; All pins on P1 & P2 for output except for
            mov.b   #0FDh,&P1DIR            ; for push button
            mov.b   #0FFh,&P9DIR            ; All pins on P9 for output


            bic.b   #10000000b, &P9OUT      ; Turn off green LED on P9.7
            bic.b   #00000001b, &P1OUT      ; Turn off red LED on P1.0

            bic.b   #00000011b, &P1SEL0     ; For each port pin, a 0 on both PxSEL0 and PxSEL1
            bic.b   #00000011b, &P1SEL1     ; indicates that it will be uses as digital I/O.
            bic.b   #10000000b, &P9SEL0     ; 00 for P1.1, P1.0 and P9.7 indicates that button S1,
            bic.b   #10000000b, &P9SEL1     ; red LED and green LED respectively will be set for
                                            ; digital I/O

                                                                  ;
            bis.b   #02h, &P1OUT
            bis.b   #02h, &P1REN            ; P1.1 Resistor enabled as pullup
                                            ; resistor
            bis.b   #02h, &P1IES            ; Int generated on high to low transition
            bic.b   #02h, &P1IFG            ; Because previous instruction can (terrible) set int flag
            bis.b   #02h, &P1IE             ; Enable interrupt at P1.1

UnlockGPIO  bic.w   #LOCKLPM5,&PM5CTL0      ; Disable the GPIO power-on default
                                            ; high-impedance mode to activate
                                            ; previously configured port settings

            mov     #0, pushCount           ; When using reload with the debugger
                                            ; the memory content is not reset to
                                            ; original values. To take care of
                                            ; that situation pushCount is reset
                                            ; to 0

            bic.b   #0000010b, &P1IFG       ; To erase a flag raised before
                                            ; activating the GIE. This help to
                                            ; avoid responding to a push on button
                                            ; previous to program start.
                                            ; Already cleared in a previous instruction.
                                            ; Just showing another option

            nop                             ; Required befor setting interrupt bit

            bis.w   #GIE,SR                 ; Interrupts enabled (same as eint)
                                            ; so that the micro reacts to
                                            ; interrupts

            nop                             ; Wait after setting interrupt bit

            BIS.W #CPUOFF,SR                ; Turn off the CPU
busyWait:									; Test
            nop
            JMP busyWait                    ; jump to current location '$'
            nop                             ; (endless loop)

;Interrupt Service Routine (ISR) that will be executed when the push button
;is pressed.
    .sect   ".text:_isr:PORT1_ISR"          ; Name convention is just a matter of style
    .align  2
    .global PORT1_ISR                       ; In case you reference it from another file

PORT1_ISR:
            bit.b   #00000010b, &P1IFG      ; Test P1IFG to detect if there is
                                            ; an interrupt generated by P1.3
                                            ; that corresponds to push button

            jz      falseAlarm              ; if no interrupt from push button

            bic.b   #00000010b, &P1IFG      ; to check if it is the first time
            cmp     #0, pushCount           ; the button was pressed. If not, go
            jne     notFirst                ; to light on green LED

            bis.b   #00000001b,&P1OUT       ; turn on red LED and
            jmp     fin                     ; go to end of ISR

notFirst:
            bis.b   #10000000b,&P9OUT       ; light on the green LED

fin:        inc     pushCount               ; Increment the pushes counter

falseAlarm:
            reti                            ; Return from interrupt

                                            

;-------------------------------------------------------------------------------
; Stack Pointer definition
;-------------------------------------------------------------------------------
            .global __STACK_END
            .sect   .stack
            
;-------------------------------------------------------------------------------
; Interrupt Vectors
;-------------------------------------------------------------------------------
            .sect   ".int37"    ; Port1 Interrupt vector (FFDA).
            .short  PORT1_ISR
            .sect   ".reset"                ; MSP430 RESET Vector
            .short  RESET
            .end
