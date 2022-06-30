;Universidade Federal de Alagoas
;Instituto de Computação
;Microcontroladores e Aplicações
;Alunos: Aldemir Melo Rocha Filho, Darlysson Olímpio Nascimento, Sandoval da Silva Almeida Junior, Tayco Murilo Santos Rodrigues
;Professor: Erick Barboza
;Período: 2021.2


;representação do semáforo:

	;## Usamos duas portas para controle, PORTD e PORTB ##
	;PORTD é usada para alimentar os barramentos das cores do semáforo e o chaveamento dos mesmos.
	;PORTB é usada para alimentar os dois displays de 7 segmentos, o chaveamentos dos mesmos 
	;e para enviar o valor a ser exibido para o decodificador.


.def temp = r16     ;definimos o registrador 16 como temp (variável que armazena um valor temporário)
.def saida = r17    ;definimos o registrador 17 como saida (variável que armazena o vetor de cotrole do semáforo)
.def count = r18	;definimos o registrador 18 como count (variável que vai armazenar a duração do estado)
.def unidade = r19  ;definimos o registrador 19 como unidade (variável que vai armazenar o valor numérico a ser exibido no display de unidade)
.def dezena = r20	;definimos o registrador 20 como dezena (variável que vai armazenar o valor numérico a ser exibido no display de dezena)

;Setando o vetor de interrupção
.cseg 				;flash
jmp reset			
.org OC1Aaddr		; A próxima prosição de memória vai ser a da interrupção OC!Aaddr
jmp OCI1A_Interrupt	; Dentro dessa posição de memória temos um jump para o tratamento que vai ser realizado quando ela ocorrer

OCI1A_Interrupt:

	;Salvamos o contexto do conteúdo do registrador 16
	push r16   
	in r16, SREG   
	push r16
	
	;A cada interrupção diminuimos em 1 segundo o tempo que vamos passar no estado atual
	subi count, 1
	; A cada interrupção aumentamos o valor a ser exibido no display de unidade em 1
	inc unidade

	;Restauramos o contexto do conteúdo do registrador 16
	pop r16
	out SREG, r16
	pop r16

	;Caso o valor da unidade seja 10 teremos um desvio para a label overflow
	cpi unidade, 0b00011010
	breq overflow

	reti  ;retornamos para a rotina principal
	overflow:
		;dentro do tratamento de overflow, faremos a unidade voltar a 0 e incrementamos o valor da dezena em 1
		ldi unidade, 0b00010000
		inc dezena	
		reti ;retornamos para a rotina principal

;Definimos um delay de 0.001 segundos para ser usado na rotina principal do programa
.equ ClockMHz = 16
.equ DelayMs = 1
Delay:
	ldi r23, byte3(ClockMHz * 1000 * DelayMs / 5)
	ldi r22, high(ClockMHz * 1000 * DelayMs / 5)
	ldi r21, low(ClockMHz * 1000 * DelayMs / 5)

	subi r21, 1
	sbci r22, 0
	sbci r23, 0

	brcc pc-3
			
	ret

