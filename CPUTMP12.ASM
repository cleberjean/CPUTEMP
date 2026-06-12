;Exibe a Temperatura de um Processador Intel com Sensor Digital de Temperatura.
;Usa a instru‡„o RDMSR para obter a temperatura.
;Funciona com processadores Intel Core 2 e mais novos.
;Compile with "nasm cputemp.asm -o cputemp.com" or
;             "fasm cputemp.asm cputemp.com" (BEWARE! May to produce instructions to 80386+)
;By cleberjean@hotmail.com
;02feb2024 - Fixed Core 2 Tjmax (105 -> 100 degrees)
;24may2024 - Support for Processors with the IA32_TEMPERATURE_TARGET MSR   
;22jun2024 - Support for Celeron J1800 Processor
;26jun2024 - Check for RDMSR 0x1A2 first, to get Tjmax (default)
;27jun2025 - Only shows version if something is typeded after program name
;29jun2025 - Ignores Tab
;22jul2025 - Meaningless change
;20may2026 - Google Gemini's suggests applied



;Defines
    IA32_THERM_STATUS_MSR  equ 0x19C
    IA32_TEMP_TARGET_MSR   equ 0x1A2


    org    100h              ; A .COM program

begin:
    push   cs
    pop    ds                ; Certifies that Data Segment is the same of the program code (ES not used)
    cld                      ; SI/DI increments
    mov    si,0081h          ; Start of command line options


;Checks Command Line
Check_CR:    
    lodsb
    cmp    al,0Dh            ; Is a Carriage Return?
    je     Get_Country_Info  ; ...then skips program info
    cmp    al,20h            ; Is a Space?
    je     Check_CR          ; ...then continues to search for Carriage Return
    cmp    al,09h            ; Is a Tab?
    je     Check_CR          ; ...then continues to search for Carriage Return

;Show Program Name and Version    
    mov    dx,PROG_NAME
    mov    ah,09h
    int    21h


;Gets Country Information
Get_Country_Info:    
    mov    ax,3800h
    mov    dx,COUNTRY_INFO   ; NOT USED, BUT MUST HAVE THIS BUFFER!
    int    21h
    mov    [COUNTRY_CODE],bx ; Saves locale country code


;O c¢digo abaixo foi retirado do Intel Pentium Processor User's Manual
;Volume 3, Cap¡tulo 5.3 - SAMPLE CPUID IDENTIFICATION/FPU DETECTION CODE, 
;p ginas 129 a 123, de 1993.
;Example 5-1. CPU Identification and FPU Detection
;Apenas o registrador CX foi trocado por BX
;O coment rio original diz:
;       "This program has been developed by Intel Corporation. You have
;        Intel's permission to incorporate this source code into your
;        product royalty free."


;Double check for 8086/8088.
;Processors later of 8086 always pushes SP to stack, and then decrements 
;SP by 2. 8086 always decrements SP by 2 and then pushes it on stack.
;Also bits 12..15 are always set on the 8086 processor.
;[MODIFIED] Test only bits 14 and 15, due a detection fail when in Priviligied Level != 0.
Check_8086:
    push   sp                ; Pushes SP
    pop    ax                ; Restore in AX
    sub    ax,sp             ; Clears AX if CPU is an 80286 or later
    jnz    Bad_Proc          ; Processor is an 80186 or early
    pushf
    pop    bx                ; Save FLAGS in BX
    mov    ax,bx             ; Copy flags to AX
    and    ax,0FFFh          ; Clear bits 12..15
    push   ax
    popf                     ; Clear bits 12..15 in FLAGS
    pushf
    pop    ax                ; Copy flags again to AX
;    and    ax,0F000h         ; Checks if bits 12..15 still always clean
;    jnz    Bad_Proc          ; Bits 12..15 do flags continuam setados (processador 8086/80186)
    and    ax,0C000h         ; Checks if bits 14 and 15 still always clean
    jnz    Bad_Proc          ; Bits 14 and 15 from flags register remains set (processor is an 8086/80186)


