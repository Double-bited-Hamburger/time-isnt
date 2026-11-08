; =============================================================================
;  Time ISN't  -  a tiny, dark, internet-synced full-screen clock for Windows
;  x64 Assembly (flat assembler).  Build with build.bat
;
;  F11 / F / double-click : toggle full screen      Esc : leave full screen
;  S                      : sync with time servers now
; =============================================================================

format PE64 GUI 6.0
entry start

include 'win64w.inc'

; ---- look & feel -------------------------------------------------------------
COL_BG        = 00120F0Eh       ; #0E0F12 as COLORREF (00BBGGRR), title bar
ARGB_BG       = 0FF0E0F12h      ; colours below are AARRGGBB (GDI+)
ARGB_TIME     = 0FFE8EAEDh
ARGB_DATE     = 0FF8B9099h
ARGB_STATUS   = 0FF5C636Ah
ARGB_WARN     = 0FFD09A3Eh
TIME_WEIGHT   = 700             ; GDI weight used to measure the time
TIME_STYLE    = 1               ; GDI+ FontStyleBold  (0 = regular)
TEXT_STYLE    = 0

; ---- behaviour ---------------------------------------------------------------
RESYNC_MS     = 15*60*1000      ; re-sync every 15 minutes
RETRY_MS      = 30*1000         ; retry after 30 s if every server failed
CURSOR_IDLE   = 2500            ; hide the mouse after 2.5 s in full screen
SAMPLES       = 4               ; NTP queries per server, keep the fastest

; ---- constants missing from fasm's headers ----------------------------------
X_WM_DPICHANGED = 02E0h
X_WM_SYNCED     = 8001h         ; WM_APP+1, posted by the sync thread
X_GWL_STYLE     = -16
X_HTCLIENT      = 1
X_SWP_FULL      = 0220h         ; NOOWNERZORDER | FRAMECHANGED
X_SWP_RESTORE   = 0227h         ; + NOSIZE | NOMOVE | NOZORDER
X_SWP_DPI       = 0014h         ; NOZORDER | NOACTIVATE

; =============================================================================
section '.text' code readable executable

start:
        sub     rsp,8
        invoke  SetProcessDpiAwarenessContext,-4        ; per-monitor v2: sharp text
        invoke  GetModuleHandleW,0
        mov     [wc.hInstance],rax
        invoke  LoadIconW,[wc.hInstance],1                      ; our icon (resource 1)
        mov     [wc.hIcon],rax
        invoke  GetSystemMetrics,SM_CXSMICON
        invoke  LoadImageW,[wc.hInstance],1,1,rax,rax,0        ; IMAGE_ICON, small size
        mov     [wc.hIconSm],rax
        invoke  LoadCursorW,0,IDC_ARROW
        mov     [wc.hCursor],rax
        mov     [hArrow],rax
        invoke  CreateSolidBrush,COL_BG
        mov     [wc.hbrBackground],rax
        invoke  RegisterClassExW,wc
        test    rax,rax
        jz      .fail
        invoke  CreateEventW,0,0,0,0
        mov     [hWake],rax

        ; GDI+ : smooth anti-aliased text at any size
        invoke  GdiplusStartup,gdipToken,gdipInput,0
        invoke  GdipCreateFontFamilyFromName,szFace,0,gdipFamily
        test    eax,eax
        jz      @f
        invoke  GdipGetGenericFontFamilySansSerif,gdipFamily
    @@: invoke  GdipGetCellAscent,[gdipFamily],TIME_STYLE,ascTime
        invoke  GdipGetEmHeight,[gdipFamily],TIME_STYLE,emhTime
        invoke  GdipGetCellAscent,[gdipFamily],TEXT_STYLE,ascText
        invoke  GdipGetEmHeight,[gdipFamily],TEXT_STYLE,emhText
        invoke  GdipCreateSolidFill,ARGB_TIME,brTime
        invoke  GdipCreateSolidFill,ARGB_DATE,brDate
        invoke  GdipCreateSolidFill,ARGB_STATUS,brStatus
        invoke  GdipCreateSolidFill,ARGB_WARN,brWarn
        invoke  GdipStringFormatGetGenericTypographic,fmtTmp
        invoke  GdipCloneStringFormat,[fmtTmp],strFmt
        invoke  GdipSetStringFormatAlign,[strFmt],1             ; centre
        invoke  GdipSetStringFormatFlags,[strFmt],5000h         ; no wrap, no clip
        invoke  GdipCloneStringFormat,[fmtTmp],strFmtNear       ; left-aligned copy
        invoke  GdipSetStringFormatFlags,[strFmtNear],5000h

        ; window = 60% of the primary screen, centred
        invoke  GetSystemMetrics,SM_CXSCREEN
        mov     ebx,eax
        invoke  GetSystemMetrics,SM_CYSCREEN
        mov     esi,eax
        imul    eax,ebx,6
        xor     edx,edx
        mov     ecx,10
        div     ecx
        mov     r12d,eax                ; width
        imul    eax,esi,6
        xor     edx,edx
        div     ecx
        mov     r13d,eax                ; height
        mov     r14d,ebx
        sub     r14d,r12d
        shr     r14d,1                  ; x
        mov     r15d,esi
        sub     r15d,r13d
        shr     r15d,1                  ; y
        invoke  CreateWindowExW,0,szClass,szTitle,WS_OVERLAPPEDWINDOW,r14,r15,r12,r13,0,0,[wc.hInstance],0
        test    rax,rax
        jz      .fail
        mov     [hwndMain],rax
        invoke  ShowWindow,rax,SW_SHOWNORMAL
        invoke  UpdateWindow,[hwndMain]
        invoke  SetTimer,[hwndMain],1,20,0
        invoke  CreateThread,0,0,NtpThread,0,0,0
        invoke  CloseHandle,rax

  .msg_loop:
        invoke  GetMessageW,msg,0,0,0
        cmp     eax,1
        jb      .quit
        jne     .msg_loop
        invoke  TranslateMessage,msg
        invoke  DispatchMessageW,msg
        jmp     .msg_loop
  .fail:
        invoke  MessageBoxW,0,szFail,szTitle,MB_ICONERROR
  .quit:
        invoke  ExitProcess,[msg.wParam]

