
%include "../include/macro.s"
%include "../include/define.s"


  ORG BOOT_LOAD
entry:
  ; BPB(BIOS Parameter Block)
  jmp ipl
  times 90 - ($ - $$) db 0x90

  ; IPL(Initial Parameter Block)
ipl:
  cli                           ; 割り込み禁止

  mov ax, 0x0000
  mov ds, ax
  mov es, ax
  mov ss, ax
  mov sp, BOOT_LOAD

  sti                           ; 割り込み禁止解除

  mov [BOOT + drive.no], dl     ;  ブートドライブを保存

  ; 文字列を表示
  cdecl puts, .s0

  ; 残りのセクタをすべて読み込む
  mov bx, BOOT_SECT - 1
  mov cx, BOOT_LOAD + SECT_SIZE

  cdecl read_chs, BOOT, bx, cx

  cmp ax, bx
.10Q:
  jz .10E
.10T:
  cdecl puts, .e0
  call reboot
.10E:


  jmp stage_2                   ; 次のステージへ移行

  ; データ
.s0: db "Booting...", 0x0A, 0x0D, 0
.e0: db "Error:sector read", 0

  ; ブートドライブに関する情報
ALIGN 2, db 0
BOOT:                           ;  ブートドライブに関する情報
  istruc drive
      at drive.no,   dw 0       ; ドライブ番号
      at drive.cyln, dw 0       ; C:シリンダ
      at drive.head, dw 0       ; H:ヘッド
      at drive.sect, dw 2       ; S:セクタ
  iend

  ; モジュール情報(先頭512バイトに配置)
%include "../modules/real/puts.s"
%include "../modules/real/read_chs.s"
%include "../modules/real/reboot.s"

  ; BOOT FLAG(Finishing 512 bites)
  times 510 - ($ - $$) db 0x00
  db    0x55, 0xAA

  ; リアルモード時に取得した情報
FONT:
.seg: dw 0
.off: dw 0
ACPI_DATA:
.adr: dd 0
.len: dd 0

  ; モジュール情報(先頭512バイト以降に配置)
  %include "../modules/real/itoa.s"
  %include "../modules/real/get_drive_param.s"
  %include "../modules/real/get_font_adr.s"
  %include "../modules/real/get_mem_info.s"
  %include "../modules/real/kbc.s"
  %include "../modules/real/read_lba.s"
  %include "../modules/real/lba_chs.s"

  ; ブート処理の第２ステージ
stage_2:
  cdecl puts, .s0                ; 文字列を表示

  ; ドライブ情報の取得
  cdecl get_drive_param, BOOT
  cmp ax, 0
.10Q:
  jne .10E
.10T:
  cdecl puts, .e0
  call reboot
.10E:

  ; ドライブ情報を表示
  mov ax, [BOOT + drive.no]
  cdecl itoa, ax, .p1, 2, 16, 0b0100
  mov ax, [BOOT + drive.cyln]
  cdecl itoa, ax, .p2, 4, 16, 0b0100
  mov ax, [BOOT + drive.head]
  cdecl itoa, ax, .p3, 2, 16, 0b0100
  mov ax, [BOOT + drive.sect]
  cdecl itoa, ax, .p4, 2, 16, 0b0100
  cdecl puts, .s1


  jmp stage_3rd                               ; 次のステージへ移行

  ; データ
.s0: db "2nd stage ... ", 0x0A, 0x0D, 0

.s1: db " Drive:0x"
.p1: db " , C:0x"
.p2: db "   , H:0x"
.p3: db " , S:0x"
.p4: db " ", 0x0A, 0x0D, 0

.e0: db "Can't get drive parameter.", 0


  ; ブート処理の第３ステージ
stage_3rd:
  cdecl puts, .s0                             ; 文字列を表示
  cdecl get_font_adr, FONT                    ; BIOSのフォントアドレスを取得

  ; フォントアドレスの表示
  cdecl itoa, word [FONT.seg], .p1, 4, 16, 0b0100
  cdecl itoa, word [FONT.off], .p2, 4, 16, 0b0100
  cdecl puts, .s1

  ; メモリ情報の取得と表示
  cdecl get_mem_info

  mov eax, [ACPI_DATA.adr]
  cmp eax, 0
  je .10E

  cdecl itoa, ax, .p4, 4, 16, 0b0100
  shr eax, 16
  cdecl itoa, ax, .p3, 4, 16, 0b0100

  cdecl puts, .s2
.10E:


  jmp stage_4                                       ; 次のステージへ移行


  ; データ
.s0: db "3rd stage...", 0x0A, 0x0D, 0

.s1: db " Font Address = "
.p1: db "ZZZZ:"
.p2: db "ZZZZ", 0x0A, 0x0D, 0
    db 0x0A, 0x0D, 0

.s2: db " ACPI data="
.p3: db "ZZZZ"
.p4: db "ZZZZ", 0x0A, 0x0D, 0

  ; ブート処理の第４ステージ