;Checks Ring 0 (https://en.wikipedia.org/wiki/Protection_ring#IOPL)
;RDMSR instruction MUST BE used in Priviligied Level 0 ONLY!
    mov    ax,bx
    and    ax,0FFFh
    push   ax
    popf
    pushf
    pop    ax
    and    ah,30h            ; If 0 then system in Ring 0 (Real mode)
    jnz    Test_EMM386
    
    
;Intel 286 CPU Check
;Bits 12-15 are always clear on the Intel 286 processor.
Check_80286:
    mov    ax,bx             ; Copy flags to AX
    or     ax,0F000h         ; Set bits 12..15
    push   ax
    popf
    pushf
    pop    ax
    and    ax,0F000h         ; If bits 12..15 are cleared, then CPU=80286
    jz     Bad_Proc          ; CPU is an 80286


         ;--------------------------------------------------------;
         ; Starting here, now is safe to use 32 bits instructions ;
         ;--------------------------------------------------------;

;Intel386 CPU Check
;The AC bit, bit #18, is a new bit introduced in the EFLAGS
;register on the Intel486 DX CPU to generate alignment faults.
;This bit can not be set on the Intel386 CPU.
Check_80386:
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
    

Check_80486:
    mov    eax,ebx           ; Copy original EFLAGS to EAX
    xor    eax,200000h       ; Flip ID bit in EFLAGS
    push   eax
    popfd
    pushfd
    pop    eax               ; Get new EFLAGS value
    xor    eax,ebx           ; Compares original EFLAGS with new EFFAGS
    jz     Bad_Proc          ; If ID bit cannot be changed, CPU=80486
                             ; without CPUID instruction functionality

;For safety only, restores original EFLAGS (is not on original source code)  
    push   ebx
    popfd

;Now is safe to use the CPUID instruction to get processor features   
    xor    eax,eax           ; EAX = 0
    cpuid
    cmp    bl,'G'            ; Testa o "G" da string "GenuineIntel"
    jne    Non_Intel         ; O processador n„o ‚ Intel
    shr    edx,24
    cmp    dl,'I'            ; Testa o "I" da string "GenuineIntel"
    jne    Non_Intel         ; O processador n„o ‚ Intel
    cmp    al,6              ; Tests maximum leaves supported by CPUID
    jb     Bad_Proc          ; which must be 6 or more (EAX=6)
;    mov    eax,6             ; Changed to XOR EAX,EAX and MOV AL,6 (1 byte smaller)
    xor    eax,eax
    mov    al,6              ; Now EAX = 0x00000006 (1 byte lesser - 24may2024)
    cpuid
    and    eax,1             ; Verifica se o processador possui um DTS
    jz     CPUID_No_DTS      ; O processador n„o tem um Digital Thermal Sensor
;    mov    eax,1             ; EAX j  foi deixado como 1 pela instru‡„o anterior
    cpuid                    ; Gets processor type (EAX=1)
    push   eax               ; Saves EAX from leaf 1
    
;    shr    eax,8            ;\ 
;    and    al,0Fh           ; }-> Removed in 23/may/2024
;    cmp    al,6             ;/
    and    ah,0Fh
    cmp    ah,6
    jne    Bad_Proc
    

;Check for RDMSR 0x1A2 availability and Get Tjmax from processors with the IA32_TEMPERATURE_TARGET MSR if OK
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


;Processor type checking and Tjmax selection (if RDMSR 0x1A2 do not work)
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


;Unknown processor or not supported
Bad_Proc:    
    mov    dx,BAD_PROC_MSG_BR
    mov    ax,[COUNTRY_CODE]
    cmp    ax,55                ; DOS in brazilian portuguese?
    je     Show_Info            ; Yes. Then show message in brazilian portuguese
    mov    dx,BAD_PROC_MSG_EN
    jmp    Show_Info
    

;Processor not has a Digital Thermal Sensor
CPUID_No_DTS:
    mov    dx,NO_DTS_MSG_BR
    mov    ax,[COUNTRY_CODE]
    cmp    ax,55                ; DOS in brazilian portuguese?
    je     Show_Info            ; Yes. Then show message in brazilian portuguese
    mov    dx,NO_DTS_MSG_EN
    jmp    Show_Info