; -----------------------------------------------------------------------------
; NtpToFt: rcx -> 64-bit big-endian NTP timestamp.  Returns rax = FILETIME
; (100 ns ticks since 1601).  Handles the 2036 NTP era rollover.
NtpToFt:
        mov     eax,[rcx]
        bswap   eax                     ; seconds since 1900
        mov     r8,rax
        test    eax,eax
        js      .era0
        mov     r9,100000000h           ; high bit clear => era 1 (after 2036)
        add     r8,r9
  .era0:
        mov     r9,9435484800           ; seconds from 1601 to 1900
        add     r8,r9
        imul    r8,r8,10000000
        mov     eax,[rcx+4]
        bswap   eax                     ; fraction of a second (2^-32)
        imul    rax,rax,10000000
        shr     rax,32
        add     rax,r8
        ret

; -----------------------------------------------------------------------------
proc WindowProc uses rbx rsi rdi, hwnd,wmsg,wparam,lparam
        mov     [hwnd],rcx
        mov     [wmsg],rdx
        mov     [wparam],r8
        mov     [lparam],r9
        cmp     edx,WM_PAINT
        je      .paint
        cmp     edx,WM_TIMER
        je      .timer
        cmp     edx,WM_ERASEBKGND
        je      .erase
        cmp     edx,WM_SETCURSOR
        je      .setcursor
        cmp     edx,WM_MOUSEMOVE
        je      .mousemove
        cmp     edx,WM_KEYDOWN
        je      .keydown
        cmp     edx,WM_LBUTTONDBLCLK
        je      .toggle
        cmp     edx,WM_SIZE
        je      .size
        cmp     edx,X_WM_SYNCED
        je      .redraw
        cmp     edx,WM_TIMECHANGE
        je      .resync
        cmp     edx,WM_POWERBROADCAST
        je      .power
        cmp     edx,X_WM_DPICHANGED
        je      .dpi
        cmp     edx,WM_CREATE
        je      .create
        cmp     edx,WM_DESTROY
        je      .destroy
  .default:
        invoke  DefWindowProcW,[hwnd],[wmsg],[wparam],[lparam]
        ret

  .create:
        mov     rax,[hwnd]
        mov     [hwndMain],rax
        invoke  DwmSetWindowAttribute,[hwnd],20,dwmTrue,4      ; dark title bar
        invoke  DwmSetWindowAttribute,[hwnd],35,dwmCaption,4   ; caption = background (Win11)
        jmp     .zero

  .paint:
        call    Paint
        jmp     .zero

  .timer:
        call    Tick
        jmp     .zero

  .erase:
        mov     eax,1                   ; we paint every pixel ourselves: no flicker
        ret

  .setcursor:
        cmp     [isFull],0
        je      .default
        cmp     [cursorHidden],0
        je      .default
        mov     rax,[lparam]
        cmp     ax,X_HTCLIENT
        jne     .default
        invoke  SetCursor,0
        mov     eax,1
        ret

  .mousemove:
        mov     rax,[lparam]
        cmp     eax,[lastMousePos]      ; ignore fake moves with the same position
        je      .zero
        mov     [lastMousePos],eax
        invoke  GetTickCount64
        mov     [lastMoveTick],rax
        cmp     [cursorHidden],0
        je      .zero
        mov     [cursorHidden],0
        invoke  SetCursor,[hArrow]
        jmp     .zero

  .keydown:
        mov     rax,[wparam]
        cmp     eax,VK_F11
        je      .toggle
        cmp     eax,'F'
        je      .toggle
        cmp     eax,'S'
        je      .resync
        cmp     eax,VK_ESCAPE
        jne     .default
        cmp     [isFull],0
        je      .zero
  .toggle:
        call    ToggleFullscreen
        jmp     .zero

  .resync:
        mov     [syncState],0
        invoke  SetEvent,[hWake]
        jmp     .redraw

  .power:
        cmp     [wparam],12h            ; PBT_APMRESUMEAUTOMATIC
        je      .resync
        cmp     [wparam],7              ; PBT_APMRESUMESUSPEND
        je      .resync
        jmp     .default

  .size:
        cmp     [wparam],SIZE_MINIMIZED
        je      .zero
        mov     rax,[lparam]
        movzx   ecx,ax
        shr     eax,16
        movzx   edx,ax
        call    Layout
  .redraw:
        invoke  InvalidateRect,[hwnd],0,0
        jmp     .zero

  .dpi:
        cmp     [isFull],0
        jne     .zero
        mov     rax,[lparam]            ; suggested RECT
        mov     r10d,[rax+8]
        sub     r10d,[rax]
        mov     r11d,[rax+12]
        sub     r11d,[rax+4]
        invoke  SetWindowPos,[hwnd],0,dword [rax],dword [rax+4],r10,r11,X_SWP_DPI
        jmp     .zero

  .destroy:
        invoke  PostQuitMessage,0
  .zero:
        xor     eax,eax
        ret
endp

; -----------------------------------------------------------------------------
; GetNow: corrected time -> stUtc / stLocal.  Returns eax = milliseconds.
proc GetNow
        invoke  GetSystemTimePreciseAsFileTime,nowFt
        mov     rax,[clockOffset]
        add     [nowFt],rax
        invoke  FileTimeToSystemTime,nowFt,stUtc
        invoke  SystemTimeToTzSpecificLocalTime,0,stUtc,stLocal
        movzx   eax,[stUtc.wMilliseconds]
        ret
endp

