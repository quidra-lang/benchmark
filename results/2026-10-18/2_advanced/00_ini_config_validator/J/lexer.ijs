LF =: 10{a.
HT =: 9{a.
LITERAL_DOLLAR =: 1{a.
Digits =: '0123456789'
Letters =: 'abcdefghijklmnopqrstuvwxyz'

NB. Boxed association tables keep strings and structured values separate.
empty_table =: 3 : '0 2$a:'
table_keys =: 3 : '0{"1 y'
has_key =: 4 : '(<x) e. table_keys y'
get_key =: 4 : '((table_keys y) i. <x) {:: 1{"1 y'
put_key =: 4 : 0
    'key value' =. x
    index =. (table_keys y) i. <key
    if. index < #y do.
        (<value) (<index,1)} y
    else.
        y,1 2$(<key),<value
    end.
)
drop_key =: 4 : '((<x) ~: table_keys y) # y'

number =: 3 : 0
    if. y=0 do. '0' return. end.
    n =. |y
    text =. ''
    while. n>0 do.
        text =. ((10 |!.0 n){Digits),text
        n =. <.!.0 n%10
    end.
    if. y<0 do. '-',text else. text end.
)
decimal =: 3 : '10 #. Digits i. y'
digits =: 3 : '(0<#y) *. *./y e. Digits'
width_digits =: 4 : '((#y)>:0{x) *. ((#y)<:1{x) *. digits y'
ltrim =: 3 : 0
    while. #y do.
        if. ' '~:{.y do. break. end.
        y =. }.y
    end.
    y
)
rtrim =: 3 : 0
    while. #y do.
        if. ' '~:{:y do. break. end.
        y =. }:y
    end.
    y
)
trim_spaces =: rtrim@ltrim
cut_first =: 4 : 0
    positions =. I.x E.y
    if. 0=#positions do. (<y),(<''),<0 return. end.
    position =. {.positions
    (<position{.y),(<(position+#x)}.y),<1
)
split =: 4 : 0
    parts =. 0$a:
    while. 1 do.
        'before after found' =. x cut_first y
        parts =. parts,<before
        if. -.found do. parts return. end.
        y =. after
    end.
)
join =: 4 : 0
    text =. ''
    for_index. i.#y do.
        if. index do. text =. text,x end.
        text =. text,index{::y
    end.
    text
)
read_lines =: 3 : '<;._2 (1!:1 <y)'

NB. Explicit lexical comparison also handles prefixes and section/key order.
lex_less =: 4 : 0
    n =. (#x)<.#y
    different =. I.(n{.x)~:n{.y
    if. #different do.
        i =. {.different
        (a.i.i{x)<a.i.i{y
    else.
        (#x)<#y
    end.
)
sort_by =: 1 : 0
    sorted =. 0$a:
    for_item. y do.
        value =. >item
        position =. #sorted
        while. position>0 do.
            if. -.value u (position-1){::sorted do. break. end.
            position =. position-1
        end.
        sorted =. (position{.sorted),(<value),position}.sorted
    end.
    sorted
)
sort_strings =: lex_less sort_by
section_of =: 3 : '({:I.y=''.''){.y'
key_name =: 3 : '(1+{:I.y=''.'')}.y'
key_less =: 4 : 0
    a =. section_of x
    b =. section_of y
    if. a-:b do. (key_name x) lex_less key_name y else. a lex_less b end.
)
sort_keys =: key_less sort_by

NB. A logical line is (physical start; alternating segments; first error).
logical_lines =: 3 : 0
    physical =. y
    lines =. 0$a:
    index =. 0
    while. index<#physical do.
        start =. index+1
        source =. index{::physical
        index =. index+1
        position =. 0
        quoted =. 0
        current =. ''
        segments =. 0$a:
        error =. 0$a:
        while. position<#source do.
            char =. position{source
            if. (char='\') *. position=<:#source do.
                source =. ltrim index{::physical
                index =. index+1
                position =. 0
            elseif. quoted *. char='\' do.
                follower =. (position+1){source
                escape =. '\"nt$' i.follower
                if. escape<5 do.
                    current =. current,escape{'\"',LF,HT,LITERAL_DOLLAR
                elseif. 0=#error do.
                    error =. (<'E_ESCAPE'),<'invalid escape sequence \',follower
                end.
                position =. position+2
            elseif. char='"' do.
                segments =. segments,<current
                current =. ''
                quoted =. -.quoted
                position =. position+1
            elseif. (-.quoted) *. char e.';#' do.
                break.
            else.
                current =. current,char
                position =. position+1
            end.
        end.
        if. quoted *. 0=#error do. error =. (<'E_UNTERMINATED'),<'unterminated string' end.
        segments =. segments,<current
        lines =. lines,<(<start),(<segments),<error
    end.
    lines
)