;Processor is not an Intel
Non_Intel:
    mov    dx,INTEL_ONLY_MSG_BR
    mov    ax,[COUNTRY_CODE]
    cmp    ax,55                ; DOS in brazilian portuguese?
    je     Show_Info            ; Yes. Then show message in brazilian portuguese
    mov    dx,INTEL_ONLY_MSG_EN
    jmp    Show_Info


;System is in protected mode (EMM386.EXE loaded or Windows in Enhanced Mode)
;RDMSR instruction in Ring 0 ONLY!
Test_EMM386:
    mov    ax,0FFA5h
    mov    dx,0FFFFh
    int    67h
    cmp    ax,845Ah             ; is EMM386.EXE loaded?
    jne    Priv_Level_Not_0     ; no
    mov    dx,EMM386_MSG_BR
    mov    ax,[COUNTRY_CODE]
    cmp    ax,55                ; DOS in brazilian portuguese?
    je     Show_Info            ; Yes. Then show message in brazilian portuguese
    mov    dx,EMM386_MSG_EN     ; otherwise show in english
    jmp    Show_Info

Priv_Level_Not_0:    
    mov    dx,PRIV_LEVEL_MSG_BR
    mov    ax,[COUNTRY_CODE]
    cmp    ax,55                ; DOS in brazilian portuguese?
    je     Show_Info            ; Yes. Then show message in brazilian portuguese
    mov    dx,PRIV_LEVEL_MSG_EN
    jmp    Show_Info
    
        
;Loads locale language temperature message
Load_Temp_Msg:
    mov    di,TEMP_ASCII_BR     ; Temperature address inside of portuguese phrase buffer
    mov    ax,[COUNTRY_CODE]
    cmp    ax,55                ; Is DOS in brazilian portuguese?
    je     Init_Retries_Counter ; Yes. Then maintains the address inside of portuguese phrase
    mov    di,TEMP_ASCII_EN     ; Temperature address inside of english phrase buffer
    
;Init the temperature Reading Retries Counter
Init_Retries_Counter:    
    mov    cx,1000h             ; # of reading retries if the temperature on MSR is invalid
                                ; Suggest from Google Gemini (19may2026)
;Gets temperature
Get_Temp:    
    push   cx                   ; preserves Reading Retries Counter
    mov    ecx,IA32_THERM_STATUS_MSR  ; 0x19C MSR
    rdmsr
    pop    cx                   ; restores Reading Retries Counter
    shr    eax,10h              ; shifts temperature and reading OK flag (bit 31) to low word part (AX)
    test   ax,8000h             ; if EAX bit 31 = 0 temperature is not OK on the MSR
    jnz    Temp_Reading_Is_OK   ; EAX bit 31 = 1, then temperature reading is valid
    loop   Get_Temp             ; retries to read the temperature
    
;Cannot to read the temperature    
    mov    dx,TEMP_ERROR_MSG_BR ; Preloads brazilian portuguese error message (default)
    mov    ax,[COUNTRY_CODE]
    cmp    ax,55                ; DOS in brazilian portuguese?
    je     Show_Info            ; Yes. Then show message in brazilian portuguese
    mov    dx,TEMP_ERROR_MSG_EN ; No. Show message in english language
    jmp    Show_Info            ; Show error message and exit to DOS

Temp_Reading_Is_OK:
;    and    ax,7Fh
;    neg    ax
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


;Converts temperature value into an ASCII sequence
Bin2ASCII:
    aam                         ; Converts AL value (max. 99) to BCD
    add    ax,3030h             ; Converts BCD para ASCII
    xchg   ah,al                ; Exchange unity and ten from the ASCII temperature
    stosw                       ; Put the temperature on the message to show
;    mov    al,' '
;    stosb                       ; Space between the temperature and degree symbol (Inmetro standard)
;    mov    ax,'øC'              ; Gemini suggested swap ø (degree symbol) by 0xF8 (code page 850)
    mov    ax,43F8h             ; 0xF8 = 'ø' in CP-850, 0x43 = 'C' (Suggest by Google Gemini)
    stosw
    mov    al,'.'
    stosb
    mov    ax,0A0Dh             ; Skips one line (0Dh,0Ah)
    stosw
    mov    al,'$'               ; DOS function 09h (INT 21h) terminator character
    stosb
    

;Shows the temperature information    
    mov    dx,TEMP_MSG_BR
    mov    ax,[COUNTRY_CODE]
    cmp    ax,55                ; DOS in brazilian portuguese?
    je     Show_Info            ; Yes. Then show message in brazilian portuguese
    mov    dx,TEMP_MSG_EN       ; No. Show message in english language
    

Show_Info:    
    mov    ah,09h
    int    21h
    int    20h                  ; Back to DOS


;Tjmax para ser somado … temperatura lida
TJMAX              db 100       ; Tjmax for Core 2/i3/i5/i7 processors (default)


;Locale Information
COUNTRY_CODE       dw 55        ; Locale country code (55 = Brazil)
COUNTRY_INFO       dw 0,0,0,0,0,0,0,0,0,0,0,0 ; (REQUIRED) this buffer must be 24 bytes!


;Brazilian Portuguese Messages
TEMP_MSG_BR         db 0Dh,0Ah,'A temperatura do processador ‚ '
TEMP_ASCII_BR      db '$$$$$$$$$' ;<---<<< MUST CONTAIN 9 BYTES!
BAD_PROC_MSG_BR    db 0Dh,0Ah,'Este processador n„o ‚ suportado!',0Dh,0Ah,'$'
NO_DTS_MSG_BR      db 0Dh,0Ah,'[CPUID] Processador sem um "Digital Thermal Sensor"!',0Dh,0Ah,'$'
INTEL_ONLY_MSG_BR  db 0Dh,0Ah,'Suporte somente para processadores Intel Core 2 ou mais novos, nesta vers„o.',0Dh,0Ah,'$'
PRIV_LEVEL_MSG_BR  db 0Dh,0Ah,'[IOPL] Processador em Modo Protegido!',0Dh,0Ah,'$'
EMM386_MSG_BR      db 0Dh,0Ah,'[CPUTEMP] N„o ‚ poss¡vel ler a temperatura com o EMM386 carregado.',0Dh,0Ah,'$'
TEMP_ERROR_MSG_BR  db 0Dh,0Ah,'[RDMSR] N„o foi poss¡vel ler a temperatura do processador!',0Dh,0Ah,'$'


;English Messages
TEMP_MSG_EN        db 0Dh,0Ah,'The processor temperature is '
TEMP_ASCII_EN      db '$$$$$$$$$' ;<---<<< MUST CONTAIN 9 DOLLAR CHARACTERS!
BAD_PROC_MSG_EN    db 0Dh,0Ah,'Unsupported processor!',0Dh,0Ah,'$'
NO_DTS_MSG_EN      db 0Dh,0Ah,'[CPUID] Processor has no a "Digital Thermal Sensor"!',0Dh,0Ah,'$'
INTEL_ONLY_MSG_EN  db 0Dh,0Ah,'Only Intel Core 2 processors or later are supported, in this version.',0Dh,0Ah,'$'
PRIV_LEVEL_MSG_EN  db 0Dh,0Ah,'[IOPL] Processor in Protected Mode!',0Dh,0Ah,'$'
EMM386_MSG_EN      db 0Dh,0Ah,'[CPUTEMP] Cannot read the temperature with EMM386 loaded.',0Dh,0Ah,'$'
TEMP_ERROR_MSG_EN  db 0Dh,0Ah,"[RDMSR] Cannot read the processor temperature!",0Dh,0Ah,"$"


;Program Version and Date Revision to Show
PROG_NAME          db 0Dh,0Ah,'CPUTemp 1.12 [20may2026]',0Dh,0Ah,'========================',0Dh,0Ah,'$'

;Version Signature
VER                db '___[Ver. 20may2026]___'

