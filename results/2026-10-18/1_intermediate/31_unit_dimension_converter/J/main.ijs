LF =: 10{a.
Digits =: '0123456789'
Letters =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
BaseNames =: ;:'kg m s A K mol cd'
Dimensionless =: 7#0x
Identity =: 1x,Dimensionless
Error =: ''
split =: 4 : '<;._1 x,y'
emit =: 3 : '(y,LF) 1!:2 4'
fail =: 3 : 0
    Error =: y
    throw.
)
number =: 3 : 0
    text =. ,'0' 8!:2 |y
    if. y<0 do. '-',text else. text end.
)
integer =: 3 : 0
    if. '-'={.y do. -x:0".}.y else. x:0".y end.
)
fraction =: 3 : 0
    'n d' =. 2 x:y
    if. d=1 do. number n else. (number n),'/',number d end.
)
decimal =: 3 : 0
    'n d' =. 2 x:|y
    whole =. <.n%d
    tail =. <.(1000000x*d|n)%d
    text =. (number whole),'.',_6{.'000000',number tail
    if. y<0 do. '-',text else. text end.
)
notation =: 4 : '(fraction x),'' '',y,'' ('',(decimal x),'')'''
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
scalar_power =: 4 : 0
    value =. x
    if. y<0 do. value =. 1x%value end.
    result =. 1x
    for_i. i.|y do. result =. result*value end.
    result
)
all_digits =: 3 : '(0<#y)*.*./y e.Digits'
parse_number =: 3 : 0
    negative =. '-'={.y
    body =. negative}.y
    separators =. I.body e.'./'
    if. 0=#separators do.
        if. -.all_digits body do. fail 'BAD NUMBER ',y end.
        value =. integer body
    else.
        if. 1~:#separators do. fail 'BAD NUMBER ',y end.
        index =. {.separators
        left =. index{.body
        right =. (index+1)}.body
        if. -. (all_digits left)*.all_digits right do. fail 'BAD NUMBER ',y end.
        n =. integer left
        d =. integer right
        if. '/'=index{body do.
            if. d=0 do. fail 'BAD NUMBER ',y end.
            value =. n%d
        else.
            scale =. 10x scalar_power #right
            value =. ((n*scale)+d)%scale
        end.
    end.
    if. negative do. -value else. value end.
)
exponent_value =: 3 : 0
    value =. integer y
    if. -.value e._3 _2 _1 1 2 3 do. fail 'BAD EXPONENT ',y end.
    value
)
check_name =: 4 : 0
    valid =. ((#y)e.1+i.12)*.*./y e.Letters
    if. x do. valid =. valid*.-.(<y)e.;:'abs sqrt min max' end.
    if. -.valid do. fail 'BAD NAME ',y end.
)
dimension_text =: 3 : 0
    parts =. 0$a:
    for_i. I.y~:0 do.
        text =. i{::BaseNames
        if. 1~:i{y do. text =. text,'^',number i{y end.
        parts =. parts,<text
    end.
    if. #parts do. ' ' join parts else. '1' end.
)
match_dimensions =: 4 : 0
    if. -.x-:y do. fail 'DIMENSION MISMATCH ',(dimension_text x),' vs ',dimension_text y end.
)
KindRows =: <;._2 (0 : 0)
dimensionless 0 0 0 0 0 0 0
length 0 1 0 0 0 0 0
mass 1 0 0 0 0 0 0
time 0 0 1 0 0 0 0
current 0 0 0 1 0 0 0
temperature 0 0 0 0 1 0 0
amount 0 0 0 0 0 1 0
luminous_intensity 0 0 0 0 0 0 1
area 0 2 0 0 0 0 0
volume 0 3 0 0 0 0 0
speed 0 1 _1 0 0 0 0
acceleration 0 1 _2 0 0 0 0
density 1 _3 0 0 0 0 0
momentum 1 1 _1 0 0 0 0
force 1 1 _2 0 0 0 0
energy 1 2 _2 0 0 0 0
power 1 2 _3 0 0 0 0
pressure 1 _1 _2 0 0 0 0
frequency 0 0 _1 0 0 0 0
charge 0 0 1 1 0 0 0
voltage 1 2 _3 _1 0 0 0
resistance 1 2 _3 _2 0 0 0
conductance _1 _2 3 2 0 0 0
capacitance _1 _2 4 2 0 0 0
magnetic_flux 1 2 _2 _1 0 0 0
flux_density 1 0 _2 _1 0 0 0
inductance 1 2 _2 _2 0 0 0
illuminance 0 _2 0 0 0 0 1
catalytic_activity 0 0 _1 0 0 1 0
)
BuiltinRows =: <;._2 (0 : 0)
m 1 length 1
g 1/1000 mass 1
s 1 time 1
A 1 current 1
K 1 temperature 1
mol 1 amount 1
cd 1 luminous_intensity 1
N 1 force 1
J 1 energy 1
W 1 power 1
Pa 1 pressure 1
Hz 1 frequency 1
C 1 charge 1
V 1 voltage 1
ohm 1 resistance 1
S 1 conductance 1
F 1 capacitance 1
Wb 1 magnetic_flux 1
T 1 flux_density 1
H 1 inductance 1
lx 1 illuminance 1
kat 1 catalytic_activity 1
L 1/1000 volume 1
t 1000 mass 0
min 60 time 0
h 3600 time 0
day 86400 time 0
in 127/5000 length 0
ft 381/1250 length 0
yd 1143/1250 length 0
mi 201168/125 length 0
nmi 1852 length 0
ha 10000 area 0
kn 463/900 speed 0
bar 100000 pressure 1
atm 101325 pressure 0
Torr 20265/152 pressure 0
cal 523/125 energy 1
Wh 3600 energy 1
Ah 3600 charge 1
dC 1 temperature 0
dF 5/9 temperature 0
)
PrefixSymbols =: ;:'G M k h da d c m u n'
PrefixFactors =: 1000000000x 1000000x 1000x 100x 10x,1x%10x 100x 1000x 1000000x 1000000000x
KindNames =: UnitNames =: VariableNames =: 0$a:
KindDims =: UnitDims =: 0 7$0x
UnitFactors =: DefinitionValues =: 0$0x
Prefixable =: i.0
DefinitionExpressions =: 0$a:
Variables =: 0 8$0x
initialize =: 3 : 0
    for_line. KindRows do.
        words =. ' ' split >line
        KindNames =: KindNames,{.words
        KindDims =: KindDims,x:0".' ' join }.words
    end.
    for_line. BuiltinRows do.
        'symbol factor kind prefix' =. ' ' split >line
        UnitNames =: UnitNames,<symbol
        UnitFactors =: UnitFactors,parse_number factor
        UnitDims =: UnitDims,(KindNames i.<kind){KindDims
        Prefixable =: Prefixable,0".prefix
    end.
    DefinitionValues =: 42#1x
    DefinitionExpressions =: 42$a:
)
kind_name =: 3 : 0
    index =. KindDims i.y
    if. index<#KindNames do. index{::KindNames else. '-' end.
)
resolve =: 3 : 0
    index =. UnitNames i.<y
    if. index<#UnitNames do. (index{UnitFactors),index{UnitDims return. end.
    for_p. i.#PrefixSymbols do.
        prefix =. p{::PrefixSymbols
        if. (#y)>#prefix do.
            if. prefix-:(#prefix){.y do.
                index =. (42{.UnitNames)i.<(#prefix)}.y
                if. index<42 do.
                    if. index{Prefixable do.
                        ((p{PrefixFactors)*index{UnitFactors),index{UnitDims return.
                    end.
                end.
            end.
        end.
    end.
    0$0x
)
simplified =: 3 : 0
    matches =. I.(UnitFactors=1)*.UnitDims-:"1 y
    if. #matches do. ({.matches){::UnitNames else. dimension_text y end.
)
selected_units =: 3 : 0
    selected =. I.UnitDims-:"1 y
    selected =. selected{~/:s:selected{UnitNames
    selected{~/:selected{UnitFactors
)

Nodes =: 0 4$a:
Tokens =: 0$a:
TokenTypes =: Positions =: i.0
Cursor =: 0
ExpressionSource =: ''
lex =: 4 : 0
    Tokens =: 0$a:
    TokenTypes =: Positions =: i.0
    Cursor =: 0
    ExpressionSource =: y
    position =. 0
    while. position<#y do.
        start =. position
        ch =. position{y
        position =. position+1
        type =. 0
        if. ch e.Letters do.
            type =. 1
            while. position<#y do.
                if. -. (position{y)e.Letters do. break. end.
                position =. position+1
            end.
        elseif. ch e.Digits do.
            type =. 2
            while. position<#y do.
                if. -. (position{y)e.Digits do. break. end.
                position =. position+1
            end.
            if. x do.
                if. (position+1)<#y do.
                    if. ('.'=position{y)*.((position+1){y)e.Digits do.
                        position =. position+1
                        while. position<#y do.
                            if. -. (position{y)e.Digits do. break. end.
                            position =. position+1
                        end.
                    end.
                end.
            end.
        elseif. x*.ch='[' do.
            closing =. position+((position}.y)i.']')
            if. (closing<#y)*.closing>position do.
                type =. 3
                position =. closing+1
            end.
        end.
        Tokens =: Tokens,<(position-start){.start}.y
        TokenTypes =: TokenTypes,type
        Positions =: Positions,1+start
    end.
)
peek =: 3 : 0
    if. Cursor=#Tokens do. '' else. Cursor{::Tokens end.
)
peek_type =: 3 : 0
    if. Cursor=#Tokens do. _1 else. Cursor{TokenTypes end.
)
syntax_error =: 3 : 0
    place =. 'END'
    if. Cursor<#Tokens do. place =. number Cursor{Positions end.
    fail 'SYNTAX ',ExpressionSource,' AT ',place
)
accept =: 3 : 0
    if. y-:peek '' do.
        Cursor =: Cursor+1
        1
    else. 0 end.
)
expect =: 3 : 0
    if. -.accept y do. syntax_error '' end.
)
node =: 3 : 0
    index =. #Nodes
    Nodes =: Nodes,y
    index
)
parse_exponent =: 3 : 0
    prefix =. ''
    if. accept '-' do. prefix =. '-' end.
    word =. peek ''
    if. (2~:peek_type '')+.'.'e.word do. syntax_error '' end.
    Cursor =: Cursor+1
    prefix,word
)
unit_term =: 3 : 0
    word =. peek ''
    type =. peek_type ''
    if. type=1 do.
        Cursor =: Cursor+1
        result =. node 'unitname';word;_1;_1
    elseif. (type=2)*.'0'~:{.word do.
        Cursor =: Cursor+1
        result =. node 'number';word;_1;_1
    elseif. accept '(' do.
        result =. unit_expression ''
        expect ')'
    else. syntax_error ''
    end.
    if. accept '^' do.
        exponent =. parse_exponent ''
        result =. node 'power';exponent;result;_1
    end.
    result
)
unit_expression =: 3 : 0
    one =. node 'number';'1';_1;_1
    right =. unit_term ''
    result =. node '*';'';one;right
    while. (<peek '')e.('*';'/') do.
        operator =. peek ''
        Cursor =: Cursor+1
        right =. unit_term ''
        result =. node operator;'';result;right
    end.
    result
)
validate_unit =: 3 : 0
    'kind data left right' =. y{Nodes
    select. kind
    case. 'unitname' do.
        quantity =. resolve data
        if. 0=#quantity do. fail 'UNKNOWN UNIT ',data end.
        Nodes =: (<quantity) (<y,2)}Nodes
    case. 'power' do.
        validate_unit left
        exponent =. exponent_value data
        Nodes =: (<exponent) (<y,3)}Nodes
    case. '*';'/' do.
        validate_unit left
        validate_unit right
    end.
)
evaluate_unit =: 3 : 0
    'kind data left right' =. y{Nodes
    select. kind
    case. 'number' do. (parse_number data),Dimensionless
    case. 'unitname' do. left
    case. 'power' do.
        value =. evaluate_unit left
        (({.value) scalar_power right),right*}.value
    case. do.
        a =. evaluate_unit left
        b =. evaluate_unit right
        if. kind-:'*' do. (({.a)*{.b),(}.a)+}.b
        else. (({.a)%{.b),(}.a)-}.b end.
    end.
)
parse_unit =: 3 : 0
    0 lex y
    root =. unit_expression ''
    if. Cursor<#Tokens do. syntax_error '' end.
    validate_unit root
    root
)
unit_value =: 3 : 'evaluate_unit parse_unit y'

ReduceNames =: 0$a:
reduce_node =: 3 : 0
    'kind data left right' =. y{Nodes
    if. kind-:'number' do. (parse_number data);201#0x return. end.
    if. kind-:'unitname' do.
        index =. ReduceNames i.<data
        if. index=#ReduceNames do. ReduceNames =: ReduceNames,<data end.
        exponents =. 201#0x
        exponents =. 1x (index}) exponents
        1x;exponents return.
    end.
    'coefficient exponents' =. reduce_node left
    if. kind-:'power' do. (coefficient scalar_power right);right*exponents return. end.
    'other powers' =. reduce_node right
    if. kind-:'*' do. (coefficient*other);exponents+powers
    else. (coefficient%other);exponents-powers end.
)
reduced_text =: 3 : 0
    ReduceNames =: 0$a:
    'coefficient exponents' =. reduce_node y
    parts =. 0$a:
    if. coefficient~:1 do. parts =. parts,<fraction coefficient end.
    for_i. i.#ReduceNames do.
        exponent =. i{exponents
        if. exponent=0 do. continue. end.
        text =. i{::ReduceNames
        if. exponent~:1 do. text =. text,'^',number exponent end.
        parts =. parts,<text
    end.
    if. #parts do. ' ' join parts else. '1' end.
)
quantity_primary =: 3 : 0
    word =. peek ''
    type =. peek_type ''
    if. type=2 do.
        Cursor =: Cursor+1
        if. 3=peek_type '' do.
            unit =. }.}:peek ''
            Cursor =: Cursor+1
            result =. node 'unitvalue';word;unit;_1
        else. result =. node 'number';word;_1;_1 end.
    elseif. type=3 do.
        Cursor =: Cursor+1
        result =. node 'unitvalue';'1';(}.}:word);_1
    elseif. type=1 do.
        Cursor =: Cursor+1
        if. accept '(' do.
            arguments =. ,quantity_expression ''
            while. accept ',' do. arguments =. arguments,quantity_expression '' end.
            expect ')'
            result =. node 'call';word;arguments;_1
        else. result =. node 'variable';word;_1;_1 end.
    elseif. accept '(' do.
        result =. quantity_expression ''
        expect ')'
    else. syntax_error ''
    end.
    if. accept '^' do.
        exponent =. parse_exponent ''
        result =. node 'power';exponent;result;_1
    end.
    result
)
quantity_unary =: 3 : 0
    if. accept '-' do.
        child =. quantity_unary ''
        node 'negative';'';child;_1
    else. quantity_primary '' end.
)
quantity_product =: 3 : 0
    result =. quantity_unary ''
    while. (<peek '')e.('*';'/') do.
        operator =. peek ''
        Cursor =: Cursor+1
        right =. quantity_unary ''
        result =. node operator;'';result;right
    end.
    result
)
quantity_expression =: 3 : 0
    result =. quantity_product ''
    while. (<peek '')e.('+';'-') do.
        operator =. peek ''
        Cursor =: Cursor+1
        right =. quantity_product ''
        result =. node operator;'';result;right
    end.
    result
)
integer_sqrt =: 3 : 0
    if. y<2 do. y return. end.
    current =. y
    following =. <.(y+1x)%2x
    while. following<current do.
        current =. following
        following =. <.(current+<.y%current)%2x
    end.
    current
)
evaluate_quantity =: 3 : 0
    'kind data left right' =. y{Nodes
    select. kind
    case. 'number' do. (parse_number data),Dimensionless
    case. 'unitvalue' do.
        unit =. unit_value left
        value =. parse_number data
        (value*{.unit),}.unit
    case. 'variable' do.
        index =. VariableNames i.<data
        if. index=#VariableNames do. fail 'UNKNOWN VARIABLE ',data end.
        index{Variables
    case. 'call' do.
        if. -.(<data)e.;:'abs sqrt min max' do. fail 'UNKNOWN FUNCTION ',data end.
        count =. 2
        if. (<data)e.;:'abs sqrt' do. count =. 1 end.
        if. count~:#left do. fail 'BAD ARGUMENTS ',data end.
        a =. evaluate_quantity {.left
        select. data
        case. 'abs' do. (|{.a),}.a
        case. 'sqrt' do.
            if. 0>{.a do. fail 'NEGATIVE ROOT' end.
            if. +./2|}.a do. fail 'ODD DIMENSION ',dimension_text }.a end.
            'n d' =. 2 x:{.a
            p =. integer_sqrt n
            q =. integer_sqrt d
            if. (n~:p*p)+.d~:q*q do. fail 'NOT EXACT' end.
            (p%q),(}.a)%2x
        case. do.
            b =. evaluate_quantity 1{left
            (}.a) match_dimensions }.b
            if. data-:'min' do.
                if. ({.a)<:{.b do. a else. b end.
            else.
                if. ({.a)>:{.b do. a else. b end.
            end.
        end.
    case. 'negative' do.
        a =. evaluate_quantity left
        (-{.a),}.a
    case. 'power' do.
        a =. evaluate_quantity left
        exponent =. exponent_value data
        if. (0={.a)*.exponent<0 do. fail 'DIVISION BY ZERO' end.
        (({.a) scalar_power exponent),exponent*}.a
    case. do.
        a =. evaluate_quantity left
        b =. evaluate_quantity right
        select. kind
        case. '+';'-' do.
            (}.a) match_dimensions }.b
            if. kind-:'+' do. (({.a)+{.b),}.a else. (({.a)-{.b),}.a end.
        case. '*' do. (({.a)*{.b),(}.a)+}.b
        case. '/' do.
            if. 0={.b do. fail 'DIVISION BY ZERO' end.
            (({.a)%{.b),(}.a)-}.b
        end.
    end.
)
quantity_value =: 3 : 0
    1 lex y
    root =. quantity_expression ''
    if. Cursor<#Tokens do. syntax_error '' end.
    evaluate_quantity root
)

execute =: 3 : 0
    Nodes =: 0 4$a:
    words =. ' ' split y
    command =. 0{::words
    select. command
    case. 'DEFINE' do.
        name =. 1{::words
        0 check_name name
        value =. parse_number 3{::words
        unit =. unit_value 4{::words
        if. ((<name)e.KindNames)+.0<#resolve name do. fail 'NAME TAKEN ',name end.
        if. value<:0 do. fail 'NOT POSITIVE ',3{::words end.
        factor =. value*{.unit
        UnitNames =: UnitNames,<name
        UnitFactors =: UnitFactors,factor
        UnitDims =: UnitDims,}.unit
        Prefixable =: Prefixable,0
        DefinitionValues =: DefinitionValues,value
        DefinitionExpressions =: DefinitionExpressions,4{words
        emit 'DEFINE ',name,' factor=',(fraction factor),' dim=',(dimension_text }.unit),' kind=',kind_name }.unit
    case. 'UNDEF' do.
        name =. 1{::words
        index =. UnitNames i.<name
        if. index<42 do. fail 'BUILTIN UNIT ',name end.
        if. index=#UnitNames do. fail 'NOT DEFINED ',name end.
        keep =. (i.#UnitNames)~:index
        UnitNames =: keep#UnitNames
        UnitFactors =: keep#UnitFactors
        UnitDims =: keep#UnitDims
        Prefixable =: keep#Prefixable
        DefinitionValues =: keep#DefinitionValues
        DefinitionExpressions =: keep#DefinitionExpressions
        emit 'UNDEF ',name
    case. 'DEFS' do.
        emit 'DEFS count=',number (#UnitNames)-42
        for_i. 42+i.(#UnitNames)-42 do.
            emit 'DEF ',(i{::UnitNames),' = ',(fraction i{DefinitionValues),' ',(i{::DefinitionExpressions),' factor=',(fraction i{UnitFactors),' dim=',dimension_text i{UnitDims
        end.
    case. 'CONVERT';'INVERT' do.
        value =. parse_number 1{::words
        source =. unit_value 2{::words
        target =. unit_value 4{::words
        if. command-:'INVERT' do.
            if. (Dimensionless-:}.source)+.-.Dimensionless-:(}.source)+}.target do.
                fail 'NOT RECIPROCAL ',(dimension_text }.source),' vs ',dimension_text }.target
            end.
            if. value=0 do. fail 'DIVISION BY ZERO' end.
        else. (}.source) match_dimensions }.target end.
        result =. value*{.source
        if. command-:'INVERT' do. result =. 1x%result end.
        result =. result%{.target
        emit command,' ',(fraction value),' ',(2{::words),' = ',result notation 4{::words
    case. 'DIM';'REDUCE';'SIMPLIFY' do.
        root =. parse_unit 1{::words
        unit =. evaluate_unit root
        select. command
        case. 'DIM' do.
            emit 'DIM ',(1{::words),' = ',(dimension_text }.unit),' factor=',(fraction {.unit),' kind=',kind_name }.unit
        case. 'REDUCE' do. emit 'REDUCE ',(1{::words),' = ',reduced_text root
        case. 'SIMPLIFY' do. emit 'SIMPLIFY ',(1{::words),' = ',({.unit) notation simplified }.unit
        end.
    case. 'ADD';'SUB';'MUL';'DIV';'COMPARE' do.
        a =. parse_number 1{::words
        first =. unit_value 2{::words
        b =. parse_number 3{::words
        second =. unit_value 4{::words
        has_target =. 7=#words
        target =. first
        if. has_target do. target =. unit_value 6{::words end.
        prefix =. command,' ',(fraction a),' ',(2{::words),' '
        suffix =. ' ',(fraction b),' ',4{::words
        if. (<command)e.;:'ADD SUB COMPARE' do.
            (}.first) match_dimensions }.second
            if. has_target do. (}.first) match_dimensions }.target end.
            left =. a*{.first
            right =. b*{.second
            if. command-:'COMPARE' do.
                relation =. '='
                if. left<right do. relation =. '<' elseif. left>right do. relation =. '>' end.
                ratio =. 'undefined'
                if. right~:0 do. ratio =. fraction left%right end.
                emit prefix,relation,suffix,' ratio=',ratio
            else.
                if. command-:'SUB' do.
                    operator =. '-'
                    result =. left-right
                else.
                    operator =. '+'
                    result =. left+right
                end.
                result =. result%{.target
                label =. 2{::words
                if. has_target do. label =. 6{::words end.
                emit prefix,operator,suffix,' = ',result notation label
            end.
        else.
            product =. command-:'MUL'
            dimensions =. (}.first)+(}.second)*_1+2*product
            if. (-.product)*.b=0 do. fail 'DIVISION BY ZERO' end.
            if. has_target do. dimensions match_dimensions }.target end.
            if. product do. raw =. a*b else. raw =. a%b end.
            left =. a*{.first
            right =. b*{.second
            if. product do. coherent =. left*right [ operator =. '*'
            else. coherent =. left%right [ operator =. '/' end.
            text =. prefix,operator,suffix,' = '
            if. has_target do. text =. text,(coherent%{.target) notation 6{::words
            else.
                right_unit =. 4{::words
                if. (-.product)*.+./right_unit e.'*/' do. right_unit =. '(',right_unit,')' end.
                combined =. (2{::words),operator,right_unit
                text =. text,(fraction raw),' ',combined,' = ',coherent notation simplified dimensions
            end.
            emit text
        end.
    case. 'TEMP' do.
        value =. parse_number 1{::words
        source =. 2{::words
        target =. 4{::words
        if. -.(<source)e.;:'C F K R' do. fail 'UNKNOWN SCALE ',source end.
        if. -.(<target)e.;:'C F K R' do. fail 'UNKNOWN SCALE ',target end.
        kelvin =. value
        select. source
        case. 'C' do. kelvin =. value+5463r20
        case. 'F' do. kelvin =. (value+45967r100)*5r9
        case. 'R' do. kelvin =. value*5r9
        end.
        if. kelvin<0 do. fail 'BELOW ABSOLUTE ZERO' end.
        result =. kelvin
        select. target
        case. 'C' do. result =. kelvin-5463r20
        case. 'F' do. result =. (kelvin*9r5)-45967r100
        case. 'R' do. result =. kelvin*9r5
        end.
        emit 'TEMP ',(fraction value),' ',source,' = ',result notation target
    case. 'LIST';'TABLE' do.
        table =. command-:'TABLE'
        value =. 1x
        unit =. Identity
        if. table do.
            value =. parse_number 1{::words
            unit =. unit_value 2{::words
            dimensions =. }.unit
        else.
            kind =. KindNames i.1{words
            if. kind<#KindNames do. dimensions =. kind{KindDims
            else.
                unit =. unit_value 1{::words
                dimensions =. }.unit
            end.
        end.
        selected =. selected_units dimensions
        if. table do. emit 'TABLE ',(fraction value),' ',(2{::words),' dim=',(dimension_text dimensions),' count=',number #selected
        else. emit 'LIST ',(1{::words),' dim=',(dimension_text dimensions),' kind=',(kind_name dimensions),' count=',number #selected end.
        for_i. selected do.
            if. table do.
                coherent =. value*{.unit
                result =. coherent%i{UnitFactors
                emit 'ROW ',result notation i{::UnitNames
            else.
                origin =. 'builtin'
                if. i>:42 do. origin =. 'user' end.
                prefix =. 'no'
                if. i{Prefixable do. prefix =. 'yes' end.
                emit 'UNIT ',(i{::UnitNames),' factor=',(fraction i{UnitFactors),' origin=',origin,' prefix=',prefix
            end.
        end.
    case. 'AUTO' do.
        value =. parse_number 1{::words
        unit =. unit_value 2{::words
        matches =. I.(42{.Prefixable)*.(42{.UnitDims)-:"1 }.unit
        if. 0=#matches do. fail 'NO PREFIXABLE UNIT ',dimension_text }.unit end.
        reference =. {.matches
        scaled =. (value*{.unit)%reference{UnitFactors
        magnitude =. |scaled
        exponent =. 0
        if. magnitude>:1 do.
            while. exponent<9 do.
                if. magnitude<10x scalar_power exponent+3 do. break. end.
                exponent =. exponent+3
            end.
        elseif. magnitude>0 do.
            while. exponent>_9 do.
                if. magnitude>:10x scalar_power exponent do. break. end.
                exponent =. exponent-3
            end.
        end.
        prefixes =. 'n';'u';'m';'';'k';'M';'G'
        label =. ((<.(exponent+9)%3){::prefixes),reference{::UnitNames
        emit 'AUTO ',(fraction value),' ',(2{::words),' = ',(scaled%10x scalar_power exponent) notation label
    case. 'SPLIT' do.
        value =. parse_number 1{::words
        unit =. unit_value 2{::words
        parts =. ',' split 4{::words
        targets =. 0 8$0x
        for_part. parts do. targets =. targets,unit_value >part end.
        if. value<0 do. fail 'NEGATIVE VALUE' end.
        for_target. targets do. (}.unit) match_dimensions }.target end.
        factors =. 0{"1 targets
        if. +./(}:factors)<:}.factors do. fail 'UNIT ORDER' end.
        remaining =. value*{.unit
        text =. 'SPLIT ',(fraction value),' ',(2{::words),' = '
        for_i. i.(#parts)-1 do.
            count =. <.remaining%i{factors
            remaining =. remaining-count*i{factors
            text =. text,(number count),' ',(i{::parts),' '
        end.
        emit text,(remaining%{:factors) notation >{:parts
    case. 'LET' do.
        name =. 1{::words
        1 check_name name
        quantity =. quantity_value 3{::words
        index =. VariableNames i.<name
        if. index=#VariableNames do.
            VariableNames =: VariableNames,<name
            Variables =: Variables,quantity
        else. Variables =: quantity index}Variables end.
        emit 'LET ',name,' = ',({.quantity) notation simplified }.quantity
    case. 'EVAL' do.
        quantity =. quantity_value 1{::words
        value =. {.quantity
        label =. simplified }.quantity
        if. 4=#words do.
            unit =. unit_value 3{::words
            (}.quantity) match_dimensions }.unit
            value =. value%{.unit
            label =. 3{::words
        end.
        emit 'EVAL ',(1{::words),' = ',value notation label
    case. 'VARS' do.
        emit 'VARS count=',number #VariableNames
        for_i. /:s:VariableNames do.
            quantity =. i{Variables
            emit 'VAR ',(i{::VariableNames),' = ',({.quantity) notation simplified }.quantity
        end.
    case. do. fail 'UNKNOWN COMMAND ',command
    end.
)
main =: 3 : 0
    initialize ''
    count =. 0".1!:1 3
    for_i. i.count do.
        line =. 1!:1 3
        try. execute line
        catcht. emit 'ERROR ',Error
        end.
    end.
)
main ''
exit 0