; -----------------------------------------------------------------------------
; Tick: runs right after each second boundary, repaints only when the second
; changed, then re-arms the timer for the next boundary.  ~1 wake-up / second.
proc Tick uses rbx
        call    GetNow
        mov     ebx,eax
        movzx   eax,[stLocal.wSecond]
        cmp     eax,[shownSecond]
        je      .arm
        test    eax,eax                 ; :00 -> full repaint (date, status)
        jz      .all
        ; otherwise repaint only the characters that changed (usually one)
        movzx   r8d,[stLocal.wHour]
        movzx   r9d,[stLocal.wMinute]
        movzx   r10d,[stLocal.wSecond]
        invoke  wsprintfW,bufNext,fmtTime,r8,r9,r10
        xor     ecx,ecx
  .cmp:
        mov     ax,[bufNext+rcx*2]
        cmp     ax,[bufTime+rcx*2]
        jne     .found
        inc     ecx
        cmp     ecx,8
        jb      .cmp
        mov     ecx,7
  .found:
        mov     eax,[charX+rcx*4]
        mov     [dirty.left],eax
        mov     eax,[charX+8*4]
        mov     [dirty.right],eax
        mov     eax,[timeBox.top]
        mov     [dirty.top],eax
        mov     eax,[timeBox.bottom]
        mov     [dirty.bottom],eax
        invoke  InvalidateRect,[hwndMain],dirty,0
        jmp     .arm
  .all:
        invoke  InvalidateRect,[hwndMain],0,0
  .arm:
        mov     r10d,1001
        sub     r10d,ebx
        invoke  SetTimer,[hwndMain],1,r10,0
        cmp     [isFull],0
        je      .done
        cmp     [cursorHidden],0
        jne     .done
        invoke  GetTickCount64
        sub     rax,[lastMoveTick]
        cmp     rax,CURSOR_IDLE
        jb      .done
        mov     [cursorHidden],1
        invoke  SetCursor,0
  .done:
        ret
endp

