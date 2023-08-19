; USB gamepad firmware for UKP
; By hi631, nand2mario

cstart:
; ---- interrupt transfer interval (10-1mS)
	ldi	9
cstart2:
	wait
	bc	connected
	bz	cstart

; ---- wait 200mS after device attached
	ldi	200
w200ms:
	wait
	djnz	w200ms

; ---- USB bus reset
	out0
	ldi	10
busrstlp:
	wait
	djnz	busrstlp
	hiz

; ---- 40mS wait
	ldi	40
w40ms:
	wait
	out4 0x03
	hiz
	djnz	w40ms
	wait

; nand2mario: see USB device initialization sequence
; https://www.usbmadesimple.co.uk/ums_4.htm
; CRC calculator: https://www.lddgo.net/en/encrypt/crc

; ---- send set address 1
	jmp  setadr1
	hiz

; ---- recieve
	jmp  rcvdt

; ---- send IN(0,0)
sendinlp:
	jmp  in00
	hiz

; ---- receive
	jmp  rcvdt
	bnak	sendinlp

; ---- send ACK
	jmp  sendack
	hiz

; ---- wait 1mS
	wait

; nand2mario: request device descriptor and receive ACK
	jmp getdesc
	hiz
	jmp rcvdt

; ---- send IN(1,0) and receive 1st half of device descriptor
wait_desc:
	jmp in10
	hiz
	jmp rcvdt
	bnak wait_desc
; send ACK
	jmp  sendack
	hiz

; request 2nd half of device descriptor
wait_desc2:
	jmp in10
	hiz
	jmp rcvdt
	bnak wait_desc2
	vidpid			; register VID and PID just received
; send ACK
	jmp  sendack
	hiz

; TODO: need to send a status transaction
; https://www.beyondlogic.org/usbnutshell/usb4.shtml#Control

; ---- wait 1mS
	wait

; ---- send set configuration 1
	jmp  setconfig1
	hiz

; ---- recieve
	jmp  rcvdt

; ---- send IN(1,0)
in10lp:
	jmp  in10
	hiz

; ---- recieve
	jmp  	rcvdt
	bnak	in10lp

; ---- send ACK
	jmp sendack
	hiz
	toggle
	jmp  cstart

; -------------------
;  when connected    
; -------------------
connected:
	bz	connerr

	out4 0x03
	hiz
	djnz	cstart2
	wait

; ---- IN(1,1) (interrupt transfer)
	jmp  in11
	hiz

; ---- recieve
	jmp  rcvdt
	bnak	cstart

; ---- send ACK
	jmp  sendack
	hiz

; ---- jump startf
	jmp  cstart

; ---- jupm start(&toggle)
connerr:
	toggle
	jmp  cstart

; --------------
; sub           
; --------------
setadr1:
	outb 0x80
	outb 0x2d
	outb 0x00
	outb 0x10
	out4 0x03

	outb 0x80
	outb 0xc3
	outb 0x00
	outb 0x05
	outb 0x01
	outb 0x00
	outb 0x00
	outb 0x00
	outb 0x00
	outb 0x00
	outb 0xeb
	outb 0x25
	out4 0x03
	ret

getdesc:			; get device descriptor
	outb 0x80		; SYNC
	outb 0x2d		; PID
	outb 0x01		; ADDR + ENDP 
	outb 0xe8		; + CRC5
	out4 0x03		; EOP

	outb 0x80		; SYNC
	outb 0xc3		; PID=DATA0
	outb 0x80		; bmRequestType: 0
	outb 0x06		; bRequest=1 Get_Descriptor
	outb 0x00		; Desc Index: 0
	outb 0x01		; Desc Type: 1 Device
	outb 0x00		; Language ID: 0
	outb 0x00		; 
	outb 0x12		; wLength = 18
	outb 0x00
	outb 0xE0		; CRC16
	outb 0xF4
	out4 0x03		; EOP
	ret

setconfig1:
	outb 0x80
	outb 0x2d
	outb 0x01
	outb 0xe8
	out4 0x03

	outb 0x80
	outb 0xc3
	outb 0x00
	outb 0x09
	outb 0x01
	outb 0x00
	outb 0x00
	outb 0x00
	outb 0x00
	outb 0x00
	outb 0x27
	outb 0x25
	out4 0x03
	ret

rcvdt:
	ldi	104
	start
	in
rcvdt2:
	ldi	2
rcvdt3:
	bz		rcvdt2
	djnz	rcvdt3
	ret

in00:
	outb 0x80
	outb 0x69
	outb 0x00
	outb 0x10
	out4 0x03
	ret

in10:
	outb 0x80
	outb 0x69
	outb 0x01
	outb 0xe8
	out4 0x03
	ret

in11:
	outb 0x80
	outb 0x69
	outb 0x81
	outb 0x58
	out4 0x03
	ret

sendack:
	outb 0x80
	outb 0xd2
	out4 0x03
	ret
prgend:
