#define __SFR_OFFSET 0
#include "avr/io.h"

temp1 = 16           
counter = 17         
keyCode = 18         
inputPos = 19        
sysState = 20        
flashCount = 21      
timerCount = 22      
buttonState = 23     
Button_debouncing = 24 
temp2 = 25           
modeButtonState = 26 
servoPosition = 27   
codeMatch = 28       

.equ STATE_LOCKED, 0     
.equ STATE_UNLOCKED, 1   
.equ STATE_ERROR, 2      
.equ STATE_ALARM, 3      
.equ STATE_PROGRAMMING, 4 

; PIN/PORT assignments
.equ SERVO_PIN, 2        
.equ RED_LED, 5          
.equ YELLOW_LED, 4       
.equ GREEN_LED, 3       
.equ BUTTON_PIN, 0       
.equ MODE_BUTTON_PIN, 1  
.equ correctCode, 0x0100 
.equ enteredCode, 0x0200 
.equ tempCode, 0x0300    

; Servo positions
.equ SERVO_LOCKED, 2000    
.equ SERVO_HALF_OPEN, 3000 
.equ SERVO_FULL_OPEN, 4000 

; Timing Constants
.equ UNLOCK_TIME, 180    
.equ FLASH_INTERVAL, 25  
.equ DEBOUNCE_TIME, 5    

.global main
.global TIMER2_OVF_vect
.global PCINT2_vect      
.global PCINT1_vect      

main:
    ; Initialize stack pointer
    ldi temp1, hi8(RAMEND)
    out SPH, temp1
    ldi temp1, lo8(RAMEND)
    out SPL, temp1

    ; Initialize system state and variables
    ldi sysState, STATE_LOCKED
    clr inputPos
    clr flashCount
    clr timerCount
    clr buttonState
    clr Button_debouncing
    clr counter
    clr modeButtonState
    ldi servoPosition, 0    
    clr codeMatch           

    ; Set default correct code (1234)
    rcall INIT_DEFAULT_CODE

    ; Configure IO ports
    ; PORT B: LEDs (outputs) and Servo (output)
    ldi temp1, (1<<SERVO_PIN)|(1<<RED_LED)|(1<<YELLOW_LED)|(1<<GREEN_LED)
    out DDRB, temp1
    
    ; PORT C: Buttons (inputs with pull-ups)
    ldi temp1, 0
    out DDRC, temp1
    ldi temp1, (1<<BUTTON_PIN)|(1<<MODE_BUTTON_PIN)
    out PORTC, temp1
    
    ; PORT D: Keypad (inputs with pull-ups)
    ldi temp1, 0
    out DDRD, temp1
    ldi temp1, 0xFF        ; Activate Internal Pull-ups for all pins
    out PORTD, temp1

    ; Setup pin change interrupts
    ldi temp1, (1<<PCIE2)|(1<<PCIE1) ; Activate PCINT2 and PCINT1 groups
    sts PCICR, temp1
    ldi temp1, 0xFF        ; Enable all PCINT in PORTD
    sts PCMSK2, temp1
    ldi temp1, (1<<PCINT8)|(1<<PCINT9) ; Enable both buttons in PORTC
    sts PCMSK1, temp1

    ; Setup Timer1 for servo control (16-bit timer)
    ; Fast PWM mode with ICR1 as TOP, prescaler = 8
    ldi temp1, (1<<COM1B1)|(1<<WGM11)  ; Enable OC1B output, Fast PWM mode part 1
    sts TCCR1A, temp1																		;These are 8 bit timers being used lines 100 - 102 and have no process access restrictions
    ldi temp1, (1<<WGM12)|(1<<WGM13)|(1<<CS11)  ; Fast PWM mode part 2, prescaler = 8
    sts TCCR1B, temp1
    
    ; Set TOP value for 20ms period (50Hz) - 16MHz/8/50Hz - 1 = 39999
    ldi temp1, hi8(39999)
    sts ICR1H, temp1
    ldi temp1, lo8(39999)
    sts ICR1L, temp1

    ; Setup Timer2 for timing and LED flashing (8-bit timer)
    ; Timer 2 Normal Mode, prescaler = 1024
    ldi temp1, (1<<CS22)|(1<<CS21)|(1<<CS20)
    sts TCCR2B, temp1
    
    ; Enable Timer2 overflow interrupt
    ldi temp1, (1<<TOIE2)
    sts TIMSK2, temp1

    ; Initialize the system in locked state
    rcall UPDATE_LEDS
    rcall LOCK_SERVO

    ; Enable global interrupts
    sei

