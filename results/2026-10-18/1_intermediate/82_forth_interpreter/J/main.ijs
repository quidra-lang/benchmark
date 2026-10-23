LF =: 10{a.
DQ =: 34{a.
SQ =: 39{a.
num =: 3 : ',''0'' 8!:2 y'
say =: 3 : '1!:2&2 y,LF'
words =: 3 : '(<;._1 '' '',y)-.<'''''
Digits =: '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
CompileOnly =: (words 'IF ELSE THEN DO ?DO LOOP +LOOP LEAVE UNLOOP I J BEGIN UNTIL WHILE REPEAT AGAIN CASE OF ENDOF ENDCASE EXIT RECURSE DOES> ; >R R> R@'),(< 'ABORT',DQ),(<('[',SQ,']')),<,'{:'
InterpretOnly =: words ': :NONAME FORGET'
Special =: CompileOnly,InterpretOnly,(<'.',DQ),( <,'('),(<,'\'),words 'TO IS'
BuiltinNames =: words '+ - * / MOD /MOD */ */MOD NEGATE ABS MIN MAX 1+ 1- 2* 2/ = <> < > 0= 0<> 0< 0> WITHIN TRUE FALSE AND OR XOR INVERT DUP ?DUP DROP SWAP OVER ROT -ROT NIP TUCK 2DUP 2DROP 2SWAP 2OVER DEPTH PICK ROLL . .R .S ? CR EMIT SPACE SPACES BL ! @ +! , ALLOT HERE CELLS CELL+ BASE HEX DECIMAL CREATE VARIABLE CONSTANT VALUE DEFER '' EXECUTE CATCH THROW ABORT WORDS'
fail =: 3 : 0
    'ErrorReason ErrorCode ErrorCatchable ErrorWord'=:y
    throw.
)
failCode =: 4 : 'fail (<y),(<x),(<1),<'''''
uncaught =: 3 : 'fail (<y),(<0),(<0),<'''''
pushData =: 3 : 0
    if. (#Stack)=1000 do. _3 failCode 'stack overflow' end.
    Stack=:Stack,y
)
popData =: 3 : 0
    if. 0=#Stack do. _4 failCode 'stack underflow' end.
    result=.{:Stack
    Stack=:}:Stack
    result
)
takeData =: 3 : 0
    if. (#Stack)<y do. _4 failCode 'stack underflow' end.
    at=.(#Stack)-y
    result=.at}.Stack
    Stack=:at{.Stack
    result
)
pushValues =: 3 : 'for_value. y do. pushData value end.'
pushReturn =: 3 : 0
    if. (#Returns)=1000 do. _5 failCode 'return stack overflow' end.
    Returns=:Returns,y
)
requireReturn =: 3 : 'if. (#Returns)<y do. _6 failCode ''return stack underflow'' end.'
hereAddress =: 3 : '8*#Memory'
cellIndex =: 3 : 0
    if. (y<0)+.(0~:8|y)+.y>:hereAddress'' do. _9 failCode 'invalid address' end.
    <.y%8
)
radix =: 3 : 0
    base=.0{Memory
    if. (base<2)+.base>36 do. _40 failCode 'invalid base' end.
    base
)
parseDigits =: 4 : 0
    text=.,y
    negative=.0
    if. #text do. if. '-'={.text do. negative=.1
        text=.}.text end. end.
    if. 0=#text do. 0 0 return. end.
    digits=.Digits i.toupper text
    if. +./digits>:x do. 0 0 return. end.
    value=.0
    for_digit. digits do. value=.digit+x*value end.
    if. negative do. value=.-value end.
    1,value
)
parseNumber =: 4 : 0
    if. 3=#y do.
        if. (SQ={.y)*.SQ={:y do. 1,a.i.1{y return. end.
    end.
    prefix=.('$#%'i.{.y)
    if. prefix<3 do. (prefix{16 10 2)parseDigits }.y return. end.
    base=.x
    if. base<0 do. base=.radix'' end.
    base parseDigits y
)
literal =: 3 : 0
    'has value'=._1 parseNumber y
    if. -.has do. _13 failCode 'undefined word' end.
    value
)
formatNumber =: 3 : 0
    base=.radix''
    value=.|y
    result=.,(base|value){Digits
    while. value>:base do. value=.<.value%base
        result=.((base|value){Digits),result end.
    if. y<0 do. '-',result else. result end.
)
flushLine =: 3 : 0
    while. #Pending do. if. ' '~:{:Pending do. break. end.
        Pending=:}:Pending end.
    say Pending
    Pending=:''
)
readWord =: 3 : 0
    while. Position<#InputLine do. if. ' '~:Position{InputLine do. break. end.
        Position=:Position+1 end.
    start=.Position
    while. Position<#InputLine do. if. ' '=Position{InputLine do. break. end.
        Position=:Position+1 end.
    (Position-start){.start}.InputLine
)
readName =: 3 : 0
    name=.readWord''
    if. 0=#name do. _16 failCode 'missing name' end.
    name
)
readString =: 3 : 0
    start=.Position+1
    if. start>#InputLine do. uncaught 'unterminated string' end.
    tail=.start}.InputLine
    at=.tail i.DQ
    if. at=#tail do. uncaught 'unterminated string' end.
    Position=:start+at+1
    at{.tail
)
setWordField =: 4 : 0
    'id field'=.x
    record=.id{::WordPool
    record=.(<y)field}record
    WordPool=:(<record)id}WordPool
)
setDefField =: 4 : 0
    'id field'=.x
    record=.id{::Definitions
    record=.(<y)field}record
    Definitions=:(<record)id}Definitions
)
newWord =: 4 : 0
    (<,x),(<y),(<_1),(<0),(<0),(<0),(<_1),(<0),(<_1),<0
)
findWord =: 3 : 0
    key=.<,y
    for_id. |.Dictionary do. if. key-:0{id{::WordPool do. id return. end. end.
    at=.BuiltinNames i.key
    if. at<#BuiltinNames do. at else. _1 end.
)
existingWord =: 3 : 0
    id=.findWord toupper y
    if. id<0 do. fail (<'undefined word'),(<_13),(<1),<y end.
    id
)
checkName =: 3 : 0
    invalid=.(<toupper y)e.Special
    if. -.invalid do. invalid=.{.10 parseNumber y end.
    if. invalid do. fail (<'invalid name'),(<_19),(<1),<y end.
)
newName =: 3 : 0
    name=.readName''
    checkName name
    toupper name
)
addWord =: 3 : 0
    record=.(<hereAddress'')5}y
    Dictionary=:Dictionary,#WordPool
    WordPool=:WordPool,<record
)
tokenOf =: 3 : 0
    xt=.9{::y{::WordPool
    if. xt=0 do. Xts=:Xts,y
        xt=.#Xts
        (y,9)setWordField xt end.
    xt
)
tokenWord =: 3 : 0
    if. (y<1)+.y>#Xts do. _24 failCode 'invalid argument' end.
    (y-1){Xts
)
setDeferred =: 3 : 0
    target=.tokenWord popData''
    (y,8)setWordField target
)
executeWord =: 4 : 0
    id=.x
    owner=.y
    try.
        while. 'defer'-:1{::id{::WordPool do.
            target=.8{::id{::WordPool
            if. target<0 do. _21 failCode 'deferred word not set' end.
            id=.target
            owner=.0{::id{::WordPool
        end.
        executeInner id
    catcht.
        if. 0=#ErrorWord do. ErrorWord=:owner end.
        throw.
    end.
)
executeInner =: 3 : 0
    item=.y{::WordPool
    kind=.1{::item
    select. kind
    case. 'builtin' do. builtin 0{::item
    case. 'colon' do. (2{::item)runDefinition 0
    case. 'create';'variable' do.
        pushData 3{::item
        if. (6{::item)>:0 do. (6{::item)runDefinition 7{::item end.
    case. 'constant' do. pushData 4{::item
    case. 'value' do. pushData (<.(3{::item)%8){Memory
    end.
)
builtin =: 3 : 0
    name=.,y
    if. (<name)e.words '+ - * / MOD /MOD */ */MOD MIN MAX = <> < > AND OR XOR WITHIN' do.
        count=.2
        if. (<name)e.words '*/ */MOD WITHIN' do. count=.3 end.
        values=.takeData count
        'a b'=.2{.values
        if. (<name)e.words '/ MOD /MOD */ */MOD' do.
            if. count=3 do. a=.a*b
                b=.2{values end.
            if. b=0 do. _10 failCode 'division by zero' end.
            q=.<.a%b
            remainder=.a-b*q
            if. (<name)e.words '/MOD */MOD' do. pushValues remainder,q
            elseif. name-:'MOD' do. pushData remainder
            else. pushData q end.
        else.
            select. name
            case. , '+' do. result=.a+b
            case. , '-' do. result=.a-b
            case. , '*' do. result=.a*b
            case. 'MIN' do. result=.a<.b
            case. 'MAX' do. result=.a>.b
            case. 'AND' do. result=.a(17 b.)b
            case. 'OR' do. result=.a(23 b.)b
            case. 'XOR' do. result=.a(22 b.)b
            case. , '=' do. result=.-a=b
            case. '<>' do. result=.-a~:b
            case. , '<' do. result=.-a<b
            case. , '>' do. result=.-a>b
            case. 'WITHIN' do. result=.-(b<:a)*.a<2{values
            end.
            pushData result
        end.
    elseif. (<name)e.words 'NEGATE ABS 1+ 1- 2* 2/ 0= 0<> 0< 0> INVERT CELLS CELL+' do.
        a=.popData''
        select. name
        case. 'NEGATE' do. result=.-a
        case. 'ABS' do. result=.|a
        case. '1+' do. result=.a+1
        case. '1-' do. result=.a-1
        case. '2*' do. result=.a*2
        case. '2/' do. result=.<.a%2
        case. '0=' do. result=.-a=0
        case. '0<>' do. result=.-a~:0
        case. '0<' do. result=.-a<0
        case. '0>' do. result=.-a>0
        case. 'INVERT' do. result=.-1+a
        case. 'CELLS' do. result=.a*8
        case. 'CELL+' do. result=.a+8
        end.
        pushData result
    elseif. (<name)e.words 'DUP ?DUP DROP SWAP OVER ROT -ROT NIP TUCK 2DUP 2DROP 2SWAP 2OVER' do.
        count=.2
        if. (<name)e.words 'DUP ?DUP DROP' do. count=.1
        elseif. (<name)e.words 'ROT -ROT' do. count=.3
        elseif. (<name)e.words '2SWAP 2OVER' do. count=.4 end.
        values=.takeData count
        select. name
        case. 'DUP' do. order=.0 0
        case. '?DUP' do. if. 0={.values do. order=.,0 else. order=.0 0 end.
        case. 'DROP';'2DROP' do. order=.i.0
        case. 'SWAP' do. order=.1 0
        case. 'OVER' do. order=.0 1 0
        case. 'ROT' do. order=.1 2 0
        case. '-ROT' do. order=.2 0 1
        case. 'NIP' do. order=.,1
        case. 'TUCK' do. order=.1 0 1
        case. '2DUP' do. order=.0 1 0 1
        case. '2SWAP' do. order=.2 3 0 1
        case. '2OVER' do. order=.0 1 2 3 0 1
        end.
        pushValues order{values
    elseif. (<name)e.words 'TRUE FALSE DEPTH BL HERE BASE' do.
        select. name
        case. 'TRUE' do. value=._1
        case. 'FALSE';'BASE' do. value=.0
        case. 'DEPTH' do. value=.#Stack
        case. 'BL' do. value=.32
        case. 'HERE' do. value=.hereAddress''
        end.
        pushData value
    elseif. (<name)e.words 'PICK ROLL' do.
        index=.popData''
        if. index<0 do. _24 failCode 'invalid argument' end.
        if. (#Stack)<:index do. _4 failCode 'stack underflow' end.
        at=.(#Stack)-(1+index)
        value=.at{Stack
        if. name-:'ROLL' do. Stack=:(at{.Stack),(at+1)}.Stack end.
        pushData value
    elseif. name-:,'.' do. value=.popData''
        Pending=:Pending,(formatNumber value),' '
    elseif. name-:'.R' do.
        'value width'=.takeData 2
        text=.formatNumber value
        Pending=:Pending,((0>.width-#text)#' '),text
    elseif. name-:'.S' do.
        text=.'<',(formatNumber #Stack),'> '
        for_value. Stack do. text=.text,(formatNumber value),' ' end.
        Pending=:Pending,text
    elseif. name-:,'?' do. address=.popData''
        value=.(cellIndex address){Memory
        Pending=:Pending,(formatNumber value),' '
    elseif. name-:'CR' do. flushLine''
    elseif. name-:'EMIT' do.
        code=.popData''
        if. (code<32)+.code>126 do. _24 failCode 'invalid argument' end.
        Pending=:Pending,code{a.
    elseif. name-:'SPACE' do. Pending=:Pending,' '
    elseif. name-:'SPACES' do. count=.popData''
        Pending=:Pending,(0>.count)#' '
    elseif. (<name)e.words '! +!' do.
        'value address'=.takeData 2
        index=.cellIndex address
        if. name-:,'!' do. Memory=:value index}Memory
        else. Memory=:(value+index{Memory)index}Memory end.
    elseif. name-:,'@' do. address=.popData''
        pushData (cellIndex address){Memory
    elseif. name-:,',' do. Memory=:Memory,popData''
    elseif. name-:'ALLOT' do.
        count=.popData''
        if. (count<0)+.0~:8|count do. _24 failCode 'invalid argument' end.
        Memory=:Memory,(<.count%8)$0
    elseif. (<name)e.words 'HEX DECIMAL' do.
        if. name-:'HEX' do. value=.16 else. value=.10 end.
        Memory=:value 0}Memory
    elseif. (<name)e.words 'CREATE VARIABLE CONSTANT VALUE DEFER' do.
        key=.newName''
        item=.key newWord tolower name
        item=.(<hereAddress'')3}item
        if. (<name)e.words 'CONSTANT VALUE' do. value=.popData''
            item=.(<value)4}item end.
        addWord item
        if. (<name)e.words 'VARIABLE VALUE' do.
            if. name-:'VALUE' do. Memory=:Memory,4{::item else. Memory=:Memory,0 end.
        end.
    elseif. name-:,SQ do. id=.existingWord readName''
        pushData tokenOf id
    elseif. name-:'EXECUTE' do. id=.tokenWord popData''
        id executeWord 0{::id{::WordPool
    elseif. name-:'CATCH' do.
        id=.tokenWord popData''
        saved=.Stack
        returnsize=.#Returns
        depth=.NestingDepth
        framesize=.#Frames
        try. id executeWord 0{::id{::WordPool
        catcht.
            if. -.ErrorCatchable do. throw. end.
            Stack=:saved
            Returns=:(returnsize<.#Returns){.Returns
            Frames=:(framesize<.#Frames){.Frames
            NestingDepth=:depth
            pushData ErrorCode
            return.
        end.
        pushData 0
    elseif. name-:'THROW' do. code=.popData''
        if. code~:0 do. code failCode 'exception ',num code end.
    elseif. name-:'ABORT' do. _1 failCode 'aborted'
    elseif. name-:'WORDS' do.
        for_id. |.Dictionary do. Pending=:Pending,(0{::id{::WordPool),' ' end.
    end.
)
runDefinition =: 4 : 0
    if. NestingDepth=100 do. _7 failCode 'nesting too deep' end.
    NestingDepth=:NestingDepth+1
    returnsize=.#Returns
    frameid=.#Frames
    Frames=:Frames,< (#5{::x{::Definitions)$0
    ip=.y
    body=.3{::x{::Definitions
    while. ip<#body do.
        action=.ip{::body
        try. ip=.runInstruction (<x),(<action),(<ip+1),<frameid
        catcht.
            if. 0=#ErrorWord do. ErrorWord=:1{::action end.
            throw.
        end.
    end.
    Returns=:(returnsize<.#Returns){.Returns
    Frames=:}:Frames
    NestingDepth=:NestingDepth-1
)
runInstruction =: 3 : 0
    'definition action next frameid'=.y
    'op token arg text slots'=.action
    select. op
    case. 'call' do. arg executeWord token
    case. 'push' do. pushData arg
    case. 'local' do. pushData arg{frameid{::Frames
    case. ,'.',DQ do. Pending=:Pending,text
    case. 'branch' do. arg return.
    case. 'zbranch' do. if. 0=popData'' do. arg return. end.
    case. 'DO';'?DO' do.
        'limit index'=.takeData 2
        if. (op-:'?DO')*.limit=index do. arg return. end.
        pushReturn limit
        pushReturn index
    case. 'LOOP';'+LOOP' do.
        if. op-:'LOOP' do. step=.1 else. step=.popData'' end.
        requireReturn 2
        'limit index'=._2{.Returns
        if. ((index-limit)<0)~:((index+step-limit)<0) do. Returns=:_2}.Returns
        else. Returns=:(index+step)(<:#Returns)}Returns
            arg return. end.
    case. 'LEAVE';'UNLOOP' do.
        requireReturn 2
        Returns=:_2}.Returns
        if. op-:'LEAVE' do. arg return. end.
    case. '>R' do. pushReturn popData''
    case. 'R>' do.
        requireReturn 1
        value=.{:Returns
        Returns=:}:Returns
        pushData value
    case. words 'R@ I J' do.
        if. op-:,'J' do. count=.3 else. count=.1 end.
        requireReturn count
        pushData ((#Returns)-count){Returns
    case. 'OF' do.
        'selector candidate'=.takeData 2
        if. selector~:candidate do. pushData selector
            arg return. end.
    case. 'ENDCASE' do. popData''
    case. 'ABORT',DQ do. if. 0~:popData'' do. _2 failCode text end.
    case. '{:' do.
        values=.takeData #slots
        frame=.frameid{::Frames
        frame=.values slots}frame
        Frames=:(<frame)frameid}Frames
    case. 'to_local' do.
        value=.popData''
        frame=.frameid{::Frames
        frame=.value arg}frame
        Frames=:(<frame)frameid}Frames
    case. 'to_value' do.
        value=.popData''
        index=.<.(3{::arg{::WordPool)%8
        Memory=:value index}Memory
    case. 'IS' do. setDeferred arg
    case. 'RECURSE' do. arg runDefinition 0
    case. 'DOES>' do.
        if. 0=#Dictionary do. _31 failCode 'no CREATE word' end.
        id=.{:Dictionary
        if. -.'create'-:1{::id{::WordPool do. _31 failCode 'no CREATE word' end.
        (id,6)setWordField definition
        (id,7)setWordField arg
        #3{::definition{::Definitions return.
    case. 'EXIT' do. #3{::definition{::Definitions return.
    end.
    next
)
emitInstruction =: 3 : 0
    body=.3{::CurrentDef{::Definitions
    result=.#body
    (CurrentDef,3)setDefField body,<y
    result
)
emitSimple =: 4 : 'emitInstruction (<,x),(<y),(<0),(<''''),<i.0'
emitArgument =: 4 : 'emitInstruction (<,x),(0{y),(1{y),(<''''),<i.0'
emitText =: 4 : 'emitInstruction (<,x),(0{y),(<0),(1{y),<i.0'
patch =: 3 : 0
    body=.3{::CurrentDef{::Definitions
    for_index. y do. action=.index{::body
        action=.(<#body)2}action
        body=.(<action)index}body end.
    (CurrentDef,3)setDefField body
)
requireTop =: 3 : 0
    controls=.4{::CurrentDef{::Definitions
    if. 0=#controls do. uncaught 'control structure mismatch' end.
    if. -.(<0{::>{:controls)e.y do. uncaught 'control structure mismatch' end.
)
popControl =: 3 : 0
    controls=.4{::CurrentDef{::Definitions
    result=.>{:controls
    (CurrentDef,4)setDefField }:controls
    result
)
pushControl =: 3 : 0
    controls=.4{::CurrentDef{::Definitions
    (CurrentDef,4)setDefField controls,<y
)
control =: 4 : '( <,x),(0{y),1{y'
localIndex =: 3 : 0
    names=.5{::CurrentDef{::Definitions
    indices=.I.names e.<y
    if. #indices do. {:indices else. _1 end.
)
declareLocals =: 3 : 0
    names=.0$a:
    while. 1 do.
        name=.readWord''
        if. 0=#name do. uncaught 'unterminated locals' end.
        if. name-:':}' do. break. end.
        names=.names,<name
    end.
    names=.(names i.<'--'){.names
    for_name. names do. checkName >name end.
    old=.5{::CurrentDef{::Definitions
    slots=.(#old)+i.#names
    (CurrentDef,5)setDefField old,toupper&.>names
    emitInstruction (<'{:'),(<y),(<0),(<''),<slots
)
compileToken =: 3 : 0
    'token name'=.y
    select. name
    case. 'IF' do. index=.'zbranch'emitSimple token
        pushControl 'IF'control (<index),<i.0
    case. 'ELSE' do.
        requireTop words 'IF'
        index=.'branch'emitSimple token
        previous=.popControl''
        patch ,1{::previous
        pushControl 'ELSE'control (<index),<i.0
    case. 'THEN' do. requireTop words 'IF ELSE'
        previous=.popControl''
        patch ,1{::previous
    case. 'BEGIN' do. pushControl 'BEGIN'control (<#3{::CurrentDef{::Definitions),<i.0
    case. 'UNTIL';'AGAIN' do.
        requireTop words 'BEGIN'
        previous=.popControl''
        if. name-:'UNTIL' do. op=.'zbranch' else. op=.'branch' end.
        op emitArgument (<token),<1{::previous
    case. 'WHILE' do.
        requireTop words 'BEGIN'
        index=.'zbranch'emitSimple token
        previous=.popControl''
        pushControl 'WHILE'control (1{previous),<,index
    case. 'REPEAT' do.
        requireTop words 'WHILE'
        previous=.popControl''
        'branch'emitArgument (<token),<1{::previous
        patch 2{::previous
    case. 'DO';'?DO' do.
        index=.name emitSimple token
        refs=.i.0
        if. name-:'?DO' do. refs=.,index end.
        pushControl name control (<index+1),<refs
    case. 'LOOP';'+LOOP' do.
        requireTop words 'DO ?DO'
        previous=.popControl''
        name emitArgument (<token),<1{::previous
        patch 2{::previous
    case. 'LEAVE' do.
        controls=.4{::CurrentDef{::Definitions
        loop=._1
        for_i. |.i.#controls do.
            if. (<0{::i{::controls)e.words 'DO ?DO' do. loop=.i break. end.
        end.
        if. loop<0 do. uncaught 'control structure mismatch' end.
        index=.'LEAVE'emitSimple token
        record=.loop{::controls
        record=.(<(2{::record),index)2}record
        controls=.(<record)loop}controls
        (CurrentDef,4)setDefField controls
    case. 'CASE' do. pushControl 'CASE'control (<0),<i.0
    case. 'OF' do. requireTop words 'CASE'
        index=.'OF'emitSimple token
        pushControl 'OF'control (<index),<i.0
    case. 'ENDOF' do.
        requireTop words 'OF'
        index=.'branch'emitSimple token
        previous=.popControl''
        patch ,1{::previous
        controls=.4{::CurrentDef{::Definitions
        record=.>{:controls
        record=.(<(2{::record),index)2}record
        controls=.(<record)(<:#controls)}controls
        (CurrentDef,4)setDefField controls
    case. 'ENDCASE' do.
        requireTop words 'CASE'
        'ENDCASE'emitSimple token
        previous=.popControl''
        patch 2{::previous
    case. 'RECURSE' do. 'RECURSE'emitArgument (<token),<CurrentDef
    case. 'DOES>' do.
        if. #4{::CurrentDef{::Definitions do. uncaught 'control structure mismatch' end.
        'DOES>'emitArgument (<token),<1+#3{::CurrentDef{::Definitions
    case. ,';' do.
        definition=.CurrentDef{::Definitions
        controls=.4{::definition
        if. #controls do.
            kind=.0{::>{:controls
            if. kind-:'ELSE' do. kind=.'IF' elseif. kind-:'WHILE' do. kind=.'BEGIN' end.
            uncaught 'unclosed ',kind
        end.
        key=.0{::definition
        if. #key do. wordname=.key else. wordname=.':NONAME' end.
        item=.wordname newWord 'colon'
        item=.(<CurrentDef)2}item
        item=.(2{definition)5}item
        id=.#WordPool
        WordPool=:WordPool,<item
        CurrentDef=:_1
        if. #key do. Dictionary=:Dictionary,id else. pushData tokenOf id end.
    case. '[',SQ,']' do. id=.existingWord readName''
        'push'emitArgument (<token),<tokenOf id
    case. '{:' do. declareLocals token
    case. words 'EXIT >R R> R@ I J UNLOOP' do. name emitSimple token
    case. do.
        slot=.localIndex name
        if. slot>:0 do. 'local'emitArgument (<token),<slot
        else.
            id=.findWord name
            if. id<0 do. 'push'emitArgument (<token),<literal token
            else. 'call'emitArgument (<token),<id end.
        end.
    end.
)
processToken =: 3 : 0
    token=.y
    name=.toupper token
    compiling=.CurrentDef>:0
    if. name-:,'\' do. Position=:#InputLine
    elseif. name-:,'(' do.
        tail=.Position}.InputLine
        at=.tail i.')'
        if. at=#tail do. uncaught 'unterminated comment' end.
        Position=:Position+at+1
    elseif. (-.compiling)*.(<name)e.CompileOnly do. uncaught 'compile only'
    elseif. compiling*.(<name)e.InterpretOnly do. uncaught 'interpret only'
    elseif. (<name)e.('.';'ABORT'),&.><DQ do.
        text=.readString''
        if. compiling do. name emitText (<token),<text else. Pending=:Pending,text end.
    elseif. (<name)e.words 'TO IS' do.
        raw=.readName''
        key=.toupper raw
        if. compiling*.name-:'TO' do.
            slot=.localIndex key
            if. slot>:0 do. 'to_local'emitArgument (<token),<slot return. end.
        end.
        id=.existingWord raw
        if. name-:'TO' do. expected=.'value'
        else. expected=.'defer' end.
        if. -.expected-:1{::id{::WordPool do.
            if. name-:'TO' do. reason=.'not a value' else. reason=.'not deferred' end.
            fail (<reason),(<0),(<0),<raw
        end.
        if. compiling do.
            if. name-:'TO' do. op=.'to_value' else. op=.'IS' end.
            op emitArgument (<token),<id
        elseif. name-:'TO' do. value=.popData''
            index=.<.(3{::id{::WordPool)%8
            Memory=:value index}Memory
        else. setDeferred id end.
    elseif. (<name)e.words ': :NONAME' do.
        if. name-:,':' do. raw=.readName''
            checkName raw
            key=.toupper raw
        else. raw=.token
            key=.'' end.
        CurrentDef=:#Definitions
        definition=.(<key),(<raw),(<hereAddress''),(<0$a:),(<0$a:),<0$a:
        Definitions=:Definitions,<definition
    elseif. name-:'FORGET' do.
        raw=.readName''
        key=.toupper raw
        for_i. |.i.#Dictionary do.
            id=.i{Dictionary
            if. key-:0{::id{::WordPool do.
                Memory=:(<.(5{::id{::WordPool)%8){.Memory
                Dictionary=:i{.Dictionary
                return.
            end.
        end.
        fail (<'undefined word'),(<_13),(<1),<raw
    elseif. compiling do. compileToken (<token),<name
    else.
        id=.findWord name
        if. id<0 do. pushData literal token else. id executeWord token end.
    end.
)
processLine =: 3 : 0
    InputLine=:y
    Position=:0
    token=.''
    try.
        while. 1 do. token=.readWord''
            if. 0=#token do. break. end.
            processToken token
        end.
    catcht.
        if. #Pending do. flushLine'' end.
        if. 0=#ErrorWord do. ErrorWord=:token end.
        say 'ERROR ',ErrorWord,': ',ErrorReason
        Stack=:Returns=:i.0
        Frames=:0$a:
        NestingDepth=:0
        CurrentDef=:_1
    end.
    if. #Pending do. flushLine'' end.
)
main =: 3 : 0
    Stack=:Returns=:Dictionary=:Xts=:i.0
    Memory=:,10
    WordPool=:Definitions=:Frames=:0$a:
    for_name. BuiltinNames do. WordPool=:WordPool,< (>name)newWord 'builtin' end.
    CurrentDef=:_1
    NestingDepth=:0
    Pending=:''
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    for_line. lines do.
        line=.>line
        if. line-:'BYE' do.
            if. CurrentDef>:0 do. say 'ERROR ',(1{::CurrentDef{::Definitions),': unterminated definition' end.
            break.
        end.
        processLine line
    end.
)
main''
