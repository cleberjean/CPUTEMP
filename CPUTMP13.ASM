;------------------------------------------------------------------------------
; Exibe a Temperatura de um Processador Intel com Sensor Digital de Temperatura.
; Usa a instru‡„o RDMSR para obter a temperatura.
; Funciona com processadores Intel Core 2 e mais novos.
; By cleberjean@hotmail.com
;
; Compile with "nasm cputemp.asm -o cputemp.com" or
;             "fasm cputemp.asm cputemp.com" (BEWARE! May to produce instructions to 80386+)
;
; History
; -------
;   02feb2024 - Fixed Core 2 Tjmax (105 -> 100 degrees)
;   24may2024 - Support for Processors with the IA32_TEMPERATURE_TARGET MSR   
;   22jun2024 - Support for Celeron J1800 Processor
;   26jun2024 - Check for RDMSR 0x1A2 first, to get Tjmax (default)
;   27jun2025 - Only shows version if something is typeded after program name
;   29jun2025 - Ignores Tab
;   22jul2025 - Meaningless change
;   20may2026 - Google Gemini's suggests applied
;   02jun2026 - Checking if interrupt 67h exists before check EMM386.EXE
;               is loaded
;   18jun2026 - Adds directives cpu 8086 and cpu 386 and adjusts on
;               conditional branchs.
;   21jun2026 - Removed Protected Mode tests and added Windows Enhanced Mode
;               checking
;------------------------------------------------------------------------------


;------------------------------------------------------------------------------
; Defines
;------------------------------------------------------------------------------
    IA32_THERM_STATUS_MSR  equ 0x19C
    IA32_TEMP_TARGET_MSR   equ 0x1A2


    org    100h              ; A .COM program

    cpu    8086              ; Nasm directive. Code below is for 8086 only.


;------------------------------------------------------------------------------
; Code Start
;------------------------------------------------------------------------------
Start:
    push   cs
    pop    ds                ; Certifies that Data Segment is the same of the program code (ES not used)
    cld                      ; SI/DI increments
    mov    si,0081h          ; Start of command line options


;------------------------------------------------------------------------------
; Checks Command Line
;------------------------------------------------------------------------------
Check_CR:    
    lodsb
    cmp    al,0Dh            ; Is a Carriage Return?
    je     Get_Country_Info  ; ...then skips program info
    cmp    al,20h            ; Is a Space?
    je     Check_CR          ; ...then continues to search for Carriage Return
    cmp    al,09h            ; Is a Tab?
    je     Check_CR          ; ...then continues to search for Carriage Return

; Show Program Name and Version    
    mov    dx,PROG_NAME
    mov    ah,09h
    int    21h


;------------------------------------------------------------------------------
; Gets Country Information
;------------------------------------------------------------------------------
Get_Country_Info:    
    mov    ax,3800h
    mov    dx,COUNTRY_INFO   ; NOT USED, BUT MUST HAVE THIS BUFFER!
    int    21h
    mov    [COUNTRY_CODE],bx ; Saves locale country code


;------------------------------------------------------------------------------
; Checks Processor
;
; O code below was taken from Intel Pentium Processor User's Manual Volume 3,
; Chapter 5.3 - SAMPLE CPUID IDENTIFICATION/FPU DETECTION CODE, pages 129 to
; 123, from 1993.
; Example 5-1. CPU Identification and FPU Detection
; Only the CX register was changed to BX.
; The original note says:
;       "This program has been developed by Intel Corporation. You have
;        Intel's permission to incorporate this source code into your
;        product royalty free."


; Double check for 8086/8088.
; Processors later of 8086 always pushes SP to stack, and then decrements 
; SP by 2. 8086 always decrements SP by 2 and then pushes it on stack.
; Also bits 12..15 are always set on the 8086 processor.
; [MODIFIED] Test only bits 14 and 15, due a detection fail when in 
; Priviligied Level != 0.
;------------------------------------------------------------------------------
Check_8086:
    push   sp                ; Pushes SP
    pop    ax                ; Restore in AX
    sub    ax,sp             ; Clears AX if CPU is an 80286 or later
    jnz    Chk_8086_Bad_Proc ; Processor is an 80186 or early
    pushf
    pop    bx                ; Save FLAGS in BX
    mov    ax,bx             ; Copy flags to AX
    and    ax,0FFFh          ; Clear bits 12..15
    push   ax
    popf                     ; Clear bits 12..15 in FLAGS
    pushf
    pop    ax                ; Copy flags again to AX