;Rotina principal do programa
reset:
	;pilha iniciando no final da RAM
	ldi temp, low(RAMEND)
	out SPL, temp
	ldi temp, high(RAMEND)
	out SPH, temp
	
	;Configurando timer e depois interrupção a cada 1 segundo
	#define CLOCK 16.0e6 ;clock do Arduino UNO
	#define DELAY 1 ; Definimos o intervalo entre as interrupções para 1 segundo

	.equ PRESCALE = 0b100 ; Valor que deve ser definido no clock select para definir que se utilizará o clock que será definido pelo clock com preescale.
	.equ PRESCALE_DIV = 256 ; O prescale para se contar 1 segundo com um clock de 16 mhz é de 256
	.equ WGM = 0b0100 ; Waveform Generation Mode: CTC (Clear time and compare) -> Utilizaremos o modo 4, que usará como top o valor em OCR1A
	.equ TOP = int(0.5 + ((CLOCK/PRESCALE_DIV)*DELAY)) ; cálculo do top. O 0.5 vai garantir um inteiro acima da divisão dada
	.if TOP > 65535
	.error "TOP is out of range"
	.endif
	
	; Inicializando o valor de comparação (TOP). Para configurar o top, tem que se colocar no OCR1A. Carregamos o TOP nos 16 bits desse registrador:
	ldi temp, high(TOP) 
	sts OCR1AH, temp
	;Carregando o WGM nos seus respectivos registradores:
	ldi temp, low(TOP)
	sts OCR1AL, temp
	ldi temp, ((WGM&0b11) << WGM10) ;Fazendo AND com 1 do WGM (WGM&0b11 = 0b0100 & 0b001 = 0b0000) e depois desloca do WGM10 (valor 0 no 328p, mas garante compatibilidade com outros micros)
	sts TCCR1A, temp ;Carregamos os bits menos significados do WGM nos bits menos significativos do TCCR1A. Nesse caso é carregado apenas o 0
	;Tomando os dois bits mais significativos do WGM  e definindo o bit do clock select:
	ldi temp, ((WGM>> 2) << WGM12)|(PRESCALE << CS10) ;Desloca-se de 2 do WGM (WGM >> 2 = 0b0100 >> 2 = 0b0001) depois desloca WGM12 (3), o que nos dá 0b0001 << 3 = 0b0001000.
	; Depois é feito um OU com o PRESCALE deslocado de CS10 (vale 0), que resulta no próprio PRESCALE. O OU resulta em 0b000100 | 0b100 = 0b0001100
	; Jogando isso no TCCR1B, definimos o clock select para 100 (nos menos sig. define o prescale) e o bit 01 (mais sig.) para o WGM no nesse registrador
	sts TCCR1B, temp ;Configuração do contador definida. Então temos TCCR1A com seus bits do WGM setados, assim como o TCCR1B
	
	lds r16, TIMSK1 ;carregamos o espaço de dados de  timer counter 1 interrupt mask register
	sbr r16, 1 <<OCIE1A ; habilitamos a interrupção de match com o valor do canal A. OCIEA vale um no TMSK1, então deslocamos de 1 para corresponder a esse campo. 
	;O sbr faz uma troca de bits, evitando a alteração dos outros bits de TIMSK1, só mudando o bit 1 desse registrador.
	sts TIMSK1, r16 ;Salvamos esse valor novo, que foi deslocado, no TIMSK1
	; Com isso, o timer/counter está configurado para dar match/overflow a cada 1s através do valor de TOP definido no OCR1A, tratando a em OCI1A_Interrupt
	
	;Definimos toda a PORTD como saída
	ldi temp, 0b11111111
	out DDRD, temp

	;Definimos os 6 primeiros pinos de PORTB como saída
	ldi temp, 0b00111111
	out DDRB, temp

	;Ligando a flag de interrupção
	sei
	