MAIN_LOOP:
    rjmp MAIN_LOOP

INIT_DEFAULT_CODE:
    ldi ZL, lo8(correctCode)
    ldi ZH, hi8(correctCode)
    ldi temp1, 1
    st Z+, temp1
    ldi temp1, 2
    st Z+, temp1
    ldi temp1, 3
    st Z+, temp1
    ldi temp1, 4
    st Z+, temp1
    ret
    
PROCESS_LOCKED:
    ; Check if mode button was pressed to enter programming
    cpi modeButtonState, 1
    breq ENTER_PROGRAMMING_MODE
    
    ; Check if a key was pressed
    tst keyCode
    breq PROCESS_LOCKED_DONE
    
    ; Store the entered digit
    ldi ZL, lo8(enteredCode)
    ldi ZH, hi8(enteredCode)
    add ZL, inputPos      ; Add offset for current digit position
    st Z, keyCode         ; Store the digit
    inc inputPos          ; Move to next position
    
    ; Check if code entry is complete
    cpi inputPos, 4
    brne PROCESS_LOCKED_DONE
    
    ; Verify entered code
    rcall CHECK_CODE
    tst codeMatch         ; Check if code matches (0 = match, 1 = no match)
    brne WRONG_CODE
    
    ; Correct code - unlock
    ldi sysState, STATE_UNLOCKED
    clr timerCount        ; Start countdown timer
    ldi servoPosition, 2  ; Set to full-open (180 degrees)
    rcall UPDATE_SERVO    ; Activate servo
    rcall UPDATE_LEDS     ; Update LEDs
    rjmp PROCESS_LOCKED_DONE
    
WRONG_CODE:
    ; First error or second error?
    cpi sysState, STATE_ERROR
    breq SECOND_ERROR
    
    ; First error
    ldi sysState, STATE_ERROR
    clr flashCount        ; Reset flash counter
    rcall UPDATE_LEDS
    rjmp PROCESS_LOCKED_DONE
    
SECOND_ERROR:
    ; Second error - go to alarm state
    ldi sysState, STATE_ALARM
    clr flashCount        ; Reset flash counter
    rcall UPDATE_LEDS
    
PROCESS_LOCKED_DONE:
    clr keyCode           ; Clear keyCode for next press
    ret

ENTER_PROGRAMMING_MODE:
    ; Enter programming mode
    ldi sysState, STATE_PROGRAMMING
    clr inputPos          ; Reset for new code entry
    clr modeButtonState   ; Clear button state
    rcall UPDATE_LEDS
    ret

PROCESS_UNLOCKED:
    ; Check if mode button was pressed to change servo position
    cpi modeButtonState, 1
    breq TOGGLE_SERVO_POSITION
    
    ; Check if button was pressed to lock immediately
    cpi buttonState, 1
    breq LOCK_SYSTEM
    
    ; Otherwise handled by timer for auto-lock
    ret

TOGGLE_SERVO_POSITION:
    ; We'll keep the servo at full open (180 degrees) when unlocked
    ; Just clear the mode button state
    clr modeButtonState
    ret

PROCESS_ERROR:
    ; Check if a key was pressed to start new code entry
    tst keyCode
    breq PROCESS_ERROR_DONE
    
    ; Reset input position and start new code entry
    clr inputPos
    
    ; Store the first digit
    ldi ZL, lo8(enteredCode)
    ldi ZH, hi8(enteredCode)
    st Z, keyCode
    inc inputPos
    
PROCESS_ERROR_DONE:
    clr keyCode
    ret

PROCESS_ALARM:
    ; Alarm state is managed by timer interrupt for flashing
    ; Can only be reset by holding both buttons for 3 seconds
    cpi buttonState, 1
    brne PROCESS_ALARM_DONE
    cpi modeButtonState, 1
    brne PROCESS_ALARM_DONE
    
    ; Both buttons are pressed, increment counter
    inc counter
    cpi counter, 150      ; ~3 seconds (in timer ticks)
    brne PROCESS_ALARM_DONE
    
    ; Reset alarm state
    ldi sysState, STATE_LOCKED
    clr inputPos
    clr counter
    clr buttonState
    clr modeButtonState
    rcall LOCK_SERVO
    rcall UPDATE_LEDS
    