;    and    ax,0F000h         ; Checks if bits 12..15 still always clean
    and    ax,0C000h         ; Checks if bits 14 and 15 still always clean
    jz     Check_286         ; Processor is in Real Mode


; Fix for Short Only Conditional Branch Instruction on 16-bit Processors
; 16-bit processors not has near conditional branch instructions
Chk_8086_Bad_Proc:    
    jmp    Bad_Proc          ; Bits 14 and 15 from flags register remains
                             ; set (processor is an 8086/80186)

    
;------------------------------------------------------------------------------
; Intel 286 CPU Checking
; Bits 12-15 are always clear on the Intel 286 processor.
;------------------------------------------------------------------------------
Check_286:
    mov    ax,bx               ; Copy flags to AX
    or     ax,0F000h           ; Set bits 12..15
    push   ax
    popf
    pushf
    pop    ax
    and    ax,0F000h           ; If bits 12..15 are cleared, then CPU=80286
    jnz    Check_386           ; CPU is not an 80286


; Fix for Short Only Conditional Branch Instruction on 16-bit Processors
; 16-bit processors not has near conditional branch instructions
    jmp    Bad_Proc            ; CPU is an 80286


         ;--------------------------------------------------------;
         ; Starting here, now is safe to use 32 bits instructions ;
         ;--------------------------------------------------------;

;------------------------------------------------------------------------------
; Intel386 CPU Checking
; The AC bit, bit #18, is a new bit introduced in the EFLAGS
; register on the Intel486 DX CPU to generate alignment faults.
; This bit can not be set on the Intel386 CPU.
;------------------------------------------------------------------------------
    cpu    386               ; Nasm directive. Code below is for 386 until 486.

Check_386:
    push   bx
    popf                     ; Restore original FLAGS
    pushfd
    pop    ebx               ; Save original EFLAGS in EBX
    mov    eax,ebx           ; Copy original EFLAGS to EAX
    xor    eax,40000h        ; Flip AC bit in EFLAGS
    push   eax
    popfd
    pushfd
    pop    eax               ; Get new EFLAGS value
    xor    eax,ebx           ; Compares original EFLAGS with new EFLAGS.
                             ; If cannot toggle AC bit, CPU=80386
    jz     Bad_Proc          ; CPU is an 80386
    

;------------------------------------------------------------------------------
; 80486 Checking
;------------------------------------------------------------------------------
Check_486:
    mov    eax,ebx           ; Copy original EFLAGS to EAX
    xor    eax,200000h       ; Flip ID bit in EFLAGS
    push   eax
    popfd
    pushfd
    pop    eax               ; Get new EFLAGS value
    xor    eax,ebx           ; Compares original EFLAGS with new EFFAGS
    jz     Bad_Proc          ; If ID bit cannot be changed, CPU=80486
                             ; without CPUID instruction functionality

;------------------------------------------------------------------------------
; For safety only, restores original EFLAGS (is not on original source code)  
;------------------------------------------------------------------------------
    push   ebx
    popfd


;------------------------------------------------------------------------------
; Now is safe to use the CPUID instruction to get the processor features   
;------------------------------------------------------------------------------
    cpu    586               ; Nasm directive. Code below is for 486 or newer.

    xor    eax,eax           ; EAX = 0
    cpuid
    cmp    bl,'G'            ; Testa o "G" da string "GenuineIntel"
    jne    Non_Intel         ; O processador n„o ‚ Intel
    shr    edx,24
    cmp    dl,'I'            ; Testa o "I" da string "GenuineIntel"
    jne    Non_Intel         ; O processador n„o ‚ Intel
    cmp    al,6              ; Tests maximum leaves supported by CPUID
    jb     Bad_Proc          ; which must be 6 or more (EAX=6)
    xor    eax,eax
    mov    al,6              ; EAX = 0x00000006 (1 byte lesser then MOV EAX,6)
    cpuid
    and    eax,1             ; Verifica se o processador possui um DTS
    jz     CPUID_No_DTS      ; O processador n„o tem um Digital Thermal Sensor
    cpuid                    ; Gets processor type (EAX=1)
    push   eax               ; Saves EAX from leaf 1
    
    and    ah,0Fh
    cmp    ah,6
    jne    Bad_Proc