/*	bits:     ##### | ### 
		semaforos Cores:
		10000(s1) | 001 (Vermelho)
		01000(s2) | 010 (Amarelo)
		00100(s3) | 100 (Verde)
		00010(s4)
		00001(sP)	*/		

	s1: ;label que representa o estado 1	
		ldi count, 18; tempo que vamos pasar dentro do estado 1

		ldi unidade, 0b00010000; iniciamos o valor da unidade do contador em 0
		ldi dezena,  0b00100000 ; iniciamos o valor da dezena do contador em 0

		;rotina do estado 1
		s1_routine:

			cpi count, 0 ; Caso o contador seja 0 --> O tempo que passamos aqui acabou --> vamos para o próximo estado
			breq s2		 ; Desvio condicional para a label do próximo estado  
			
			;Enviamos os vetores de controle para os 5 semáforos com delay de 0.001 segundos
			 
			ldi saida, 0b10000001 
			out PORTD, saida
			rcall Delay

			ldi saida, 0b01000001
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00100001 
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00010001 
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00001100
			out PORTD, saida
			rcall Delay

			;Enviamos os vetores de controle para os 2 displays com delay de 0.001 segundos 
			out PORTB, unidade
			rcall Delay
			out PORTB, dezena
			rcall Delay

			;retornamos para a rotina do estado 1
			rjmp s1_routine		
		
	s2:	;label que representa o estado 2
		ldi count, 5 ;tempo que vamos pasar dentro do estado 2

		ldi unidade, 0b00010000; iniciamos o valor da unidade do contador em 0
		ldi dezena, 0b00100000 ; iniciamos o valor da dezena do contador em 0

		;rotina do estado 2
		s2_routine:

			cpi count, 0 ;Caso o contador seja 0 --> O tempo que passamos aqui acabou --> vamos para o próximo estado
			breq s3		 ; Desvio condicional para a label do próximo estado  
			
			;Enviamos os vetores de controle para os 5 semáforos com delay de 0.001 segundos  
			ldi saida, 0b10000001 
			out PORTD, saida
			rcall Delay

			ldi saida, 0b01000001
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00100001 
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00010001
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00001001
			out PORTD, saida
			rcall Delay

			;Enviamos os vetores de controle para os 2 displays com delay de 0.001 segundos
			out PORTB, unidade
			rcall Delay
			out PORTB, dezena
			rcall Delay

			;retornamos para a rotina do estado 2
			rjmp s2_routine
	
	s3:	;label que representa o estado 3
		ldi count, 20 ;tempo que vamos pasar dentro do estado 3

		ldi unidade, 0b00010000; iniciamos o valor da unidade do contador em 0
		ldi dezena, 0b00100000 ; iniciamos o valor da dezena do contador em 0

		;rotina do estado 3
		s3_routine:
			cpi count, 0 ;Caso o contador seja 0 --> O tempo que passamos aqui acabou --> vamos para o próximo estado
			breq s4      ; Desvio condicional para a label do próximo estado  
			 
			;Enviamos os vetores de controle para os 5 semáforos com delay de 0.001 segundos 
			ldi saida, 0b10000001 
			out PORTD, saida
			rcall Delay

			ldi saida, 0b01000100
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00100100 
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00010001
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00001001
			out PORTD, saida
			rcall Delay

			;Enviamos os vetores de controle para os 2 displays com delay de 0.001 segundos 
			out PORTB, unidade
			rcall Delay
			out PORTB, dezena
			rcall Delay

			;retornamos para a rotina do estado 3
			rjmp s3_routine
		
	s4:	;label que representa o estado 4
		ldi count, 4 ;tempo que vamos pasar dentro do estado 4

		ldi unidade, 0b00010000; iniciamos o valor da unidade do contador em 0
		ldi dezena, 0b00100000 ; iniciamos o valor da dezena do contador em 0

		;rotina do estado 4
		s4_routine:
			cpi count, 0 ;Caso o contador seja 0 --> O tempo que passamos aqui acabou --> vamos para o próximo estado
			breq s5      ;Desvio condicional para a label do próximo estado  
			
			;Enviamos os vetores de controle para os 5 semáforos com delay de 0.001 segundos 
			ldi saida, 0b10000001 
			out PORTD, saida
			rcall Delay

			ldi saida, 0b01000010
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00100100 
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00010001
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00001001
			out PORTD, saida
			rcall Delay

			;Enviamos os vetores de controle para os 2 displays com delay de 0.001 segundos 
			out PORTB, unidade
			rcall Delay
			out PORTB, dezena
			rcall Delay

			;retornamos para a rotina do estado 4
			rjmp s4_routine

	s5:	;label que representa o estado 5
		ldi count, 53 ;tempo que vamos pasar dentro do estado 5

		ldi unidade, 0b00010000; iniciamos o valor da unidade do contador em 0
		ldi dezena, 0b00100000 ; iniciamos o valor da dezena do contador em 0

		;rotina do estado 5
		s5_routine:
			cpi count, 0 ;Caso o contador seja 0 --> O tempo que passamos aqui acabou --> vamos para o próximo estado
			breq s6      ;Desvio condicional para a label do próximo estado  
			
			;Enviamos os vetores de controle para os 5 semáforos com delay de 0.001 segundos 
			ldi saida, 0b10000001 
			out PORTD, saida
			rcall Delay

			ldi saida, 0b01000001
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00100100 
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00010100
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00001001
			out PORTD, saida
			rcall Delay

			;Enviamos os vetores de controle para os 2 displays com delay de 0.001 segundos 
			out PORTB, unidade
			rcall Delay
			out PORTB, dezena
			rcall Delay

			;retornamos para a rotina do estado 5
			rjmp s5_routine
			
	s6:	;label que representa o estado 6
		ldi count, 4 ;tempo que vamos pasar dentro do estado 6

		ldi unidade, 0b00010000; iniciamos o valor da unidade do contador em 0
		ldi dezena, 0b00100000 ; iniciamos o valor da dezena do contador em 0

		;rotina do estado 6
		s6_routine:
			cpi count, 0;Caso o contador seja 0 --> O tempo que passamos aqui acabou --> vamos para o próximo estado
			breq s7     ;Desvio condicional para a label do próximo estado  
			
			;Enviamos os vetores de controle para os 5 semáforos com delay de 0.001 segundos 
			ldi saida, 0b10000001 
			out PORTD, saida
			rcall Delay

			ldi saida, 0b01000001
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00100010 
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00010010
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00001001
			out PORTD, saida
			rcall Delay

			;Enviamos os vetores de controle para os 2 displays com delay de 0.001 segundos 
			out PORTB, unidade
			rcall Delay
			out PORTB, dezena
			rcall Delay

			;retornamos para a rotina do estado 6
			rjmp s6_routine
		
	s7:	;label que representa o estado 7
		ldi count, 19 ;tempo que vamos pasar dentro do estado 7

		ldi unidade, 0b00010000; iniciamos o valor da unidade do contador em 0
		ldi dezena, 0b00100000 ; iniciamos o valor da dezena do contador em 0

		;rotina do estado 7
		s7_routine:
			cpi count, 0 ; Caso o contador seja 0 --> O tempo que passamos aqui acabou --> vamos para o próximo estado
			breq s8      ; Desvio condicional para a label do próximo estado  
			
			;Enviamos os vetores de controle para os 5 semáforos com delay de 0.001 segundos 
			ldi saida, 0b10000100 
			out PORTD, saida
			rcall Delay

			ldi saida, 0b01000001
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00100001 
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00010001
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00001001
			out PORTD, saida
			rcall Delay

			;Enviamos os vetores de controle para os 2 displays com delay de 0.001 segundos 
			out PORTB, unidade
			rcall Delay
			out PORTB, dezena
			rcall Delay

			;retornamos para a rotina do estado 7
			rjmp s7_routine

	aux:		;label auxiliar para conseguir ir do estado 8 para o estado 1
		jmp s1	;jump para o estado 1
			
	s8:	;label que representa o estado 8
		ldi count, 4 ;tempo que vamos passar dentro do estado 8

		ldi unidade, 0b00010000; iniciamos o valor da unidade do contador em 0
		ldi dezena, 0b00100000 ; iniciamos o valor da dezena do contador em 0

		;rotina do estado 8
		s8_routine:
			cpi count, 0 ; Caso o contador seja 0 --> O tempo que passamos aqui acabou --> vamos para o próximo estado
			breq aux     ; Desvio condicional para a label do próximo estado
			
			;Enviamos os vetores de controle para os 5 semáforos com delay de 0.001 segundos 
			ldi saida, 0b10000010 
			out PORTD, saida
			rcall Delay

			ldi saida, 0b01000001
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00100001 
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00010001
			out PORTD, saida
			rcall Delay

			ldi saida, 0b00001001
			out PORTD, saida
			rcall Delay

			;Enviamos os vetores de controle para os 2 displays com delay de 0.001 segundos 
			out PORTB, unidade
			rcall Delay
			out PORTB, dezena
			rcall Delay

			;retornamos para a rotina do estado 8
			rjmp s8_routine	
