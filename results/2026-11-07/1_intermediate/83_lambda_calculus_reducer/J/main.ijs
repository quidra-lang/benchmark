LF =: 10{a.
BSLASH =: 92{a.
SQ =: 39{a.
num =: 3 : ',''0'' 8!:2 y'
say =: 3 : '1!:2&2 y,LF'
words =: 3 : '(<;._1 '' '',y)-.<'''''
join =: 4 : '(#x)}.;(<x),&.>y'
Strategies =: words 'NORMAL APPLICATIVE CBN CBV'
Reserved =: (words 'S K I'),Strategies
WordCommands =: words 'unlet macros steps eta limit'
TermCommands =: words 'let expand subst reduce equal alpha debruijn fv size depth type church ski skireduce kam'
fail =: 3 : 0
    Reason=:y
    throw.
)
kind =: 3 : '0{::y{::Nodes'
textOf =: 3 : '1{::y{::Nodes'
numberOf =: 3 : '2{::y{::Nodes'
left =: 3 : '3{::y{::Nodes'
right =: 3 : '4{::y{::Nodes'
free =: 3 : 'y{::FreeSets'
refs =: 3 : 'y{::References'
addNode =: 3 : 0
    'k text number first second'=.y
    names=.references=.0$a:
    size=.depth=.1
    if. k=0 do. names=.,<text
    elseif. k=1 do. references=.,<text
    elseif. k e.3 7 do.
        names=.free first
        if. k=3 do. names=.names-.<text end.
        references=.refs first
        size=.size+first{Sizes
        depth=.depth+first{Depths
    elseif. k=4 do.
        names=.~.(free first),free second
        names=.(/:names){names
        references=.(refs first),refs second
        size=.size+(first{Sizes)+second{Sizes
        depth=.depth+(first{Depths)>.second{Depths
    end.
    result=.#Nodes
    Nodes=:Nodes,<y
    FreeSets=:FreeSets,<names
    References=:References,<references
    Sizes=:Sizes,size
    Depths=:Depths,depth
    result
)
variable =: 3 : 'addNode (<0),(<,y),(<0),(<0),<0'
macroNode =: 3 : 'addNode (<1),(<,y),(<0),(<0),<0'
numeralNode =: 3 : 'addNode (<2),(<''''),(<y),(<0),<0'
lam =: 4 : 'addNode (<3),(<,x),(<0),(<y),<0'
app =: 4 : 'addNode (<4),(<''''),(<0),(<x),<y'
constant =: 3 : 'addNode (<5),(<,y),(<0),(<0),<0'
indexNode =: 3 : 'addNode (<6),(<''''),(<y),(<0),<0'
dbLam =: 3 : 'addNode (<7),(<''''),(<0),(<y),<0'
applyAll =: 4 : 0
    result=.x
    for_argument. y do. result=.result app argument end.
    result
)
pretty =: 4 : 0
    k=.kind y
    if. k e.0 1 5 do. textOf y return. end.
    if. k=2 do. '#',num numberOf y return. end.
    if. k=6 do. num numberOf y return. end.
    if. k=3 do.
        names=.0$a:
        current=.y
        while. 3=kind current do. names=.names,<textOf current
            current=.left current end.
        text=.BSLASH,(' 'join names),'. ',1 pretty current
        if. x do. text else. '(',text,')' end. return.
    end.
    if. k=7 do.
        text=.BSLASH,1 pretty left y
        if. x do. text else. '(',text,')' end. return.
    end.
    f=.left y
    a=.right y
    if. (kind f)e.3 7 do. first=.'(',(1 pretty f),')' else. first=.0 pretty f end.
    if. 4=kind a do. second=.'(',(1 pretty a),')' else. second=.x pretty a end.
    first,' ',second
)
churchNumeral =: 3 : 0
    body=.variable 'x'
    function=.variable 'f'
    for_i. i.y do. body=.function app body end.
    'f'lam 'x'lam body
)
substitute =: 3 : 0
    'term name value'=.y
    if. -.(<name)e.free term do. term return. end.
    k=.kind term
    if. k=0 do. value return. end.
    if. k=4 do.
        first=.substitute (<left term),(<name),<value
        second=.substitute (<right term),(<name),<value
        first app second return.
    end.
    bound=.textOf term
    body=.left term
    if. (bound-:name)+.-.(<name)e.free body do. term return. end.
    if. -.(<bound)e.free value do.
        bound lam substitute (<body),(<name),<value return.
    end.
    base=.bound
    while. #base do. if. -.({:base)e.'0123456789' do. break. end.
        base=.}:base end.
    suffix=.1
    while. 1 do.
        fresh=.base,num suffix
        if. -.(<fresh)e.(free value),free body do. break. end.
        suffix=.suffix+1
    end.
    replacement=.variable fresh
    renamed=.substitute (<body),(<bound),<replacement
    fresh lam substitute (<renamed),(<name),<value
)
sequenceName =: 3 : 0
    letter=.,(26|y){'abcdefghijklmnopqrstuvwxyz'
    if. y<26 do. letter else. letter,num <.y%26 end.
)
toDB =: 4 : 0
    k=.kind y
    if. k=0 do.
        at=.x i.<textOf y
        if. at<#x do. indexNode at else. y end. return.
    end.
    if. k=3 do. dbLam ((<textOf y),x)toDB left y return. end.
    if. k=4 do.
        first=.x toDB left y
        second=.x toDB right y
        first app second return.
    end.
    y
)
renameDB =: 4 : 0
    k=.kind y
    if. k=6 do. variable (numberOf y){::x return. end.
    if. k=7 do.
        name=.sequenceName NameCounter
        NameCounter=:NameCounter+1
        while. (<name)e.Excluded do. name=.sequenceName NameCounter
            NameCounter=:NameCounter+1 end.
        body=.((<name),x)renameDB left y
        name lam body return.
    end.
    if. k=4 do.
        first=.x renameDB left y
        second=.x renameDB right y
        first app second return.
    end.
    y
)
fromDB =: 3 : 0
    NameCounter=:0
    Excluded=:free y
    (0$a:)renameDB y
)
canonical =: 3 : 'fromDB (0$a:)toDB y'
alphaEqual =: 4 : 0
    first=.(0$a:)toDB x
    second=.(0$a:)toDB y
    (1 pretty first)-:1 pretty second
)
etaRedex =: 3 : 0
    if. 3~:kind y do. 0 return. end.
    body=.left y
    if. 4~:kind body do. 0 return. end.
    argument=.right body
    if. 0~:kind argument do. 0 return. end.
    ((textOf y)-:textOf argument)*.-.(<textOf y)e.free left body
)
oneStep =: 3 : 0
    'term strategy eta'=.y
    k=.kind term
    if. k=4 do.
        f=.left term
        a=.right term
        if. (3=kind f)*.(<strategy)e.words 'NORMAL CBN' do.
            result=.substitute (<left f),(<textOf f),<a
            (<1),(<result),<'beta' return.
        end.
        changed=.oneStep (<f),(<strategy),<eta
        if. 0{::changed do.
            result=.(1{::changed)app a
            (<1),(<result),2{changed return.
        end.
        if. -.strategy-:'CBN' do.
            changed=.oneStep (<a),(<strategy),<eta
            if. 0{::changed do.
                result=.f app 1{::changed
                (<1),(<result),2{changed return.
            end.
        end.
        if. (3=kind f)*.((strategy-:'APPLICATIVE')+.((kind a)e.0 3)) do.
            result=.substitute (<left f),(<textOf f),<a
            (<1),(<result),<'beta' return.
        end.
    elseif. (k=3)*.(<strategy)e.words 'NORMAL APPLICATIVE' do.
        contractible=.eta*.etaRedex term
        if. contractible*.strategy-:'NORMAL' do. (<1),(<left left term),<'eta' return. end.
        changed=.oneStep (<left term),(<strategy),<eta
        if. 0{::changed do.
            result=.(textOf term)lam 1{::changed
            (<1),(<result),2{changed return.
        end.
        if. contractible do. (<1),(<left left term),<'eta' return. end.
    end.
    (<0),(<term),<''
)
abstractSKI =: 4 : 0
    if. -.(<x)e.free y do. (constant 'K')app y return. end.
    if. (kind y)=0 do. constant 'I' return. end.
    f=.left y
    a=.right y
    if. (kind a)=0 do.
        if. ((textOf a)-:x)*.-.(<x)e.free f do. f return. end.
    end.
    first=.x abstractSKI f
    second=.x abstractSKI a
    ((constant 'S')app first)app second
)
toSKI =: 3 : 0
    k=.kind y
    if. k=3 do. (textOf y)abstractSKI toSKI left y return. end.
    if. k=4 do.
        first=.toSKI left y
        second=.toSKI right y
        first app second return.
    end.
    y
)
skiStep =: 3 : 0
    head=.y
    arguments=.i.0
    while. (kind head)=4 do. arguments=.(right head),arguments
        head=.left head end.
    if. (kind head)=5 do.
        name=.textOf head
        if. (name-:,'I')*.(#arguments)>:1 do. result=.({.arguments)applyAll }.arguments
            (<1),(<result),<,'I' return. end.
        if. (name-:,'K')*.(#arguments)>:2 do. result=.({.arguments)applyAll 2}.arguments
            (<1),(<result),<,'K' return. end.
        if. (name-:,'S')*.(#arguments)>:3 do.
            first=.(0{arguments)app 2{arguments
            second=.(1{arguments)app 2{arguments
            result=.(first app second)applyAll 3}.arguments
            (<1),(<result),<,'S' return.
        end.
    end.
    for_i. i.#arguments do.
        changed=.skiStep i{arguments
        if. 0{::changed do.
            arguments=.(1{::changed)i}arguments
            result=.head applyAll arguments
            (<1),(<result),2{changed return.
        end.
    end.
    (<0),(<y),<''
)
readChurch =: 3 : 0
    if. 3=kind y do.
        inner=.left y
        if. 3=kind inner do.
            body=.left inner
            count=.0
            while. 4=kind body do.
                f=.left body
                if. 0~:kind f do. break. end.
                if. -.(textOf f)-:textOf y do. break. end.
                body=.right body
                count=.count+1
            end.
            if. 0=kind body do. if. (textOf body)-:textOf inner do. num count return. end. end.
            body=.left inner
            if. 0=kind body do. if. (textOf body)-:textOf y do. 'true' return. end. end.
        end.
        body=.left y
        if. 4=kind body do.
            f=.left body
            if. 4=kind f do.
                head=.left f
                first=.right f
                second=.right body
                if. 0=kind head do.
                    if. ((textOf head)-:textOf y)*.-.(<textOf y)e.(free first),free second do.
                        firsttext=.readChurch first
                        secondtext=.readChurch second
                        '(',firsttext,', ',secondtext,')' return.
                    end.
                end.
            end.
        end.
    end.
    1 pretty canonical y
)
lex =: 4 : 0
    'firstcolumn endcolumn'=.x
    Tokens=:0$a:
    at=.0
    while. at<#y do.
        c=.at{y
        if. c=' ' do. at=.at+1 continue. end.
        start=.at
        if. c e.'abcdefghijklmnopqrstuvwxyz' do.
            k=.0
            while. at<#y do.
                if. -.(at{y)e.'abcdefghijklmnopqrstuvwxyz0123456789' do. break. end.
                at=.at+1 end.
        elseif. c e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ' do.
            k=.1
            while. at<#y do.
                if. -.(at{y)e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_' do. break. end.
                at=.at+1 end.
        elseif. (c='#')*.(at+1)<#y do.
            if. -.( (at+1){y)e.'0123456789' do. fail 'column ',(num firstcolumn+at),': unexpected character ',SQ,c,SQ end.
            k=.2
            at=.at+1
            while. at<#y do.
                if. -.(at{y)e.'0123456789' do. break. end.
                at=.at+1 end.
        else.
            k=.3+(BSLASH,'.()=;')i.c
            if. k=9 do. fail 'column ',(num firstcolumn+at),': unexpected character ',SQ,c,SQ end.
            at=.at+1
        end.
        Tokens=:Tokens,<(<k),(<(at-start){.start}.y),<firstcolumn+start
    end.
    Tokens=:Tokens,<(<9),(<''),<endcolumn
    TokenPosition=:0
)
peek =: 3 : 'TokenPosition{::Tokens'
advance =: 3 : 0
    result=.TokenPosition{::Tokens
    TokenPosition=:TokenPosition+1
    result
)
expect =: 3 : 0
    token=.peek''
    if. y~:0{::token do.
        descriptions=.('variable';'macro name';'';'';'.';'';')';'=';';')
        description=.y{::descriptions
        if. y>:4 do. description=.SQ,description,SQ end.
        fail 'column ',(num 2{::token),': expected ',description
    end.
    advance''
)
finishParse =: 3 : 0
    token=.peek''
    if. 9~:0{::token do. fail 'column ',(num 2{::token),': unexpected ',SQ,(1{::token),SQ end.
)
readTerm =: 3 : 0
    elements=.i.0
    while. (0{::peek'')e.0 1 2 5 do.
        token=.advance''
        'k text column'=.token
        select. k
        case. 0 do. element=.variable text
        case. 1 do. element=.macroNode text
        case. 2 do. element=.numeralNode 0".}.text
        case. 5 do. element=.readTerm''
            expect 6
        end.
        elements=.elements,element
    end.
    if. 3=0{::peek'' do.
        advance''
        names=.,<1{::expect 0
        while. 0=0{::peek'' do. names=.names,<1{::advance'' end.
        expect 4
        body=.readTerm''
        for_name. |.names do. body=.(>name)lam body end.
        elements=.elements,body
    end.
    if. 0=#elements do. fail 'column ',(num 2{::peek''),': expected term' end.
    ({.elements)applyAll }.elements
)
copyTerm =: 3 : 0
    cached=.y{CopyMemo
    if. cached>:0 do. cached return. end.
    item=.y{::OldNodes
    k=.0{::item
    if. k e.3 4 7 do. first=.copyTerm 3{::item
        item=.(<first)3}item end.
    if. k=4 do. second=.copyTerm 4{::item
        item=.(<second)4}item end.
    result=.addNode item
    CopyMemo=:result y}CopyMemo
    result
)
compact =: 3 : 0
    OldNodes=:Nodes
    CopyMemo=:(#Nodes)$_1
    Nodes=:FreeSets=:References=:0$a:
    Sizes=:Depths=:i.0
    updated=.i.0
    for_body. MacroTerms do. updated=.updated,copyTerm body end.
    MacroTerms=:updated
    OldNodes=:0$a:
    CopyMemo=:i.0
)
dependsOn =: 4 : 0
    pending=.,<y
    visited=.0$a:
    while. #pending do.
        name=.>{:pending
        pending=.}:pending
        if. (<name)e.visited do. continue. end.
        visited=.visited,<name
        if. (<name)e.words 'S K I' do. continue. end.
        at=.MacroNames i.<name
        if. at=#MacroNames do. continue. end.
        references=.refs at{MacroTerms
        if. (<x)e.references do. 1 return. end.
        pending=.pending,references-.visited
    end.
    0
)
expandTerm =: 3 : 0
    cached=.ExpansionFrom i.y
    if. cached<#ExpansionFrom do. cached{ExpansionTo return. end.
    k=.kind y
    result=.y
    if. k=1 do.
        name=.textOf y
        at=.MacroNames i.<name
        if. at=#MacroNames do. fail 'unbound macro ',name end.
        result=.expandTerm at{MacroTerms
    elseif. k=2 do. result=.churchNumeral numberOf y
    elseif. k=3 do. result=.(textOf y)lam expandTerm left y
    elseif. k=4 do.
        first=.expandTerm left y
        second=.expandTerm right y
        result=.first app second
    end.
    ExpansionFrom=:ExpansionFrom,y
    ExpansionTo=:ExpansionTo,result
    result
)
normalize =: 3 : 0
    'term strategy eta display ski'=.y
    count=.0
    while. 1 do.
        if. ski do. changed=.skiStep term else. changed=.oneStep (<term),(<strategy),<eta end.
        if. -.0{::changed do. 1,term,count return. end.
        if. count=StepLimit do. 0,term,count return. end.
        term=.1{::changed
        count=.count+1
        if. display do. say 'step ',(num count),' (',(2{::changed),'): ',1 pretty term end.
    end.
)
normal =: 3 : 'normalize (<y),(<''NORMAL''),(<EtaMode),(<0),<0'
noNormalForm =: 3 : '''no normal form within '',(num StepLimit),'' steps'''
reportOutcome =: 4 : 0
    'success term count'=.y
    if. -.success do. say noNormalForm'' return. end.
    if. x do. term=.canonical term end.
    say 'result: ',(1 pretty term),' (steps: ',(num count),')'
)
typeFresh =: 3 : 0
    result=.#TypeKinds
    TypeKinds=:TypeKinds,0
    TypeLeft=:TypeLeft,0
    TypeRight=:TypeRight,0
    TypeLinks=:TypeLinks,_1
    result
)
typeArrow =: 4 : 0
    result=.#TypeKinds
    TypeKinds=:TypeKinds,1
    TypeLeft=:TypeLeft,x
    TypeRight=:TypeRight,y
    TypeLinks=:TypeLinks,_1
    result
)
typeResolve =: 3 : 0
    current=.y
    while. -.current{TypeKinds do.
        next=.current{TypeLinks
        if. next<0 do. break. end.
        current=.next
    end.
    current
)
typeOccurs =: 4 : 0
    current=.typeResolve y
    if. current{TypeKinds do.
        (x typeOccurs current{TypeLeft)+.x typeOccurs current{TypeRight
    else. x=current end.
)
typeUnify =: 4 : 0
    a=.typeResolve x
    b=.typeResolve y
    if. -.a{TypeKinds do.
        if. a~:b do.
            if. a typeOccurs b do. throw. end.
            TypeLinks=:b a}TypeLinks
        end.
    elseif. -.b{TypeKinds do. b typeUnify a
    else.
        (a{TypeLeft)typeUnify b{TypeLeft
        (a{TypeRight)typeUnify b{TypeRight
    end.
)
inferType =: 4 : 0
    'names types'=.x
    k=.kind y
    if. k=0 do.
        at=.{:I.names e.<textOf y
        at{types return.
    end.
    if. k=3 do.
        parameter=.typeFresh''
        boundnames=.names,<textOf y
        boundtypes=.types,parameter
        scope=.(<boundnames),<boundtypes
        body=.scope inferType left y
        parameter typeArrow body return.
    end.
    function=.x inferType left y
    result=.typeFresh''
    argument=.x inferType right y
    function typeUnify argument typeArrow result
    result
)
renderType =: 3 : 0
    current=.typeResolve y
    if. -.current{TypeKinds do.
        at=.RenderTypes i.current
        if. at=#RenderTypes do. RenderTypes=:RenderTypes,current end.
        sequenceName at return.
    end.
    domain=.renderType current{TypeLeft
    if. (typeResolve current{TypeLeft){TypeKinds do. domain=.'(',domain,')' end.
    codomain=.renderType current{TypeRight
    domain,' -> ',codomain
)
principalType =: 3 : 0
    TypeKinds=:TypeLeft=:TypeRight=:TypeLinks=:i.0
    names=.free y
    types=.i.0
    for_name. names do. types=.types,typeFresh'' end.
    scope=.(<names),<types
    try. result=.scope inferType y
    catcht. 'not typable' return. end.
    RenderTypes=:i.0
    renderType result
)
readBack =: 4 : 0
    'environment binders'=.x
    current=.y
    while. 6=kind current do.
        index=.numberOf current
        if. index<binders do. break. end.
        closure=.(index-binders){environment
        'current environment'=.closure{::KClosures
        binders=.0
    end.
    k=.kind current
    if. k=7 do. dbLam ((<environment),<binders+1)readBack left current return. end.
    if. k=4 do.
        scope=.(<environment),<binders
        first=.scope readBack left current
        second=.scope readBack right current
        first app second return.
    end.
    current
)
runKAM =: 3 : 0
    code=.(0$a:)toDB y
    environment=.stack=.i.0
    KClosures=:0$a:
    count=.0
    while. 1 do.
        k=.kind code
        if. (k=0)+.((k=7)*.0=#stack) do. break. end.
        if. count=StepLimit do. say 'no result within ',(num StepLimit),' transitions' return. end.
        if. k=4 do.
            stack=.stack,#KClosures
            KClosures=:KClosures,<(<right code),<environment
            code=.left code
            transition=.'push'
        elseif. k=7 do.
            closure=.{:stack
            stack=.}:stack
            environment=.closure,environment
            code=.left code
            transition=.'grab'
        else.
            saved=.(numberOf code){environment
            'code environment'=.saved{::KClosures
            transition=.'access'
        end.
        count=.count+1
        if. ShowSteps do. say 'step ',(num count),' (',transition,'): ',(1 pretty code),' [env ',(num #environment),', stack ',(num #stack),']' end.
    end.
    result=.((<environment),<0)readBack code
    for_closure. |.stack do.
        'code saved'=.closure{::KClosures
        argument=.((<saved),<0)readBack code
        result=.result app argument
    end.
    say 'result: ',(1 pretty fromDB result),' (transitions: ',(num count),')'
)
macroName =: 3 : 0
    if. 0=#y do. 0 return. end.
    (({.y)e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ')*.*./y e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'
)
userNames =: 3 : '/:~MacroNames-.words ''S K I'''
wordCommand =: 4 : 0
    fields=.words y
    if. (<x)e.words 'steps eta' do.
        if. 1~:#fields do. fail 'bad argument' end.
        value=.0{::fields
        if. -.(<value)e.words 'on off' do. fail 'bad argument' end.
        if. x-:'steps' do. ShowSteps=:'on'-:value else. EtaMode=:'on'-:value end.
    elseif. x-:'limit' do.
        if. 1~:#fields do. fail 'bad argument' end.
        value=.0{::fields
        if. ((#value)>5)+.-.*./value e.'0123456789' do. fail 'bad argument' end.
        number=.0".value
        if. (number<1)+.number>10000 do. fail 'bad argument' end.
        StepLimit=:number
    elseif. x-:'macros' do.
        if. #fields do. fail 'bad argument' end.
        names=.userNames''
        if. 0=#names do. say '(none)' end.
        for_name. names do.
            name=.>name
            say name,' = ',1 pretty (MacroNames i.<name){MacroTerms
        end.
    else.
        if. 1~:#fields do. fail 'bad argument' end.
        name=.0{::fields
        if. -.macroName name do. fail 'bad argument' end.
        if. (<name)e.Reserved do. fail 'reserved name ',name end.
        at=.MacroNames i.<name
        if. at=#MacroNames do. fail 'unbound macro ',name end.
        for_other. userNames'' do.
            other=.>other
            body=.(MacroNames i.<other){MacroTerms
            if. (<name)e.refs body do. fail name,' is used by ',other end.
        end.
        MacroNames=:(at{.MacroNames),(at+1)}.MacroNames
        MacroTerms=:(at{.MacroTerms),(at+1)}.MacroTerms
        say 'removed ',name
    end.
)
executeLine =: 3 : 0
    compact''
    split=.y i.' '
    command=.split{.y
    argument=.(split+1)}.y
    if. (<command)e.WordCommands do. command wordCommand argument return. end.
    if. -.(<command)e.TermCommands do. fail 'unknown command ',command end.
    (((#command)+2),1+#y)lex argument
    ExpansionFrom=:ExpansionTo=:i.0
    if. command-:'let' do.
        name=.1{::expect 1
        expect 7
        body=.readTerm''
        finishParse''
        if. (<name)e.Reserved do. fail 'reserved name ',name end.
        for_reference. refs body do.
            reference=.>reference
            if. (reference-:name)+.name dependsOn reference do. fail 'recursive definition of ',name end.
            if. -.(<reference)e.MacroNames do. fail 'unbound macro ',reference end.
        end.
        names=.free body
        if. #names do. fail 'free variable ',(0{::names),' in definition of ',name end.
        at=.MacroNames i.<name
        if. at=#MacroNames do.
            MacroNames=:MacroNames,<name
            MacroTerms=:MacroTerms,body
            say 'defined ',name
        else. MacroTerms=:body at}MacroTerms
            say 'redefined ',name end.
        return.
    end.
    if. command-:'subst' do.
        name=.1{::expect 0
        expect 7
        value=.readTerm''
        expect 8
        target=.readTerm''
        finishParse''
        value=.expandTerm value
        target=.expandTerm target
        say 1 pretty substitute (<target),(<name),<value
        return.
    end.
    strategy=.'NORMAL'
    if. command-:'reduce' do.
        token=.peek''
        if. (0{::token)=1 do.
            if. (<1{::token)e.Strategies do. strategy=.1{::advance'' end.
        end.
    end.
    first=.readTerm''
    if. (<command)e.words 'equal alpha' do.
        expect 8
        second=.readTerm''
        finishParse''
        first=.expandTerm first
        second=.expandTerm second
        if. command-:'alpha' do. equal=.first alphaEqual second
        else.
            a=.normal first
            b=.normal second
            if. (0={.a)+.0={.b do. say 'unknown' return. end.
            equal=.(1{a)alphaEqual 1{b
        end.
        if. equal do. say 'yes' else. say 'no' end.
        return.
    end.
    finishParse''
    first=.expandTerm first
    select. command
    case. 'expand' do. say 1 pretty first
    case. 'reduce' do. 1 reportOutcome normalize (<first),(<strategy),(<EtaMode),(<ShowSteps),<0
    case. 'debruijn' do. say 1 pretty (0$a:)toDB first
    case. 'fv' do. names=.free first
        if. #names do. say ' 'join names else. say '(none)' end.
    case. 'size' do. say num first{Sizes
    case. 'depth' do. say num first{Depths
    case. 'type' do. say principalType first
    case. 'church' do.
        result=.normalize (<first),(< 'NORMAL'),(<0),(<0),<0
        if. {.result do. say readChurch canonical 1{result else. say noNormalForm'' end.
    case. 'ski';'skireduce' do.
        converted=.toSKI first
        if. command-:'ski' do. say 1 pretty converted
        else. 0 reportOutcome normalize (<converted),(< 'NORMAL'),(<0),(<ShowSteps),<1 end.
    case. 'kam' do. runKAM first
    end.
)
main =: 3 : 0
    Nodes=:FreeSets=:References=:0$a:
    Sizes=:Depths=:i.0
    MacroNames=:words 'S K I'
    MacroTerms=:i.0
    for_source. ('\x y z. x z (y z)';'\x y. x';'\x. x') do.
        source=.>source
        (1,1+#source)lex source
        MacroTerms=:MacroTerms,readTerm''
    end.
    ShowSteps=:EtaMode=:0
    StepLimit=:10000
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    for_line. lines do.
        line=.>line
        if. line-:'quit' do. break. end.
        if. (0=#line)+.'--'-:2{.line do. continue. end.
        try. executeLine line
        catcht. say 'error: ',Reason end.
    end.
)
main''