;------------------------------------------------------------------------------
; Checks if Windows is in Enhanced Mode
; Windows in Enhanced Mode not allow execute the RDMSR instruction
; EMM386.EXE is OK.
;------------------------------------------------------------------------------
    mov    ax,160Ah              ; Get Windows version and mode
    int    2Fh
    test   ax,ax                 ; Checks if function is supported
    jnz    Check_MSR             ; Function not supported or not in Windows
    cmp    cl,2                  ; Checks Windows Standard Mode
    je     Check_MSR             ; Ok. Windows in Standard Mode
    mov    dx,WIN_E_MODE_MSG_BR  ; Windows in Enhanced Mode error message
    mov    ax,[COUNTRY_CODE]
    cmp    ax,55                 ; DOS in brazilian portuguese?
    je     Check_WEM_Show_Info   ; Yes. Then show message in brazilian portuguese
    mov    dx,WIN_E_MODE_MSG_EN  ; Otherwise show it in english

Check_WEM_Show_Info:
    jmp    Show_Info
    

;------------------------------------------------------------------------------
; Check for RDMSR 0x1A2 availability and get Tjmax from processors with the 
; IA32_THERM_TARGET MSR, if OK
;------------------------------------------------------------------------------
Check_MSR:    
    xor    eax,eax           ; initialize EAX (clears garbage)
    mov    ecx,IA32_TEMP_TARGET_MSR
    rdmsr                    ; gets the processor Tjmax (0x1A2 MSR)
    shr    eax,16            ; Tjmax is in bits 23:16 (8 bits) from EAX
;    cmp    al,105            ; check the highest supported Tjmax (105øC)
;    ja     Select_Tjmax      ; NOT NEEDED (XOR EAX,EAX)
    cmp    al,60             ; tests valid/supported MSR (arbitrary value: 60øC)
;    jb     Select_Tjmax 
    jl     Select_Tjmax      ; Google Gemini's suggest for temperatures above 127øC (negative values)
    mov    [TJMAX],al        ; save Tjmax
    pop    eax               ; unstacks, no longer necessary, PUSH EAX instruction after CPUID of leaf 1 above
    jmp    Load_Temp_Msg 


;------------------------------------------------------------------------------
; Processor type checking and Tjmax selection (if RDMSR 0x1A2 do not work)
;------------------------------------------------------------------------------
Select_Tjmax:    
    pop    eax               ; Restores EAX from CPUID leaf 1
    shr    eax,4
    and    ax,0F00Fh
    or     al,ah
    cmp    al,17h            ; Is a Core 2?
    je     Load_Temp_Msg     ; Yes
    cmp    al,9Eh            ; Is an i3/i5/i7 7th/8th/9th generation?
    je     Load_Temp_Msg     ; Yes
    mov    [TJMAX],105       ; i3/i5/i7 1st and 3rd generation Tjmax (105øC)
    cmp    al,25h            ; Is an i3/i5/i7 first generation?
    je     Load_Temp_Msg     ; Yes
    cmp    al,37h            ; Is a Celeron J1800? (22jun2024)
    je     Load_Temp_Msg     ; Yes
    cmp    al,3Ah            ; Is an i3/i5/i7 3rd generation?
    je     Load_Temp_Msg     ; Yes


;------------------------------------------------------------------------------
; Unknown processor or not supported
;------------------------------------------------------------------------------
Bad_Proc:    
    mov    dx,BAD_PROC_MSG_BR
    mov    ax,[COUNTRY_CODE]
    cmp    ax,55                ; DOS in brazilian portuguese?
    je     Show_Info_Bad_Proc   ; Yes. Then show message in brazilian portuguese
    mov    dx,BAD_PROC_MSG_EN   ; Otherwise show it in english

Show_Info_Bad_Proc:
    jmp    Show_Info
    

