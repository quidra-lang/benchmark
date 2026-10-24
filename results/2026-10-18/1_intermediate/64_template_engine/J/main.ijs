LF =: 10{a.
Letters =: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_'
Digits =: '0123456789'
Output =: 0$a:
emit =: 3 : 'Output =: Output,<y'
num =: 3 : ',''0'' 8!:2 y'
join =: 4 : '(#x) }. ; (<x) ,&.> y'
split =: 4 : 0
    out=.0$a:
    start=.0
    for_i. i.#y do.
        if. x=i{y do. out=.out,<(i-start){.start}.y
        start=.i+1 end.
    end.
    out,<start}.y
)
trim =: 3 : 0
    while. #y do. if. ' '~:{.y do. break. end. y=.}.y end.
    while. #y do. if. ' '~:{:y do. break. end. y=.}:y end.
    y
)
findAt =: 4 : 0
    'at needle'=.y
    hits=.I.needle E.at}.x
    if. #hits do. at+{.hits else. #x end.
)
fields =: 4 : 0
    result=.0$a:
    for_row. y do.
        result=.result,<x{::>row
    end.
    result
)
fail =: 3 : 0
    'ErrorLine Reason'=:y
    throw.
)
identifier =: 3 : 0
    if. 0=#y do. 0 return. end.
    (({.y)e.Letters) *. *./y e.Letters,Digits
)
subscript =: 3 : 0
    if. 0=#y do. 0 return. end.
    (*./y e.Digits) *. (1=#y) +. '0'~:{.y
)
parseInt =: 3 : 0
    if. '-'={.y do. -0".}.y else. 0".y end.
)
numberText =: 3 : 0
    if. '-'={.y do. y=.}.y end.
    (1<:#y) *. (9>:#y) *. *./y e.Digits
)
validName =: 3 : 0
    if. (<y)e.'.';'@index';'@number';'@first';'@last' do. 1 return. end.
    for_p. '.'split y do.
        if. -. (identifier >p)+.subscript >p do. 0 return. end.
    end.
    1
)
upper =: 3 : '(''ABCDEFGHIJKLMNOPQRSTUVWXYZ'',a.) {~ (''abcdefghijklmnopqrstuvwxyz'',a.) i.y'
lower =: 3 : '(''abcdefghijklmnopqrstuvwxyz'',a.) {~ (''ABCDEFGHIJKLMNOPQRSTUVWXYZ'',a.) i.y'
html =: 3 : 0
    out=.''
    for_c. y do.
        n=.'&<>"''' i.c
        if. n<5 do. out=.out,n{::'&amp;';'&lt;';'&gt;';'&quot;';'&#39;'
        else. out=.out,c end.
    end.
    out
)
NB. A value is a boxed (kind,payload) pair. Maps contain boxed key/value vectors.
Absent =: (<'a'),<''
str =: 3 : '( <''s''),<y'
integer =: 3 : '( <''i''),<y'
boolean =: 3 : '( <''b''),<y'
list =: 3 : '( <''l''),<y'
emptyMap =: 3 : '( <''m''),<((<0$a:),<0$a:)'
has =: 4 : 0
    kind=.0{::x
    payload=.1{::x
    if. 2=3!:0 y do.
        if. kind~:'m' do. 0 return. end.
        (<y)e.0{::payload
    else.
        (kind='l') *. (y>:0) *. y<#payload
    end.
)
get =: 4 : 0
    payload=.1{::x
    if. 2=3!:0 y do. ((0{::payload)i.<y){::1{::payload
    else. y{::payload end.
)
put =: 4 : 0
    'p v'=.y
    kind=.0{::x
    payload=.1{::x
    if. kind='l' do.
        if. p=#payload do. payload=.payload,<v else. payload=.(<v)p}payload end.
    else.
        'keys vals'=.payload
        at=.keys i.<p
        if. at=#keys do. keys=.keys,<p
        vals=.vals,<v
        else. vals=.(<v)at}vals end.
        payload=.(<keys),<vals
    end.
    (<kind),<payload
)
keyParts =: 3 : 0
    'key n'=.y
    out=.0$a:
    at=.0
    while. at<#key do.
        if. (at>0) *. '['=at{key do.
            finish=.key findAt (at+1);']'
            word=.((finish-at)-1){.(at+1)}.key
            if. (finish=#key)+.-.subscript word do. fail n;'bad key ''',key,'''' end.
            p=.parseInt word
            at=.finish+1
        else.
            if. at>0 do.
                if. '.'~:at{key do. fail n;'bad key ''',key,'''' end.
                at=.at+1
            end.
            start=.at
            while. at<#key do. if. (at{key)e.'.[' do. break. end. at=.at+1 end.
            p=.(at-start){.start}.key
            if. -.identifier p do. fail n;'bad key ''',key,'''' end.
        end.
        out=.out,<((<p),<at{.key)
    end.
    if. (0=#out)+.('.'={:key) do. fail n;'bad key ''',key,'''' end.
    out
)
scalar =: 4 : 0
    at=.y
    if. at<#x do.
        if. '"'=at{x do.
            at=.at+1
            text=.''
            while. at<#x do.
                c=.at{x
                at=.at+1
                if. c='"' do. (<str text),<at return. end.
                if. c='\' do.
                    if. at=#x do. throw. end.
                    c=.at{x
                    at=.at+1
                    if. -.c e.'"\n' do. throw. end.
                    if. c='n' do. c=.LF end.
                end.
                text=.text,c
            end.
            throw.
        end.
    end.
    start=.at
    while. at<#x do. if. (at{x)e.',]' do. break. end. at=.at+1 end.
    word=.(at-start){.start}.x
    if. (<word)e.'true';'false' do. (<boolean word-:'true'),<at return. end.
    digits=.word
    if. '-'={.digits do. digits=.}.digits end.
    if. (-.subscript digits)+.(word-:'-0') do. throw. end.
    (<integer parseInt word),<at
)
parseValue =: 3 : 0
    'text n'=.y
    try.
        if. text-:'[]' do. list 0$a: return. end.
        if. text-:'{}' do. emptyMap'' return. end.
        if. '['={.text do.
            at=.1
            vals=.0$a:
            while. 1 do.
                'v at'=.text scalar at
                vals=.vals,<v
                if. ']' -: at}.text do. list vals return. end.
                if. -. ', '-:2{.at}.text do. throw. end.
                at=.at+2
            end.
        end.
        'v at'=.text scalar 0
        if. at~:#text do. throw. end.
        v
    catcht.
        fail n;'bad value ''',text,''''
    end.
)
assign =: 4 : 0
    'parts v n'=.y
    entry=.0{::parts
    p=.0{::entry
    prefix=.1{::entry
    if. 2~:3!:0 p do.
        if. p>#1{::x do. fail n;'index gap at ''',prefix,'''' end.
    end.
    if. 1=#parts do. x put (<p),<v return. end.
    next=.0{::1{::parts
    required=.(2=3!:0 next){'lm'
    if. x has p do.
        child=.x get p
        if. required~:0{::child do. fail n;'type conflict at ''',prefix,'''' end.
    else.
        if. required='m' do. child=.emptyMap'' else. child=.list 0$a: end.
    end.
    child=.child assign (<}.parts),(<v),<n
    x put (<p),<child
)
unset =: 4 : 0
    'parts key n'=.y
    p=.0{::0{::parts
    if. -.x has p do. fail n;'no value at ''',key,'''' end.
    if. 1<#parts do.
        child=.(x get p) unset (<}.parts),(<key),<n
        x put (<p),<child return.
    end.
    kind=.0{::x
    payload=.1{::x
    if. kind='l' do. payload=.((i.#payload)~:p)#payload
    else.
        'keys vals'=.payload
        keep=.(i.#keys)~:keys i.<p
        payload=.(<keep#keys),<keep#vals
    end.
    (<kind),<payload
)
unquoted =: 4 : 0
    parts=.0$a:
    start=.0
    quoted=.0
    for_i. i.#y do.
        c=.i{y
        if. c='''' do. quoted=.-.quoted
        elseif. (c=x)*.-.quoted do. parts=.parts,<(i-start){.start}.y
        start=.i+1 end.
    end.
    parts,<start}.y
)
validArgs =: 4 : 0
    n=.#y
    kinds=.;0 fields y
    select. x
    case. 'default';'eq' do. n=1
    case. 'pad';'lpad' do.
        if. -.n e.1 2 do. 0 return. end.
        if. 'i'~:0{::0{::y do. 0 return. end.
        if. 0>1{::0{::y do. 0 return. end.
        if. n=1 do. 1 else. ('s'=0{::1{::y)*.1=#1{::1{::y end.
    case. 'truncate' do. if. kinds-:,'i' do. 0<:1{::0{::y else. 0 end.
    case. 'replace' do. if. kinds-:'ss' do. 0<#1{::0{::y else. 0 end.
    case. 'join';'pluck' do. kinds-:,'s'
    case. 'sort' do. (n=0)+.kinds-:,'s'
    case. 'div';'mod' do. if. kinds-:,'i' do. 0~:1{::0{::y else. 0 end.
    case. 'add';'sub';'mul';'gt';'lt' do. kinds-:,'i'
    case. do. n=0
    end.
)
expression =: 3 : 0
    'text n'=.y
    pieces=.'|'unquoted text
    name=.trim 0{::pieces
    if. -.validName name do. fail n;'invalid name ''',name,'''' end.
    filters=.0$a:
    for_piece. }.pieces do.
        fields=.':'unquoted trim >piece
        f=.0{::fields
        args=.0$a:
        if. -. (<f)e.;:'upper lower title trim length first last reverse items comma sum min max default eq pad lpad truncate replace join sort pluck add sub mul div mod gt lt' do. fail n;'unknown filter ''',f,'''' end.
        for_raw. }.fields do.
            raw=.>raw
            valid=.0
            if. 2<:#raw do.
                if. (''''={.raw)*.(''''={:raw)*.-.''''e.}.}:raw do. args=.args,<str }.}:raw
                valid=.1 end.
            end.
            if. -.valid do.
                if. -.numberText raw do. fail n;'bad arguments for ''',f,'''' end.
                args=.args,<integer parseInt raw
            end.
        end.
        if. -.f validArgs args do. fail n;'bad arguments for ''',f,'''' end.
        filters=.filters,<((<f),<args)
    end.
    (<name),<filters
)
addNode =: 3 : 0
    Nodes=:Nodes,<y
    <:#Nodes
)
node =: 3 : 0
    'kind n text'=.y
    (<kind),(<n),(<text),(<0$a:),(<i.0),<''
)
parseSource =: 3 : 0
    'numbers lines'=.y
    opening=.'{{'
    closing=.'}}'
    root=.addNode node 'r';0;''
    targets=.,root
    stack=.i.0
    for_row. i.#lines do.
        line=.row{::lines
        n=.row{numbers
        at=.0
        tokens=.i.0
        tags=.i.0
        while. 1 do.
            start=.line findAt at;opening
            tokens=.tokens,addNode node 't';n;(start-at){.at}.line
            if. start=#line do. break. end.
            after=.start+#opening
            triple=.'{'=after{line,' '
            stop=.(triple#'}'),closing
            contentstart=.after+triple
            close=.line findAt contentstart;stop
            if. close=#line do. fail n;'unclosed tag' end.
            content=.trim (close-contentstart){.contentstart}.line
            at=.close+#stop
            kind=.'v'
            arg=.content
            if. triple do. kind=.'&'
            elseif. ({.content)e.'#^/!>&=' do.
                kind=.{.content
                if. kind~:'=' do. arg=.trim }.content end.
            end.
            item=.node kind;n;arg
            if. kind='=' do.
                ds=.(' 'split }.}:content)-.<''
                if. (2>#content)+.('='~:{:content)+.(2~:#ds) do. fail n;'invalid delimiters' end.
                if. +./'='e.;ds do. fail n;'invalid delimiters' end.
                'opening closing'=.ds
            elseif. kind e.'v&#^' do.
                item=.(<expression arg;n)3}item
            elseif. kind='/' do.
                if. -.validName arg do. fail n;'invalid name ''',arg,'''' end.
                if. 0=#stack do. fail n;'unexpected closing ''',arg,'''' end.
                expected=.0{::3{::({:stack){::Nodes
                if. -.arg-:expected do. fail n;'mismatched closing ''',arg,''', expected ''',expected,'''' end.
                stack=.}:stack
            elseif. kind='>' do.
                if. -.identifier arg do. fail n;'invalid name ''',arg,'''' end.
            end.
            id=.addNode item
            tokens=.tokens,id
            tags=.tags,id
            if. kind e.'#^' do. stack=.stack,id end.
        end.
        standalone=.0
        if. 1=#tags do.
            tag=.{.tags
            standalone=.(0{::tag{::Nodes)e.'#^/!>='
            for_id. tokens do.
                item=.id{::Nodes
                if. (0{::item)='t' do. if. #trim 2{::item do. standalone=.0 end. end.
            end.
        end.
        if. standalone do.
            item=.tag{::Nodes
            if. (0{::item)='>' do. item=.(<2{::({.tokens){::Nodes)5}item
            Nodes=.(<item)tag}Nodes end.
            tokens=.tags
        else. tokens=.tokens,addNode node 't';n;LF end.
        for_id. tokens do.
            item=.id{::Nodes
            k=.0{::item
            if. k='/' do. targets=.}:targets
            elseif. -.k e.'!=' do.
                parent=.{:targets
                p=.parent{::Nodes
                p=.(<(4{::p),id)4}p
                Nodes=.(<p)parent}Nodes
                if. k e.'#^' do. targets=.targets,id end.
            end.
        end.
    end.
    if. #stack do.
        item=.({:stack){::Nodes
        fail (1{::item);'unclosed section ''',(0{::3{::item),''''
    end.
    root
)
truth =: 3 : 0
    'k p'=.y
    select. k
    case. 'a' do. 0
    case. 'b' do. p
    case. 'i' do. p~:0
    case. 'm' do. 0<#0{::p
    case. do. 0<#p
    end.
)
toText =: 4 : 0
    'k p'=.y
    select. k
    case. 'a' do. ''
    case. 's' do. p
    case. 'b' do. p{::'false';'true'
    case. 'i' do. num p
    case. 'l' do. ', 'join (x&toText)&.>p
    case. do. fail x;'cannot render map'
    end.
)
toNumber =: 4 : 0
    'f n'=.x
    'k p'=.y
    if. k='a' do. 0 return. end.
    if. k='i' do. p return. end.
    if. k='s' do. if. numberText p do. parseInt p return. end. end.
    fail n;'not a number for ''',f,''''
)
field =: 4 : 0
    if. x has y do. x get y else. Absent end.
)
rank =: 3 : 0
    'k p'=.y
    r=.'aisb' i.k
    if. r e.0 4 do. p=.0 end.
    (<r),<p
)
less =: 4 : 0
    'a av'=.rank x
    'b bv'=.rank y
    if. a~:b do. a<b
    elseif. a=2 do. (-.av-:bv) *. 0=({. /: av;bv)
    else. av<bv end.
)
apply =: 3 : 0
    'f args v n'=.y
    'k p'=.v
    select. f
    case. 'default' do. if. truth v do. v else. 0{::args end.
    case. 'eq' do. boolean (n toText v)-:n toText 0{::args
    case. 'first';'last' do.
        if. k~:'l' do. v elseif. 0=#p do. Absent elseif. f-:'first' do. 0{::p else. _1{::p end.
    case. 'reverse' do. if. k e.'sl' do. (<k),<|.p else. v end.
    case. 'items' do.
        if. k~:'m' do. v return. end.
        'keys vals'=.p
        out=.0$a:
        for_key. /:~keys do.
            fields=.(<str >key),<(keys i.key){::vals
            out=.out,<(<'m'),<((<('key';'value')),<fields)
        end.
        list out
    case. 'sort';'pluck' do.
        if. k~:'l' do. v return. end.
        if. f-:'pluck' do.
            out=.0$a:
            for_item. p do. out=.out,< (>item) field 1{::0{::args end.
            list out return.
        end.
        out=.p
        for_i. }.i.#out do.
            j=.i
            while. j>0 do.
                a=.j{::out
                b=.(j-1){::out
                if. #args do. key=.1{::0{::args
                a=.a field key
                b=.b field key end.
                if. -.a less b do. break. end.
                out=.((j,(j-1)){out) ((j-1),j)}out
                j=.j-1
            end.
        end.
        list out
    case. 'length' do.
        if. k='m' do. integer #0{::p elseif. k='l' do. integer #p else. integer #n toText v end.
    case. 'sum';'min';'max' do.
        if. k~:'l' do. integer (f;n)toNumber v return. end.
        vals=.i.0
        for_item. p do. vals=.vals,(f;n)toNumber >item end.
        if. f-:'sum' do. integer +/vals elseif. 0=#vals do. Absent elseif. f-:'min' do. integer <./vals else. integer >./vals end.
    case. 'comma';'add';'sub';'mul';'div';'mod';'gt';'lt' do.
        a=.(f;n)toNumber v
        if. f-:'comma' do.
            s=.num |a
            out=.''
            for_i. i.#s do.
                if. (i>0)*.0=3|(#s)-i do. out=.out,',' end.
                out=.out,i{s
            end.
            str ((a<0)#'-'),out return.
        end.
        b=.1{::0{::args
        select. f
        case. 'add' do. integer a+b
        case. 'sub' do. integer a-b
        case. 'mul' do. integer a*b
        case. 'div' do. integer <.a%b
        case. 'mod' do. integer a-b*<.a%b
        case. 'gt' do. boolean a>b
        case. 'lt' do. boolean a<b
        end.
    case. do.
        s=.n toText v
        select. f
        case. 'upper' do. s=.upper s
        case. 'lower' do. s=.lower s
        case. 'title' do.
            out=.''
            for_i. i.#s do.
                if. (i=0)+.' '=(i-1){s do. out=.out,upper i{s else. out=.out,lower i{s end.
            end.
            s=.out
        case. 'trim' do. s=.trim s
        case. 'pad';'lpad' do.
            count=.0>. (1{::0{::args)-#s
            c=.' '
            if. 2=#args do. c=.1{::1{::args end.
            if. f-:'pad' do. s=.s,count#c else. s=.(count#c),s end.
        case. 'truncate' do. count=.1{::0{::args
        if. count<#s do. s=.(count{.s),'...' end.
        case. 'replace' do.
            from=.1{::0{::args
            to=.1{::1{::args
            at=.0
            out=.''
            while. at<#s do.
                found=.s findAt at;from
                out=.out,(found-at){.at}.s
                if. found=#s do. break. end.
                out=.out,to
                at=.found+#from
            end.
            s=.out
        case. 'join' do. if. k='l' do. s=.(1{::0{::args) join (n&toText)&.>p end.
        end.
        str s
    end.
)
NB. Numeric NAME parts are unbounded. Compare their digit count with the
NB. actual container length before converting a usable list index.
nameHas =: 4 : 0
    if. subscript y do.
        if. 'l'~:0{::x do. 0 return. end.
        if. (#y)>#num #1{::x do. 0 return. end.
        x has parseInt y
    else.
        x has y
    end.
)
nameGet =: 4 : 0
    if. subscript y do. x get parseInt y else. x get y end.
)
resolve =: 3 : 0
    'name contexts loops'=.y
    if. name-:'.' do. 1;<_1{::contexts return. end.
    if. '@'={.name do.
        if. 0=#loops do. 0;<Absent return. end.
        'i count'=.>_1{loops
        select. name
        case. '@index' do. v=.integer i
        case. '@number' do. v=.integer i+1
        case. '@first' do. v=.boolean i=0
        case. '@last' do. v=.boolean i=count-1
        end.
        1;<v return.
    end.
    parts=.'.'split name
    for_context. |.contexts do.
        v=.>context
        if. v nameHas 0{::parts do.
            for_p. parts do.
                if. -.v nameHas >p do. 0;<Absent return. end.
                v=.v nameGet >p
            end.
            1;<v return.
        end.
    end.
    0;<Absent
)
evaluate =: 3 : 0
    'expr contexts loops strict n'=.y
    'name filters'=.expr
    'found v'=.resolve (<name),(<contexts),<loops
    if. strict*.-.found do. fail n;'missing ''',name,'''' end.
    for_filter. filters do.
        'f args'=.>filter
        v=.apply (<f),(<args),(<v),<n
    end.
    v
)
render =: 3 : 0
    'root contexts loops depth'=.y
    out=.''
    for_id. 4{::root{::Nodes do.
        item=.id{::Nodes
        'k n arg expr children indent'=.item
        if. k='t' do. out=.out,arg continue. end.
        if. k='>' do.
            p=.PartialNames i.<arg
            if. p=#PartialNames do. fail n;'unknown partial ''',arg,'''' end.
            if. depth=8 do. fail n;'partial depth exceeded at ''',arg,'''' end.
            'numbers lines'=.p{::PartialBodies
            for_i. i.#lines do. if. #i{::lines do. lines=.(<indent,i{::lines)i}lines end. end.
            subtree=.parseSource (<numbers),<lines
            out=.out,render (<subtree),(<contexts),(<loops),<depth+1
            continue.
        end.
        v=.evaluate (<expr),(<contexts),(<loops),(<Strict*.k e.'v&'),<n
        if. k e.'v&' do.
            s=.n toText v
            if. k='v' do. s=.html s end. out=.out,s
        elseif. k='^' do.
            if. -.truth v do. out=.out,render (<id),(<contexts),(<loops),<depth end.
        elseif. 'l'=0{::v do.
            vals=.1{::v
            for_i. i.#vals do.
                out=.out,render (<id),(<contexts,i{vals),(<loops,<i,#vals),<depth
            end.
        elseif. truth v do. out=.out,render (<id),(<contexts,<v),(<loops),<depth end.
    end.
    out
)
notation =: 3 : 0
    'k p'=.y
    if. k='s' do.
        out=.'"'
        for_c. p do.
            if. c=LF do. out=.out,'\n'
            elseif. c e.'\"' do. out=.out,'\',c
            else. out=.out,c end.
        end.
        out,'"'
    elseif. k='l' do. '[]' elseif. k='m' do. '{}' else. 0 toText y end.
)
leaves =: 4 : 0
    'k p'=.y
    out=.0$a:
    if. k='m' do.
        'keys vals'=.p
        if. #keys do.
            for_key. /:~keys do.
                path=.x,((0<#x)#'.'),>key
                out=.out,path leaves (keys i.key){::vals
            end.
            out return.
        end.
    elseif. k='l' do.
        if. #p do.
            for_i. i.#p do.
                out=.out,(x,'[',(num i),']') leaves i{::p
            end.
            out return.
        end.
    end.
    if. #x do. out=.,<x,' = ',notation y end.
    out
)
showTemplate =: 3 : 0
    'name body'=.y
    try.
        tree=.parseSource body
        result=.render (<tree),(<,<Root),(<0$a:),<0
        lines=.LF split result
        if. ''-:_1{::lines do. lines=.}:lines end.
        emit 'TEMPLATE ',name,' OK lines=',(num #lines),' chars=',num #result
        for_line. lines do. emit >line end.
    catcht.
        emit 'TEMPLATE ',name,' ERROR line ',(num ErrorLine),': ',Reason
    end.
)
reset =: 3 : 0
    Root=:emptyMap''
    PartialNames=:PartialBodies=:TemplateNames=:TemplateBodies=:0$a:
)
main =: 3 : 0
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    Strict=:0
    Nodes=:0$a:
    at=.0
    reset''
    while. -. 'END'-:at{::lines do.
        line=.at{::lines
        n=.at+1
        words=.' 'split line
        cmd=.0{::words
        name=.1{::words,<''
        at=.at+1
        if. (<cmd)e.'DATA';'PARTIAL';'TEMPLATE' do.
            marker=.'END',cmd
            bodylines=.0$a:
            numbers=.i.0
            while. -.marker-:at{::lines do. bodylines=.bodylines,at{lines
            numbers=.numbers,at+1
            at=.at+1 end.
            at=.at+1
            body=.(<numbers),<bodylines
            if. cmd-:'DATA' do.
                sets=.0
                unsets=.0
                errors=.0$a:
                for_i. i.#bodylines do.
                    text=.i{::bodylines
                    no=.i{numbers
                    if. (0=#text)+. '#'={.text do. continue. end.
                    try.
                        if. 'UNSET '-:6{.text do.
                            key=.6}.text
                            parts=.keyParts key;no
                            Root=:Root unset (<parts),(<key),<no
                            unsets=.unsets+1
                        else.
                            sep=.text findAt 0;' = '
                            if. sep=#text do. fail no;'bad line' end.
                            parts=.keyParts (sep{.text);no
                            v=.parseValue ((sep+3)}.text);no
                            Root=:Root assign (<parts),(<v),<no
                            sets=.sets+1
                        end.
                    catcht. errors=.errors,<'ERROR line ',(num ErrorLine),': ',Reason end.
                end.
                emit 'DATA set=',(num sets),' unset=',(num unsets),' errors=',num #errors
                for_error. errors do. emit >error end.
            elseif. cmd-:'PARTIAL' do.
                try.
                    tree=.parseSource body
                    p=.PartialNames i.<name
                    status=.'REPLACED'
                    if. p=#PartialNames do. PartialNames=:PartialNames,<name
                    PartialBodies=:PartialBodies,<body
                    status=.'DEFINED'
                    else. PartialBodies=:(<body)p}PartialBodies end.
                    emit 'PARTIAL ',name,' ',status,' lines=',num #bodylines
                catcht. emit 'PARTIAL ',name,' ERROR line ',(num ErrorLine),': ',Reason end.
            else.
                p=.TemplateNames i.<name
                if. p=#TemplateNames do. TemplateNames=:TemplateNames,<name
                TemplateBodies=:TemplateBodies,<body
                else. TemplateBodies=:(<body)p}TemplateBodies end.
                showTemplate (<name),<body
            end.
        elseif. cmd-:'RENDER' do.
            p=.TemplateNames i.<name
            if. p=#TemplateNames do. emit 'TEMPLATE ',name,' ERROR line ',(num n),': unknown template ''',name,''''
            else. showTemplate (<name),<p{::TemplateBodies end.
        elseif. cmd-:'DUMP' do.
            result=.''leaves Root
            emit 'DUMP leaves=',num #result
            for_leaf. result do. emit >leaf end.
        elseif. cmd-:'STRICT' do. Strict=:name-:'ON'
        emit line
        elseif. cmd-:'RESET' do. reset''
        emit 'RESET' end.
    end.
    1!:2&2 ;Output,&.><LF
)
main''