PROCESS_ALARM_DONE:
    ret

PROCESS_PROGRAMMING:
    ; Check if a key was pressed for code programming
    tst keyCode
    breq PROCESS_PROGRAMMING_DONE
    
    ; Store the entered digit in tempCode
    ldi ZL, lo8(tempCode)
    ldi ZH, hi8(tempCode)
    add ZL, inputPos      ; Add offset for current digit position
    st Z, keyCode         ; Store the digit
    inc inputPos          ; Move to next position
    
    ; Check if new code entry is complete
    cpi inputPos, 4
    brne PROCESS_PROGRAMMING_DONE
    
    ; Save the new code
    rcall SAVE_NEW_CODE
    
    ; Return to locked state
    ldi sysState, STATE_LOCKED
    clr inputPos
    rcall UPDATE_LEDS
    
PROCESS_PROGRAMMING_DONE:
    clr keyCode
    ret
    
SAVE_NEW_CODE:
    ; Copy the tempCode to correctCode
    ldi ZL, lo8(tempCode)
    ldi ZH, hi8(tempCode)
    ldi YL, lo8(correctCode)
    ldi YH, hi8(correctCode)
    
    ldi counter, 4
    
SAVE_NEW_CODE_LOOP:
    ld temp1, Z+
    st Y+, temp1
    dec counter
    brne SAVE_NEW_CODE_LOOP
    
    ret

LOCK_SYSTEM:
    ; Reset to locked state
    ldi sysState, STATE_LOCKED
    clr inputPos
    clr buttonState
    ldi servoPosition, 0  ; Set to locked position
    rcall UPDATE_SERVO
    rcall UPDATE_LEDS
    ret

PCINT1_vect:
    push temp1           ; Save working register
    in temp1, SREG       ; Save status register
    push temp1
    push temp2
    
    ; Read PORTC input to determine which button was pressed
    in temp2, PINC
    com temp2            ; Invert because pull-ups (0 = pressed)
    
    ; Check unlock button (PC0)
    sbrc temp2, BUTTON_PIN
    ldi buttonState, 1
    
    ; Check mode button (PC1)
    sbrc temp2, MODE_BUTTON_PIN
    ldi modeButtonState, 1
    
    ldi Button_debouncing, DEBOUNCE_TIME  ; Set debounce timer
    
    pop temp2
    pop temp1            ; Restore status register
    out SREG, temp1
    pop temp1            ; Restore working register
    reti

PCINT2_vect:
    push temp1           ; Save working register
    in temp1, SREG       ; Save status register
    push temp1
    
    clr temp1
    sts PCICR, temp1      ; Disable pin change interrupts temporarily
    ldi Button_debouncing, DEBOUNCE_TIME  ; Set debounce timer
    
    pop temp1            ; Restore status register
    out SREG, temp1
    pop temp1            ; Restore working register
    reti

READ_KEYPAD:
    push temp1           ; Save working register
    push temp2
    
    ; Read PORT D input
    in temp1, PIND
    com temp1            ; Invert because pull-ups (0 = pressed)
    
    ; Check if any key is pressed
    cpi temp1, 0
    breq READ_KEYPAD_NONE
    
    ; Extended key decode for 8 keys (simplified example - would be matrix in real implementation)
    clr keyCode
    ldi temp2, 1
    
READ_KEYPAD_CHECK_LOOP:
    lsr temp1
    brcc READ_KEYPAD_NO_KEY
    mov keyCode, temp2
    rjmp READ_KEYPAD_FOUND
    
READ_KEYPAD_NO_KEY:
    inc temp2
    cpi temp2, 9         ; Check all 8 bits
    brne READ_KEYPAD_CHECK_LOOP
    clr keyCode
    
READ_KEYPAD_FOUND:
    
READ_KEYPAD_NONE:
    ; Process the key press based on current state
    tst keyCode
    breq READ_KEYPAD_EXIT
    
    cpi sysState, STATE_LOCKED
    breq READ_KEYPAD_LOCKED
    cpi sysState, STATE_ERROR
    breq READ_KEYPAD_ERROR
    cpi sysState, STATE_PROGRAMMING
    breq READ_KEYPAD_PROGRAMMING
    rjmp READ_KEYPAD_EXIT
    