;------------------------------------------------------------------------------
; Processor not has a Digital Thermal Sensor
;------------------------------------------------------------------------------
CPUID_No_DTS:
    mov    dx,NO_DTS_MSG_BR
    mov    ax,[COUNTRY_CODE]
    cmp    ax,55                ; DOS in brazilian portuguese?
    je     Show_Info_No_DTS     ; Yes. Then show message in brazilian portuguese
    mov    dx,NO_DTS_MSG_EN     ; Otherwise show it in english

Show_Info_No_DTS:
    jmp    Show_Info


;------------------------------------------------------------------------------
; Processor is not an Intel
;------------------------------------------------------------------------------
Non_Intel:
    mov    dx,INTEL_ONLY_MSG_BR
    mov    ax,[COUNTRY_CODE]
    cmp    ax,55                ; DOS in brazilian portuguese?
    je     Show_Info_Non_Intel  ; Yes. Then show message in brazilian portuguese
    mov    dx,INTEL_ONLY_MSG_EN ; Otherwise show it in english

Show_Info_Non_Intel:
    jmp    Show_Info
    
        
;------------------------------------------------------------------------------
; Loads locale language temperature message
;------------------------------------------------------------------------------
Load_Temp_Msg:
    mov    di,TEMP_ASCII_BR     ; Temperature address inside of portuguese phrase buffer
    mov    ax,[COUNTRY_CODE]
    cmp    ax,55                ; Is DOS in brazilian portuguese?
    je     Init_Retries_Counter ; Yes. Then maintains the address inside of portuguese phrase
    mov    di,TEMP_ASCII_EN     ; Temperature address inside of english phrase buffer
    

;------------------------------------------------------------------------------
; Init the temperature reading retries counter
;------------------------------------------------------------------------------
Init_Retries_Counter:    
    mov    cx,1000h             ; # of reading retries if the temperature on
                                ; MSR is invalid.

;------------------------------------------------------------------------------
; Gets the temperature
;------------------------------------------------------------------------------
Get_Temp:    
    push   cx                   ; preserves Reading Retries Counter
    mov    ecx,IA32_THERM_STATUS_MSR  ; 0x19C MSR
    rdmsr
    pop    cx                   ; restores Reading Retries Counter
    shr    eax,10h              ; shifts temperature and reading OK flag (bit 31) to low word part (AX)
    test   ax,8000h             ; if EAX bit 31 = 0 temperature is not OK on the MSR
    jnz    Temp_Reading_Is_OK   ; EAX bit 31 = 1, then temperature reading is valid
    loop   Get_Temp             ; retries to read the temperature
    

;------------------------------------------------------------------------------
; Can not to read the temperature    
;------------------------------------------------------------------------------
    mov    dx,TEMP_ERROR_MSG_BR ; Preloads brazilian portuguese error message (default)
    mov    ax,[COUNTRY_CODE]
    cmp    ax,55                ; DOS in brazilian portuguese?
    je     Show_Info_Temp_Error ; Yes. Then show message in brazilian portuguese
    mov    dx,TEMP_ERROR_MSG_EN ; Otherwise show it in english

Show_Info_Temp_Error:
    jmp    Show_Info            ; Show error message and exit to DOS


Temp_Reading_Is_OK:
    and    al,7Fh
    neg    al
    add    al,[TJMAX]
    cmp    al,100               ; Check if temperature is > 100øC
    jb     Bin2ASCII
    push   ax                   ; Saves temperature
    mov    al,'1'               ; Hundred
    stosb                       ; Prints hundred
    pop    ax                   ; Restore temperature
    sub    al,100               ; Gets ten and unit of temperature


;------------------------------------------------------------------------------
; Converts temperature value into an ASCII sequence
;------------------------------------------------------------------------------
Bin2ASCII:
    aam                         ; Converts AL value (max. 99) to BCD
    add    ax,3030h             ; Converts BCD para ASCII
    xchg   ah,al                ; Exchange unity and ten from the ASCII temperature
    stosw                       ; Put the temperature on the message to show
    mov    ax,43F8h             ; F8h = degree symbol in CP-850, 43h = 'C'
    stosw
    mov    al,'.'
    stosb
    mov    ax,0A0Dh             ; Skips one line (0Dh,0Ah)
    stosw
    mov    al,'$'               ; DOS function 09h (INT 21h) terminator character
    stosb
    

