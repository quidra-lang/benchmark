LF =: 10{a.
FormatNames =: ;:'HALF E5M2 E4M3'
Formats =: x:3 2$5 10 5 2 4 3
Modes =: ;:'RNE RNA RTZ RUP RDN'
Types =: ;:'I8 U8 I16 U16 I32 U32'
Limits =: 6 2$_128x 127x 0x 255x _32768x 32767x 0x 65535x _2147483648x 2147483647x 0x 4294967295x
FlagNames =: ;:'invalid divbyzero overflow underflow inexact'
NoFlags =: 5#0
Error =: ''
div =: <.@%
split =: 4 : '<;._1 x,y'
number =: 3 : 0
    text =. ,'0' 8!:2 |y
    if. y<0 do. '-',text else. text end.
)
join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do. text =. text,x end.
        text =. text,i{::y
    end.
    text
)
words =: 3 : 0
    parts =. 0$a:
    for_part. y do.
        part =. >part
        if. 2~:3!:0 part do. part =. number part end.
        parts =. parts,<part
    end.
    ' ' join parts
)
emit =: 3 : '(y,LF) 1!:2 4'
say =: 3 : 'emit words y'
fail =: 3 : 0
    Error =: y
    throw.
)
flag_text =: 3 : 0
    names =. (I.y){FlagNames
    if. #names do. 'flags=',',' join names else. 'flags=none' end.
)
mode_index =: 3 : 0
    index =. Modes i.<y
    if. index=#Modes do. fail 'BAD MODE ',y end.
    index
)
format_index =: 3 : 0
    index =. FormatNames i.<y
    if. index=#FormatNames do. fail 'UNKNOWN FORMAT ',y end.
    index
)
use_format =: 3 : 0
    'EBits MBits' =: y{Formats
    Width =: 1+EBits+MBits
    Bias =: (2x^(EBits-1))-1
    Emin =: 1-Bias
    Emax =: Bias
    Hidden =: 2x^MBits
    ExponentMask =: (2x^EBits)-1
    SignBit =: 2x^(EBits+MBits)
    Infinity =: ExponentMask*Hidden
    Quiet =: Infinity+Hidden div 2
    Maximum =: Infinity-1
)
fields =: 3 : 0
    sign =. y div SignBit
    exponent =. (ExponentMask+1)|y div Hidden
    fraction =. Hidden|y
    q =. Emin
    if. exponent do. q =. exponent-Bias end.
    sign,exponent,fraction,q-MBits
)
is_nan =: 3 : '(ExponentMask=1{fields y)*.0~:Hidden|y'
is_signaling =: 3 : '(is_nan y)*.(Hidden|y)<Hidden div 2'
is_infinity =: 3 : 'Infinity=SignBit|y'
is_zero =: 3 : '0=SignBit|y'
is_finite =: 3 : 'ExponentMask~:1{fields y'
flip =: 3 : 'y+SignBit*1-2*(y div SignBit)'
exact_pattern =: 3 : 0
    'sign exponent fraction q' =. fields y
    (fraction+Hidden*exponent~:0),1x,q,sign
)
binary =: 4 : '''01''{~(x#2)#:y'
bit_text =: 3 : 0
    'sign exponent fraction q' =. fields y
    (number sign),'|',(EBits binary exponent),'|',MBits binary fraction
)
hex_text =: 3 : '''0x'',''0123456789ABCDEF''{~(((Width+3) div 4)#16)#:y'

scale =: 4 : 0
    'n d exponent sign' =. y
    shift =. exponent-x
    if. shift>:0 do. n =. n*2x^shift
    else. d =. d*2x^-shift end.
    n,d
)
negate =: 3 : '(1-3{y) (3}) y'
exact_product =: 4 : '((0{x)*0{y),((1{x)*1{y),((2{x)+2{y),(3{x)~:3{y'
exact_sum =: 4 : 0
    nonzero =. (0~:0{"1 y)#y
    if. 0=#nonzero do.
        signs =. 3{"1 y
        sign =. x=4
        if. *./signs={.signs do. sign =. {.signs end.
        0x,1x,0x,sign return.
    end.
    exponent =. <./2{"1 nonzero
    total =. +/((1-2*3{"1 nonzero)*0{"1 nonzero)*2x^(2{"1 nonzero)-exponent
    sign =. total<0
    if. total=0 do. sign =. x=4 end.
    (|total),1x,exponent,sign
)
fraction_text =: 3 : 0
    if. 0=0{y do. '0' return. end.
    'n d' =. 0 scale y
    common =. n+.d
    n =. n div common
    d =. d div common
    text =. number n
    if. d~:1 do. text =. text,'/',number d end.
    if. 3{y do. text =. '-',text end.
    text
)
decimal_text =: 4 : 0
    'n d' =. 0 scale y
    text =. number n div d
    remainder =. d|n
    if. remainder do.
        text =. text,'.'
        while. remainder do.
            remainder =. 10x*remainder
            text =. text,number remainder div d
            remainder =. d|remainder
        end.
    end.
    if. (3{y)*.(x+.0~:0{y) do. text =. '-',text end.
    text
)
value_text =: 3 : 0
    if. is_nan y do. 'nan'
    elseif. is_infinity y do. ((y div SignBit)#'-'),'inf'
    else. 1 decimal_text exact_pattern y end.
)
pattern_text =: 3 : '(bit_text y),'' '',(hex_text y),'' '',value_text y'
result_text =: 3 : '(pattern_text {.y),'' '',flag_text }.y'
binary_order =: 3 : 0
    order =. _1
    while. y>0 do.
        y =. y div 2
        order =. order+1
    end.
    order
)
log_floor =: 3 : 0
    order =. ((binary_order 0{y)-binary_order 1{y)+2{y
    'n d' =. order scale y
    order-n<d
)
integer_sqrt =: 3 : 0
    if. y=0 do. 0x return. end.
    root =. 1x
    while. (root*root)<:y do. root =. 2x*root end.
    while. 1 do.
        next =. (root+y div root) div 2
        if. next>:root do. root return. end.
        root =. next
    end.
)
increment =: 3 : 0
    'mode sign integer inexact midpoint' =. y
    if. -.inexact do. 0 return. end.
    select. mode
    case. 0 do. (midpoint>0)+.(midpoint=0)*.2|integer
    case. 1 do. midpoint>:0
    case. 3 do. sign=0
    case. 4 do. sign=1
    case. do. 0
    end.
)
round_units =: 3 : 0
    'value exponent mode square_root' =. y
    if. square_root do.
        'n d' =. (2*exponent) scale value
        integer =. integer_sqrt n div d
        inexact =. n~:d*integer*integer
        midpoint =. (4x*n)-d*(1+2x*integer)^2
    else.
        'n d' =. exponent scale value
        integer =. n div d
        remainder =. d|n
        inexact =. remainder~:0
        midpoint =. (2x*remainder)-d
    end.
    integer =. integer+increment mode,(3{value),integer,inexact,midpoint
    integer,inexact
)
overflow =: 4 : 0
    infinite =. (x e.0 1)+.((x=3)*.y=0)+.(x=4)*.y=1
    ((y*SignBit)+infinite{Maximum,Infinity),0 0 1 0 1
)
round_exact =: 3 : 0
    'value mode square_root' =. y
    'n d exponent sign' =. value
    if. n=0 do. (sign*SignBit),NoFlags return. end.
    t =. log_floor value
    if. square_root do. t =. t div 2 end.
    if. t>Emax do. mode overflow sign return. end.
    q =. (t>.Emin)-MBits
    'units inexact' =. round_units value;q;mode;square_root
    if. units=2*Hidden do.
        units =. Hidden
        q =. q+1
    end.
    if. q>Emax-MBits do. mode overflow sign return. end.
    magnitude =. units
    if. units>:Hidden do. magnitude =. ((q+MBits+Bias)*Hidden)+units-Hidden end.
    tiny =. 0
    if. inexact*.t<Emin do.
        tiny =. 1
        if. t=Emin-1 do.
            unbounded =. {.round_units value;(t-MBits);mode;square_root
            tiny =. unbounded<2*Hidden
        end.
    end.
    ((sign*SignBit)+magnitude),0,0,0,tiny,inexact
)
round_value =: 4 : 'round_exact y;x;0'
parse_real =: 3 : 0
    if. y-:'nan' do. 2x,0x,1x,0x,0x return. end.
    if. (<y)e.'inf';'-inf' do. 1x,0x,1x,0x,('-'={.y) return. end.
    if. (<2{.y)e.'0b';'0x' do. fail 'BAD OPERAND ',y end.
    sign =. '-'={.y
    body =. sign}.y
    if. '/'e.body do.
        parts =. '/' split body
        n =. x:0".0{::parts
        d =. x:0".1{::parts
        if. d=0 do. fail 'BAD OPERAND ',y end.
    else.
        parts =. '.' split body
        n =. x:0".;parts
        d =. 1x
        if. 2=#parts do. d =. 10x^#1{::parts end.
    end.
    0x,n,d,0x,sign
)
encode_real =: 4 : 0
    select. {.y
    case. 1 do. (Infinity+SignBit*{:y),NoFlags
    case. 2 do. Quiet,NoFlags
    case. do. x round_value }.y
    end.
)
operand =: 3 : 0
    if. '0b'-:2{.y do.
        if. Width~:(#y)-2 do. fail 'BAD OPERAND ',y end.
        2x#.'01'i.2}.y
    elseif. '0x'-:2{.y do.
        pattern =. 16x#.'0123456789ABCDEF'i.2}.y
        if. (((Width+3) div 4)~:(#y)-2)+.pattern>:2*SignBit do. fail 'BAD OPERAND ',y end.
        pattern
    else. {.0 encode_real parse_real y end.
)
operands =: 3 : 0
    patterns =. 0$0x
    for_word. y do. patterns =. patterns,operand >word end.
    patterns
)
invalid_result =: 3 : 'Quiet,1 0 0 0 0'
operation =: 3 : 0
    'command mode patterns' =. y
    a =. 0{patterns
    if. command-:'SUB' do.
        operation 'ADD';mode;(a,flip 1{patterns) return.
    end.
    if. +./is_nan"0 patterns do. Quiet,(+./is_signaling"0 patterns),0 0 0 0 return. end.
    if. command-:'SQRT' do.
        if. is_zero a do. a,NoFlags return. end.
        if. a div SignBit do. invalid_result'' return. end.
        if. is_infinity a do. a,NoFlags return. end.
        round_exact (exact_pattern a);mode;1 return.
    end.
    b =. 1{patterns
    sigma =. (a div SignBit)~:b div SignBit
    if. command-:'ADD' do.
        if. (is_infinity a)*.(is_infinity b)*.sigma do. invalid_result'' return. end.
        if. is_infinity a do. a,NoFlags return. end.
        if. is_infinity b do. b,NoFlags return. end.
        mode round_value mode exact_sum exact_pattern"0 patterns return.
    elseif. command-:'MUL' do.
        if. (is_infinity a)+.is_infinity b do.
            if. (is_zero a)+.is_zero b do. invalid_result''
            else. (Infinity+SignBit*sigma),NoFlags end. return.
        end.
        if. (is_zero a)+.is_zero b do. (SignBit*sigma),NoFlags return. end.
        mode round_value (exact_pattern a) exact_product exact_pattern b return.
    elseif. command-:'DIV' do.
        if. is_infinity a do.
            if. is_infinity b do. invalid_result'' else. (Infinity+SignBit*sigma),NoFlags end. return.
        end.
        if. is_infinity b do. (SignBit*sigma),NoFlags return. end.
        if. is_zero b do.
            if. is_zero a do. invalid_result'' else. (Infinity+SignBit*sigma),0 1 0 0 0 end. return.
        end.
        if. is_zero a do. (SignBit*sigma),NoFlags return. end.
        left =. exact_pattern a
        right =. exact_pattern b
        mode round_value (0{left),(0{right),((2{left)-2{right),sigma return.
    end.
    c =. 2{patterns
    if. (is_infinity a)+.is_infinity b do.
        if. (is_zero a)+.(is_zero b)+.(is_infinity c)*.sigma~:c div SignBit do. invalid_result''
        else. (Infinity+SignBit*sigma),NoFlags end. return.
    end.
    if. is_infinity c do. c,NoFlags return. end.
    product =. (exact_pattern a) exact_product exact_pattern b
    mode round_value mode exact_sum product,:exact_pattern c
)
next_up =: 3 : 0
    if. y=Infinity do. y
    elseif. is_zero y do. 1x
    else. y+1-2*(y div SignBit) end.
)
order_key =: 3 : 0
    if. y<SignBit do. y else. (SignBit-y)-1 end.
)
relation =: 4 : 0
    if. x<y do. 'LT' elseif. x>y do. 'GT' else. 'EQ' end.
)
difference =: 4 : 0
    if. -.is_finite x do. value_text x
    else. fraction_text 0 exact_sum (exact_pattern x),:negate y end.
)
summary =: 3 : 0
    'mode patterns result' =. y
    exact =. mode exact_sum exact_pattern"0 patterns
    emit 'RESULT ',result_text result
    emit 'EXACT ',0 decimal_text exact
    emit 'ROUNDED ',result_text mode round_value exact
    emit 'DIFF ',({.result) difference exact
)
summation =: 3 : 0
    'command name mode patterns' =. y
    if. -. *./is_finite"0 patterns do. fail 'NOT FINITE' end.
    emit (words command;name;(mode{::Modes)),' count=',number #patterns
    sum =. {.patterns
    compensation =. 0x
    flags =. NoFlags
    for_i. }.i.#patterns do.
        if. command-:'SUM' do.
            result =. operation 'ADD';mode;(sum,i{patterns)
            sum =. {.result
            flags =. flags+.}.result
            say 'PARTIAL';(i+1);result_text result
        else.
            yvalue =. operation 'SUB';mode;((i{patterns),compensation)
            tvalue =. operation 'ADD';mode;(sum,{.yvalue)
            dvalue =. operation 'SUB';mode;(({.tvalue),sum)
            cvalue =. operation 'SUB';mode;(({.dvalue),{.yvalue)
            sum =. {.tvalue
            compensation =. {.cvalue
            step =. (}.yvalue)+.(}.tvalue)+.(}.dvalue)+.}.cvalue
            flags =. flags+.step
            emit 'KSTEP ',(number i+1),' sum=',(value_text sum),' comp=',(value_text compensation),' ',flag_text step
        end.
    end.
    summary mode;patterns;(sum,flags)
)
dot_product =: 3 : 0
    'name mode a b' =. y
    if. (#a)~:#b do. fail 'LENGTH MISMATCH' end.
    if. -. *./is_finite"0 a,b do. fail 'NOT FINITE' end.
    naive =. operation 'MUL';mode;(({.a),{.b)
    chained =. naive
    for_i. }.i.#a do.
        product =. operation 'MUL';mode;((i{a),i{b)
        added =. operation 'ADD';mode;(({.naive),{.product)
        naive =. ({.added),(}.naive)+.(}.product)+.}.added
        fused =. operation 'FMA';mode;((i{a),(i{b),{.chained)
        chained =. ({.fused),(}.chained)+.}.fused
    end.
    terms =. 0 4$0x
    for_i. i.#a do. terms =. terms,(exact_pattern i{a) exact_product exact_pattern i{b end.
    exact =. mode exact_sum terms
    emit (words 'DOT';name;(mode{::Modes)),' n=',number #a
    emit 'NAIVE ',result_text naive
    emit 'CHAINED ',result_text chained
    emit 'EXACT ',0 decimal_text exact
    emit 'FUSED ',result_text mode round_value exact
    emit 'DIFF naive=',(({.naive) difference exact),' chained=',({.chained) difference exact
)
table_output =: 3 : 0
    if. Width>8 do. fail 'TABLE TOO LARGE' end.
    emit 'TABLE ',y,' count=',number Infinity
    for_i. i.Infinity do.
        gap =. '-'
        if. i<Maximum do. gap =. 0 decimal_text 0 exact_sum (exact_pattern i+1),:negate exact_pattern i end.
        emit 'ENTRY ',(number i),' ',(pattern_text i),' gap=',gap
    end.
    emit 'MAX ',pattern_text Maximum
    emit 'MINNORMAL ',pattern_text Hidden
    emit 'MINSUBNORMAL ',pattern_text 1
    emit 'EPSILON ',0 decimal_text 1x,1x,(-MBits),0x
    emit 'PATTERNS finite=',(number 2*Infinity),' infinite=2 nan=',(number 2*Hidden-1),' total=',number 2*SignBit
)

command =: 3 : 0
    tokens =. ' ' split y
    op =. 0{::tokens
    name =. 1{::tokens
    if. op-:'FORMAT' do.
        if. (<name)e.FormatNames do. fail 'FORMAT EXISTS ',name end.
        e =. x:0".2{::tokens
        m =. x:0".3{::tokens
        if. (e<2)+.(e>5)+.(m<1)+.m>10 do. fail 'BAD FORMAT' end.
        index =. #FormatNames
        FormatNames =: FormatNames,<name
        Formats =: Formats,e,m
        use_format index
        emit 'FORMAT ',name,' e=',(number e),' m=',(number m),' bits=',(number Width),' bias=',(number Bias),' emin=',(number Emin),' emax=',number Emax
        return.
    end.
    active =. format_index name
    use_format active
    select. op
    case. 'ENCODE' do.
        real =. parse_real 2{::tokens
        mode =. 0
        if. 3<#tokens do. mode =. mode_index 3{::tokens end.
        if. 0={.real do. text =. fraction_text }.real else. text =. 2{::tokens end.
        say 'ENCODE';name;(mode{::Modes);text;result_text mode encode_real real
    case. 'CONVERT' do.
        target =. format_index 2{::tokens
        a =. operand 3{::tokens
        mode =. 0
        if. 4<#tokens do. mode =. mode_index 4{::tokens end.
        nan =. is_nan a
        signaling =. is_signaling a
        infinite =. is_infinity a
        value =. exact_pattern a
        use_format target
        if. nan do. result =. Quiet,signaling,0 0 0 0
        elseif. infinite do. result =. (Infinity+SignBit*3{value),NoFlags
        else. result =. mode round_value value end.
        say 'CONVERT';name;(target{::FormatNames);(mode{::Modes);result_text result
    case. 'SUM';'KAHAN';'DOT' do.
        mode =. mode_index 2{::tokens
        if. op-:'DOT' do.
            separator =. tokens i.<'|'
            a =. operands 3}.separator{.tokens
            b =. operands (separator+1)}.tokens
            dot_product name;mode;a;b
        else. summation op;name;mode;operands 3}.tokens end.
    case. 'TABLE' do. table_output name
    case. 'ADD';'SUB';'MUL';'DIV';'SQRT';'FMA' do.
        count =. 2
        if. op-:'SQRT' do. count =. 1 elseif. op-:'FMA' do. count =. 3 end.
        patterns =. operands count{.2}.tokens
        mode =. 0
        if. (#tokens)>count+2 do. mode =. mode_index (count+2){::tokens end.
        say op;name;(mode{::Modes);result_text operation op;mode;patterns
    case. do.
        a =. operand 2{::tokens
        'sign exponent fraction q' =. fields a
        select. op
        case. 'DECODE' do.
            if. is_nan a do. class =. (is_signaling a){::'qnan';'snan'
            elseif. is_infinity a do. class =. 'infinity'
            elseif. is_zero a do. class =. 'zero'
            elseif. exponent=0 do. class =. 'subnormal'
            else. class =. 'normal' end.
            emit (words 'DECODE';name;(bit_text a);(hex_text a);class),' sign=',number sign
            text =. 'FIELDS exponent=',(number exponent),' fraction=',number fraction
            if. is_finite a do.
                emit text,' unbiased=',(number q+MBits),' significand=',(number exponent~:0),'.',MBits binary fraction
                say 'VALUE';(fraction_text exact_pattern a);value_text a
            else.
                if. is_nan a do. text =. text,' payload=',number (Hidden div 2)|fraction end.
                emit text
            end.
        case. 'COMPARE' do.
            b =. operand 3{::tokens
            total =. (order_key a) relation order_key b
            numeric =. total
            if. (is_nan a)+.is_nan b do. numeric =. 'UN'
            elseif. (is_zero a)*.is_zero b do. numeric =. 'EQ' end.
            flags =. ((is_signaling a)+.is_signaling b),0 0 0 0
            say 'COMPARE';name;(hex_text a);(hex_text b);numeric;('total=',total);flag_text flags
        case. 'TOINT' do.
            type =. 3{::tokens
            index =. Types i.<type
            if. index=#Types do. fail 'BAD TYPE ',type end.
            mode =. 0
            if. 4<#tokens do. mode =. mode_index 4{::tokens end.
            prefix =. words 'TOINT';name;type;(mode{::Modes)
            if. -.is_finite a do. emit prefix,' invalid flags=invalid'
            else.
                'units inexact' =. round_units (exact_pattern a);0;mode;0
                integer =. units*1-2*sign
                'minimum maximum' =. index{Limits
                if. (integer<minimum)+.integer>maximum do. emit prefix,' invalid flags=invalid'
                else. emit prefix,' ',(number integer),' ',flag_text 0,0,0,0,inexact end.
            end.
        case. do.
            if. is_nan a do. result =. Quiet,(is_signaling a),0 0 0 0
            elseif. op-:'NEXTUP' do. result =. (next_up a),NoFlags
            elseif. op-:'NEXTDOWN' do. result =. (flip next_up flip a),NoFlags
            elseif. is_infinity a do. result =. Infinity,NoFlags
            else. result =. ({.0 round_value 1x,1x,q,0x),NoFlags end.
            say op;name;result_text result
        end.
    end.
)
main =: 3 : 0
    lines =. <;._2 (1!:1 3),LF
    count =. 0".0{::lines
    for_line. count{.}.lines do.
        try. command >line
        catcht. emit 'ERROR ',Error end.
    end.
)
main''