stage_4:
  cdecl puts, .s0                                   ; 文字列を表示

  ; A20ゲートの有効化
  cli                                               ; 割り込み禁止

  cdecl KBC_Cmd_Write, 0xAD                         ; キーボード無効化命令

  cdecl KBC_Cmd_Write, 0xD0                         ; 出力ポート読み出し命令
  cdecl KBC_Data_Read, .key

  mov bl, [.key]
  or bl, 0x02                                       ; A20ゲート有効化

  cdecl KBC_Cmd_Write, 0xD1                         ; 出力ポート書き込み命令
  cdecl KBC_Data_Write, bx

  cdecl KBC_Cmd_Write, 0xAE                         ; キーボード有効化

  sti                                               ; 割り込み許可

  cdecl puts, .s1                                   ; 文字列を表示


  ; キーボードLEDのテスト
  cdecl puts, .s2

  mov bx, 0
.10L:
  mov ah, 0x00
  int 0x16                                          ; キー入力待ち

  cmp al, '1'
  jb .10E

  cmp al, '3'
  ja .10E

  mov cl, al
  dec cl
  and cl, 0x03
  mov ax, 0x0001
  shl ax, cl
  xor bx, ax

  ; LEDコマンドの送信
  cli                                               ; 割り込み禁止

  cdecl KBC_Cmd_Write, 0xAD                         ; キーボード無効化

  cdecl KBC_Data_Write, 0xED                        ; LEDコマンド
  cdecl KBC_Data_Read, .key                         ; 受信応答

  cmp [.key], byte 0xFA
  jne .11F

  cdecl KBC_Data_Write, bx                          ; LEDデータ出力
  jmp .11E
.11F:
  cdecl itoa, word [.key], .e1, 2, 16, 0b0100
  cdecl puts, .e0
.11E:
  cdecl KBC_Cmd_Write, 0xAE                         ; キーボード有効化

  sti                                               ; 割り込み許可

  jmp .10L
.10E:


  cdecl puts, .s3                                   ; 文字列を表示

  jmp stage_5                                       ; 次のステージへ移行

  ; データ
.s0: db "4th stage...", 0x0A, 0x0D, 0
.s1: db " A20 Gate Enabled.", 0x0A, 0x0D, 0
.s2: db " Keyboard LED Test...", 0
.s3: db " (done)", 0x0A, 0x0D, 0
.e0: db "["
.e1: db "ZZ]", 0

.key: dw 0

  ; ブート処理の第５ステージ
stage_5:
  cdecl puts, .s0                                   ; 文字列を表示

  ; カーネルを読み込む
  cdecl read_lba, BOOT, BOOT_SECT, KERNEL_SECT, BOOT_END

  cmp ax, KERNEL_SECT
.10Q:
  jz .10E
.10T:
  cdecl puts, .e0
  call reboot
.10E:

  jmp stage_6                                        ; 次のステージへ移行

  ; データ
.s0: db "5th stage...", 0x0A, 0x0D, 0
.e0: db " Failure load kernel...", 0x0A, 0x0D, 0

  ; ブート処理の第６ステージ
stage_6:
  cdecl puts, .s0                                     ; 文字列を表示

  ; ユーザーからの入力待ち
.10L:
  mov ah, 0x00
  int 0x16
  cmp al, ' '
  jne .10L

  ; ビデオモードの設定
  mov ax, 0x0012
  int 0x10

  jmp stage_7                                          ; 次のステージへ移行

  ; データ
.s0: db "6th stage...", 0x0A, 0x0D, 0x0A, 0x0D
     db " [Push SPACE key to protect mode...]", 0x0A, 0x0D, 0

;**************************************************************
  ; GLOBAL DESCRIPTOR TABLE(セグメントディスクリプタの配列)
;**************************************************************
ALIGN 4, db 0
GDT:            dq 0x00_0_0_0_0_000000_0000            ; NULL
.cs:            dq 0x00_C_F_9_A_000000_FFFF            ; CODE 4G
.ds:            dq 0x00_C_F_9_2_000000_FFFF            ; DATA 4G
.gdt_end:

  ; セレクタ
SEL_CODE equ .cs - GDT
SEL_DATA equ .ds - GDT

  ; GDT
GDTR: dw GDT.gdt_end - GDT - 1                         ; GDTのリミット
      dd GDT                                           ; GDTのアドレス

  ; IDT(疑似：割り込み禁止にするため)
IDTR: dw 0                                             ; IDTのリミット
      dd 0                                             ; IDTのアドレス



  ; ブート処理の第７ステージ
stage_7:
  cli                                                  ; 割込み禁止

  ; GDTロード
  lgdt [GDTR]                                          ; GDTをロード
  lidt [IDTR]                                          ; IDTをロード

  ; プロテクトモードへ移行
  mov eax, cr0
  or ax, 1
  mov cr0, eax

  jmp $ + 2                                            ; 先読みをクリア

  ; セグメント間ジャンプ
[BITS 32]
  DB 0x66                               ; オペランドサイズオーバーライドプレフィックス
  jmp SEL_CODE:CODE_32

;***************************************************************
  ; 32ビットコード開始
;***************************************************************
CODE_32:
  ; セレクタを初期化
  mov ax, SEL_DATA
  mov ds, ax
  mov es, ax
  mov fs, ax
  mov gs, ax
  mov ss, ax

  ; カーネル部をコピー
  mov ecx, (KERNEL_SIZE) / 4
  mov esi, BOOT_END
  mov edi, KERNEL_LOAD
  cld
  rep movsd

  ; カーネル処理に移行
  jmp KERNEL_LOAD

  ; パディング（このファイルは8Kバイトとする）
  times BOOT_SIZE - ($ - $$) db 0
