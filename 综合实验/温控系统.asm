;++++++++++++++++++++++++++++++++++++++++++++++++++++++
;             @xianwu   2020/6/29                     
;             coding:   GBK                                        
;主要分为三部分:1外接8279进行键盘扫描，数码管显示           
;             2利用DS18B20读取温度，改变温度值           
;             3根据温度历用DAC0832进行DA转换控制电机     
;
;数码管显示从左到右第1、2位表示高温阈值；3、4位表示低温阈值
;                 5、6位表示当前温度值
;按键F1改变高温阈值，F2改变低温阈值         
;
;++++++++++++++++++++++++++++++++++++++++++++++++++++

;======================预定义==============================
TEMPER_L   EQU 	41H     ;存放读出温度低位数据
TEMPER_H   EQU 	40H     ;存放读出温度高位数据
TH	   EQU	42H     ;存放温度最高预设值
TL	   EQU  43H     ;存放温度最低预设值
TEMPER_NUM EQU 	60H     ;存放转换后的温度值
FLAG1      BIT  10H     ;ds18B20存在标志位
DQ         BIT  P3.3    ;一线总线控制端口;读出转换后的温度值
LED0       EQU  0FFF0H  ;8279数据通道
LED1       EQU  0FFF1H  ;8279数据通道
LEDBUFF    EQU  30H     ;缓存头地址30-35
DAC0832    EQU  0300H   ;入口地址
;==========================================================

;===============初始化======================================
ORG 0000H
	MOV SP,#10H
	MOV DPTR,#LED1     ;指向命令口
        MOV A,#00H         ;6个8位显示
        MOVX @DPTR,A       ;方式字写入
        MOV A,#32H         ;设分频初值
        MOVX @DPTR,A       ;分频字写入
        MOV A,#0DFH        ;定义清显字
        MOVX @DPTR,A       ;关闭显示器
	MOV TEMPER_NUM,#27H
	MOV LEDBUFF , #10H
	MOV LEDBUFF+1,#10H
	MOV LEDBUFF+2,#10H
	MOV LEDBUFF+3,#10H
	MOV LEDBUFF+4,#10H
	MOV LEDBUFF+5,#10H
	MOV TH,	      #30H ;最高温赋初值
	LCALL GET_TEMPER   ;获取温度并初始化ds1820
	MOV TL,	      #27H ;最低温初值
	LCALL RE_CONFIG    ;写入阈值
	LJMP MLOOP
;===============初始化======================================
	
;=================主程序====================================	
	ORG 0100H
MLOOP:   
	 LCALL GET_TEMPER ;获取温度
         LCALL TEMPER_COV ;温度转换
         LCALL XMON       ;按键检测+重写温度限值内容
	 LCALL NEW_CACHE  ;刷新数据
	 LCALL TEMP_CACHE ;电机控制
	 LCALL DISP
	 SJMP MLOOP
;===================END====================================



;==================8279键盘显示=============================
;----------------------------------------------------------
;扫描键盘，检测功能键是否按下
XMON:   CALL DIKEY         ;调显示键扫
        CJNE A,#20H,JUGE   ;有无按键按下
	RET                ;无按键则返回
JUGE:   CJNE A,#10H,KRDS   ;有按键，判断功能键还是数字键
KRDS:   jnc KRDY           ;转功能键处理
	RET                ;数字键无效返回
;功能键处理写入低温还是高温
KRDY:   ANL A, #01H   ;11H,10H对应按键f1,f0，只需要判断后1位
	JNZ WRIT_TL   ;1为第二个按键，低温区域
