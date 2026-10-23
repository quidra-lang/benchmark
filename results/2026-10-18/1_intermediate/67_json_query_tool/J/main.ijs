LF =: 10{a.
Letters =: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
Digits =: '0123456789'
Output =: 0$a:
num =: 3 : ',''0'' 8!:2 y'
emit =: 3 : 'Output=:Output,<y'
join =: 4 : '(#x)}.;(<x),&.>y'
split =: 4 : 0
    result=.0$a:
    start=.0
    for_i. i.#y do.
        if. x=i{y do.
            result=.result,<(i-start){.start}.y
            start=.i+1
        end.
    end.
    result,<start}.y
)
fail =: 3 : 0
    Reason=:'ERROR ',y
    throw.
)
check =: 4 : 'if. -.y do. fail x end.'
identifier =: 3 : 0
    if. 0=#y do. 0 return. end.
    (({.y)e.Letters,'_')*.*./y e.Letters,Digits,'_'
)
integerWord =: 3 : 0
    if. y-:'0' do. 1 return. end.
    if. '-'={.y do. y=.}.y end.
    if. (0=#y)+.9<#y do. 0 return. end.
    ('0'~:{.y)*.*./y e.Digits
)
parseInt =: 3 : 0
    if. '-'={.y do. -0".}.y else. 0".y end.
)
hexValue =: 3 : 0
    if. (4~:#y)+.-.*./y e.'0123456789abcdefABCDEF' do. _1 return. end.
    16#.16|'0123456789abcdef0123456789ABCDEF'i.y
)
quote =: 4 : 0
    out=.x
    for_c. y do.
        n=.a.i.c
        if. c=x do. out=.out,'\',c
        elseif. c='\' do. out=.out,'\\'
        elseif. n e.8 12 10 13 9 do. out=.out,'\',(8 12 10 13 9 i.n){'bfnrt'
        elseif. (n<32)+.n=127 do. out=.out,'\u00','0123456789abcdef'{~16 16#:n
        else. out=.out,c end.
    end.
    out,x
)
kind =: 3 : '0{::y'
scalar =: 3 : '1{::y'
keys =: 3 : '2{::y'
items =: 3 : '3{::y'
Null =: (<'null'),(<0),(<0$a:),<0$a:
stringValue =: 3 : '(<''string''),(<y),(<0$a:),<0$a:'
valueCount =: 3 : '1++/valueCount&>items y'
valueDepth =: 3 : '1+>./0,valueDepth&>items y'
compact =: 3 : 0
    k=.kind y
    select. k
    case. 'null' do. 'null'
    case. 'boolean' do. (scalar y){::'false';'true'
    case. 'number' do. num scalar y
    case. 'string' do. '"'quote scalar y
    case. 'array' do. '[',(','join compact&.>items y),']'
    case. do.
        parts=.0$a:
        for_i. i.#items y do. parts=.parts,<('"'quote i{::keys y),':',compact i{::items y end.
        '{',(','join parts),'}'
    end.
)
pretty =: 4 : 0
    if. 0=#items y do. compact y return. end.
    inner=.x,'  '
    parts=.0$a:
    for_i. i.#items y do.
        label=.''
        if. 'object'-:kind y do. label=.('"'quote i{::keys y),': ' end.
        parts=.parts,<inner,label,inner pretty i{::items y
    end.
    if. 'object'-:kind y do. braces=.'{}' else. braces=.'[]' end.
    ({.braces),LF,(((',' ,LF)join parts)),LF,x,{:braces
)
equalValue =: 4 : 0
    if. -. (kind x)-:kind y do. 0 return. end.
    if. (<kind x)e.'array';'object' do.
        if. (#items x)~:#items y do. 0 return. end.
        for_i. i.#items x do.
            j=.i
            if. 'object'-:kind x do. j=.(keys y)i.i{keys x end.
            if. j=#items y do. 0 return. end.
            if. -. (i{::items x)equalValue j{::items y do. 0 return. end.
        end.
        1
    else. (scalar x)-:scalar y end.
)
peek =: 3 : 'if. Pos<#Text do. Pos{Text else. '''' end.'
jsonFail =: 4 : 0
    ErrorPos=:x
    ErrorReason=:y
    Reason=:'PARSE ERROR col ',(num x+1),': ',y
    throw.
)
skip =: 3 : 'while. (<peek'''')e.(<'' ''),<LF do. Pos=:Pos+1 end.'
expect =: 4 : 0
    if. 0=#peek'' do. Pos jsonFail 'unexpected end of input' end.
    if. -.x-:peek'' do. Pos jsonFail y end.
)
readString =: 3 : 0
    Pos=:Pos+1
    out=.''
    while. 1 do.
        c=.peek''
        if. (<c)e.('';LF) do. Pos jsonFail 'unterminated string' end.
        Pos=:Pos+1
        if. c='"' do. out return. end.
        if. c~:'\' do. out=.out,c continue. end.
        start=.Pos-1
        e=.peek''
        if. (<e)e.('';LF) do. Pos jsonFail 'unterminated string' end.
        if. e='u' do.
            n=.hexValue 4{.(Pos+1)}.Text
            if. n<0 do. start jsonFail 'bad unicode escape' end.
            if. n>127 do. start jsonFail 'non-ascii escape' end.
            out=.out,n{a.
            Pos=:Pos+5
        else.
            i=.'"\/bfnrt'i.e
            if. i=8 do. start jsonFail 'invalid escape ''\',e,'''' end.
            out=.out,i{('"\/',(8 12 10 13 9){a.)
            Pos=:Pos+1
        end.
    end.
)
readNumber =: 3 : 0
    start=.Pos
    negative=.'-'-:peek''
    Pos=:Pos+negative
    first=.Pos
    while. (0<#peek'')*.(peek'')e.Digits do. Pos=:Pos+1 end.
    digits=.(Pos-first){.first}.Text
    if. 0=#digits do. start jsonFail 'invalid number' end.
    if. (1<#digits)*.'0'={.digits do. first jsonFail 'leading zero' end.
    if. '.'-:peek'' do. Pos jsonFail 'fraction not allowed' end.
    if. (<peek'')e.'e';'E' do. Pos jsonFail 'exponent not allowed' end.
    if. 9<#digits do. start jsonFail 'number out of range' end.
    (<'number'),(<((0".digits)*1-2*negative)),(<0$a:),<0$a:
)
readValue =: 3 : 0
    skip''
    c=.peek''
    if. 0=#c do. Pos jsonFail 'unexpected end of input' end.
    if. c='"' do. stringValue readString'' return. end.
    if. (c='-')+.c e.Digits do. readNumber'' return. end.
    if. c e.Letters do.
        start=.Pos
        while. (0<#peek'')*.(peek'')e.Letters do. Pos=:Pos+1 end.
        word=.(Pos-start){.start}.Text
        if. word-:'null' do. Null return. end.
        if. (<word)e.'true';'false' do. (<'boolean'),(<word-:'true'),(<0$a:),<0$a: return. end.
        start jsonFail 'invalid literal ''',word,''''
    end.
    if. -.c e.'{[' do. Pos jsonFail 'unexpected character ''',c,'''' end.
    object=.c='{'
    if. object do. closing=.'}' else. closing=.']' end.
    ks=.0$a:
    vs=.0$a:
    Pos=:Pos+1
    skip''
    if. closing-:peek'' do. Pos=:Pos+1
    else.
        while. 1 do.
            if. object do.
                skip''
                '"'expect 'expected key'
                start=.Pos
                key=.readString''
                if. (<key)e.ks do. start jsonFail 'duplicate key ','"'quote key end.
                skip''
                ':'expect 'expected '':'''
                Pos=:Pos+1
                ks=.ks,<key
            end.
            vs=.vs,<readValue''
            skip''
            if. closing-:peek'' do. Pos=:Pos+1 break. end.
            if. object do. message=.'expected '','' or ''}''' else. message=.'expected '','' or '']''' end.
            ','expect message
            Pos=:Pos+1
            skip''
            if. closing-:peek'' do. Pos jsonFail 'trailing comma' end.
        end.
    end.
    (<object{::'array';'object'),(<0),(<ks),<vs
)
parseJson =: 3 : 0
    Text=:y
    Pos=:0
    result=.readValue''
    skip''
    if. Pos<#Text do. Pos jsonFail 'trailing characters' end.
    result
)
ppeek =: 3 : 'if. PPos<#PText do. PPos{PText else. '''' end.'
paccept =: 3 : 0
    if. -.y-:ppeek'' do. 0 return. end.
    PPos=:PPos+1
    1
)
pexpect =: 3 : 'if. -.paccept y do. fail PError end.'
readIdentifier =: 3 : 0
    start=.PPos
    if. (0=#ppeek'')+.-.(ppeek'')e.Letters,'_' do. fail PError end.
    while. (0<#ppeek'')*.(ppeek'')e.Letters,Digits,'_' do. PPos=:PPos+1 end.
    (PPos-start){.start}.PText
)
readKey =: 3 : 0
    pexpect ''''
    out=.''
    while. 1 do.
        c=.ppeek''
        if. 0=#c do. fail PError end.
        PPos=:PPos+1
        if. c='''' do. out return. end.
        if. c~:'\' do. out=.out,c continue. end.
        e=.ppeek''
        if. 0=#e do. fail PError end.
        PPos=:PPos+1
        if. e='u' do.
            n=.hexValue 4{.PPos}.PText
            if. (n<0)+.n>127 do. fail PError end.
            out=.out,n{a.
            PPos=:PPos+4
        else.
            i=.('''\/bfnrt')i.e
            if. i=8 do. fail PError end.
            out=.out,i{('''\/',(8 12 10 13 9){a.)
        end.
    end.
)
segment =: 3 : '(<y),(<''''),(<0),(<a:),(<a:),<0'
readSelection =: 3 : 0
    if. ''''-:ppeek'' do.
        key=.readKey''
        pexpect ']'
        (<key)1}segment 'key'
        return.
    end.
    start=.PPos
    while. (0<#ppeek'')*.-.']'-:ppeek'' do. PPos=:PPos+1 end.
    content=.(PPos-start){.start}.PText
    pexpect ']'
    if. content-:'*' do. segment 'all' return. end.
    if. integerWord content do. (<parseInt content)2}segment 'index' return. end.
    parts=.':'split content
    if. 2~:#parts do. fail PError end.
    s=.segment 'slice'
    for_i. i.2 do.
        bound=.i{::parts
        if. #bound do.
            if. -.integerWord bound do. fail PError end.
            s=.(<parseInt bound)(3+i)}s
        end.
    end.
    s
)
parsePath =: 4 : 0
    PText=:y
    PPos=:0
    PError=:(x{::'bad path';'bad field')
    pexpect x{'$@'
    out=.0$a:
    while. PPos<#PText do.
        if. paccept '[' do.
            s=.readSelection''
            if. x do. if. -. (<0{::s)e.'key';'index' do. fail PError end. end.
        else.
            pexpect '.'
            descendant=.0
            if. -.x do. descendant=.paccept '.' end.
            if. (-.x)*.'*'-:ppeek'' do. PPos=:PPos+1
                s=.segment 'all'
            elseif. descendant*.'['-:ppeek'' do. PPos=:PPos+1
                s=.readSelection''
            else. s=.(<readIdentifier'')1}segment 'key' end.
            s=.(<descendant)5}s
        end.
        out=.out,<s
    end.
    out
)
parseKey =: 3 : 0
    PText=:y
    PPos=:0
    PError=:'bad key'
    if. ''''-:ppeek'' do. result=.readKey'' else. result=.readIdentifier'' end.
    if. PPos<#PText do. fail PError end.
    result
)
child =: 4 : 0
    'v steps'=.x
    flag=.'object'-:kind v
    key=.''
    if. flag do. key=.y{::keys v end.
    (<y{::items v),<steps,<flag;key;y
)
location =: 3 : 0
    out=.'$'
    for_step. 1{::y do.
        'flag key position'=.>step
        if. -.flag do. out=.out,'[',(num position),']'
        elseif. identifier key do. out=.out,'.',key
        else. out=.out,'[',(''''quote key),']' end.
    end.
    out
)
preorder =: 3 : 0
    result=.,<y
    for_i. i.#items 0{::y do. result=.result,preorder y child i end.
    result
)
childPosition =: 4 : 0
    if. 'key'-:0{::y do.
        if. 'object'-:kind x do.
            p=.(keys x)i.<1{::y
            if. p<#items x do. p else. _1 end.
        else. _1 end.
        return.
    end.
    if. -. 'array'-:kind x do. _1 return. end.
    p=.2{::y
    if. p<0 do. p=.p+#items x end.
    if. (p>:0)*.p<#items x do. p else. _1 end.
)
clampBound =: 4 : 0
    if. y<0 do. y=.y+x end.
    0>.x<.y
)
applySegment =: 4 : 0
    result=.0$a:
    for_m. y do.
        m=.>m
        if. 5{::x do. sources=.preorder m else. sources=.,<m end.
        for_source. sources do.
            source=.>source
            v=.0{::source
            k=.0{::x
            positions=.i.0
            if. k-:'all' do. positions=.i.#items v
            elseif. k-:'slice' do.
                if. 'array'-:kind v do.
                    n=.#items v
                    a=.0
                    b=.n
                    if. -.a:-:3{::x do. a=.n clampBound 3{::x end.
                    if. -.a:-:4{::x do. b=.n clampBound 4{::x end.
                    positions=.a+i.0>.b-a
                end.
            else.
                p=.v childPosition x
                if. p>:0 do. positions=.,p end.
            end.
            for_p. positions do. result=.result,<source child p end.
        end.
    end.
    result
)
evaluate =: 4 : 0
    result=.,<(<x),<0$a:
    for_s. y do. result=.(>s)applySegment result end.
    result
)
fieldValue =: 4 : 0
    for_s. y do.
        p=.x childPosition >s
        if. p<0 do. a: return. end.
        x=.p{::items x
    end.
    x
)
filterHolds =: 4 : 0
    'op reference'=.x
    if. op-:'EXISTS' do. -.y-:a: return. end.
    same=.0
    if. -.y-:a: do. same=.y equalValue reference end.
    if. op-:'==' do. same return. end.
    if. op-:'!=' do. -.same return. end.
    if. y-:a: do. 0 return. end.
    if. -. (kind y)-:kind reference do. 0 return. end.
    if. -. (<kind y)e.'number';'string' do. 0 return. end.
    a=.scalar y
    b=.scalar reference
    if. 'string'-:kind y do.
        less=.(0={./:a;b)*.-.a-:b
        more=.(1={./:a;b)*.-.a-:b
    else. less=.a<b
        more=.a>b end.
    select. op
    case. '<' do. less
    case. '<=' do. -.more
    case. '>' do. more
    case. do. -.less
    end.
)
positions =: 3 : '2&{::&>1{::y'
earlier =: 4 : 0
    n=.(#x)<.#y
    for_i. i.n do. if. (i{x)~:i{y do. (i{x)<i{y return. end. end.
    (#x)<#y
)
targets =: 3 : 0
    out=.0$a:
    for_m. y do.
        m=.>m
        p=.positions m
        at=.#out
        duplicate=.0
        for_i. i.#out do.
            q=.positions i{::out
            if. p-:q do. duplicate=.1 break. end.
            if. q earlier p do. at=.i break. end.
        end.
        if. -.duplicate do. out=.(at{.out),(<m),at}.out end.
    end.
    out
)
resolve =: 4 : 0
    for_p. y do. x=.p{::items x end.
    x
)
replaceAt =: 4 : 0
    'path replacement'=.y
    if. 0=#path do. replacement return. end.
    p=.{.path
    children=.items x
    children=.(<((p{::children)replaceAt (}.path);<replacement))p}children
    (<children)3}x
)
deepMerge =: 4 : 0
    ks=.keys x
    vs=.items x
    for_i. i.#items y do.
        key=.i{::keys y
        patch=.i{::items y
        p=.ks i.<key
        if. p=#ks do. ks=.ks,<key
            vs=.vs,<patch
        else.
            current=.p{::vs
            if. ('object'-:kind current)*.'object'-:kind patch do. patch=.current deepMerge patch end.
            vs=.(<patch)p}vs
        end.
    end.
    (<vs)3}(<ks)2}x
)
sortRank =: 3 : 0
    if. y-:a: do. 3 return. end.
    ('null';'number';'string')i.<kind y
)
lessKey =: 4 : 0
    ar=.sortRank x
    br=.sortRank y
    if. ar~:br do. ar<br return. end.
    if. ar=1 do. (scalar x)<scalar y
    elseif. ar=2 do. ((0={./:(scalar x);scalar y)*.-.(scalar x)-:scalar y)
    else. 0 end.
)
sortArray =: 3 : 0
    vs=.items y
    for_i. 1+i.0>.(_1+#vs) do.
        j=.i
        while. j>0 do.
            a=.(j-1){::vs
            b=.j{::vs
            ak=.a fieldValue Field
            bk=.b fieldValue Field
            if. Descending do. less=.ak lessKey bk else. less=.bk lessKey ak end.
            if. -.less do. break. end.
            vs=.(<b)(j-1)}vs
            vs=.(<a)j}vs
            j=.j-1
        end.
    end.
    (<vs)3}y
)
requireKind =: 4 : 0
    for_m. y do.
        m=.>m
        if. -.x-:kind 0{::m do. fail 'not an ',x,' at ',location m end.
    end.
)
words =: 4 : 0
    if. HasArgument do. result=.' 'split y else. result=.0$a: end.
    'bad arguments'check ((#result)>:{.x)*.(#result)<:{:x
    result
)
arguments =: 4 : 0
    'bad arguments'check HasArgument
    result=.0$a:
    rest=.y
    for_i. i.x-1 do.
        at=.rest i.' '
        'bad arguments'check at<#rest
        result=.result,<at{.rest
        rest=.(at+1)}.rest
    end.
    result,<rest
)
commit =: 3 : 0
    History=:History,<Document
    Document=:y
)
load =: 3 : 0
    try.
        value=.parseJson y
        commit value
        emit 'LOADED nodes=',(num valueCount value),' depth=',num valueDepth value
    catcht.
        before=.ErrorPos{.y
        line=.1++/before=LF
        column=.ErrorPos-(before i:LF)
        if. -.LF e.before do. column=.ErrorPos+1 end.
        emit 'PARSE ERROR line ',(num line),' col ',(num column),': ',ErrorReason
    end.
)
execute =: 3 : 0
    at=.y i.' '
    command=.at{.y
    argument=.((at+1)<.#y)}.y
    HasArgument=:at<#y
    known=.;:'GET COMPACT PRETTY TYPE LENGTH KEYS FLATTEN COUNT SUM MIN MAX AVG FILTER SET DELETE INSERT MERGE SORT RENAME UNDO'
    if. -.(<command)e.known do. fail 'unknown command ''',command,'''' end.
    if. command-:'UNDO' do.
        0 0 words argument
        'nothing to undo'check 0<#History
        Document=:{:History
        Document=:>Document
        History=:}:History
        emit 'UNDO ',num #History
        return.
    end.
    Field=:0$a:
    Descending=:0
    reference=.Null
    index=.0
    newkey=.''
    operator=.''
    if. (<command)e.'SET';'MERGE' do.
        args=.2 arguments argument
        path=.0 parsePath 0{::args
        reference=.parseJson 1{::args
        if. command-:'MERGE' do. 'merge value is not an object'check 'object'-:kind reference end.
    elseif. command-:'INSERT' do.
        args=.3 arguments argument
        path=.0 parsePath 0{::args
        'bad index'check integerWord 1{::args
        index=.parseInt 1{::args
        reference=.parseJson 2{::args
    elseif. command-:'FILTER' do.
        args=.0$a:
        rest=.argument
        if. HasArgument do.
            for_i. i.3 do.
                at=.rest i.' '
                if. at=#rest do. break. end.
                args=.args,<at{.rest
                rest=.(at+1)}.rest
            end.
            args=.args,<rest
        end.
        'bad arguments'check 3<:#args
        operator=.2{::args
        'bad arguments'check (4=#args)~:operator-:'EXISTS'
        path=.0 parsePath 0{::args
        Field=:1 parsePath 1{::args
        'bad operator'check (<operator)e.'==';'!=';'<';'<=';'>';'>=';'EXISTS'
        if. 4=#args do. reference=.parseJson 3{::args end.
    elseif. command-:'SORT' do.
        args=.1 3 words argument
        options=.}.args
        if. #options do. Descending=:'DESC'-:>{:options end.
        if. Descending do. options=.}:options end.
        'bad arguments'check (2>#options)*.-.(<'DESC')e.options
        path=.0 parsePath 0{::args
        if. #options do. Field=:1 parsePath 0{::options else. Field=:1 parsePath '@' end.
    elseif. command-:'RENAME' do.
        args=.2 2 words argument
        path=.0 parsePath 0{::args
        newkey=.parseKey 1{::args
    else.
        optional=.(<command)e.'COMPACT';'PRETTY';'FLATTEN'
        args=.(-.optional),1
        args=.args words argument
        if. #args do. path=.0 parsePath 0{::args else. path=.0 parsePath '$' end.
    end.
    if. command-:'DELETE' do. 'cannot delete root'check 0<#path end.
    matches=.Document evaluate path
    if. (<command)e.'KEYS';'MERGE' do. 'object'requireKind matches end.
    if. (<command)e.'FILTER';'INSERT';'SORT' do. 'array'requireKind matches end.
    for_m. matches do.
        m=.>m
        v=.0{::m
        if. command-:'LENGTH' do. ('no length at ',location m)check (<kind v)e.'object';'array';'string' end.
    end.
    for_m. matches do.
        m=.>m
        if. command-:'INSERT' do.
            n=.#items 0{::m
            ('index out of range at ',location m)check (index>:-(n+1))*.index<:n
        elseif. command-:'RENAME' do.
            steps=.1{::m
            ('not a member at ',location m)check 0<#steps
            ('not a member at ',location m)check 0{::>{:steps
        end.
    end.
    if. command-:'COUNT' do. emit 'COUNT ',num #matches return. end.
    if. (<command)e.'SUM';'MIN';'MAX';'AVG' do.
        numbers=.i.0
        for_m. matches do.
            v=.0{::>m
            if. 'number'-:kind v do. numbers=.numbers,scalar v end.
        end.
        total=.+/numbers
        if. command-:'SUM' do. text=.num total
        elseif. 0=#numbers do. text=.'null'
        elseif. command-:'MIN' do. text=.num <./numbers
        elseif. command-:'MAX' do. text=.num >./numbers
        else.
            n=.#numbers
            q=.<.((200*|total)+n)%2*n
            sign=.''
            if. (total<0)*.q>0 do. sign=.'-' end.
            text=.sign,(num <.q%100),'.',_2{.'00',num 100|q
        end.
        emit command,' ',text
        return.
    end.
    if. command-:'FILTER' do.
        found=.0
        for_m. matches do.
            m=.>m
            for_i. i.#items 0{::m do.
                element=.m child i
                value=.(0{::element)fieldValue Field
                if. (operator;<reference)filterHolds value do. emit (location element),' = ',compact 0{::element
                    found=.1 end.
            end.
        end.
        if. -.found do. emit 'no match' end.
        return.
    end.
    if. (<command)e.'SET';'DELETE';'INSERT';'MERGE';'SORT';'RENAME' do.
        selected=.matches
        if. (command-:'SET')*.0<#path do.
            selected=.0$a:
            last=.>{:path
            for_parent. Document evaluate }:path do.
                parent=.>parent
                v=.0{::parent
                if. ('key'-:0{::last)*.(-.5{::last)*.'object'-:kind v do.
                    p=.(keys v)i.<1{::last
                    steps=.(1{::parent),<1;(1{::last);p
                    selected=.selected,<(<Null),<steps
                else. selected=.selected,last applySegment ,<parent end.
            end.
        end.
        selected=.targets selected
        document=.Document
        for_m. selected do.
            m=.>m
            ps=.positions m
            if. (command-:'SET')*.0=#ps do. document=.reference continue. end.
            if. (<command)e.'SET';'DELETE';'RENAME' do.
                parent=.document resolve }:ps
                p=.{:ps
                ks=.keys parent
                vs=.items parent
                if. command-:'SET' do.
                    if. p=#vs do. ks=.ks,<1{::>{:1{::m
                        vs=.vs,<reference
                    else. vs=.(<reference)p}vs end.
                elseif. command-:'DELETE' do.
                    vs=.((i.#vs)~:p)#vs
                    if. 'object'-:kind parent do. ks=.((i.#ks)~:p)#ks end.
                else.
                    ('key exists at ',location m)check ((p{::ks)-:newkey)+.-.(<newkey)e.ks
                    ks=.(<newkey)p}ks
                end.
                replacement=.(<vs)3}(<ks)2}parent
                document=.document replaceAt (}:ps);<replacement
            else.
                target=.document resolve ps
                if. command-:'INSERT' do.
                    vs=.items target
                    j=.index
                    if. j<0 do. j=.(#vs)+1+j end.
                    target=.(<(j{.vs),(<reference),j}.vs)3}target
                elseif. command-:'MERGE' do. target=.target deepMerge reference
                else. target=.sortArray target end.
                document=.document replaceAt ps;<target
            end.
        end.
        commit document
        emit command,' ',num #selected
        return.
    end.
    if. 0=#matches do. emit 'no match' end.
    for_m. matches do.
        m=.>m
        v=.0{::m
        select. command
        case. 'GET' do. emit (location m),' = ',compact v
        case. 'COMPACT' do. emit compact v
        case. 'PRETTY' do. emit ''pretty v
        case. 'TYPE' do. emit (location m),' ',kind v
        case. 'LENGTH' do.
            if. 'string'-:kind v do. n=.#scalar v else. n=.#items v end.
            emit (location m),' ',num n
        case. 'KEYS' do. emit (location m),' [',(','join '"'&quote&.>keys v),']'
        case. 'FLATTEN' do.
            for_leaf. preorder m do.
                leaf=.>leaf
                if. 0=#items 0{::leaf do. emit (location leaf),' = ',compact 0{::leaf end.
            end.
        end.
    end.
)
main =: 3 : 0
    Document=:Null
    History=:0$a:
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    at=.0
    while. 1 do.
        start=.at
        while. -. '%%'-:at{::lines do. at=.at+1 end.
        load LF join (at-start){.start}.lines
        at=.at+1
        while. at<#lines do.
            line=.at{::lines
            at=.at+1
            if. line-:'END' do. 1!:2&2 ;Output,&.><LF return. end.
            if. line-:'LOAD' do. break. end.
            try. execute line catcht. emit Reason end.
        end.
    end.
)
main''
