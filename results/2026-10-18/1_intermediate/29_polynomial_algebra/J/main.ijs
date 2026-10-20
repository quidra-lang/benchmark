NB. Ascending coefficient vectors use J's native extended integers and rationals.
LF =: 10{a.
Digits =: '0123456789'
Upper =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
Zero =: 0$0x
One =: ,1x
Variable =: 0x 1x
Names =: 0$a:
Polynomials =: 0$a:
Error =: ''
split =: 4 : '<;._1 x,y'
emit =: 3 : '(y,LF) 1!:2 4'
number =: 3 : 0
    text =. ,'0' 8!:2 |y
    if. y<0 do. '-',text else. text end.
)
integer =: 3 : 0
    if. '-'={.y do. -x:0".}.y else. x:0".y end.
)
fraction =: 3 : 0
    'p q' =. 2 x:y
    if. q=1 do. number p else. (number p),'/',number q end.
)
join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do. text =. text,x end.
        text =. text,i{::y
    end.
    text
)
fail =: 3 : 0
    Error =: y
    throw.
)
rational =: 3 : 0
    fields =. '/' split y
    p =. integer 0{::fields
    q =. 1x
    if. 2=#fields do. q =. integer 1{::fields end.
    if. q=0 do. fail 'ZERO DENOMINATOR' end.
    p%q
)
trim =: 3 : 0
    coefficients =. ,y
    nonzero =. I.0~:coefficients
    if. 0=#nonzero do. Zero else. (1+{:nonzero){.coefficients end.
)
degree =: 3 : '<:#y'
NB. Padding both operands also preserves a vector for constants and zero.
padd =: 4 : 0
    n =. (#x)>.#y
    trim (n{.x)+n{.y
)
psub =: 4 : 'x padd -y'
pmul =: 4 : 0
    if. (0=#x)+.0=#y do. Zero return. end.
    result =. ((#x)+(#y)-1)#0x
    for_i. i.#x do.
        for_j. i.#y do.
            index =. i+j
            result =. ((index{result)+(i{x)*j{y) index}result
        end.
    end.
    trim result
)
ppower =: 4 : 0
    if. y=0 do. One return. end.
    if. 0=#x do. Zero return. end.
    if. (1=#x)*.1=|{.x do.
        if. 2|y do. x return. end.
        One return.
    end.
    result =. One
    for_i. i.y do. result =. result pmul x end.
    result
)
scalar_power =: 4 : 0
    result =. 1x
    for_i. i.y do. result =. result*x end.
    result
)
pdivide =: 4 : 0
    remainder =. x
    quotient =. (0>.1+(#x)-#y)#0x
    while. (0<#remainder)*.(#remainder)>:#y do.
        t =. ({:remainder)%{:y
        d =. (#remainder)-#y
        quotient =. t d}quotient
        for_j. i.#y do.
            index =. d+j
            remainder =. ((index{remainder)-t*j{y) index}remainder
        end.
        remainder =. trim remainder
    end.
    (trim quotient);remainder
)
pquotient =: 4 : '0{::x pdivide y'
pmod =: 4 : '1{::x pdivide y'
monic =: 3 : 0
    if. #y do. y%{:y else. Zero end.
)
pgcd =: 4 : 0
    a =. x
    b =. y
    while. #b do.
        remainder =. a pmod b
        a =. b
        b =. remainder
    end.
    monic a
)
xgcd =: 4 : 0
    r0 =. x
    r1 =. y
    s0 =. t1 =. One
    s1 =. t0 =. Zero
    while. #r1 do.
        'q remainder' =. r0 pdivide r1
        next_s =. s0 psub q pmul s1
        next_t =. t0 psub q pmul t1
        r0 =. r1
        r1 =. remainder
        s0 =. s1
        s1 =. next_s
        t0 =. t1
        t1 =. next_t
    end.
    if. #r0 do.
        leading =. {:r0
        r0 =. r0%leading
        s0 =. s0%leading
        t0 =. t0%leading
    end.
    r0;s0;t0
)
derivative =: 3 : 'trim (}.y)*1+i.0>.(_1+#y)'
integral =: 3 : 'trim 0x,y%1+i.#y'
peval =: 4 : 0
    result =. 0x
    for_i. |.i.#x do. result =. (result*y)+i{x end.
    result
)
compose =: 4 : 0
    result =. Zero
    for_i. |.i.#x do. result =. (result pmul y) padd ,i{x end.
    result
)
content =: 3 : 0
    denominator =. 1x
    numerator =. 0x
    for_coefficient. y do.
        'p q' =. 2 x:coefficient
        denominator =. denominator*.q
        numerator =. numerator+. |p
    end.
    (*{:y)*numerator%denominator
)
primitive =: 3 : 'y%content y'
squarefree =: 3 : 0
    if. 1<#y do. y pquotient y pgcd derivative y else. y end.
)
notation =: 3 : 0
    'x' notation y
:
    text =. ''
    for_i. |.I.0~:y do.
        coefficient =. i{y
        term =. ''
        if. (i=0)+.1~:|coefficient do. term =. fraction |coefficient end.
        if. i>0 do. term =. term,x end.
        if. i>1 do. term =. term,'^',number i end.
        if. 0=#text do.
            if. coefficient<0 do. text =. '-' end.
        elseif. coefficient<0 do. text =. text,' - '
        else. text =. text,' + ' end.
        text =. text,term
    end.
    if. #text do. text else. '0' end.
)
lookup =: 3 : 0
    index =. Names i.<y
    if. index=#Names do. fail 'UNKNOWN ',y end.
    index{::Polynomials
)
store_poly =: 4 : 0
    index =. Names i.<x
    if. index=#Names do.
        Names =: Names,<x
        Polynomials =: Polynomials,<y
    else. Polynomials =: (<y) index}Polynomials end.
    emit x,' = ',notation y
)
product_checked =: 4 : 0
    if. (0<#x)*.0<#y do.
        if. 30<(degree x)+degree y do. fail 'DEGREE LIMIT' end.
    end.
    x pmul y
)
power_checked =: 4 : 0
    if. (0<#x)*.30<y*degree x do. fail 'DEGREE LIMIT' end.
    x ppower y
)
compose_checked =: 4 : 0
    if. ((#x)>1)*.(#y)>1 do.
        if. 30<(degree x)*degree y do. fail 'DEGREE LIMIT' end.
    end.
    x compose y
)

NB. Parse the entire expression into an indexed tree before any lookup or evaluation.
Tokens =: 0$a:
Positions =: i.0
Cursor =: 0
Nodes =: 0 4$a:
lex =: 3 : 0
    Tokens =: 0$a:
    Positions =: i.0
    Cursor =: 0
    Nodes =: 0 4$a:
    i =. 0
    while. i<#y do.
        ch =. i{y
        if. ch=' ' do. i =. i+1 continue. end.
        start =. i
        i =. i+1
        alphabet =. ''
        if. ch e.Digits do. alphabet =. Digits
        elseif. ch e.Upper do. alphabet =. Upper,Digits end.
        while. i<#y do.
            if. -. (i{y)e.alphabet do. break. end.
            i =. i+1
        end.
        Tokens =: Tokens,<(i-start){.start}.y
        Positions =: Positions,1+start
    end.
)
peek =: 3 : 0
    if. Cursor=#Tokens do. '' else. Cursor{::Tokens end.
)
syntax_error =: 3 : 0
    if. Cursor=#Tokens do. fail 'SYNTAX AT END' end.
    fail 'SYNTAX AT ',number Cursor{Positions
)
node =: 3 : 0
    index =. #Nodes
    Nodes =: Nodes,y
    index
)
parse_primary =: 3 : 0
    word =. peek ''
    if. 0=#word do. syntax_error '' end.
    Cursor =: Cursor+1
    if. ({.word)e.Digits do.
        node 'number';(integer word);_1;_1
    elseif. word-:'x' do.
        node 'x';0;_1;_1
    elseif. ({.word)e.Upper do.
        count =. 0
        while. ''''-:peek '' do.
            count =. count+1
            Cursor =: Cursor+1
        end.
        result =. node 'name';word;count;_1
        if. '('-:peek '' do.
            Cursor =: Cursor+1
            argument =. parse_expression ''
            if. -. ')'-:peek '' do. syntax_error '' end.
            Cursor =: Cursor+1
            result =. node 'call';0;result;argument
        end.
        result
    elseif. word-:'(' do.
        result =. parse_expression ''
        if. -. ')'-:peek '' do. syntax_error '' end.
        Cursor =: Cursor+1
        result
    else.
        Cursor =: Cursor-1
        syntax_error ''
    end.
)
parse_factor =: 3 : 0
    result =. parse_primary ''
    if. '^'-:peek '' do.
        Cursor =: Cursor+1
        word =. peek ''
        if. 0=#word do. syntax_error '' end.
        if. -. ({.word)e.Digits do. syntax_error '' end.
        Cursor =: Cursor+1
        result =. node 'power';(integer word);result;_1
    end.
    result
)
parse_term =: 3 : 0
    result =. parse_factor ''
    while. 1 do.
        word =. peek ''
        if. (<word)e.('*';'/') do.
            Cursor =: Cursor+1
            right =. parse_factor ''
            result =. node word;0;result;right
        elseif. (word-:'x')+.(word-:'(')+.({.word)e.Upper do.
            right =. parse_factor ''
            result =. node '*';0;result;right
        else. break. end.
    end.
    result
)
parse_expression =: 3 : 0
    negative =. '-'-:peek ''
    if. negative do. Cursor =: Cursor+1 end.
    result =. parse_term ''
    if. negative do. result =. node 'neg';0;result;_1 end.
    while. (<peek '')e.('+';'-') do.
        operator =. peek ''
        Cursor =: Cursor+1
        right =. parse_term ''
        result =. node operator;0;result;right
    end.
    result
)
evaluate =: 3 : 0
    'kind data left right' =. y{Nodes
    select. kind
    case. 'number' do. trim ,data
    case. 'x' do. Variable
    case. 'name' do.
        result =. lookup data
        for_i. i.left do. result =. derivative result end.
        result
    case. 'neg' do. -evaluate left
    case. 'power' do.
        result =. evaluate left
        result power_checked data
    case. do.
        a =. evaluate left
        b =. evaluate right
        select. kind
        case. '+' do. a padd b
        case. '-' do. a psub b
        case. '*' do. a product_checked b
        case. 'call' do. a compose_checked b
        case. '/' do.
            if. 0=#b do. fail 'DIVISION BY ZERO' end.
            if. 1<#b do. fail 'NONCONSTANT DIVISOR' end.
            a%{.b
        end.
    end.
)

sign_changes =: 3 : 0
    signs =. *y#~y~:0
    +/(}.signs)~:}:signs
)
divisors =: 3 : 0
    values =. x:1+i.<.y
    values#~0=values|y
)
rational_roots =: 3 : 0
    p =. primitive y
    zero_count =. 0
    while. 0={.p do.
        p =. }.p
        zero_count =. zero_count+1
    end.
    candidates =. Zero
    for_s. divisors |{.p do.
        for_t. divisors {:p do.
            if. 1=s+.t do. candidates =. candidates,(s%t),-s%t end.
        end.
    end.
    roots =. 0 2$0x
    for_r. /:~~.candidates do.
        's t' =. 2 x:r
        factor =. (-s),t
        count =. 0
        while. 1<#p do.
            if. 0~:p peval r do. break. end.
            p =. p pquotient factor
            count =. count+1
        end.
        if. count do. roots =. roots,r,count end.
    end.
    if. zero_count do. roots =. roots,0x,zero_count end.
    roots =. (/:0{"1 roots){roots
    roots;p
)
factor_text =: 4 : 0
    text =. x
    if. y>1 do. text =. text,'^',number y end.
    ' * ',text
)
factorization =: 3 : 0
    'roots remaining' =. rational_roots y
    text =. fraction content y
    for_row. roots do.
        'r multiplicity' =. row
        's t' =. 2 x:r
        factor =. 'x'
        if. r~:0 do. factor =. '(', (notation (-s),t),')' end.
        text =. text,factor factor_text multiplicity
    end.
    if. 1<#remaining do. text =. text,' * (',(notation remaining),')' end.
    text
)
squarefree_factors =: 3 : 0
    text =. fraction content y
    if. 1=#y do. text return. end.
    w0 =. monic y
    c =. w0 pgcd derivative w0
    w =. w0 pquotient c
    multiplicity =. 1
    while. 1<#w do.
        common =. w pgcd c
        factor =. w pquotient common
        if. 1<#factor do.
            factor =. primitive factor
            label =. 'x'
            if. -.factor-:Variable do. label =. '(', (notation factor),')' end.
            text =. text,label factor_text multiplicity
        end.
        c =. c pquotient common
        w =. common
        multiplicity =. multiplicity+1
    end.
    text
)
sturm_sequence =: 3 : 0
    previous =. squarefree y
    current =. derivative previous
    sequence =. ,<previous
    while. #current do.
        sequence =. sequence,<current
        following =. -previous pmod current
        previous =. current
        current =. following
    end.
    sequence
)
variations =: 4 : 0
    signs =. i.0
    for_polynomial. x do.
        polynomial =. >polynomial
        if. 2=3!:0 y do.
            sign =. *{:polynomial
            if. y-:'-inf' do. sign =. sign*_1x^degree polynomial end.
        else. sign =. *polynomial peval y end.
        signs =. signs,sign
    end.
    sign_changes signs
)
root_count =: 4 : 0
    'low high' =. y
    left =. x variations low
    right =. x variations high
    left-right
)
endpoint_kind =: 3 : 0
    if. 2~:3!:0 y do. 0 elseif. y-:'-inf' do. _1 else. 1 end.
)
before =: 4 : 0
    a =. endpoint_kind x
    b =. endpoint_kind y
    if. (a=0)*.b=0 do. x<y else. a<b end.
)
endpoint_text =: 3 : 0
    if. 2=3!:0 y do. y else. fraction y end.
)
IsolationSequence =: 0$a:
IsolationWidth =: 1x
examine =: 3 : 0
    'low high' =. y
    count =. IsolationSequence root_count low;high
    if. count>1 do.
        midpoint =. (low+high)%2x
        left =. examine low,midpoint
        right =. examine midpoint,high
        left,right
    elseif. count=1 do.
        while. IsolationWidth<high-low do.
            midpoint =. (low+high)%2x
            if. 0<IsolationSequence root_count low;midpoint do. high =. midpoint
            else. low =. midpoint end.
        end.
        ,<low,high
    else. 0$a: end.
)
resultant =: 4 : 0
    p =. x
    q =. y
    result =. 1x
    while. 1<#q do.
        remainder =. p pmod q
        if. 0=#remainder do. 0x return. end.
        result =. result*({:q) scalar_power (#p)-#remainder
        if. 2|(degree p)*degree q do. result =. -result end.
        p =. q
        q =. remainder
    end.
    result*({.q) scalar_power degree p
)
interpolate =: 3 : 0
    xs =. 0{"1 y
    differences =. 1{"1 y
    n =. #xs
    for_j. 1+i.n-1 do.
        if. (j{xs)e.j{.xs do. fail 'DUPLICATE X ',fraction j{xs end.
    end.
    for_j. 1+i.n-1 do.
        for_i. |.j+i.n-j do.
            value =. ((i{differences)-(i-1){differences)%((i{xs)-(i-j){xs)
            differences =. value i}differences
        end.
    end.
    result =. Zero
    for_i. |.i.n do.
        result =. (result pmul (-(i{xs)),1x) padd ,i{differences
    end.
    result
)
special =: 4 : 0
    if. -. (<x)e.;:'chebyshev chebyshev2 legendre hermite laguerre' do. fail 'UNKNOWN KIND ',x end.
    if. y>30 do. fail 'DEGREE LIMIT' end.
    previous =. One
    if. y=0 do. previous return. end.
    current =. Variable
    if. (<x)e.;:'chebyshev2 hermite' do. current =. 2x*Variable end.
    if. x-:'laguerre' do. current =. 1x _1x end.
    for_j. 1+i.y-1 do.
        select. x
        case. 'chebyshev';'chebyshev2' do. following =. (0x 2x pmul current) psub previous
        case. 'legendre' do.
            following =. ((0x,1+2*j) pmul current) psub j*previous
            following =. following*(1x%j+1)
        case. 'hermite' do. following =. (0x 2x pmul current) psub (2x*j)*previous
        case. 'laguerre' do.
            following =. (((1+2*j),_1x) pmul current) psub j*previous
            following =. following*(1x%j+1)
        end.
        previous =. current
        current =. following
    end.
    current
)

operand_indices =: 3 : 0
    select. y
    case. 'PRINT';'DELETE';'DEGREE';'AREA';'TAYLOR';'EVAL';'ROOTS';'FACTOR';'SQFREE';'DESCARTES';'STURM';'ISOLATE';'DISCRIM';'POWERSUM' do. ,1
    case. 'POW';'DERIV';'INTEG';'TANGENT' do. ,2
    case. 'ADD';'SUB';'MUL';'GCD';'LCM';'INVMOD';'COMPOSE' do. 2 3
    case. 'DIV' do. 3 4
    case. 'XGCD' do. 4 5
    case. 'CRT' do. 2 3 4 5
    case. 'MODPOW' do. 2 4
    case. 'RESULTANT' do. 1 2
    case. do. i.0
    end.
)
execute =: 3 : 0
    args =. ' ' split y
    command =. 0{::args
    if. command-:'DEF' do.
        destination =. 1{::args
        lex (5+#destination)}.y
        root =. parse_expression ''
        if. Cursor<#Tokens do. syntax_error '' end.
        result =. evaluate root
        destination store_poly result
        return.
    end.
    if. command-:'DIV' do.
        if. (1{args)-:2{args do. fail 'SAME NAME' end.
    elseif. command-:'XGCD' do.
        if. 3~:#~.1 2 3{args do. fail 'SAME NAME' end.
    end.
    operands =. 0$a:
    for_index. operand_indices command do. operands =. operands,<lookup index{::args end.
    a =. b =. Zero
    if. #operands do. a =. 0{::operands end.
    if. 1<#operands do. b =. 1{::operands end.
    literal_indices =. i.0
    select. command
    case. 'AREA';'STURM' do. literal_indices =. 2 3
    case. 'TANGENT' do. literal_indices =. ,3
    case. 'TAYLOR' do. literal_indices =. ,2
    case. 'EVAL';'INTERP' do. literal_indices =. 2+i.(#args)-2
    end.
    literals =. 0$a:
    for_index. literal_indices do.
        word =. index{::args
        if. (<word)e.('-inf';'inf') do. value =. word else. value =. rational word end.
        literals =. literals,<value
    end.
    name =. ''
    if. 1<#args do. name =. 1{::args end.
    select. command
    case. 'PRINT' do. emit name,' = ',notation a
    case. 'DELETE' do.
        index =. Names i.<name
        Names =: ((i.#Names)-.index){Names
        Polynomials =: ((i.#Polynomials)-.index){Polynomials
        emit 'deleted ',name
    case. 'LIST' do.
        if. 0=#Names do. emit 'no polynomials' end.
        for_index. /:s:Names do. emit (index{::Names),' = ',notation index{::Polynomials end.
    case. 'DEGREE' do.
        text =. '-inf'
        if. #a do. text =. number degree a end.
        emit 'deg(',name,') = ',text
    case. 'ADD' do. name store_poly a padd b
    case. 'SUB' do. name store_poly a psub b
    case. 'MUL' do. name store_poly a product_checked b
    case. 'POW' do. name store_poly a power_checked integer 3{::args
    case. 'DIV' do.
        if. 0=#b do. fail 'DIVISION BY ZERO' end.
        'quotient remainder' =. a pdivide b
        name store_poly quotient
        (2{::args) store_poly remainder
    case. 'GCD' do. name store_poly a pgcd b
    case. 'XGCD' do.
        results =. a xgcd b
        for_i. i.3 do. ((i+1){::args) store_poly i{::results end.
    case. 'LCM' do.
        result =. Zero
        if. (0<#a)*.0<#b do.
            common =. a pgcd b
            if. 30<((degree a)+degree b)-degree common do. fail 'DEGREE LIMIT' end.
            result =. monic (a pquotient common) pmul b
        end.
        name store_poly result
    case. 'INVMOD' do.
        if. 0=#b do. fail 'DIVISION BY ZERO' end.
        if. 1=#b do. fail 'DEGREE TOO LOW' end.
        'g s t' =. a xgcd b
        if. -.g-:One do. fail 'NOT COPRIME' end.
        name store_poly s pmod b
    case. 'CRT' do.
        'a1 m1 a2 m2' =. operands
        if. (0=#m1)+.0=#m2 do. fail 'DIVISION BY ZERO' end.
        if. 30<(degree m1)+degree m2 do. fail 'DEGREE LIMIT' end.
        'g s t' =. m1 xgcd m2
        if. -.g-:One do. fail 'NOT COPRIME' end.
        r1 =. a1 pmod m1
        r2 =. a2 pmod m2
        u =. ((r2 psub r1) pmul s) pmod m2
        name store_poly r1 padd m1 pmul u
    case. 'MODPOW' do.
        if. 0=#b do. fail 'DIVISION BY ZERO' end.
        if. 30<(2*degree b)-2 do. fail 'DEGREE LIMIT' end.
        result =. One pmod b
        base =. a pmod b
        exponent =. integer 3{::args
        while. exponent>0 do.
            if. 2|exponent do. result =. (result pmul base) pmod b end.
            exponent =. <.exponent%2x
            if. exponent do. base =. (base pmul base) pmod b end.
        end.
        name store_poly result
    case. 'DERIV' do.
        for_i. i.integer 3{::args do. a =. derivative a end.
        name store_poly a
    case. 'INTEG' do.
        if. 30<#a do. fail 'DEGREE LIMIT' end.
        name store_poly integral a
    case. 'AREA' do.
        'u v' =. literals
        antiderivative =. integral a
        upper =. antiderivative peval v
        lower =. antiderivative peval u
        emit 'integral(',name,', ',(fraction u),', ',(fraction v),') = ',fraction upper-lower
    case. 'TANGENT' do.
        c =. 0{::literals
        height =. a peval c
        slope =. (derivative a) peval c
        name store_poly trim (height-slope*c),slope
    case. 'TAYLOR' do.
        c =. 0{::literals
        variable =. 'x'
        if. c>0 do. variable =. '(x - ',(fraction c),')'
        elseif. c<0 do. variable =. '(x + ',(fraction -c),')' end.
        emit 'taylor(',name,', ',(fraction c),') = ',variable notation a compose c,1x
    case. 'COMPOSE' do. name store_poly a compose_checked b
    case. 'EVAL' do.
        for_c. >literals do. emit name,'(',(fraction c),') = ',fraction a peval c end.
    case. 'ROOTS';'FACTOR';'SQFREE';'DESCARTES';'STURM';'ISOLATE';'RESULTANT';'DISCRIM';'POWERSUM' do.
        if. 0=#a do. fail 'ZERO POLYNOMIAL' end.
        select. command
        case. 'ROOTS' do.
            'roots remaining' =. rational_roots a
            terms =. 0$a:
            for_row. roots do.
                'r multiplicity' =. row
                terms =. terms,<(fraction r),' (',(number multiplicity),')'
            end.
            text =. 'none'
            if. #terms do. text =. ', ' join terms end.
            emit 'roots(',name,') = ',text
        case. 'FACTOR' do. emit 'factor(',name,') = ',factorization a
        case. 'SQFREE' do. emit 'sqfree(',name,') = ',squarefree_factors a
        case. 'DESCARTES' do.
            positive =. sign_changes |.a
            negative =. sign_changes |.a*_1x^i.#a
            emit 'descartes(',name,') = positive ',(number positive),', negative ',number negative
        case. 'STURM' do.
            'u v' =. literals
            if. -.u before v do. fail 'BAD INTERVAL' end.
            count =. (sturm_sequence a) root_count u;v
            emit 'sturm(',name,', ',(endpoint_text u),', ',(endpoint_text v),') = ',number count
        case. 'ISOLATE' do.
            n =. integer 2{::args
            IsolationSequence =: sturm_sequence a
            IsolationWidth =: 1x%2x^n
            first =. 0{::IsolationSequence
            bound =. 1x
            if. 1<#first do. bound =. 1x+>./|(}:first)%{:first end.
            intervals =. examine (-bound),bound
            terms =. 0$a:
            for_interval. intervals do.
                'low high' =. >interval
                terms =. terms,<'(',(fraction low),', ',(fraction high),']'
            end.
            text =. 'none'
            if. #terms do. text =. ', ' join terms end.
            emit 'isolate(',name,', ',(number n),') = ',text
        case. 'RESULTANT' do.
            if. 0=#b do. fail 'ZERO POLYNOMIAL' end.
            emit 'res(',name,', ',(2{::args),') = ',fraction a resultant b
        case. 'DISCRIM' do.
            if. 1=#a do. fail 'DEGREE TOO LOW' end.
            d =. degree a
            result =. (a resultant derivative a)%{:a
            if. 2|<.(d*(d-1))%2x do. result =. -result end.
            emit 'disc(',name,') = ',fraction result
        case. 'POWERSUM' do.
            if. 1=#a do. fail 'DEGREE TOO LOW' end.
            d =. degree a
            c =. monic a
            values =. ,0x
            for_j. 1+i.integer 2{::args do.
                total =. 0x
                if. j<:d do. total =. j*(d-j){c end.
                for_i. 1+i.(j-1)<.d do. total =. total+((d-i){c)*(j-i){values end.
                values =. values,-total
            end.
            emit 'powersum(',name,') = ', ', ' join fraction each <"0 }.values
        end.
    case. 'INTERP' do. name store_poly interpolate _2]\>literals
    case. 'SPECIAL' do. name store_poly (2{::args) special integer 3{::args
    end.
)
main =: 3 : 0
    count =. integer 1!:1 3
    for_i. i.count do.
        line =. 1!:1 3
        try. execute line
        catcht. emit 'ERROR ',Error
        end.
    end.
)
main ''
exit 0