READ_KEYPAD_LOCKED:
    rcall PROCESS_LOCKED
    rjmp READ_KEYPAD_EXIT
    
READ_KEYPAD_ERROR:
    rcall PROCESS_ERROR
    rjmp READ_KEYPAD_EXIT
    
READ_KEYPAD_PROGRAMMING:
    rcall PROCESS_PROGRAMMING
    
READ_KEYPAD_EXIT:
    ; Re-enable pin change interrupts
    ldi temp1, (1<<PCIE2)|(1<<PCIE1)
    sts PCICR, temp1
    
    pop temp2
    pop temp1            ; Restore working register
    ret

CHECK_CODE:
    push temp1
    push temp2
    push counter
    push ZL
    push ZH
    push YL
    push YH
    
    ; Set Z pointer to correct code
    ldi ZL, lo8(correctCode)
    ldi ZH, hi8(correctCode)
    
    ; Set Y pointer to entered code
    ldi YL, lo8(enteredCode)
    ldi YH, hi8(enteredCode)
    
    ; Compare 4 digits
    ldi counter, 4
    ldi codeMatch, 0     ; Assume match initially
    
CHECK_CODE_LOOP:
    ld temp1, Z+           ; Load digit from correct code
    ld temp2, Y+           ; Load digit from entered code
    cp temp1, temp2
    breq CHECK_CODE_DIGIT_MATCH
    
    ; Digits don't match - set mismatch flag and exit
    ldi codeMatch, 1       ; Set to 1 = no match
    rjmp CHECK_CODE_EXIT
    
CHECK_CODE_DIGIT_MATCH:
    dec counter
    brne CHECK_CODE_LOOP
    
    ; If we get here, all digits matched
    ldi codeMatch, 0       ; Set to 0 = match
    
CHECK_CODE_EXIT:
    ; Reset input position for next entry
    clr inputPos
    
    pop YH
    pop YL
    pop ZH
    pop ZL
    pop counter
    pop temp2
    pop temp1
    ret

UPDATE_LEDS:
    push temp1
    push temp2
    
    ; Turn off all LEDs first
    in temp1, PORTB
    andi temp1, ~((1<<RED_LED)|(1<<YELLOW_LED)|(1<<GREEN_LED))
    
    ; Set LEDs based on state
    cpi sysState, STATE_LOCKED
    brne CHECK_UNLOCKED
    ori temp1, (1<<RED_LED)
    rjmp UPDATE_LEDS_DONE
    
CHECK_UNLOCKED:
    cpi sysState, STATE_UNLOCKED
    brne CHECK_ERROR
    ori temp1, (1<<GREEN_LED)
    rjmp UPDATE_LEDS_DONE
    
CHECK_ERROR:
    cpi sysState, STATE_ERROR
    brne CHECK_ALARM
    ori temp1, (1<<RED_LED)
    rjmp UPDATE_LEDS_DONE
    
CHECK_ALARM:
    cpi sysState, STATE_ALARM
    brne CHECK_PROGRAMMING
    ; In ALARM state, both RED and YELLOW will flash - controlled by timer
    rjmp UPDATE_LEDS_DONE
    
CHECK_PROGRAMMING:
    cpi sysState, STATE_PROGRAMMING
    brne UPDATE_LEDS_DONE
    ; In PROGRAMMING state, flash green LED
    ori temp1, (1<<GREEN_LED)|(1<<YELLOW_LED)
    
UPDATE_LEDS_DONE:
    out PORTB, temp1
    
    pop temp2
    pop temp1
    ret

UPDATE_SERVO:
    push temp1
    push temp2
    
    ; Set servo position based on servoPosition
    cpi servoPosition, 0
    brne CHECK_HALF_OPEN
    
    ; Locked position
    ldi temp1, hi8(SERVO_LOCKED)
    ldi temp2, lo8(SERVO_LOCKED)
    rjmp SET_SERVO_POS
    
CHECK_HALF_OPEN:
    cpi servoPosition, 1
    brne SET_FULL_OPEN
    
    ; Half-open position (90 degrees)
    ldi temp1, hi8(SERVO_HALF_OPEN)
    ldi temp2, lo8(SERVO_HALF_OPEN)
    rjmp SET_SERVO_POS
    
