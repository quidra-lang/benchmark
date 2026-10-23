LF =: 10{a.
SQ =: 39{a.
DQ =: 34{a.
NUL =: 0{a.
num =: 3 : ',''0'' 8!:2 y'
say =: 3 : '1!:2&2 y,LF'
join =: 4 : '(#x)}.;(<x),&.>y'
words =: 3 : '(<;._1 '' '',y)-.<'''''
CommandNames =: words 'FD BK RT LT SETH PU PD PE SETPEN SETXY SETX SETY HOME CS CLEAN FILL LABEL SNAPSHOT REPEAT FOR WHILE IF IFELSE TEST IFTRUE IFFALSE STOP OUTPUT MAKE LOCAL LOCALMAKE TRACE UNTRACE SEED PRINT'
CommandSigs =: 'E';'E';'E';'E';'E';'';'';'';'E';'EE';'E';'E';'';'';'';'';'P';'';'EL';'QEEL';'EL';'EL';'ELL';'E';'L';'L';'';'E';'QE';'Q';'QE';'Q';'Q';'E';'P'
FunctionNames =: words 'XCOR YCOR HEADING REPCOUNT RANDOM ABS NOT AND OR MAX MIN'
FunctionArities =: 0 0 0 0 1 1 1 2 2 2 2
AliasNames =: words 'FORWARD BACK RIGHT LEFT SETHEADING PENUP PENDOWN PENERASE CLEARSCREEN IFT IFF OP PR'
AliasTargets =: words 'FD BK RT LT SETH PU PD PE CS IFTRUE IFFALSE OUTPUT PRINT'
Primitives =: CommandNames,FunctionNames,AliasNames,words 'TO END MOD'
Directions =: 8 2$0 1 1 1 1 0 1 _1 0 _1 _1 _1 _1 0 _1 1
fail =: 4 : 0
    ErrorLine=:x
    Reason=:y
    throw.
)
rejection =: 3 : 0
    'line owner value'=.y
    line fail owner,' doesn',SQ,'t like ',value,' as input'
)
canonical =: 3 : 0
    i=.AliasNames i.<y
    if. i<#AliasNames do. i{::AliasTargets else. y end.
)
nameValid =: 3 : 0
    if. 0=#y do. 0 return. end.
    (({.y)e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ')*.*./y e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'
)
digits =: 3 : '(0<#y)*.*./y e.''0123456789'''
classify =: 4 : 0
    if. digits y do. (<'number'),(<y),(<x),<0".y return. end.
    if. nameValid y do. (<'word'),(<y),(<x),<y return. end.
    if. ({.y)e.':',DQ do.
        if. nameValid }.y do.
            if. ':'={.y do. kind=.'variable' else. kind=.'quoted' end.
            (<kind),(<y),(<x),<}.y return.
        end.
    end.
    x fail 'bad token ',SQ,y,SQ
)
tokenize =: 4 : 0
    text=.toupper (y i.';'){.y
    delimiters=.' []()+-*/=<>'
    result=.0$a:
    i=.0
    while. i<#text do.
        c=.i{text
        following=.''
        if. (i+1)<#text do. following=.,(i+1){text end.
        if. c=' ' do. i=.i+1
        elseif. c='-' do.
            if. i=0 do. starts=.1 else. starts=.((i-1){text)e.' [(' end.
            sign=.starts*.(0<#following)*.-.following-:,' '
            if. sign do. kind=.'sign' else. kind=.'symbol' end.
            result=.result,<(<kind),(<,'-'),(<x),<''
            i=.i+1
        elseif. c e.'<>' do.
            spelling=.,c
            if. (<c,following)e.('<=';'<>';'>=') do. spelling=.c,following end.
            result=.result,<(<'symbol'),(<spelling),(<x),<''
            i=.i+#spelling
        elseif. c e.delimiters do.
            result=.result,<(<'symbol'),(<,c),(<x),<''
            i=.i+1
        else.
            start=.i
            while. i<#text do. if. (i{text)e.delimiters do. break. end.
                i=.i+1 end.
            result=.result,<x classify (i-start){.start}.text
        end.
    end.
    result
)
isWord =: 4 : '((''word''-:0{::y)*.x-:1{::y)'
extract =: 3 : 0
    ProcNames=:ProcParams=:ProcTokens=:ProcBodies=:0$a:
    ProcLines=:i.0
    TopTokens=:0$a:
    current=._1
    for_record. y do.
        'line text'=.>record
        tokens=.line tokenize text
        if. 0=#tokens do. continue. end.
        first=.0{::tokens
        if. 'TO'isWord first do.
            if. current>:0 do. line fail 'TO inside definition of ',current{::ProcNames end.
            if. (#tokens)<2 do. line fail 'bad procedure header' end.
            if. -.'word'-:0{::1{::tokens do. line fail 'bad procedure header' end.
            name=.1{::1{::tokens
            if. (<name)e.Primitives do. line fail name,' is a primitive' end.
            if. (<name)e.ProcNames do. line fail name,' is already defined' end.
            parameters=.0$a:
            for_token. 2}.tokens do.
                token=.>token
                if. -.'variable'-:0{::token do. line fail 'bad procedure header' end.
                value=.3{::token
                if. (<value)e.parameters do. line fail 'duplicate input ',1{::token end.
                parameters=.parameters,<value
            end.
            current=.#ProcNames
            ProcNames=:ProcNames,<name
            ProcParams=:ProcParams,<parameters
            ProcLines=:ProcLines,line
            ProcTokens=:ProcTokens,<0$a:
            ProcBodies=:ProcBodies,<0$a:
        elseif. ((#tokens)=1)*.'END'isWord first do.
            if. current<0 do. line fail 'END without TO' end.
            current=._1
        elseif. current>:0 do. ProcTokens=:(<(current{::ProcTokens),tokens)current}ProcTokens
        else. TopTokens=:TopTokens,tokens end.
    end.
    if. current>:0 do. (current{ProcLines)fail 'missing END for ',current{::ProcNames end.
)
peek =: 3 : 'if. Position<#PTokens do. Position{::PTokens else. i.0 end.'
advance =: 3 : 0
    result=.Position{::PTokens
    Position=:Position+1
    result
)
nextIs =: 3 : 0
    token=.peek''
    if. 0=#token do. 0 return. end.
    (-.'sign'-:0{::token)*.(<,1{::token)e.,&.>y
)
unknown =: 3 : '((''word''-:0{::y)*.(-.(<1{::y)e.Primitives)*.-.(<1{::y)e.ProcNames)'
inputToken =: 3 : 0
    token=.peek''
    missing=.0=#token
    if. -.missing do. missing=.(<,1{::token)e.,&.>(']';')') end.
    if. missing do. (2{::y)fail 'not enough inputs to ',1{::y end.
    if. unknown token do. (2{::token)fail 'I don',SQ,'t know how to ',1{::token end.
    token
)
parseSequence =: 3 : 0
    commands=.0$a:
    while. Position<#PTokens do.
        token=.peek''
        if. (,']')-:,1{::token do. (2{::token)fail 'unexpected ]' end.
        commands=.commands,<parseCommand''
    end.
    (<'list'),(<''),(<''),(<0),<commands
)
parseList =: 3 : 0
    opening=.advance''
    commands=.0$a:
    while. -.nextIs ,<']' do.
        if. Position=#PTokens do. (2{::opening)fail 'missing ]' end.
        commands=.commands,<parseCommand''
    end.
    advance''
    (<'list'),(<''),(<''),(<2{::opening),<commands
)
parseInput =: 4 : 0
    token=.inputToken x
    if. (y-:'L')*.(,'[')-:,1{::token do. parseList'' return. end.
    if. ((<y)e.('Q';'P'))*.'quoted'-:0{::token do.
        advance''
        (<'quoted'),(<3{::token),(<1{::token),(<2{::token),<0$a: return.
    end.
    if. (<y)e.('E';'P') do. 0 parseExpression x return. end.
    rejection (<2{::token),(<1{::x),<1{::token
)
parseCall =: 4 : 0
    inputs=.0$a:
    for_i. i.y do. inputs=.inputs,<0 parseExpression x end.
    (<'call'),(<1{::x),(<1{::x),(<2{::x),<inputs
)
parseCommand =: 3 : 0
    token=.advance''
    'kind spelling line value'=.token
    if. ((,spelling)-:,'(')*.nextIs words 'PRINT PR' do.
        word=.advance''
        inputs=.0$a:
        while. -.nextIs ,<')' do.
            if. (Position=#PTokens)+.nextIs ,<']' do. line fail 'missing )' end.
            inputs=.inputs,<word parseInput 'P'
        end.
        advance''
        (<'call'),(<'PRINT'),(<1{::word),(<line),<inputs return.
    end.
    if. kind-:'word' do.
        name=.canonical spelling
        if. (<name)e.words 'TO END' do. line fail 'misplaced ',name end.
        i=.CommandNames i.<name
        if. i<#CommandNames do.
            if. (-.InProcedure)*.(<name)e.words 'STOP OUTPUT LOCAL LOCALMAKE' do. line fail 'can only use ',spelling,' inside a procedure' end.
            inputs=.0$a:
            for_k. i{::CommandSigs do. inputs=.inputs,<token parseInput k end.
            if. (<name)e.words 'TRACE UNTRACE' do.
                quoted=.0{::inputs
                if. -.(<1{::quoted)e.ProcNames do. (3{::quoted)fail 'I don',SQ,'t know how to ',1{::quoted end.
            end.
            (<'call'),(<name),(<spelling),(<line),<inputs return.
        end.
        i=.ProcNames i.<name
        if. i<#ProcNames do. token parseCall #i{::ProcParams return. end.
        if. unknown token do. line fail 'I don',SQ,'t know how to ',name end.
    end.
    line fail 'you don',SQ,'t say what to do with ',spelling
)
parseExpression =: 4 : 0
    if. x=3 do. parseTerm y return. end.
    left=.(x+1)parseExpression y
    if. x=0 do. operators=.'=';'<>';'<' ;'>' ;'<=';'>='
    elseif. x=1 do. operators=.'+';'-'
    else. operators=.'*';'/';'MOD' end.
    while. nextIs operators do.
        op=.advance''
        right=.(x+1)parseExpression op
        children=.(<left),<right
        left=.(<'binary'),(<1{::op),(<1{::op),(<2{::op),<children
    end.
    left
)
parseTerm =: 3 : 0
    token=.inputToken y
    advance''
    'kind spelling line value'=.token
    if. kind-:'number' do. (<'number'),(<value),(<spelling),(<line),<0$a: return. end.
    if. kind-:'variable' do. (<'variable'),(<value),(<spelling),(<line),<0$a: return. end.
    if. (,spelling)-:,'-' do.
        operand=.parseTerm token
        (<'neg'),(<''),(<spelling),(<line),<,<operand return.
    end.
    if. (,spelling)-:,'(' do.
        result=.0 parseExpression token
        if. -.nextIs ,<')' do. line fail 'missing )' end.
        advance''
        result return.
    end.
    i=.FunctionNames i.<spelling
    if. i<#FunctionNames do. token parseCall i{FunctionArities return. end.
    i=.ProcNames i.<spelling
    if. i<#ProcNames do. token parseCall #i{::ProcParams return. end.
    rejection (<line),(<1{::y),<spelling
)
bind =: 4 : 0
    'name value'=.y
    'names values'=.x{::EnvBindings
    i=.names i.<name
    if. i=#names do. names=.names,<name
        values=.values,value
    else. values=.value i}values end.
    EnvBindings=:(<(<names),<values)x}EnvBindings
)
lookup =: 3 : 0
    name=.1{::y
    for_i. |.i.#EnvBindings do.
        'names values'=.i{::EnvBindings
        at=.names i.<name
        if. at<#names do. at{values return. end.
    end.
    (3{::y)fail name,' has no value'
)
makeVariable =: 3 : 0
    name=.0{::y
    for_i. |.1+i.<:#EnvBindings do.
        names=.0{::i{::EnvBindings
        if. (<name)e.names do. i bind y return. end.
    end.
    0 bind y
)
callProcedure =: 3 : 0
    name=.1{::y
    index=.ProcNames i.<name
    arguments=.4{::y
    values=.i.0
    for_arg. arguments do. values=.values,evaluate >arg end.
    depth=.<:#EnvNames
    if. depth>:100 do. (3{::y)fail 'recursion too deep' end.
    traced=.(<name)e.Traced
    indent=.(2*depth)#' '
    if. traced do. say indent,'( ',(' 'join (<name),num&.>values),' )' end.
    EnvNames=:EnvNames,<name
    EnvBindings=:EnvBindings,< (index{ProcParams),<values
    EnvTests=:EnvTests,_1
    signal=.runList index{::ProcBodies
    EnvNames=:}:EnvNames
    EnvBindings=:}:EnvBindings
    EnvTests=:}:EnvTests
    if. traced do.
        if. 2={.signal do. ending=.' outputs ',num 1{signal else. ending=.' stops' end.
        say indent,name,ending
    end.
    (2={.signal),1{signal
)
evaluate =: 3 : 0
    'kind name spelling line inputs'=.y
    if. kind-:'number' do. name return. end.
    if. kind-:'variable' do. lookup y return. end.
    if. kind-:'neg' do. -evaluate 0{::inputs return. end.
    if. kind-:'binary' do.
        if. 1=#name do. name=.{.name end.
        a=.evaluate 0{::inputs
        b=.evaluate 1{::inputs
        if. (<name)e.('/';'MOD') do.
            if. b=0 do. rejection (<line),(<name),<'0' end.
            q=.<.(|a)%|b
            if. (a<0)~:b<0 do. q=.-q end.
            if. name-:'/' do. q else. a-b*q end. return.
        end.
        select. name
        case. '+' do. a+b
        case. '-' do. a-b
        case. '*' do. a*b
        case. '=' do. a=b
        case. '<>' do. a~:b
        case. '<' do. a<b
        case. '>' do. a>b
        case. '<=' do. a<:b
        case. '>=' do. a>:b
        end.
        return.
    end.
    if. (<name)e.ProcNames do.
        'has value'=.callProcedure y
        if. -.has do. line fail name,' did not output' end.
        value return.
    end.
    args=.i.0
    for_arg. inputs do. args=.args,evaluate >arg end.
    select. name
    case. 'XCOR' do. TurtleX
    case. 'YCOR' do. TurtleY
    case. 'HEADING' do. Heading
    case. 'REPCOUNT' do.
        if. 0=#Repcounts do. line fail 'REPCOUNT outside REPEAT' end.
        {:Repcounts
    case. 'RANDOM' do.
        n=.0{args
        if. n<1 do. rejection (<line),(<spelling),<num n end.
        RandomState=:2147483647|48271*RandomState
        n|RandomState
    case. 'ABS' do. |0{args
    case. 'NOT' do. 0=0{args
    case. 'AND' do. *./0~:args
    case. 'OR' do. +./0~:args
    case. 'MAX' do. >./args
    case. 'MIN' do. <./args
    end.
)
printItem =: 3 : 'if. ''quoted''-:0{::y do. 1{::y else. num evaluate y end.'
cellIndex =: 3 : 0
    'x y0'=.y
    (2001*(y0+1000))+x+1000
)
applyPen =: 3 : 0
    index=.cellIndex y
    if. Pen-:'DOWN' do. Canvas=:PenChar index}Canvas
    elseif. Pen-:'ERASE' do. Canvas=:NUL index}Canvas end.
)
forward =: 3 : 0
    'dx dy'=.(<.Heading%45){Directions
    steps=.y
    if. steps<0 do. dx=.-dx
        dy=.-dy
        steps=.-steps end.
    applyPen TurtleX,TurtleY
    for_i. i.steps do. TurtleX=:TurtleX+dx
        TurtleY=:TurtleY+dy
        applyPen TurtleX,TurtleY end.
)
moveTo =: 3 : 0
    'x y0'=.y
    dx=.x-TurtleX
    dy=.y0-TurtleY
    s=.(|dx)>.|dy
    if. s=0 do. applyPen TurtleX,TurtleY
    else.
        for_i. i.s+1 do.
            a=.TurtleX+<.((2*i*dx)+s)%2*s
            b=.TurtleY+<.((2*i*dy)+s)%2*s
            applyPen a,b
        end.
    end.
    TurtleX=:x
    TurtleY=:y0
)
canvasBounds =: 3 : 0
    xs=.(2001|y)-1000
    ys=.(<.y%2001)-1000
    (<./xs),(<./ys),(>./xs),>./ys
)
fillCanvas =: 3 : 0
    marked=.I.Canvas~:NUL
    start=.cellIndex TurtleX,TurtleY
    if. (0=#marked)+.NUL~:start{Canvas do. return. end.
    'x y0 u v'=.canvasBounds marked
    if. (TurtleX<x)+.(TurtleX>u)+.(TurtleY<y0)+.TurtleY>v do. return. end.
    Canvas=:PenChar start}Canvas
    pending=.,:TurtleX,TurtleY
    while. #pending do.
        'a b'=.{:pending
        pending=.}:pending
        neighbors=.((a-1),b),((a+1),b),:(a,b-1)
        neighbors=.neighbors,a,b+1
        for_next. neighbors do.
            'p q'=.next
            if. (x<:p)*.(p<:u)*.(y0<:q)*.q<:v do.
                index=.cellIndex p,q
                if. NUL=index{Canvas do. Canvas=:PenChar index}Canvas
                    pending=.pending,p,q end.
            end.
        end.
    end.
)
writeCanvas =: 3 : 0
    marked=.I.Canvas~:NUL
    if. 0=#marked do. say 'CANVAS 0 0 0' return. end.
    'x y0 u v'=.canvasBounds marked
    say 'CANVAS ',(num 1+u-x),' ',(num 1+v-y0),' ',num #marked
    for_row. |.y0+i.1+v-y0 do.
        start=.cellIndex x,row
        text=.(1+u-x){.start}.Canvas
        text=.' '(I.text=NUL)}text
        while. #text do. if. ' '~:{:text do. break. end.
            text=.}:text end.
        say text
    end.
)
runList =: 3 : 0
    for_command. 4{::y do.
        signal=.execute >command
        if. 0~:{.signal do. signal return. end.
    end.
    0 0
)
execute =: 3 : 0
    'kind name spelling line inputs'=.y
    if. (<name)e.ProcNames do.
        'has value'=.callProcedure y
        if. has do. line fail 'you don',SQ,'t say what to do with ',num value end.
        0 0 return.
    end.
    select. name
    case. 'FD';'BK' do.
        n=.evaluate 0{::inputs
        if. name-:'BK' do. n=.-n end.
        forward n
    case. 'RT';'LT';'SETH' do.
        angle=.evaluate 0{::inputs
        if. 0~:45|angle do. rejection (<line),(<spelling),<num angle end.
        if. name-:'SETH' do. Heading=:360|angle
        elseif. name-:'RT' do. Heading=:360|Heading+angle
        else. Heading=:360|Heading-angle end.
    case. 'PU';'PD';'PE' do.
        Pen=:('UP';'DOWN';'ERASE'){::~('PU';'PD';'PE')i.<name
    case. 'SETPEN' do.
        n=.evaluate 0{::inputs
        if. (n<33)+.n>126 do. rejection (<line),(<spelling),<num n end.
        PenChar=:n{a.
    case. 'SETXY' do.
        x=.evaluate 0{::inputs
        y0=.evaluate 1{::inputs
        moveTo x,y0
    case. 'SETX' do. x=.evaluate 0{::inputs
        moveTo x,TurtleY
    case. 'SETY' do. y0=.evaluate 0{::inputs
        moveTo TurtleX,y0
    case. 'HOME' do. moveTo 0 0
        Heading=:0
    case. 'CS';'CLEAN' do.
        Canvas=:(#Canvas)$NUL
        if. name-:'CS' do. TurtleX=:TurtleY=:Heading=:0 end.
    case. 'FILL' do. fillCanvas''
    case. 'LABEL' do.
        text=.printItem 0{::inputs
        'dx dy'=.(<.Heading%45){Directions
        for_i. i.#text do.
            index=.cellIndex (TurtleX+i*dx),TurtleY+i*dy
            Canvas=:(i{text)index}Canvas
        end.
    case. 'SNAPSHOT' do. writeCanvas''
    case. 'REPEAT' do.
        n=.evaluate 0{::inputs
        if. 0=#4{::1{::inputs do. 0 0 return. end.
        k=.1
        while. k<:n do.
            Repcounts=:Repcounts,k
            try. signal=.runList 1{::inputs
            catcht. Repcounts=:}:Repcounts
                throw. end.
            Repcounts=:}:Repcounts
            if. 0~:{.signal do. signal return. end.
            k=.k+1
        end.
    case. 'FOR' do.
        variable=.1{::0{::inputs
        first=.evaluate 1{::inputs
        last=.evaluate 2{::inputs
        if. 0=#4{::3{::inputs do. makeVariable (<variable),<last
            0 0 return. end.
        if. first<:last do. step=.1 else. step=._1 end.
        value=.first
        while. 1 do.
            makeVariable (<variable),<value
            signal=.runList 3{::inputs
            if. 0~:{.signal do. signal return. end.
            if. value=last do. break. end.
            value=.value+step
        end.
    case. 'WHILE' do.
        while. 0~:evaluate 0{::inputs do.
            signal=.runList 1{::inputs
            if. 0~:{.signal do. signal return. end.
        end.
    case. 'IF' do.
        if. 0~:evaluate 0{::inputs do. runList 1{::inputs return. end.
    case. 'IFELSE' do.
        condition=.evaluate 0{::inputs
        if. condition do. runList 1{::inputs else. runList 2{::inputs end. return.
    case. 'TEST' do.
        value=.evaluate 0{::inputs
        EnvTests=:(value~:0)(<:#EnvTests)}EnvTests
    case. 'IFTRUE';'IFFALSE' do.
        test=.{:EnvTests
        if. test<0 do. line fail spelling,' without TEST' end.
        if. test=(name-:'IFTRUE') do. runList 0{::inputs return. end.
    case. 'STOP' do. 1 0 return.
    case. 'OUTPUT' do. 2,evaluate 0{::inputs return.
    case. 'MAKE';'LOCALMAKE';'LOCAL' do.
        variable=.1{::0{::inputs
        if. name-:'LOCAL' do. value=.0 else. value=.evaluate 1{::inputs end.
        binding=.(<variable),<value
        if. name-:'MAKE' do. makeVariable binding else. (<:#EnvBindings)bind binding end.
    case. 'TRACE' do. Traced=:~.Traced,<1{::0{::inputs
    case. 'UNTRACE' do. Traced=:Traced-.<1{::0{::inputs
    case. 'SEED' do.
        n=.evaluate 0{::inputs
        if. n<1 do. rejection (<line),(<spelling),<num n end.
        RandomState=:n
    case. 'PRINT' do.
        texts=.0$a:
        for_item. inputs do. texts=.texts,<printItem >item end.
        say ' 'join texts
    end.
    0 0
)
runProgram =: 3 : 0
    'name source'=.y
    say 'PROGRAM ',name
    try.
        extract source
        for_i. i.#ProcNames do.
            PTokens=:i{::ProcTokens
            Position=:0
            InProcedure=:1
            body=.parseSequence''
            ProcBodies=:(<body)i}ProcBodies
        end.
        PTokens=:TopTokens
        Position=:0
        InProcedure=:0
        top=.parseSequence''
    catcht.
        say 'ERROR line ',(num ErrorLine),': ',Reason
        return.
    end.
    TurtleX=:TurtleY=:Heading=:0
    Pen=:'DOWN'
    PenChar=:'*'
    NB. The stated coordinate range is -1000..1000 on both axes.
    Canvas=:4004001$NUL
    EnvNames=:,<''
    EnvBindings=:,<(<0$a:),<i.0
    EnvTests=:,_1
    Repcounts=:i.0
    Traced=:0$a:
    RandomState=:1
    try.
        runList top
        say 'TURTLE ',(num TurtleX),' ',(num TurtleY),' ',(num Heading),' ',Pen,' ',PenChar
        writeCanvas''
    catcht.
        say 'ERROR line ',(num ErrorLine),': ',Reason
        calls=.|.}.EnvNames
        at=.0
        while. at<#calls do.
            name=.at{::calls
            finish=.at+1
            while. finish<#calls do. if. -.name-:finish{::calls do. break. end.
                finish=.finish+1 end.
            count=.finish-at
            ending=.''
            if. count>1 do. ending=.' x',num count end.
            say '  in ',name,ending
            at=.finish
        end.
    end.
)
main =: 3 : 0
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    name=.''
    source=.0$a:
    for_i. i.#lines do.
        line=.i{::lines
        if. line-:'#EOF' do. runProgram (<name),<source break. end.
        if. '#PROGRAM '-:(9<.#line){.line do.
            if. #name do. runProgram (<name),<source end.
            name=.9}.line
            source=.0$a:
        else. source=.source,<(<i+1),<line end.
    end.
)
main''