; -----------------------------------------------------------------------------
; Paint: builds the invalid area in an off-screen bitmap, then copies it to
; the screen with one BitBlt (no flicker).  The digits are copied from a
; glyph atlas rendered once per resize, so a normal tick costs 8 tiny blits.
proc Paint uses rbx rsi rdi r12 r13 r14 r15
  locals
    ps     PAINTSTRUCT
    rc     RECT
    rf     rd 4                     ; GDI+ RectF layout box
    gfx    dq ?
    oldBmp dq ?
    brush  dq ?
    len    dd ?
    k      dd ?
    srcX   dd ?
  endl
        invoke  BeginPaint,[hwndMain],addr ps
        mov     rbx,rax                 ; screen DC
        mov     r12d,[ps.rcPaint.left]
        mov     r13d,[ps.rcPaint.top]
        mov     r14d,[ps.rcPaint.right]
        sub     r14d,r12d               ; width
        jle     .end
        mov     r15d,[ps.rcPaint.bottom]
        sub     r15d,r13d               ; height
        jle     .end
        cmp     [atlasDC],0
        je      .end

        invoke  CreateCompatibleDC,rbx
        mov     rsi,rax
        invoke  CreateCompatibleBitmap,rbx,r14,r15
        mov     rdi,rax
        invoke  SelectObject,rsi,rdi
        mov     [oldBmp],rax
        mov     [rc.left],0
        mov     [rc.top],0
        mov     [rc.right],r14d
        mov     [rc.bottom],r15d
        invoke  FillRect,rsi,addr rc,[wc.hbrBackground]

        ; --- time: copy each character from the atlas ---
        call    GetNow
        movzx   eax,[stLocal.wSecond]
        mov     [shownSecond],eax
        movzx   r8d,[stLocal.wHour]
        movzx   r9d,[stLocal.wMinute]
        movzx   r10d,[stLocal.wSecond]
        invoke  wsprintfW,bufTime,fmtTime,r8,r9,r10
        mov     [k],0
  .blit:
        mov     ecx,[k]
        movzx   eax,word [bufTime+rcx*2]
        sub     eax,30h                 ; '0'..'9' -> 0..9, ':' -> 10
        imul    eax,[cellW]
        mov     [srcX],eax
        mov     eax,[charX+rcx*4]
        mov     r11d,[charX+rcx*4+4]
        sub     r11d,eax                ; cell width on screen
        sub     eax,r12d                ; -> back-buffer x
        mov     r10d,[timeBox.top]
        sub     r10d,r13d               ; -> back-buffer y
        invoke  BitBlt,rsi,rax,r10,r11,[cellH],[atlasDC],[srcX],0,0CC0020h
        inc     [k]
        cmp     [k],8
        jb      .blit

        ; --- date & status, only when the repainted area reaches them ---
        mov     eax,r13d
        add     eax,r15d
        cmp     eax,[dateTop]
        jle     .present
        mov     [gfx],0
        invoke  GdipCreateFromHDC,rsi,addr gfx
        mov     eax,r12d
        neg     eax
        cvtsi2ss xmm1,eax
        mov     eax,r13d
        neg     eax
        cvtsi2ss xmm2,eax
        invoke  GdipTranslateWorldTransform,[gfx],float xmm1,float xmm2,0
        mov     dword [rf],0            ; layout box: full width, text centred
        cvtsi2ss xmm0,dword [clientW]
        movss   [rf+8],xmm0
        mov     eax,[clientH]
        add     eax,eax
        cvtsi2ss xmm0,eax
        movss   [rf+12],xmm0
        invoke  GdipSetTextRenderingHint,[gfx],4                ; AntiAlias

        ; --- date (in the user's language) ---
        invoke  GetDateFormatEx,0,2,stLocal,0,bufDate,64,0      ; DATE_LONGDATE
        dec     eax
        jns     @f
        xor     eax,eax
    @@: mov     [len],eax
        cvtsi2ss xmm0,dword [dateY]
        movss   [rf+4],xmm0
        invoke  GdipDrawString,[gfx],bufDate,[len],[hFontDate],addr rf,[strFmt],[brDate]

        ; --- sync status ---
        call    BuildStatus
        mov     [len],eax
        mov     [brush],rdx
        invoke  GdipSetTextRenderingHint,[gfx],5                ; ClearType for small text
        cvtsi2ss xmm0,dword [statusY]
        movss   [rf+4],xmm0
        invoke  GdipDrawString,[gfx],bufStatus,[len],[hFontStatus],addr rf,[strFmt],[brush]
        invoke  GdipDeleteGraphics,[gfx]

  .present:
        invoke  BitBlt,rbx,r12,r13,r14,r15,rsi,0,0,0CC0020h     ; SRCCOPY
        invoke  SelectObject,rsi,[oldBmp]
        invoke  DeleteObject,rdi
        invoke  DeleteDC,rsi
  .end:
        invoke  EndPaint,[hwndMain],addr ps
        ret
endp

; -----------------------------------------------------------------------------
; BuildStatus -> bufStatus.  Returns eax = length, rdx = GDI+ brush.
proc BuildStatus uses rbx rsi
        mov     eax,[syncState]
        cmp     eax,1
        je      .synced
        cmp     eax,2
        je      .failed
        invoke  lstrcpyW,bufStatus,strSyncing
        mov     rbx,[brStatus]
        jmp     .hint
  .failed:
        invoke  lstrcpyW,bufStatus,strFailed
        mov     rbx,[brWarn]
        jmp     .hint
  .synced:
        mov     rbx,[brStatus]
        mov     rax,[syncDelay]         ; accuracy = round-trip / 2, in ms
        add     rax,10000
        xor     edx,edx
        mov     ecx,20000
        div     rcx
        mov     r11,rax
        mov     rax,[clockOffset]       ; >0 : internet time is ahead of the PC
        lea     r10,[strBehind]
        test    rax,rax
        jns     @f
        neg     rax
        lea     r10,[strAhead]
    @@: add     rax,5000
        xor     edx,edx
        mov     ecx,10000
        div     rcx                     ; rax = |offset| in ms
        cmp     rax,1000
        jae     .secs
        invoke  wsprintfW,bufStatus,fmtSyncMs,[syncServer],rax,r10,r11
        jmp     .hint
  .secs:
        xor     edx,edx
        mov     ecx,1000
        div     rcx
        mov     esi,edx
        invoke  wsprintfW,bufStatus,fmtSyncS,[syncServer],rax,rsi,r10,r11
  .hint:
        cmp     [isFull],0
        jne     .len
        invoke  lstrcatW,bufStatus,strHint
  .len:
        invoke  lstrlenW,bufStatus
        mov     rdx,rbx
        ret
endp

; -----------------------------------------------------------------------------
; MakeFont: ecx = em height in px, edx = weight.  Returns rax = HFONT.
proc MakeFont
        mov     r10d,ecx
        neg     r10d
        mov     r11d,edx
        invoke  CreateFontW,r10,0,0,0,r11,0,0,0,DEFAULT_CHARSET,0,0,ANTIALIASED_QUALITY,0,szFace
        ret
endp

; MakeGpFont: ecx = em height in px, edx = GDI+ style.  Returns rax = GpFont*.
proc MakeGpFont
  locals
    font dq ?
  endl
        mov     r11d,edx
        cvtsi2ss xmm1,ecx
        mov     [font],0
        invoke  GdipCreateFont,[gdipFamily],float xmm1,r11,2,addr font   ; UnitPixel
        mov     rax,[font]
        ret
endp

proc DeleteFonts
        mov     rcx,[hFontTime]
        test    rcx,rcx
        jz      @f
        invoke  GdipDeleteFont,rcx
    @@: mov     rcx,[hFontDate]
        test    rcx,rcx
        jz      @f
        invoke  GdipDeleteFont,rcx
    @@: mov     rcx,[hFontStatus]
        test    rcx,rcx
        jz      @f
        invoke  GdipDeleteFont,rcx
    @@: mov     [hFontTime],0
        mov     [hFontDate],0
        mov     [hFontStatus],0
        ret
endp

; -----------------------------------------------------------------------------
; BuildAtlas: renders "0123456789:" once, anti-aliased, into an off-screen
; strip (cellW x cellH per character, same vertical position as on screen).
proc BuildAtlas uses rbx r12 r13
  locals
    rf  rd 4
    gfx dq ?
    chr dw ?,?
  endl
        call    FreeAtlas
        mov     eax,[adv0]
        cmp     eax,[advC]
        jge     @f
        mov     eax,[advC]
    @@: imul    eax,[emTime]
        xor     edx,edx
        mov     ecx,1000
        div     ecx
        add     eax,3
        mov     [cellW],eax
        mov     eax,[timeBox.bottom]
        sub     eax,[timeBox.top]
        jle     .out
        mov     [cellH],eax

        invoke  GetDC,[hwndMain]
        mov     rbx,rax
        invoke  CreateCompatibleDC,rbx
        mov     [atlasDC],rax
        imul    r12d,[cellW],11
        invoke  CreateCompatibleBitmap,rbx,r12,[cellH]
        mov     [atlasBmp],rax
        invoke  SelectObject,[atlasDC],rax
        mov     [atlasOld],rax
        invoke  ReleaseDC,[hwndMain],rbx

        mov     [gfx],0
        invoke  GdipCreateFromHDC,[atlasDC],addr gfx
        invoke  GdipGraphicsClear,[gfx],ARGB_BG
        invoke  GdipSetTextRenderingHint,[gfx],4                ; AntiAlias
        mov     eax,[timeY]
        sub     eax,[timeBox.top]
        cvtsi2ss xmm0,eax
        movss   [rf+4],xmm0
        mov     eax,[cellW]
        add     eax,eax
        cvtsi2ss xmm0,eax
        movss   [rf+8],xmm0
        mov     eax,[cellH]
        add     eax,eax
        cvtsi2ss xmm0,eax
        movss   [rf+12],xmm0
        xor     r13d,r13d
  .glyph:
        lea     eax,[r13+30h]           ; '0'+i  (i = 10 gives ':')
        mov     [chr],ax
        mov     word [chr+2],0
        mov     eax,r13d
        imul    eax,[cellW]
        cvtsi2ss xmm0,eax
        movss   [rf],xmm0
        invoke  GdipDrawString,[gfx],addr chr,1,[hFontTime],addr rf,[strFmtNear],[brTime]
        inc     r13d
        cmp     r13d,11
        jb      .glyph
        invoke  GdipDeleteGraphics,[gfx]
  .out:
        ret
endp

proc FreeAtlas
        mov     rcx,[atlasDC]
        test    rcx,rcx
        jz      .out
        invoke  SelectObject,rcx,[atlasOld]
        invoke  DeleteObject,[atlasBmp]
        invoke  DeleteDC,[atlasDC]
        mov     [atlasDC],0
        mov     [atlasBmp],0
  .out:
        ret
endp

; -----------------------------------------------------------------------------
; Layout: ecx = client width, edx = client height.  Sizes the fonts so the
; time fills ~86% of the width (or 40% of the height) and centres everything.
proc Layout uses rbx rsi rdi r12 r13
  locals
    sz SIZE
    gm rb 20
  endl
        mov     [clientW],ecx
        mov     [clientH],edx
        mov     eax,ecx
        shr     eax,1
        mov     [centerX],eax
        test    ecx,ecx
        jz      .out
        test    edx,edx
        jz      .out
        call    DeleteFonts

        ; measure "00:00:00" and the digit height with a 1000 px font
        invoke  GetDC,[hwndMain]
        mov     rbx,rax
        mov     ecx,1000
        mov     edx,TIME_WEIGHT
        call    MakeFont
        mov     rsi,rax
        invoke  SelectObject,rbx,rsi
        mov     rdi,rax
        mov     [sz.cx],1000
        invoke  GetTextExtentPoint32W,rbx,strSample,8,addr sz
        invoke  GetTextExtentPoint32W,rbx,strSample,1,szTmp     ; width of a digit
        mov     eax,[szTmp.cx]
        mov     [adv0],eax
        invoke  GetTextExtentPoint32W,rbx,strColon,1,szTmp      ; width of ':'
        mov     eax,[szTmp.cx]
        mov     [advC],eax
        invoke  GetGlyphOutlineW,rbx,30h,0,addr gm,0,0,mat2   ; GGO_METRICS of '0'
        cmp     eax,-1
        je      @f
        mov     eax,dword [gm+12]       ; ink top above the baseline
        cmp     eax,100
        jl      @f
        mov     [digitTop],eax
    @@: invoke  SelectObject,rbx,rdi
        invoke  DeleteObject,rsi
        invoke  ReleaseDC,[hwndMain],rbx

        ; em = min(W*0.86, H*0.40 / digitRatio)
        mov     eax,[clientW]
        imul    eax,860
        cdq
        mov     ecx,[sz.cx]
        test    ecx,ecx
        jnz     @f
        mov     ecx,1000
    @@: idiv    ecx
        mov     r12d,eax
        mov     eax,[clientH]
        imul    eax,400
        cdq
        idiv    [digitTop]
        cmp     eax,r12d
        jge     @f
        mov     r12d,eax
    @@: cmp     r12d,8
        jge     @f
        mov     r12d,8
    @@: mov     ecx,r12d
        mov     edx,TIME_STYLE
        call    MakeGpFont
        mov     [hFontTime],rax

        ; date font: 14% of the time font, at least 12 px
        imul    eax,r12d,14
        xor     edx,edx
        mov     ecx,100
        div     ecx
        cmp     eax,12
        jge     @f
        mov     eax,12
    @@: mov     r13d,eax
        mov     ecx,eax
        mov     edx,TEXT_STYLE
        call    MakeGpFont
        mov     [hFontDate],rax

        ; status font: H/50, between 12 px and the date size
        mov     eax,[clientH]
        xor     edx,edx
        mov     ecx,50
        div     ecx
        cmp     eax,12
        jge     @f
        mov     eax,12
    @@: cmp     eax,r13d
        jle     @f
        mov     eax,r13d
    @@: mov     [emStatus],eax
        mov     ecx,eax
        mov     edx,TEXT_STYLE
        call    MakeGpFont
        mov     [hFontStatus],rax

        ; vertical geometry
        mov     eax,r12d
        imul    eax,[digitTop]
        xor     edx,edx
        mov     ecx,1000
        div     ecx
        mov     esi,eax                 ; esi = digit height
        imul    eax,r12d,15
        xor     edx,edx
        mov     ecx,100
        div     ecx
        mov     edi,eax                 ; edi = gap time -> date
        mov     eax,r13d
        imul    eax,[digitTop]
        xor     edx,edx
        mov     ecx,1000
        div     ecx
        mov     ebx,eax                 ; ebx = date cap height

        lea     eax,[esi+edi]
        add     eax,ebx                 ; block height
        mov     ecx,[clientH]
        sub     ecx,eax
        sar     ecx,1                   ; block top
        add     ecx,esi
        mov     [timeBase],ecx
        mov     eax,edi
        xor     edx,edx
        mov     r8d,3
        div     r8d
        add     eax,ecx
        mov     [dateTop],eax
        lea     eax,[ecx+edi]
        add     eax,ebx
        mov     [dateBase],eax

        mov     ecx,[emStatus]
        mov     eax,[clientH]
        sub     eax,ecx
        mov     [statusBase],eax
        imul    ecx,ecx,12
        mov     r9d,eax
        mov     eax,ecx
        xor     edx,edx
        mov     ecx,10
        div     ecx
        sub     r9d,eax                 ; status band top
        mov     eax,r13d                ; keep it below the date's descenders
        xor     edx,edx
        mov     ecx,3
        div     ecx
        add     eax,[dateBase]
        cmp     r9d,eax
        jge     @f
        mov     r9d,eax
    @@: mov     [statusTop],r9d

        ; box around the digits, the only area repainted each second
        mov     eax,r12d
        imul    eax,[sz.cx]
        xor     edx,edx
        mov     ecx,1000
        div     ecx                     ; text width
        shr     eax,1
        mov     ecx,r12d
        shr     ecx,4                   ; margin = em/16
        add     eax,ecx
        mov     edx,[centerX]
        mov     r8d,edx
        sub     r8d,eax
        mov     [timeBox.left],r8d
        add     edx,eax
        mov     [timeBox.right],edx
        mov     eax,[timeBase]
        sub     eax,esi
        sub     eax,ecx
        mov     [timeBox.top],eax
        mov     eax,[dateTop]
        mov     [timeBox.bottom],eax

        ; GDI+ positions text by the top of its line: top = baseline - ascent
        mov     eax,r12d
        imul    eax,[ascTime]
        xor     edx,edx
        div     [emhTime]
        neg     eax
        add     eax,[timeBase]
        mov     [timeY],eax
        mov     eax,r13d
        imul    eax,[ascText]
        xor     edx,edx
        div     [emhText]
        neg     eax
        add     eax,[dateBase]
        mov     [dateY],eax
        mov     eax,[emStatus]
        imul    eax,[ascText]
        xor     edx,edx
        div     [emhText]
        neg     eax
        add     eax,[statusBase]
        mov     [statusY],eax

        ; x position of each character of "HH:MM:SS" (9 boundaries)
        mov     [emTime],r12d
        imul    eax,[adv0],6
        mov     ecx,[advC]
        lea     eax,[eax+ecx*2]         ; width at 1000 px
        imul    eax,r12d
        xor     edx,edx
        mov     ecx,1000
        div     ecx
        shr     eax,1
        mov     r8d,[centerX]
        sub     r8d,eax                 ; left edge of the time
        xor     r9d,r9d                 ; running width, 1000 px units
        xor     r10d,r10d
  .pos:
        mov     eax,r9d
        imul    eax,r12d
        add     eax,500
        xor     edx,edx
        mov     ecx,1000
        div     ecx
        add     eax,r8d
        mov     [charX+r10*4],eax
        cmp     r10d,8
        je      .posdone
        mov     eax,[adv0]
        cmp     r10d,2
        je      .colon
        cmp     r10d,5
        jne     .advance
  .colon:
        mov     eax,[advC]
  .advance:
        add     r9d,eax
        inc     r10d
        jmp     .pos
  .posdone:
        call    BuildAtlas
  .out:
        ret
endp

; -----------------------------------------------------------------------------
proc ToggleFullscreen uses rbx
  locals
    mi rb 40
  endl
        invoke  GetWindowLongPtrW,[hwndMain],X_GWL_STYLE
        mov     rbx,rax
        cmp     [isFull],0
        jne     .leave
        mov     [wp.length],sizeof.WINDOWPLACEMENT
        invoke  GetWindowPlacement,[hwndMain],wp
        invoke  MonitorFromWindow,[hwndMain],2          ; MONITOR_DEFAULTTONEAREST
        mov     dword [mi],40
        invoke  GetMonitorInfoW,rax,addr mi
        mov     rax,WS_OVERLAPPEDWINDOW
        not     rax
        and     rbx,rax
        invoke  SetWindowLongPtrW,[hwndMain],X_GWL_STYLE,rbx
        mov     [isFull],1
        mov     [cursorHidden],0
        invoke  GetTickCount64
        mov     [lastMoveTick],rax
        mov     r10d,dword [mi+12]
        sub     r10d,dword [mi+4]
        mov     r11d,dword [mi+16]
        sub     r11d,dword [mi+8]
        invoke  SetWindowPos,[hwndMain],0,dword [mi+4],dword [mi+8],r10,r11,X_SWP_FULL
        invoke  SetThreadExecutionState,80000002h       ; keep the display on
        ret
  .leave:
        or      rbx,WS_OVERLAPPEDWINDOW
        invoke  SetWindowLongPtrW,[hwndMain],X_GWL_STYLE,rbx
        invoke  SetWindowPlacement,[hwndMain],wp
        invoke  SetWindowPos,[hwndMain],0,0,0,0,0,X_SWP_RESTORE
        mov     [isFull],0
        mov     [cursorHidden],0
        invoke  SetCursor,[hArrow]
        invoke  SetThreadExecutionState,80000000h
        ret
endp

; -----------------------------------------------------------------------------
; Background thread: sync, sleep 15 min (or 30 s after a failure), repeat.
; Pressing S, a clock change or waking from sleep signals hWake to sync early.
proc NtpThread uses rbx, param
        invoke  WSAStartup,202h,wsaData
  .loop:
        call    NtpSync
        mov     ebx,RESYNC_MS
        test    eax,eax
        jnz     .ok
        mov     ebx,RETRY_MS
        mov     eax,2
        cmp     [hadSync],0
        je      @f
        mov     eax,1                   ; keep using the last good offset
    @@: mov     [syncState],eax
  .ok:
        invoke  PostMessageW,[hwndMain],X_WM_SYNCED,0,0
        invoke  WaitForSingleObject,[hWake],rbx
        jmp     .loop
endp

; NtpSync: tries each server, SAMPLES queries each, keeps the lowest-delay
; sample.  offset = ((T2-T1)+(T3-T4))/2   delay = (T4-T1)-(T3-T2)
proc NtpSync uses rbx rsi rdi r12 r13 r14 r15
  locals
    hints   rb 48
    res     dq ?
    sock    dq ?
    tmo     dd ?
    pkt     rb 48
    t1      dq ?
    t4      dq ?
    bestOfs dq ?
  endl
        xor     r15d,r15d
  .server:
        cmp     r15d,NSERVERS
        jae     .fail
        mov     rsi,[servers+r15*8]
        lea     rdi,[hints]
        xor     eax,eax
        mov     ecx,6
        rep     stosq
        mov     dword [hints+4],2       ; AF_INET
        mov     dword [hints+8],2       ; SOCK_DGRAM
        mov     dword [hints+12],17     ; IPPROTO_UDP
        mov     [res],0
        invoke  GetAddrInfoW,rsi,strPort,addr hints,addr res
        test    eax,eax
        jnz     .next
        invoke  socket,2,2,17
        cmp     rax,-1
        je      .free
        mov     [sock],rax
        mov     [tmo],1500
        invoke  setsockopt,[sock],0FFFFh,1006h,addr tmo,4   ; SO_RCVTIMEO 1.5 s
        mov     rax,[res]
        invoke  connect,[sock],qword [rax+32],dword [rax+16]
        test    eax,eax
        jnz     .close
        mov     r12,7FFFFFFFFFFFFFFFh   ; best delay so far
        xor     r13d,r13d
        mov     ebx,SAMPLES
  .sample:
        lea     rdi,[pkt]
        xor     eax,eax
        mov     ecx,6
        rep     stosq
        mov     byte [pkt],23h          ; LI 0, version 4, mode 3 (client)
        invoke  GetSystemTimePreciseAsFileTime,addr t1
        invoke  send,[sock],addr pkt,48,0
        cmp     eax,48
        jne     .done
        invoke  recv,[sock],addr pkt,48,0
        mov     r14d,eax
        invoke  GetSystemTimePreciseAsFileTime,addr t4
        cmp     r14d,48
        jl      .again
        mov     al,[pkt]
        and     al,7
        cmp     al,4                    ; must be a server reply
        jne     .again
        movzx   eax,byte [pkt+1]
        dec     eax
        cmp     eax,14                  ; stratum 1..15 (0 = kiss-o'-death)
        ja      .again
        cmp     dword [pkt+40],0
        je      .again
        lea     rcx,[pkt+32]
        call    NtpToFt
        mov     r14,rax                 ; T2 server receive
        lea     rcx,[pkt+40]
        call    NtpToFt                 ; rax = T3 server transmit
        mov     rdx,[t4]
        sub     rdx,[t1]
        mov     r8,rax
        sub     r8,r14
        sub     rdx,r8                  ; delay
        jns     @f
        xor     edx,edx
    @@: mov     r9,r14
        sub     r9,[t1]
        sub     rax,[t4]
        add     r9,rax
        sar     r9,1                    ; offset
        cmp     rdx,r12
        jge     .again
        mov     r12,rdx
        mov     [bestOfs],r9
        mov     r13d,1
  .again:
        dec     ebx
        jnz     .sample
  .done:
        invoke  closesocket,[sock]
        invoke  FreeAddrInfoW,[res]
        test    r13d,r13d
        jz      .next
        mov     rax,[bestOfs]
        mov     [clockOffset],rax
        mov     [syncDelay],r12
        mov     [syncServer],rsi
        mov     [hadSync],1
        mov     [syncState],1
        mov     eax,1
        ret
  .close:
        invoke  closesocket,[sock]
  .free:
        invoke  FreeAddrInfoW,[res]
  .next:
        inc     r15d
        jmp     .server
  .fail:
        xor     eax,eax
        ret
endp

; =============================================================================
section '.data' data readable writeable

  align 8
  clockOffset   dq 0            ; internet time - PC time, 100 ns units
  syncDelay     dq 0
  syncServer    dq 0
  lastMoveTick  dq 0
  hwndMain      dq 0
  hWake         dq 0
  hArrow        dq 0
  hFontTime     dq 0
  hFontDate     dq 0
  hFontStatus   dq 0
  nowFt         dq 0
  gdipToken     dq 0
  gdipFamily    dq 0
  fmtTmp        dq 0
  strFmt        dq 0
  brTime        dq 0
  brDate        dq 0
  brStatus      dq 0
  brWarn        dq 0
  strFmtNear    dq 0
  atlasDC       dq 0
  atlasBmp      dq 0
  atlasOld      dq 0
  adv0          dd 0            ; advances at 1000 px
  advC          dd 0
  emTime        dd 0
  cellW         dd 0
  cellH         dd 0
  charX         rd 9
  szTmp         SIZE
  gdipInput     dd 1,0          ; GdiplusStartupInput: version 1
                dq 0
                dd 0,0
  ascTime       dd 2210         ; font design units, filled in from GDI+
  emhTime       dd 2048
  ascText       dd 2210
  emhText       dd 2048
  timeY         dd 0
  dateY         dd 0
  statusY       dd 0
  syncState     dd 0            ; 0 syncing, 1 synced, 2 failed
  hadSync       dd 0
  isFull        dd 0
  cursorHidden  dd 0
  lastMousePos  dd -1
  shownSecond   dd -1
  clientW       dd 0
  clientH       dd 0
  centerX       dd 0
  timeBase      dd 0
  dateTop       dd 0
  dateBase      dd 0
  statusTop     dd 0
  statusBase    dd 0
  emStatus      dd 0
  digitTop      dd 700
  dwmTrue       dd 1
  dwmCaption    dd COL_BG
  mat2          dd 10000h,0,0,10000h

  servers       dq srv1,srv2,srv3,srv4
  NSERVERS = 4

  timeBox       RECT
  dirty         RECT
  stUtc         SYSTEMTIME
  stLocal       SYSTEMTIME
  wp            WINDOWPLACEMENT
  msg           MSG
  wc            WNDCLASSEX sizeof.WNDCLASSEX,CS_DBLCLKS,WindowProc,0,0,0,0,0,0,0,szClass,0
  wsaData       rb 512

  szClass       du 'TimeIsntClock',0
  szTitle       du "Time ISN't",0
  szFace        du 'Segoe UI',0
  szFail        du 'Could not create the clock window.',0
  strSample     du '00:00:00',0
  strColon      du ':',0
  strPort       du '123',0
  fmtTime       du '%02u:%02u:%02u',0
  srv1          du 'time.cloudflare.com',0
  srv2          du 'time.google.com',0
  srv3          du 'time.windows.com',0
  srv4          du 'pool.ntp.org',0
  strSyncing    du 'Syncing with internet time',2026h,0
  strFailed     du "Can't reach time servers ",2014h," showing this PC's clock",0
  fmtSyncMs     du 'Synced ',0B7h,' %s ',0B7h,' PC clock %u ms %s ',0B7h,' ',0B1h,'%u ms',0
  fmtSyncS      du 'Synced ',0B7h,' %s ',0B7h,' PC clock %u.%03u s %s ',0B7h,' ',0B1h,'%u ms',0
  strAhead      du 'ahead',0
  strBehind     du 'behind',0
  strHint       du '     F11 full screen ',0B7h,' S resync',0

  bufTime       rw 16
  bufNext       rw 16
  bufDate       rw 64
  bufStatus     rw 256

; =============================================================================
section '.idata' import data readable writeable

  library kernel32,'KERNEL32.DLL',\
          user32,'USER32.DLL',\
          gdi32,'GDI32.DLL',\
          gdiplus,'GDIPLUS.DLL',\
          ws2_32,'WS2_32.DLL',\
          dwmapi,'DWMAPI.DLL'

  import kernel32,\
         GetModuleHandleW,'GetModuleHandleW',\
         ExitProcess,'ExitProcess',\
         CreateEventW,'CreateEventW',\
         SetEvent,'SetEvent',\
         WaitForSingleObject,'WaitForSingleObject',\
         CreateThread,'CreateThread',\
         CloseHandle,'CloseHandle',\
         GetSystemTimePreciseAsFileTime,'GetSystemTimePreciseAsFileTime',\
         FileTimeToSystemTime,'FileTimeToSystemTime',\
         SystemTimeToTzSpecificLocalTime,'SystemTimeToTzSpecificLocalTime',\
         GetDateFormatEx,'GetDateFormatEx',\
         GetTickCount64,'GetTickCount64',\
         SetThreadExecutionState,'SetThreadExecutionState',\
         lstrcpyW,'lstrcpyW',\
         lstrcatW,'lstrcatW',\
         lstrlenW,'lstrlenW'

  import user32,\
         RegisterClassExW,'RegisterClassExW',\
         CreateWindowExW,'CreateWindowExW',\
         DefWindowProcW,'DefWindowProcW',\
         GetMessageW,'GetMessageW',\
         TranslateMessage,'TranslateMessage',\
         DispatchMessageW,'DispatchMessageW',\
         PostQuitMessage,'PostQuitMessage',\
         PostMessageW,'PostMessageW',\
         MessageBoxW,'MessageBoxW',\
         LoadIconW,'LoadIconW',\
         LoadImageW,'LoadImageW',\
         LoadCursorW,'LoadCursorW',\
         SetCursor,'SetCursor',\
         ShowWindow,'ShowWindow',\
         UpdateWindow,'UpdateWindow',\
         SetTimer,'SetTimer',\
         InvalidateRect,'InvalidateRect',\
         FillRect,'FillRect',\
         BeginPaint,'BeginPaint',\
         EndPaint,'EndPaint',\
         GetDC,'GetDC',\
         ReleaseDC,'ReleaseDC',\
         GetSystemMetrics,'GetSystemMetrics',\
         GetWindowLongPtrW,'GetWindowLongPtrW',\
         SetWindowLongPtrW,'SetWindowLongPtrW',\
         GetWindowPlacement,'GetWindowPlacement',\
         SetWindowPlacement,'SetWindowPlacement',\
         SetWindowPos,'SetWindowPos',\
         MonitorFromWindow,'MonitorFromWindow',\
         GetMonitorInfoW,'GetMonitorInfoW',\
         SetProcessDpiAwarenessContext,'SetProcessDpiAwarenessContext',\
         wsprintfW,'wsprintfW'

  import gdi32,\
         CreateSolidBrush,'CreateSolidBrush',\
         CreateFontW,'CreateFontW',\
         SelectObject,'SelectObject',\
         DeleteObject,'DeleteObject',\
         SetBkColor,'SetBkColor',\
         SetTextColor,'SetTextColor',\
         SetTextAlign,'SetTextAlign',\
         ExtTextOutW,'ExtTextOutW',\
         GetTextExtentPoint32W,'GetTextExtentPoint32W',\
         GetGlyphOutlineW,'GetGlyphOutlineW',\
         CreateCompatibleDC,'CreateCompatibleDC',\
         CreateCompatibleBitmap,'CreateCompatibleBitmap',\
         BitBlt,'BitBlt',\
         DeleteDC,'DeleteDC'

  import gdiplus,\
         GdiplusStartup,'GdiplusStartup',\
         GdipCreateFontFamilyFromName,'GdipCreateFontFamilyFromName',\
         GdipGetGenericFontFamilySansSerif,'GdipGetGenericFontFamilySansSerif',\
         GdipGetCellAscent,'GdipGetCellAscent',\
         GdipGetEmHeight,'GdipGetEmHeight',\
         GdipCreateSolidFill,'GdipCreateSolidFill',\
         GdipStringFormatGetGenericTypographic,'GdipStringFormatGetGenericTypographic',\
         GdipCloneStringFormat,'GdipCloneStringFormat',\
         GdipSetStringFormatAlign,'GdipSetStringFormatAlign',\
         GdipSetStringFormatFlags,'GdipSetStringFormatFlags',\
         GdipCreateFont,'GdipCreateFont',\
         GdipDeleteFont,'GdipDeleteFont',\
         GdipCreateFromHDC,'GdipCreateFromHDC',\
         GdipDeleteGraphics,'GdipDeleteGraphics',\
         GdipGraphicsClear,'GdipGraphicsClear',\
         GdipTranslateWorldTransform,'GdipTranslateWorldTransform',\
         GdipSetTextRenderingHint,'GdipSetTextRenderingHint',\
         GdipDrawString,'GdipDrawString'

  import ws2_32,\
         WSAStartup,'WSAStartup',\
         GetAddrInfoW,'GetAddrInfoW',\
         FreeAddrInfoW,'FreeAddrInfoW',\
         socket,'socket',\
         setsockopt,'setsockopt',\
         connect,'connect',\
         send,'send',\
         recv,'recv',\
         closesocket,'closesocket'

  import dwmapi,\
         DwmSetWindowAttribute,'DwmSetWindowAttribute'

; =============================================================================
section '.rsrc' resource data readable

  directory RT_ICON,icons,\
            RT_GROUP_ICON,group_icons,\
            RT_VERSION,versions

  resource icons,\
           1,LANG_NEUTRAL,ico16,\
           2,LANG_NEUTRAL,ico20,\
           3,LANG_NEUTRAL,ico24,\
           4,LANG_NEUTRAL,ico32,\
           5,LANG_NEUTRAL,ico40,\
           6,LANG_NEUTRAL,ico48,\
           7,LANG_NEUTRAL,ico64,\
           8,LANG_NEUTRAL,ico256

  resource group_icons,\
           1,LANG_NEUTRAL,main_icon

  resource versions,\
           1,LANG_NEUTRAL,version

  icon main_icon,\
       ico16,'icon\16.ico',\
       ico20,'icon\20.ico',\
       ico24,'icon\24.ico',\
       ico32,'icon\32.ico',\
       ico40,'icon\40.ico',\
       ico48,'icon\48.ico',\
       ico64,'icon\64.ico',\
       ico256,'icon\256.ico'

  versioninfo version,VOS__WINDOWS32,VFT_APP,VFT2_UNKNOWN,LANG_ENGLISH+SUBLANG_DEFAULT,0,\
              'FileDescription',"Time ISN't clock",\
              'ProductName',"Time ISN't",\
              'FileVersion','0.1',\
              'ProductVersion','0.1',\
              'OriginalFilename','TimeIsnt.exe'