;写入高温阈值
WRIT_TH:
	MOV R5, TH         ;保存原值
	MOV TH, 00H        ;清空
	LCALL NEW_CACHE;刷新数据
	LCALL DISP
	LCALL LKEY         ;检查按键
	ANL A, #0FH
	MOV R6, A
	
	MOV LEDBuff+5,A   ;第一个位数字(十位）
	LCALL DISP
	
	LCALL LKEY        ;检查按键
	ANL A, #0FH
	MOV R7, A	
	MOV LEDBUFF+4,A   ;第二个位数字(个位）
	LCALL DISP

	MOV A, R6          ;合并为一个温度放入暂存区
	SWAP A             ;这里使用的是BCD码表示温度
	ORL A, R7
	CJNE A, TL, OKH     ;输入最大值和最小值比较
OKH:    JC  ERRORH          ;小于最小值，输入不符合
	MOV TL, A           ;输入符合
	LCALL RE_CONFIG    ;重写最高最低温度
	RET
ERRORH: MOV TH, R5         ;装回原值
        RET
;写入低温阈值
WRIT_TL:
	MOV R5, TL         ;保存原值
	MOV TL, 00H        ;清空
	LCALL NEW_CACHE    ;刷新数据
	LCALL DISP
	LCALL LKEY         ;检查按键
	ANL A, #0FH        ;保存低位
	MOV R6, A
	MOV LEDBUFF+3,A   ;第一个位数字(十位）
	LCALL DISP
	
	LCALL LKEY        ;检查按键
	MOV LEDBUFF+2,A   ;第二个位数字(个位）
	ANL A, #0FH
	MOV R7, A
	LCALL DISP
	
	MOV A, R6          ;合并为一个温度放入暂存区
	SWAP A             ;这里使用的是BCD码表示温度
	ORL A, R7
	CJNE A, TH, OKL     ;输入最小值和最大值比较
OKL:    JNC  ERRORL         ;大于最大值输入不符合
	MOV TL, A          ;输入符合
	LCALL RE_CONFIG    ;重写最高最低温度
	RET
ERRORL: MOV TL, R5         ;装回原值
        RET
	
;键盘扫描，循环检测一个数字键--------------------------------------------
LKEY:
        LCALL DIKEY         ;调显示键扫
        CJNE A,#10H,JUGE0  ;无按键和功能键都不做处理 
JUGE0:	JNC LKEY           ;无数字键,则不断检测 
        RET

;键盘扫描子程序-------------------------------------------------------
DIKEY:  MOV R4,#00H        ;设査键次数
DIKRD:  MOV DPTR,#LED1     ;指8279状态端口
        MOVX A,@DPTR       ;读键盘标志
        ANL A,#07H         ;保留低3位，即检测8279FIFO按键缓冲区
;是否有数据，有按键按下就有数据
        JNZ KEYS           ;有键按下转
        dJNZ R4,dikRd      ;未完继续査
        MOV A,#20H         ;定义无键码
        RET                ;返回
KEYS:   MOV A, #40H
        MOVX @DPTR, A      ;读8279FIFORAM命令
MOV DPTR,#LED0             ;指向8279数据端口
        MOVX A,@DPTR       ;读当前键码
        MOV R2,A           ;存当前键码
        ANL A,#03H         ;保留低二位，即行值，共4行，行值从00-11
        xcH A,R2           ;取当前键码
        ANL A,#38H         ;舍弃无效位，取列值，共5列，列值从000-100
        RR A               ;键码的压缩，即键值由列值与行值组成，范围是00000-10011
        oRl A,R2           ;与低二拼接
        MOV DPTR,#GOJZ     ;指键码表首
        MOVc A,@A+DPTR     ;查键码值
        RET                ;返回
;-----------------------------------------------------------
;显示子程序
DISP:   MOV R1,#35H        ;从高位开始
        MOV 38H,#85H
DILEX:  MOV DPTR,#LED1     ;送字位代码
        MOV A,38H
        MOVX @DPTR,A
        MOV DPTR,#ZOE0     ;索字形代码
        MOV A,@R1
        MOVc A,@A+DPTR
        MOV DPTR,#LED0     ;送当前字形
        MOVX @DPTR,A
        DEC 38H
        DEC R1
        CJNE R1,#2fH,DILEX ;末满六位转
        RET

;-----------------------------------------------------------	
;------字形代码
ZOE0:   DB 0cH,9fH,4AH,0BH,99H,29H,28H,8fH,08H,09H,88H
;          0   1   2   3   4   5   6   7   8   9   A
        DB 38H,6cH,1AH,68H,0e8H,0ffH,0c0H
;          B   c   d   e   f    关闭  p.
;------按键代码(20H为溢出码)
GOJZ:   DB 20H,20H,11H,10H,20H,20H,20H,20H,20H,03H  ;对应按键f3,f2,f1,f0,d,c,B,A,e,3的键码
        DB 06H,09H,20H,02H,05H,08H,00H,01H,04H,07H   ;对应按键6,9,f,2,5,8,0,1,4,7的键码
        DB 20H,20H,20H,20H,20H,20H,20H,20H,20H,20H,20H,20H;无按键按下的键码
;------按键对应键值
;       0e0H,0e1H,0d9H,0d1H,0e2H,0dAH,0d2H,0e3H,0DBH,0d3H
;       0    1    2    3    4    5    6    7    8    9
;       0cBH,0cAH,0c9H,0c8H,0d0H,0d8H,0c3H,0c2H,0c1H,0c0H
;       A    B    c    d    e    f    10   11   12   13
;--------------------------------------------------------
;==========================END==============================


;===============ds18b20温度===================================
;结构参考https://blog.csdn.net/yannanxiu/article/details/43916515

;读取温度---------------------------------------------------
GET_TEMPER:
        SETB DQ         ;定时入口
BCD:    LCALL INIT_1820
        JB FLAG1,S22
        LJMP BCD        ;若DS18B20不存在则返回
S22:    LCALL DISP
        MOV A,#0CCH     ;跳过ROM匹配------0CC
        LCALL WRITE_1820
        MOV A,#44H      ;发出温度转换命令
        LCALL WRITE_1820
        NOP
        LCALL DISP
CBA:    LCALL INIT_1820
        JB FLAG1,ABC
        LJMP CBA
ABC:    LCALL DISP
        MOV A,#0CCH     ;跳过ROM匹配
        LCALL WRITE_1820
        MOV A,#0BEH     ;发出读温度命令
        LCALL WRITE_1820
        LCALL READ_18200
        RET
;-----------------------------------------------------------
;读写时序参考https://blog.csdn.net/yannanxiu/article/details/43916515文章末尾
;----------------------------------------------------------
;读DS18B20的程序,从DS18B20中读出一个字节的数据-----------------
READ_1820:
        MOV R2,#8
RE1:    CLR C
        SETB DQ
        NOP
        NOP
        CLR DQ
        NOP
        NOP
        NOP
        SETB DQ
        MOV R3,#8
        DJNZ R3,$
        MOV C,DQ
        MOV R3,#21
        DJNZ R3,$
        RRC A
        DJNZ R2,RE1
        RET
	
;写DS18B20的程序-----------------------------------------------
WRITE_1820:
        MOV R2,#8
        CLR C
WR1:    CLR DQ
        MOV R3,#5
        DJNZ R3,$
        RRC A
        MOV DQ,C
        MOV R3,#21
        DJNZ R3,$
        SETB DQ
        NOP
        DJNZ R2,WR1
        SETB DQ
        RET
	
;读DS18B20的程序,从DS18B20中读出两个字节的温度数据-------------------
READ_18200:
        MOV R4,#2            ;将温度高位和低位从DS18B20中读出
        MOV R1,#TEMPER_L     ;低位存入TEMPER_L,高位存TEMPER_H
RE00:   MOV R2,#8
RE01:   CLR C
        SETB DQ
        NOP
        NOP
        CLR DQ
        NOP
        NOP
        NOP
        SETB DQ
        MOV R3,#8
        DJNZ R3,$
        MOV C,DQ
        MOV R3,#21
        DJNZ R3,$
        RRC A
        DJNZ R2,RE01
        MOV @R1,A
        DEC R1
        DJNZ R4,RE00
        RET
	
;将从DS18B20中读出的温度数据进行转换--------------------------------
;（DS18B20出厂时分辨率被设置为12位精度）。高7位是整数值 低字节低4位是精度值
TEMPER_COV:
        MOV A,#0F0H
        ANL A,TEMPER_L  ;舍去温度低位中小数点后的四位温度数值
        SWAP A
        MOV TEMPER_NUM,A
        MOV A,TEMPER_L
        JNB ACC.3,TEMPER_COV1 ;四舍五入去温度值
        INC TEMPER_NUM
TEMPER_COV1:
        MOV A,TEMPER_H
        ANL A,#07H
        SWAP A
        ADD A,TEMPER_NUM
        MOV TEMPER_NUM,A ; 保存变换后的温度数据
        LCALL BIN_BCD
        RET
	
;将16进制的温度数据转换成压缩BCD码------------------------------------
BIN_BCD:MOV DPTR,#TEMP_TAB
        MOV A,TEMPER_NUM
        MOVC A,@A+DPTR
        MOV TEMPER_NUM,A
        RET
TEMP_TAB:
        DB 00H,01H,02H,03H,04H,05H,06H,07H
        DB 08H,09H,10H,11H,12H,13H,14H,15H
        DB 16H,17H,18H,19H,20H,21H,22H,23H
        DB 24H,25H,26H,27H,28H,29H,30H,31H
        DB 32H,33H,34H,35H,36H,37H,38H,39H
        DB 40H,41H,42H,43H,44H,45H,46H,47H
        DB 48H,49H,50H,51H,52H,53H,54H,55H
        DB 56H,57H,58H,59H,60H,61H,62H,63H
        DB 64H,65H,66H,67H,68H,69H,70H,71H
        DB 72H,73H,74H,75H,76H,77H,78H,79H
        DB 80H,81H,82H,83H,84H,85H,86H,87H
        DB 88H,89H,90H,91H,92H,93H,94H,95H
        DB 96H,97H,98H,99H
	
;DS18B20初始化程序----------------------------------------------
INIT_1820: 
		SETB DQ ;复位初始化子程序
		NOP
		CLR DQ
		MOV R1,#3;延时537US
TSR1: 	MOV R0,#107
		DJNZ R0,$
		DJNZ R1,TSR1
		SETB DQ;然后拉高数据线
		NOP
		NOP
		NOP
		MOV R0,#25H
TSR2: 	JNB DQ,TSR3;等待DS18B20回应
		DJNZ R0,TSR2
		LJMP TSR4;延时
TSR3: 	SETB FLAG1
		LJMP TSR5
TSR4: 	CLR FLAG1
		LJMP TSR7
TSR5: 	MOV R0,#70
TSR6: 	DJNZ R0,TSR6
TSR7: 	SETB DQ
		RET
;-----------------------------------------------------------
;重新写DS18B20暂存存储器设定值
RE_CONFIG:
        JB FLAG1,RE_CONFIG1 ;若DS18B20存在,转RE_CONFIG1
        RET

RE_CONFIG1:
        MOV A,#0CCH     ;发SKIP ROM命令
        LCALL WRITE_1820
        MOV A,#4EH      ;发写暂存存储器命令
        LCALL WRITE_1820

        MOV A,TH      ;TH(报警上限)中写入00H ;是按照Bcd码写入吗
        LCALL WRITE_1820
        MOV A,TL      ;TL(报警下限)中写入00H
        LCALL WRITE_1820
        MOV A,#7FH      ;选择12位温度分辨率
        LCALL WRITE_1820
        RET	 
;===================END=====================================


;============DAC0832 DA转换控制电机===========================
TEMP_CACHE:
      MOV A, TH
      CJNE A, TEMPER_NUM,NEX1  
NEX1: JC MAX			;大于最大值正转
      ;小于最大值和最小值比较
      MOV A, TL
      CJNE A, TEMPER_NUM,NEX2   
NEX2: JC MID                     ;小与最大值大于最小值，停转
      ;小与等于最小值反转
 
;小于最小值反转电机工作灯亮
MIN:
      MOV DPTR,#DAC0832;dAc8032输入地址
      MOV A,#00H;-5v
      MOVX @DPTR,A
      CLR P3.2;灯亮
      LJMP EXT
;中间值停下来
MID:
      MOV DPTR,#DAC0832
      MOV A,#07FH;0v
      MOVX @DPTR,A
      SETB P3.2
      LJMP EXT
;最大值正转
MAX:
      MOV DPTR,#DAC0832
      MOV A,#0FFH;+5v
      MOVX @DPTR,A
      SETB P3.2
EXT:  RET

;===================END===================================



;=============更新单片机缓存内容============================
;刷新显示缓存内容：最高值、最低值、当前值
NEW_CACHE:	 
	 MOV A,TEMPER_NUM
	 MOV B,A
	 SWAP A
	 ANL A,#0fH
	 ANL B,#0fH
	 MOV LEDBUFF,B
	 MOV LEDBUFF+1,A
	 MOV A,TL
	 MOV B,A
	 SWAP A
	 ANL A,#0fH
	 ANL B,#0fH
	 MOV LEDBUFF+2,B
	 MOV LEDBUFF+3,A
	 MOV A,TH
	 MOV B,A
	 SWAP A
	 ANL A,#0fH
	 ANL B,#0fH
	 MOV LEDBUFF+4,B
	 MOV LEDBUFF+5,A
	 RET
;=============END=======================================
END

