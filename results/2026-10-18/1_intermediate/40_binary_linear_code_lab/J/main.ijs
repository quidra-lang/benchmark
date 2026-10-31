LF =: 10{a.
Letters =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
Digits =: '0123456789'
Commands =: ;:'GEN PCHECK HAMMING SIMPLEX REPETITION PARITY RM CYCLIC DUAL EXTEND PUNCTURE SHORTEN AUGMENT EXPURGATE PERMUTE DIRECTSUM UUV PRODUCT LIST DELETE SHOW INFO SYSTEMATIC WEIGHTS COVERING BURST TRELLIS STDARRAY EQUAL ENCODE SYNDROME DECODE BOUNDED COSET ERASURE INTERLEAVE CRC CRCCHECK FACTOR MACWILLIAMS BOUNDS'
Forms =: 'nb';'nb';'ni';'ni';'ni';'ni';'nii';'nib';'nn';'nn';'nni';'nni';'nn';'nn';'nni';'nnn';'nnn';'nnn';'';'n';'n';'n';'n';'n';'n';'n';'n';'n';'nn';'nb';'nb';'nb';'nib';'nb';'ne';'niib';'bb';'bb';'i';'ii';'ii'
Names =: Codes =: 0$a:
Error =: ''
band =: 17 b.
bxor =: 22 b.
bor =: 23 b.
number =: 3 : ',''0'' 8!:2 y'
binary =: 3 : '#.''01''i.y'
bits =: 4 : '''01''{(x#2)#:y'
weight =: 3 : '+/#:y'
bitlength =: 3 : 'if. y=0 do. 0 else. ##:y end.'
mask =: 3 : '<:2^y'
yes =: 3 : 'y{::''no'';''yes'''
encoder =: 3 : '(0~:3{::y){::''matrix'';''polynomial'''
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
emit =: 3 : 'Output =: Output,<y'
out =: 3 : 0
    parts =. 0$a:
    for_part. y do.
        value =. >part
        if. 2~:3!:0 value do. value =. number value end.
        parts =. parts,<value
    end.
    emit ' ' join parts
)
fail =: 3 : 0
    Error =: y
    throw.
)
valid =: 4 : 0
    select. x
    case. 'n' do. ((#y)<:8)*.(({.y)e.Letters)*.*./y e.Letters,Digits
    case. 'i' do. ((#y)<:4)*.(*./y e.Digits)*.((1=#y)+.'0'~:{.y)
    case. 'b' do. ((#y)<:30)*.*./y e.'01'
    case. 'e' do. ((#y)<:30)*.*./y e.'01?'
    end.
)
lookup =: 3 : 0
    index =. Names i.<y
    if. index=#Names do. fail 'no code ',y end.
    index{::Codes
)
dimension =: 3 : 0
    'n k' =. y
    if. -.(k e.1+i.12)*.(n-k)e.1+i.12 do.
        fail 'bad dimension ',(number n),' ',number k
    end.
)

basis =: 4 : 0
    pivots =. x#0
    selected =. i.0
    for_row. y do.
        value =. row
        for_column. i.x do.
            bit =. 2^(x-1)-column
            if. 0=bit band value do. continue. end.
            if. column{pivots do. value =. value bxor column{pivots
            else.
                pivots =. value column}pivots
                selected =. selected,row
                break.
            end.
        end.
    end.
    selected
)
rref =: 4 : 0
    rows =. y
    pivots =. i.0
    for_column. i.x do.
        count =. #pivots
        bit =. 2^(x-1)-column
        candidates =. I.0~:bit band count}.rows
        if. 0=#candidates do. continue. end.
        index =. count+{.candidates
        rows =. ((index,count){rows) (count,index)}rows
        others =. (I.0~:bit band rows)-.count
        rows =. ((others{rows) bxor count{rows) others}rows
        pivots =. pivots,column
    end.
    ((#pivots){.rows);pivots
)
nullspace =: 4 : 0
    'rows pivots' =. x rref y
    result =. i.0
    for_free. (i.x)-.pivots do.
        bit =. 2^(x-1)-free
        value =. bit
        for_index. I.0~:bit band rows do.
            value =. value+2^(x-1)-index{pivots
        end.
        result =. result,value
    end.
    result
)
span =: 3 : 0
    result =. ,0
    for_row. y do. result =. result,row bxor result end.
    result
)
divide =: 4 : 0
    quotient =. 0
    remainder =. x
    size =. bitlength y
    while. size<:bitlength remainder do.
        power =. 2^(bitlength remainder)-size
        quotient =. quotient+power
        remainder =. remainder bxor y*power
    end.
    quotient,remainder
)
remainder =: 4 : '1{x divide y'
encode =: 4 : 0
    'n g h polynomial' =. x
    if. polynomial do.
        shifted =. y*2^n-#g
        shifted bxor shifted remainder polynomial
    else. bxor/0,(((#g)#2)#:y)#g
    end.
)
encoded_words =: 3 : 0
    'n g h polynomial' =. y
    if. 0=polynomial do. span |.g
    else. y&encode"0 i.2^#g
    end.
)
syndrome =: 4 : '#.2|weight"0 (2{::x) band y'
leaders =: 3 : 0
    'n g h polynomial' =. y
    remaining =. <:2^#h
    result =. 0,remaining#_1
    for_w. 1+i.n do.
        candidate =. mask w
        while. candidate<2^n do.
            s =. y syndrome candidate
            if. _1=s{result do.
                result =. candidate s}result
                remaining =. remaining-1
                if. remaining=0 do. result return. end.
            end.
            low =. candidate band -candidate
            next =. candidate+low
            candidate =. next bor <.(candidate bxor next)%(4*low)
        end.
    end.
    result
)
burst_correct =: 3 : 0
    'n g h polynomial' =. y
    seen =. 1,(<:2^#h)#0
    for_size. 1+i.n do.
        for_middle. i.2^0>.size-2 do.
            pattern =. 1
            if. size>1 do. pattern =. (2^size-1)+1+2*middle end.
            for_shift. i.1+n-size do.
                s =. y syndrome pattern*2^shift
                if. s{seen do. size-1 return. end.
                seen =. 1 s}seen
            end.
        end.
    end.
)
distribution =: 4 : 0
    values =. weight"0 y
    result =. (x+1)#0
    if. #values do. result =. (#/.~values) (~.values)}result end.
    result
)
weight_list =: 3 : 0
    parts =. 0$a:
    for_i. I.0~:y do. parts =. parts,<(number i),':',number i{y end.
    ' ' join parts
)
choose =: 4 : 0
    if. (x<0)+.x>y do. 0 else. (<y,x){Choose end.
)
volume =: 4 : '+/(i.1+y) choose"0 x'
fraction =: 4 : 0
    divisor =. x+.y
    numerator =. x%divisor
    denominator =. y%divisor
    if. denominator=1 do. number numerator
    else. (number numerator),'/',number denominator end.
)
reed_muller =: 3 : 0
    'r m' =. y
    if. r=0 do. ,mask 2^m return. end.
    half =. 2^m-1
    first =. reed_muller (r<.m-1),(m-1)
    second =. reed_muller (r-1),(m-1)
    ((first*2^half)+first),second
)
remove_column =: 4 : 0
    'n column' =. x
    #."1 ((i.n)-.column){"1 (n#2)#:y
)

construct =: 3 : 0
    'kind args a b' =. y
    h =. _1
    polynomial =. 0
    select. kind
    case. 0;1 do.
        words =. }.args
        lengths =. #&>words
        if. 1~:#~.lengths do. fail 'bad length' end.
        n =. {.lengths
        g =. n basis binary&>words
        if. kind=1 do.
            h =. g
            g =. n nullspace h
        end.
    case. 2;3 do.
        r =. 0".1{::args
        if. -.r e.2 3 4 do. fail 'bad parameter' end.
        n =. mask r
        g =. #."1 |:(r#2)#:1+i.n
        if. kind=2 do.
            h =. g
            g =. n nullspace h
        end.
    case. 4;5 do.
        n =. 0".1{::args
        if. (n<2)+.n>24 do. fail 'bad parameter' end.
        if. kind=4 do. g =. ,mask n
        else. g =. 1+2^(n-1)-i.(n-1) end.
    case. 6 do.
        'r m' =. 0".&>1}.args
        if. (m<1)+.(m>4)+.r>m do. fail 'bad parameter' end.
        n =. 2^m
        g =. reed_muller r,m
    case. 7 do.
        n =. 0".1{::args
        text =. 2{::args
        if. (n<2)+.(n>24)+.('0'={.text)+.((#text)<2)+.(#text)>n do. fail 'bad parameter' end.
        polynomial =. binary text
        if. 0~:(1+2^n) remainder polynomial do. fail 'not a divisor' end.
        d =. (#text)-1
        k =. n-d
        g =. polynomial*2^|.i.k
        columns =. (2^|.i.n) remainder"0 polynomial
        h =. #."1 |:(d#2)#:columns
    case. 8;9;10;11;12;13;14 do.
        'old g oldh oldpoly' =. a
        n =. old
        select. kind
        case. 8 do.
            h =. g
            g =. oldh
        case. 9 do.
            n =. old+1
            g =. (2*g)+2|weight"0 g
        case. 10;11 do.
            position =. 0".2{::args
            if. (position<1)+.position>old do. fail 'bad position' end.
            n =. old-1
            if. kind=11 do.
                bit =. 2^old-position
                selected =. I.0~:bit band g
                if. #selected do.
                    index =. {.selected
                    row =. index{g
                    g =. ((i.#g)-.index){g
                    selected =. I.0~:bit band g
                    g =. ((selected{g) bxor row) selected}g
                end.
            end.
            g =. (old,position-1) remove_column g
            if. kind=10 do. g =. n basis g end.
        case. 12 do. g =. n basis g,mask n
        case. 13 do.
            selected =. I.2|weight"0 g
            if. #selected do.
                index =. {.selected
                row =. index{g
                g =. ((i.#g)-.index){g
                selected =. I.2|weight"0 g
                g =. ((selected{g) bxor row) selected}g
            end.
        case. 14 do.
            permutation =. 0".&>2}.args
            if. -.(1+i.n)-:/:~permutation do. fail 'bad permutation' end.
            g =. #."1 (permutation-1){"1 (n#2)#:g
        end.
    case. 15;16;17 do.
        'na ga ha pa' =. a
        'nb gb hb pb' =. b
        if. (kind=16)*.na~:nb do. fail 'bad length' end.
        if. kind=17 do.
            n =. na*nb
            k =. (#ga)*#gb
        else.
            n =. na+nb
            k =. (#ga)+#gb
        end.
        dimension n,k
        if. kind=15 do. g =. (ga*2^nb),gb
        elseif. kind=16 do. g =. ((ga*2^nb)+ga),gb
        else.
            g =. i.0
            for_left. ga do.
                for_right. gb do.
                    g =. g,#.,((na#2)#:left) */ (nb#2)#:right
                end.
            end.
        end.
    end.
    dimension n,#g
    if. _1-:h do. h =. n nullspace g end.
    n;g;h;polynomial
)

numbers =: 3 : ''' '' join number&.> <"0 y'
bit_list =: 4 : ''' '' join <"1 x bits y'
systematic =: 4 : 0
    'n rows h polynomial' =. y
    k =. #rows
    redundancy =. n-k
    permutation =. 1+i.n
    for_r. i.k do.
        bit =. 2^(n-1)-r
        if. -. +./0~:bit band r}.rows do.
            chosen =. r
            for_column. (r+1)}.i.n do.
                other =. 2^(n-1)-column
                if. +./0~:other band r}.rows do.
                    chosen =. column
                    break.
                end.
            end.
            selected =. I.(0~:bit band rows)~:0~:other band rows
            rows =. ((selected{rows) bxor bit bor other) selected}rows
            permutation =. ((chosen,r){permutation) (r,chosen)}permutation
        end.
        index =. r+{.I.0~:bit band r}.rows
        rows =. ((index,r){rows) (r,index)}rows
        selected =. (I.0~:bit band rows)-.r
        rows =. ((selected{rows) bxor r{rows) selected}rows
    end.
    out 'systematic';x;'perm';numbers permutation
    for_row. rows do. out 'G';n bits row end.
    for_j. i.redundancy do.
        column =. 0~:(2^(n-1)-(k+j)) band rows
        row =. ((#.column)*2^redundancy)+2^(redundancy-1)-j
        out 'H';n bits row
    end.
)
independent =: 4 : 0
    select. x
    case. 36;37 do.
        text =. 0{::y
        if. ('0'={.text)+.((#text)<2)+.(#text)>17 do. fail 'bad parameter' end.
        d =. (#text)-1
        polynomial =. binary text
        message =. 1{::y
        if. x=36 do.
            if. 30<d+#message do. fail 'bad length' end.
            r =. ((binary message)*2^d) remainder polynomial
            out 'crc';'remainder';(d bits r);'frame';message,d bits r
        else.
            r =. (binary message) remainder polynomial
            out 'crccheck';((0=r){::'error';'ok');'remainder';d bits r
        end.
    case. 38 do.
        n =. 0".0{::y
        if. (n<1)+.n>24 do. fail 'bad parameter' end.
        remaining =. 1+2^n
        factor =. 3
        parts =. 0$a:
        divisors =. 1
        while. (2*((bitlength factor)-1))<:(bitlength remaining)-1 do.
            exponent =. 0
            while. 0=remaining remainder factor do.
                remaining =. 0{remaining divide factor
                exponent =. exponent+1
            end.
            if. exponent do.
                parts =. parts,<((bitlength factor) bits factor),'^',number exponent
                divisors =. divisors*exponent+1
            end.
            factor =. factor+2
        end.
        if. remaining>1 do.
            parts =. parts,<((bitlength remaining) bits remaining),'^1'
            divisors =. divisors*2
        end.
        out ('factor';n),parts,('divisors';divisors)
    case. 39 do.
        n =. 0".0{::y
        if. (n<1)+.n>24 do. fail 'bad parameter' end.
        counts =. 0".&>}.y
        if. (n+1)~:#counts do. fail 'bad length' end.
        if. 1~:{.counts do. fail 'bad parameter' end.
        total =. +/counts
        numerators =. i.0
        for_degree. i.1+n do.
            value =. 0
            terms =. i.1+degree
            for_column. i.1+n do.
                coefficient =. +/(_1^terms)*(terms choose"0 column)*((degree-terms) choose"0 n-column)
                value =. value+(column{counts)*coefficient
            end.
            numerators =. numerators,value
        end.
        fractions =. 0$a:
        for_value. numerators do. fractions =. fractions,<value fraction total end.
        feasible =. (0=total band total-1)*.(*./0=total|numerators)*.*./numerators>:0
        out 'macwilliams';'n';n;'size';total
        out 'dual';' ' join fractions
        out 'feasible';yes feasible
    case. 40 do.
        'n d' =. 0".&>y
        if. (d<1)+.(d>n)+.n>24 do. fail 'bad parameter' end.
        v =. n volume <.(d-1)%2
        hamming =. {:I.((2^i.1+n)*v)<:2^n
        griesmer =. +/(+/\ >.d%2^i.n)<:n
        out 'bounds';'n';n;'d';d;'singleton';((n-d)+1);'hamming';hamming;'griesmer';griesmer
    end.
)

execute =: 3 : 0
    Output =: 0$a:
    tokens =. <;._1 ' ',y
    command =. 0{::tokens
    kind =. Commands i.<command
    if. kind=#Commands do. fail 'unknown command ',command end.
    args =. }.tokens
    form =. kind{::Forms
    minimum =. maximum =. #form
    select. kind
    case. 0;1 do. maximum =. 25
    case. 14;39 do. maximum =. 26
    case. 35 do. maximum =. 11
    end.
    if. ((#args)<minimum)+.(#args)>maximum do. fail 'bad arguments' end.
    for_i. i.#args do.
        if. -.((i<.<:#form){form) valid i{::args do. fail 'bad arguments' end.
    end.
    a =. b =. 0
    if. kind e.8+i.10 do.
        a =. lookup 1{::args
        if. kind e.15 16 17 do. b =. lookup 2{::args end.
    elseif. kind e.19+i.17 do.
        a =. lookup 0{::args
        if. kind=28 do. b =. lookup 1{::args end.
    end.
    if. kind<18 do.
        code =. construct (<kind),(<args),(<a),<b
        name =. 0{::args
        index =. Names i.<name
        if. index=#Names do.
            Names =: Names,<name
            Codes =: Codes,<code
            status =. 'defined'
        else.
            Codes =: (<code) index}Codes
            status =. 'redefined'
        end.
        out status;name;'n';(0{::code);'k';#1{::code
        Output return.
    elseif. kind>=36 do.
        kind independent args
        Output return.
    elseif. kind=18 do.
        out 'codes';#Names
        for_index. /:s:Names do.
            code =. index{::Codes
            out (index{::Names);'n';(0{::code);'k';(#1{::code);'encoder';encoder code
        end.
        Output return.
    end.
    name =. 0{::args
    'n g h polynomial' =. a
    k =. #g
    redundancy =. n-k
    select. kind
    case. 19 do.
        keep =. (i.#Names)-.Names i.<name
        Names =: keep{Names
        Codes =: keep{Codes
        out 'deleted';name
    case. 20 do.
        out 'code';name;'n';n;'k';k;'encoder';encoder a
        if. polynomial do.
            quotient =. 0{(1+2^n) divide polynomial
            out 'poly';'g';((redundancy+1) bits polynomial);'h';(k+1) bits quotient
        end.
        for_row. g do. out 'G';n bits row end.
        for_row. h do. out 'H';n bits row end.
    case. 21 do.
        words =. }.span g
        d =. <./weight"0 words
        t =. <.(d-1)%2
        rotated =. ((mask n) band 2*g)+<.g%2^n-1
        cyclic =. 'no'
        if. *./0=a&syndrome"0 rotated do.
            least =. <./words
            cyclic =. (bitlength least) bits least
        end.
        out 'info';name;'n';n;'k';k;'rate';(k fraction n);'d';d;'t';t;'perfect';(yes (n volume t)=2^redundancy);'mds';(yes d=redundancy+1);'cyclic';cyclic
    case. 22 do. name systematic a
    case. 23 do.
        primary =. n distribution span g
        dual =. n distribution span h
        orthogonal =. *./0=2|weight"0 ,g band/ g
        out 'weights';name;weight_list primary
        out 'dual';name;weight_list dual
        out 'duality';name;'self-orthogonal';(yes orthogonal);'self-dual';(yes orthogonal*.n=2*k);'formally-self-dual';yes primary-:dual
    case. 24 do.
        counts =. n distribution leaders a
        radius =. {:I.0~:counts
        items =. 0$a:
        for_i. i.1+radius do. items =. items,<(number i),':',number i{counts end.
        out 'covering';name;'radius';radius;'leaders';' ' join items
    case. 25 do.
        words =. }.span g
        detect =. <./(bitlength"0 words)-bitlength"0 words band -words
        out 'burst';name;'detect';detect;'correct';burst_correct a
    case. 26 do.
        profile =. i.0
        for_i. i.1+n do.
            right =. n-i
            rank1 =. #i basis <.g%2^right
            rank2 =. #right basis g band mask right
            profile =. profile,(rank1+rank2)-k
        end.
        out 'trellis';name;'profile';(numbers profile);'max';>./profile
    case. 27 do.
        if. (redundancy>6)+.k>4 do. fail 'too large' end.
        errors =. leaders a
        order =. /:(weight"0 errors),.errors
        words =. /:~span g
        out 'stdarray';name;'rows';(#errors);'columns';#words
        for_s. order do.
            emit (redundancy bits s),': ',n bit_list (s{errors) bxor words
        end.
    case. 28 do.
        'nb gb hb pb' =. b
        other =. 1{::args
        if. n~:nb do. out 'equal';name;other;'no';'lengths';n;nb
        else.
            common =. (k+#gb)-#n basis g,gb
            out 'equal';name;other;(yes (k=common)*.(#gb)=common);'intersection';common
        end.
    case. 29 do.
        message =. 1{::args
        if. k~:#message do. fail 'bad length' end.
        out 'encode';name;'message';message;'codeword';n bits a encode binary message
    case. 30;31;32;33 do.
        text =. (1+kind=32){::args
        if. n~:#text do. fail 'bad length' end.
        word =. binary text
        s =. a syndrome word
        if. kind=30 do.
            out 'syndrome';name;(redundancy bits s);'codeword';yes s=0
        else.
            error =. s{leaders a
            if. kind=33 do.
                out 'coset';name;'syndrome';(redundancy bits s);'leader';(n bits error);'weights';weight_list n distribution word bxor span g
            else.
                corrected =. word bxor error
                message =. (encoded_words a)i.corrected
                prefix =. (kind=32){::'decode';'bounded'
                bounded_fail =. 0
                if. kind=32 do. bounded_fail =. (weight error)>0".1{::args end.
                if. bounded_fail do.
                    out prefix;name;'fail';'weight';weight error
                else.
                    out prefix;name;'codeword';(n bits corrected);'message';(k bits message);'error';(n bits error);'weight';weight error
                end.
            end.
        end.
    case. 34 do.
        text =. 1{::args
        if. n~:#text do. fail 'bad length' end.
        known =. #.text~:'?'
        value =. #.text='1'
        words =. span g
        candidates =. words#~value=known band words
        parts =. 'erasure';name;'erased';(+/text='?');'candidates';#candidates
        if. 1=#candidates do.
            word =. {.candidates
            parts =. parts,('codeword';(n bits word);'message';k bits (encoded_words a)i.word)
        end.
        out parts
    case. 35 do.
        texts =. 3}.args
        if. -. *./k=#&>texts do. fail 'bad length' end.
        'start size' =. 0".&>1 2{args
        depth =. #texts
        if. (start<1)+.(size<1)+.((start+size)-1)>depth*n do. fail 'bad burst' end.
        messages =. binary&>texts
        sent_rows =. a&encode"0 messages
        sent =. ,|:(n#2)#:sent_rows
        positions =. (start-1)+i.size
        received =. (-.positions{sent) positions}sent
        received_rows =. #."1 |:(n,depth)$received
        out 'interleave';name;'depth';depth;'burst';start;size
        out 'sent';'01'{sent
        out 'recv';'01'{received
        errors =. leaders a
        encoded =. encoded_words a
        correct =. 0
        for_i. i.depth do.
            error =. (a syndrome i{received_rows){errors
            message =. encoded i.error bxor i{received_rows
            ok =. message=i{messages
            correct =. correct+ok
            out 'row';(i+1);'errors';(weight (i{sent_rows) bxor i{received_rows);'corrected';(weight error);'message';(k bits message);ok{::'wrong';'ok'
        end.
        out 'result';'ok';correct;'wrong';depth-correct
    end.
    Output
)

main =: 3 : 0
    Choose =: 1 (<0 0)}25 25$0
    for_n. 1+i.24 do.
        previous =. (n-1){Choose
        Choose =: (previous+0,}:previous) n}Choose
    end.
    count =. 0".1!:1[3
    for_command. i.count do.
        line =. 1!:1[3
        try. rows =. execute line
        catcht. rows =. <'error: ',Error end.
        for_row. rows do. ((>row),LF) 1!:2[4 end.
    end.
)
main ''
2!:55[0
