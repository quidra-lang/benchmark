LF=:10{a.
DQ=:34{a.
SQ=:39{a.
BS=:92{a.
num=:3 : ',''0'' 8!:2 y'
fail=:3 : 0
    Reason=:y
    throw.
)
newValue=:4 : 0
    id=.#Types
    Types=:Types,x
    Numbers=:Numbers,0
    Texts=:Texts,<''
    Cars=:Cars,0
    Cdrs=:Cdrs,0
    Params=:Params,<0$a:
    Rests=:Rests,<''
    Bodies=:Bodies,<i.0
    Captures=:Captures,_1
    Minimum=:Minimum,0
    Variadic=:Variadic,0
    Builtin=:Builtin,0
    if. x e.3 4 do. Numbers=:y id}Numbers
    elseif. x e.5 6 8 do. Texts=:(<y)id}Texts end.
    id
)
pair=:3 : 0
    id=.7 newValue 0
    Cars=:({.y)id}Cars
    Cdrs=:({:y)id}Cdrs
    id
)
makeList=:4 : 0
    result=.x
    for_item. |.y do. result=.pair item,result end.
    result
)
listItems=:3 : 0
    result=.i.0
    current=.y
    while. 7=current{Types do.
        result=.result,current{Cars
        current=.current{Cdrs
    end.
    if. current=0 do. result else. _1 end.
)
truth=:3 : '-.(4=y{Types)*.0=y{Numbers'
representation=:4 : 0
    tag=.y{Types
    if. tag=0 do. '()' return. end.
    if. tag=1 do. '#<void>' return. end.
    if. tag=3 do. num y{Numbers return. end.
    if. tag=4 do. if. y{Numbers do. '#t' else. '#f' end. return. end.
    if. tag=6 do. y{::Texts return. end.
    if. tag=5 do.
        text=.y{::Texts
        if. -.x do. text return. end.
        result=.,DQ
        for_char. text do.
            if. char=DQ do. result=.result,BS,DQ
            elseif. char=BS do. result=.result,BS,BS
            elseif. char=LF do. result=.result,BS,'n'
            else. result=.result,char end.
        end.
        result,DQ return.
    end.
    if. tag=8 do.
        name=.y{::Texts
        if. #name do. '#<procedure ',name,'>' else. '#<procedure>' end. return.
    end.
    result=.'('
    current=.y
    first=.1
    while. 7=current{Types do.
        if. -.first do. result=.result,' ' end.
        first=.0
        result=.result,x representation current{Cars
        current=.current{Cdrs
    end.
    if. current~:0 do. result=.result,' . ',x representation current end.
    result,')'
)
rep=:3 : '1 representation y'
equalValue=:4 : 0
    'a b'=.y
    tag=.a{Types
    if. tag~:b{Types do. 0 return. end.
    if. tag e.3 4 do. (a{Numbers)=b{Numbers return. end.
    if. tag e.5 6 do. (a{::Texts)-:b{::Texts return. end.
    if. (tag=7)*.x do.
        (1 equalValue (a{Cars),b{Cars)*.1 equalValue (a{Cdrs),b{Cdrs return.
    end.
    if. tag e.7 8 do. a=b else. 1 end.
)
shape=:4 : 'if. -.x do. fail ''bad syntax: '',rep y end.'
newFrame=:3 : 0
    id=.#Parents
    Parents=:Parents,y
    FrameNames=:FrameNames,<0$a:
    FrameValues=:FrameValues,<i.0
    id
)
bind=:4 : 0
    'name value'=.y
    names=.x{::FrameNames
    values=.x{::FrameValues
    at=.names i.<name
    if. at=#names do. names=.names,<name
        values=.values,value
    else. values=.value at}values end.
    FrameNames=:(<names)x}FrameNames
    FrameValues=:(<values)x}FrameValues
)
findFrame=:4 : 0
    current=.x
    while. current>:0 do.
        if. (<y)e.current{::FrameNames do. current return. end.
        current=.current{Parents
    end.
    fail 'unbound variable: ',y
)
lookup=:4 : 0
    frame=.x findFrame y
    at=.(frame{::FrameNames)i.<y
    value=.at{frame{::FrameValues
    if. value=2 do. fail 'uninitialized variable: ',y end.
    value
)
parseParameters=:3 : 0
    names=.0$a:
    current=.y
    while. 7=current{Types do.
        element=.current{Cars
        if. 6~:element{Types do. a: return. end.
        names=.names,<element{::Texts
        current=.current{Cdrs
    end.
    rest=.''
    if. current~:0 do.
        if. 6~:current{Types do. a: return. end.
        rest=.current{::Texts
    end.
    all=.names
    if. #rest do. all=.all,<rest end.
    if. (#all)~:#~.all do. a: return. end.
    (<names),<rest
)
parseBindings=:4 : 0
    entries=.listItems y
    if. entries-:_1 do. a: return. end.
    names=.0$a:
    expressions=.i.0
    for_entry. entries do.
        parts=.listItems entry
        if. 2~:#parts do. a: return. end.
        if. 6~:({.parts){Types do. a: return. end.
        names=.names,<({.parts){::Texts
        expressions=.expressions,{:parts
    end.
    if. x*.((#names)~:#~.names) do. a: return. end.
    (<names),<expressions
)
closure=:3 : 0
    'parameters rest body environment name'=.y
    id=.8 newValue name
    Params=:(<parameters)id}Params
    Rests=:(<rest)id}Rests
    Bodies=:(<body)id}Bodies
    Captures=:environment id}Captures
    Minimum=:(#parameters)id}Minimum
    Variadic=:(0<#rest)id}Variadic
    id
)
evalBody=:4 : 0
    result=.1
    for_expression. y do. result=.x evaluate expression end.
    result
)
evaluate=:4 : 0
    tag=.y{Types
    if. tag=6 do. x lookup y{::Texts return. end.
    if. tag~:7 do. (y~:0)shape y
        y return. end.
    parts=.listItems y
    (-.parts-:_1)shape y
    count=.#parts
    head=.{.parts
    keyword=.''
    if. 6=head{Types do. keyword=.head{::Texts end.
    if. keyword-:'quote' do. (count=2)shape y
        1{parts return.
    elseif. keyword-:'if' do.
        (count e.3 4)shape y
        if. truth x evaluate 1{parts do. x evaluate 2{parts return. end.
        if. count=4 do. x evaluate 3{parts else. 1 end. return.
    elseif. keyword-:'begin' do. x evalBody }.parts return.
    elseif. keyword-:'lambda' do.
        (count>:3)shape y
        p=.parseParameters 1{parts
        (-.p-:a:)shape y
        closure p,(<2}.parts),(<x),<'' return.
    elseif. keyword-:'define' do.
        (count>:3)shape y
        target=.1{parts
        if. 6=target{Types do.
            (count=3)shape y
            result=.x evaluate 2{parts
            if. 8=result{Types do.
                if. (0=result{Builtin)*.0=#result{::Texts do. Texts=:(<target{::Texts)result}Texts end.
            end.
            x bind (<target{::Texts),<result
        else.
            (7=target{Types)shape y
            name=.target{Cars
            (6=name{Types)shape y
            p=.parseParameters target{Cdrs
            (-.p-:a:)shape y
            result=.closure p,(<2}.parts),(<x),<name{::Texts
            x bind (<name{::Texts),<result
        end.
        1 return.
    elseif. keyword-:'set!' do.
        (count=3)shape y
        target=.1{parts
        (6=target{Types)shape y
        result=.x evaluate 2{parts
        frame=.x findFrame target{::Texts
        frame bind (<target{::Texts),<result
        1 return.
    elseif. (<keyword)e.'let';'let*';'letrec' do.
        named=.0
        if. count>1 do. named=.(keyword-:'let')*.6=(1{parts){Types end.
        at=.1+named
        (count>:at+2)shape y
        bs=.( -.keyword-:'let*')parseBindings at{parts
        (-.bs-:a:)shape y
        'names expressions'=.bs
        frame=.newFrame x
        if. keyword-:'let*' do.
            if. #names do. frame=.x end.
            for_i. i.#names do.
                result=.frame evaluate i{expressions
                frame=.newFrame frame
                frame bind (i{names),<result
            end.
        elseif. keyword-:'letrec' do.
            for_name. names do. frame bind name,<2 end.
            for_i. i.#names do. result=.frame evaluate i{expressions
                frame bind (i{names),<result end.
        else.
            values=.i.0
            for_expression. expressions do. values=.values,x evaluate expression end.
            if. named do.
                name=.(1{parts){::Texts
                procedure=.closure (<names),(<''),(<3}.parts),(<frame),<name
                frame bind (<name),<procedure
                procedure invoke values return.
            end.
            for_i. i.#names do. frame bind (i{names),<i{values end.
        end.
        frame evalBody (at+1)}.parts return.
    elseif. keyword-:'cond' do.
        clauses=.0$a:
        for_i. }.i.count do.
            clause=.listItems i{parts
            ((-.clause-:_1)*.0<#clause)shape y
            if. (6=({.clause){Types)*.'else'-:({.clause){::Texts do.
                ((2<:#clause)*.i=count-1)shape y
            end.
            clauses=.clauses,<clause
        end.
        for_clause. clauses do.
            c=.>clause
            if. (6=({.c){Types)*.'else'-:({.c){::Texts do. x evalBody }.c return. end.
            result=.x evaluate {.c
            if. truth result do. if. 1=#c do. result else. x evalBody }.c end. return. end.
        end.
        1 return.
    elseif. keyword-:'and' do.
        result=.4 newValue 1
        for_expression. }.parts do. result=.x evaluate expression
            if. -.truth result do. break. end. end.
        result return.
    elseif. keyword-:'or' do.
        for_expression. }.parts do. result=.x evaluate expression
            if. truth result do. result return. end. end.
        4 newValue 0 return.
    elseif. (<keyword)e.'when';'unless' do.
        (count>:3)shape y
        if. (truth x evaluate 1{parts)=keyword-:'when' do. x evalBody 2}.parts else. 1 end. return.
    end.
    procedure=.x evaluate {.parts
    arguments=.i.0
    for_expression. }.parts do. arguments=.arguments,x evaluate expression end.
    if. 8~:procedure{Types do. fail 'not a procedure: ',rep procedure end.
    procedure invoke arguments
)
writeText=:3 : 0
    Output=:Output,y
    if. #y do. Midline=:LF~:{:y end.
)
writeLine=:3 : 0
    if. Midline do. writeText LF end.
    writeText y,LF
)
expect=:4 : 0
    'name kind'=.x
    tag=.y{Types
    valid=.0
    select. kind
    case. 'integer' do. valid=.tag=3
    case. 'string' do. valid=.tag=5
    case. 'pair' do. valid=.tag=7
    case. 'procedure' do. valid=.tag=8
    case. 'list' do. valid=.-.(listItems y)-:_1
    end.
    if. -.valid do. fail name,': expected ',kind,', got ',rep y end.
    y
)
asList=:4 : 0
    (x; 'list')expect y
    listItems y
)
builtin=:4 : 0
    name=.x
    arguments=.y
    if. (<name)e.'+';'*';'-';'quotient';'remainder';'modulo';'abs';'min';'max';'gcd';'=';'<';'>';'<=';'>=' do.
        for_argument. arguments do. (name;'integer')expect argument end.
        z=.arguments{Numbers
        if. name-:'+' do. 3 newValue +/z return.
        elseif. name-:'*' do. 3 newValue */z return.
        elseif. name-:'-' do. if. 1=#z do. result=.-{.z else. result=.({.z)-+/}.z end.
        elseif. name-:'abs' do. result=.|{.z
        elseif. name-:'min' do. result=.<./z
        elseif. name-:'max' do. result=.>./z
        elseif. name-:'gcd' do.
            result=.0
            for_b. |z do. b=.b
                while. b~:0 do. r=.b|result
                    result=.b
                    b=.r end. end.
        elseif. (<name)e.'quotient';'remainder';'modulo' do.
            'a b'=.z
            if. b=0 do. fail name,': division by zero' end.
            q=.(*a)*(*b)*<.(|a)%|b
            if. name-:'quotient' do. result=.q
            elseif. name-:'remainder' do. result=.a-b*q
            else. result=.a-b*<.a%b end.
        else.
            valid=.1
            for_i. }.i.#z do.
                a=.(i-1){z
                b=.i{z
                select. name
                case. '=' do. valid=.valid*.a=b
                case. '<' do. valid=.valid*.a<b
                case. '>' do. valid=.valid*.a>b
                case. '<=' do. valid=.valid*.a<:b
                case. '>=' do. valid=.valid*.a>:b
                end.
            end.
            4 newValue valid return.
        end.
        3 newValue result return.
    end.
    if. name-:'not' do. 4 newValue -.truth {.arguments return.
    elseif. (<name)e.'eq?';'equal?' do. 4 newValue (name-:'equal?')equalValue arguments return.
    elseif. (<name)e.'null?';'pair?';'list?';'number?';'symbol?';'procedure?' do.
        value=.{.arguments
        select. name
        case. 'null?' do. valid=.value=0
        case. 'pair?' do. valid=.7=value{Types
        case. 'list?' do. valid=.-.(listItems value)-:_1
        case. 'number?' do. valid=.3=value{Types
        case. 'symbol?' do. valid=.6=value{Types
        case. 'procedure?' do. valid=.8=value{Types
        end.
        4 newValue valid return.
    elseif. name-:'cons' do. pair arguments return.
    elseif. name-:'list' do. 0 makeList arguments return.
    elseif. (<name)e.'car';'cdr';'cadr' do.
        value=.(name;'pair')expect {.arguments
        if. name-:'car' do. value{Cars return. end.
        value=.value{Cdrs
        if. name-:'cdr' do. value return. end.
        (name;'pair')expect value
        value{Cars return.
    elseif. (<name)e.'length';'reverse';'list-ref' do.
        elements=.name asList {.arguments
        if. name-:'length' do. 3 newValue #elements return. end.
        if. name-:'reverse' do. 0 makeList |.elements return. end.
        index=.Numbers{~(name;'integer')expect 1{arguments
        if. (index<0)+.index>:#elements do. fail 'list-ref: index out of range: ',num index end.
        index{elements return.
    elseif. name-:'append' do.
        if. 0=#arguments do. 0 return. end.
        elements=.i.0
        for_argument. }:arguments do. elements=.elements,name asList argument end.
        ({:arguments)makeList elements return.
    elseif. (<name)e.'map';'filter';'fold-left';'apply' do.
        procedure=.(name;'procedure')expect {.arguments
        if. name-:'apply' do.
            spread=.name asList {:arguments
            procedure invoke (}.}:arguments),spread return.
        end.
        first=.1+name-:'fold-left'
        lists=.0$a:
        length=._
        for_argument. first}.arguments do. elements=.name asList argument
            lists=.lists,<elements
            length=.length<.#elements end.
        result=.i.0
        accumulator=.1{arguments
        for_i. i.length do.
            actual=.i.0
            if. name-:'fold-left' do. actual=.,accumulator end.
            for_elements. lists do. actual=.actual,i{>elements end.
            value=.procedure invoke actual
            if. name-:'map' do. result=.result,value
            elseif. name-:'filter' do. if. truth value do. result=.result,i{0{::lists end.
            else. accumulator=.value end.
        end.
        if. name-:'fold-left' do. accumulator else. 0 makeList result end. return.
    elseif. name-:'string-append' do.
        result=.''
        for_argument. arguments do. checked=.(name;'string')expect argument
            result=.result,checked{::Texts end.
        5 newValue result return.
    elseif. name-:'number->string' do. 5 newValue rep (name;'integer')expect {.arguments return.
    elseif. name-:'display' do. writeText 0 representation {.arguments
        1 return.
    elseif. name-:'newline' do. writeText LF
        1 return.
    else.
        checked=.(name;'string')expect {.arguments
        message=.checked{::Texts
        for_argument. }.arguments do. message=.message,' ',rep argument end.
        fail message
    end.
)
invoke=:4 : 0
    minimum=.x{Minimum
    variadic=.x{Variadic
    if. ((#y)<minimum)+.(-.variadic)*.(#y)~:minimum do.
        name=.x{::Texts
        if. 0=#name do. name=.'lambda' end.
        expected=.num minimum
        if. variadic do. expected=.'at least ',expected end.
        fail name,': wrong number of arguments (expected ',expected,', got ',(num #y),')'
    end.
    if. x{Builtin do. (x{::Texts)builtin y return. end.
    frame=.newFrame x{Captures
    parameters=.x{::Params
    for_i. i.#parameters do. frame bind (i{parameters),<i{y end.
    rest=.x{::Rests
    if. #rest do. frame bind (<rest),<0 makeList minimum}.y end.
    frame evalBody x{::Bodies
)
skipLine=:3 : 'Row=:Row+1 [ Column=:0'
atEnd=:3 : 0
    while. Row<#Lines do.
        line=.Row{::Lines
        while. Column<#line do. if. ' '~:Column{line do. break. end.
            Column=:Column+1 end.
        if. Column<#line do. if. ';'~:Column{line do. 0 return. end. end.
        skipLine''
    end.
    1
)
nextToken=:3 : 0
    if. atEnd'' do. fail 'unexpected end of input' end.
    line=.Row{::Lines
    char=.Column{line
    Column=:Column+1
    if. char e.'()',SQ do. (<,char),<0 return. end.
    if. char=DQ do.
        result=.''
        while. Column<#line do.
            char=.Column{line
            Column=:Column+1
            if. char=DQ do. (<'v'),<5 newValue result return. end.
            if. char=BS do.
                if. Column=#line do. break. end.
                char=.Column{line
                Column=:Column+1
                if. -.char e.DQ,BS,'n' do. fail 'bad escape' end.
                if. char='n' do. char=.LF end.
            end.
            result=.result,char
        end.
        fail 'unterminated string'
    end.
    start=.Column-1
    while. Column<#line do.
        if. (Column{line)e.' ();',SQ,DQ do. break. end.
        Column=:Column+1
    end.
    atom=.(Column-start){.start}.line
    if. atom-:,'.' do. (<'.'),<0 return. end.
    digits=.atom
    if. ({.digits)e.'+-' do. digits=.}.digits end.
    if. (0<#digits)*.*./digits e.'0123456789' do.
        value=.0".digits
        if. '-'={.atom do. value=.-value end.
        (<'v'),<3 newValue value return.
    end.
    if. (<atom)e.'#t';'#f' do. (<'v'),<4 newValue atom-:'#t' return. end.
    if. '#'={.atom do. fail 'bad token: ',atom end.
    (<'v'),<6 newValue atom
)
readDatum=:3 : 'datumFrom nextToken'''''
datumFrom=:3 : 0
    'kind value'=.y
    if. kind-:'v' do. value return. end.
    if. kind-:,SQ do.
        quoted=.6 newValue 'quote'
        datum=.readDatum''
        0 makeList quoted,datum return.
    end.
    if. -.kind-:'(' do. fail 'unexpected ',kind end.
    result=.i.0
    while. 1 do.
        token=.nextToken''
        'kind value'=.token
        if. kind-:')' do. 0 makeList result return. end.
        if. (kind-:'.')*.0<#result do.
            tail=.readDatum''
            closing=.nextToken''
            if. -.')'-:0{::closing do. fail 'expected )' end.
            tail makeList result return.
        end.
        result=.result,datumFrom token
    end.
)
main=:3 : 0
    Types=:Numbers=:Cars=:Cdrs=:Captures=:Minimum=:Variadic=:Builtin=:i.0
    Texts=:Params=:Rests=:Bodies=:0$a:
    Parents=:i.0
    FrameNames=:FrameValues=:0$a:
    0 newValue 0
    1 newValue 0
    2 newValue 0
    global=.newFrame _1
    names=.<;._1 ' + * - quotient remainder modulo abs min max gcd = < > <= >= not eq? equal? null? pair? list? number? symbol? procedure? cons car cdr cadr list length append reverse list-ref map filter fold-left apply string-append number->string display newline error'
    minima=.0 0 1 2 2 2 1 1 1 0 1 1 1 1 1 1 2 2 1 1 1 1 1 1 2 1 1 1 0 1 0 1 2 2 2 3 2 0 1 1 0 1
    variable=.0 1 2 7 8 9 10 11 12 13 14 28 30 33 35 36 37 41
    for_i. i.#names do.
        id=.8 newValue i{::names
        Minimum=:(i{minima)id}Minimum
        Variadic=:(i e.variable)id}Variadic
        Builtin=:1 id}Builtin
        global bind (i{names),<id
    end.
    all=.<;._2 (1!:1 <'/dev/stdin'),LF
    at=.all i.<'(exit)'
    Lines=:at{.all
    Row=:Column=:0
    Output=:''
    Midline=:0
    while. -.atEnd'' do.
        try. expression=.readDatum''
        catcht.
            writeLine 'Error: read: ',Reason
            if. Reason-:'unexpected end of input' do. break. end.
            skipLine''
            continue.
        end.
        try.
            result=.global evaluate expression
            if. result~:1 do. writeLine rep result end.
        catcht. writeLine 'Error: ',Reason
        end.
    end.
    if. Midline do. writeText LF end.
    1!:2&2 Output
)
main''