SET_FULL_OPEN:
    ; Full-open position (180 degrees)
    ldi temp1, hi8(SERVO_FULL_OPEN)
    ldi temp2, lo8(SERVO_FULL_OPEN)
    
SET_SERVO_POS:
    sts OCR1BH, temp1							;lines 547-8 refer to the 16 bit timers being used in this case
    sts OCR1BL, temp2
    
    pop temp2
    pop temp1
    ret

LOCK_SERVO:
    ldi servoPosition, 0
    rcall UPDATE_SERVO
    ret

UNLOCK_SERVO:
    ldi servoPosition, 2  ; Changed to 2 for full-open (180 degrees)
    rcall UPDATE_SERVO
    ret

TIMER2_OVF_vect:
    push temp1           ; Save working register
    in temp1, SREG       ; Save status register
    push temp1
    push temp2
    
    ; Check if we're in debouncing period
    cpi Button_debouncing, 0
    breq CHECK_STATES
    
    dec Button_debouncing
    brne TIMER2_EXIT
    
    ; Debouncing complete, read the keypad
    rcall READ_KEYPAD
    
    rjmp TIMER2_EXIT
    
CHECK_STATES:
    ; Check system state for LED flashing and timing
    cpi sysState, STATE_UNLOCKED
    breq TIMER2_UNLOCKED
    
    cpi sysState, STATE_ERROR
    breq TIMER2_ERROR
    
    cpi sysState, STATE_ALARM
    breq TIMER2_ALARM
    
    cpi sysState, STATE_PROGRAMMING
    breq TIMER2_PROGRAMMING
    
    rjmp TIMER2_EXIT
    
TIMER2_UNLOCKED:
    ; Increment unlock timer
    inc timerCount
    
    ; Check if button was pressed
    tst buttonState
    brne LOCK_SYSTEM_TIMER
    
    ; Check if unlock time has elapsed
    cpi timerCount, UNLOCK_TIME
    brne TIMER2_EXIT
    
LOCK_SYSTEM_TIMER:
    ; Auto-lock after timeout or button press
    ldi sysState, STATE_LOCKED
    clr timerCount
    clr buttonState
    rcall LOCK_SERVO
    rcall UPDATE_LEDS
    rjmp TIMER2_EXIT
    
TIMER2_ERROR:
    ; Flash yellow LED in ERROR state
    inc flashCount
    cpi flashCount, FLASH_INTERVAL
    brne TIMER2_EXIT
    
    ; Toggle yellow LED
    in temp1, PORTB
    ldi temp2, (1<<YELLOW_LED)
    eor temp1, temp2
    out PORTB, temp1
    
    ; Reset flash counter
    clr flashCount
    rjmp TIMER2_EXIT
    
TIMER2_ALARM:
    ; Flash red and yellow LEDs in ALARM state
    inc flashCount
    cpi flashCount, FLASH_INTERVAL
    brne TIMER2_EXIT
    
    ; Toggle red and yellow LEDs
    in temp1, PORTB
    ldi temp2, (1<<RED_LED)|(1<<YELLOW_LED)
    eor temp1, temp2
    out PORTB, temp1
    
    ; Reset flash counter
    clr flashCount
    rjmp TIMER2_EXIT
    
TIMER2_PROGRAMMING:
    ; Alternate green and yellow LEDs in PROGRAMMING state
    inc flashCount
    cpi flashCount, FLASH_INTERVAL
    brne TIMER2_EXIT
    
    ; Toggle between green and yellow LEDs
    in temp1, PORTB
    andi temp1, ~((1<<GREEN_LED)|(1<<YELLOW_LED)) ; Clear both LEDs
    
    ; Check which one should be on
    lsr counter
    brcc PROGRAMMING_GREEN
    ori temp1, (1<<YELLOW_LED)
    rjmp PROGRAMMING_LED_DONE
    
PROGRAMMING_GREEN:
    ori temp1, (1<<GREEN_LED)
    
PROGRAMMING_LED_DONE:
    out PORTB, temp1
    inc counter
    
    ; Reset flash counter
    clr flashCount
    
TIMER2_EXIT:
    pop temp2
    pop temp1            ; Restore status register
    out SREG, temp1
    pop temp1            ; Restore working register
    reti