;------------------------------------------------------------------------------
; Shows the temperature    
;------------------------------------------------------------------------------
    mov    dx,TEMP_MSG_BR
    mov    ax,[COUNTRY_CODE]
    cmp    ax,55                ; DOS in brazilian portuguese?
    je     Show_Info            ; Yes. Then show message in brazilian portuguese
    mov    dx,TEMP_MSG_EN       ; Otherwise show it in english
    

;------------------------------------------------------------------------------
; Generic Message Printing and Exit to DOS Routine
;
; Input: DX = offset of message to show
;------------------------------------------------------------------------------
Show_Info:    
    mov    ah,09h
    int    21h
    int    20h                  ; Back to DOS


;------------------------------------------------------------------------------
; Tjmax to be added to the read temperature
;------------------------------------------------------------------------------
TJMAX              db 100       ; Tjmax for Core 2/i3/i5/i7 processors (default)


;------------------------------------------------------------------------------
; Locale Information
;------------------------------------------------------------------------------
COUNTRY_CODE       dw 55        ; Locale country code (55 = Brazil)
COUNTRY_INFO       dw 0,0,0,0,0,0,0,0,0,0,0,0 ; (REQUIRED) this buffer must be 24 bytes!


;------------------------------------------------------------------------------
; Brazilian Portuguese Messages
;------------------------------------------------------------------------------
TEMP_MSG_BR        db 0Dh,0Ah,'A temperatura do processador ‚ '
TEMP_ASCII_BR      db '$$$$$$$$$' ; <---<<< MUST CONTAIN 9 DOLLAR CHARACTERS!
BAD_PROC_MSG_BR    db 0Dh,0Ah,'Este processador n„o ‚ suportado!',0Dh,0Ah,'$'
NO_DTS_MSG_BR      db 0Dh,0Ah,'[CPUID] Processador sem um "Digital Thermal Sensor"!',0Dh,0Ah,'$'
INTEL_ONLY_MSG_BR  db 0Dh,0Ah,'Suporte somente para processadores Intel Core 2 ou mais novos, nesta vers„o.',0Dh,0Ah,'$'
WIN_E_MODE_MSG_BR  db 0Dh,0Ah,'[160Ah] N„o ‚ poss¡vel ler a temperatura com o Windows em Modo Avan‡ado!',0Dh,0Ah,'$'
TEMP_ERROR_MSG_BR  db 0Dh,0Ah,'[RDMSR] N„o foi poss¡vel ler a temperatura do processador!',0Dh,0Ah,'$'


;------------------------------------------------------------------------------
; English Messages
;------------------------------------------------------------------------------
TEMP_MSG_EN        db 0Dh,0Ah,'The processor temperature is '
TEMP_ASCII_EN      db '$$$$$$$$$' ; <---<<< MUST CONTAIN 9 DOLLAR CHARACTERS!
BAD_PROC_MSG_EN    db 0Dh,0Ah,'Unsupported processor!',0Dh,0Ah,'$'
NO_DTS_MSG_EN      db 0Dh,0Ah,'[CPUID] Processor has no a "Digital Thermal Sensor"!',0Dh,0Ah,'$'
INTEL_ONLY_MSG_EN  db 0Dh,0Ah,'Only Intel Core 2 processors or later are supported, in this version.',0Dh,0Ah,'$'
WIN_E_MODE_MSG_EN  db 0Dh,0Ah,'[160Ah] Cannot read the processor temperature in Windows Enhanced Mode!',0Dh,0Ah,'$'
TEMP_ERROR_MSG_EN  db 0Dh,0Ah,"[RDMSR] Cannot read the processor temperature!",0Dh,0Ah,"$"


;------------------------------------------------------------------------------
; Program Version and Date Revision to Show
;------------------------------------------------------------------------------
PROG_NAME          db 0Dh,0Ah,'CPUTemp 1.13 [21jun2026]', \
                      0Dh,0Ah,'========================',0Dh,0Ah,'$'


;------------------------------------------------------------------------------
; File Version Signature
;------------------------------------------------------------------------------
FILE_VER           db '___[Ver. 21jun2026]___'

