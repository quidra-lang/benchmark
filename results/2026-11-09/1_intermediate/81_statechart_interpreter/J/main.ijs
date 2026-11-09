LF =: 10{a.
DQ =: 34{a.
num =: 3 : ',''0'' 8!:2 y'
say =: 3 : '1!:2&2 y,LF'
words =: 3 : '(<;._1 '' '',y)-.<'''''
join =: 4 : '(#x)}.;(<x),&.>y'
cutOnce =: 4 : 0
    at=.x E.y
    if. +./at do. at=.{.I.at
        (<at{.y),<(at+#x)}.y
    else. (<y),<'' end.
)
exprPeek =: 3 : 'if. ExprPosition<#ExprTokens do. ExprPosition{::ExprTokens else. '''' end.'
exprTake =: 3 : 0
    result=.ExprPosition{::ExprTokens
    ExprPosition=:ExprPosition+1
    result
)
readExpression =: 3 : 0
    ExprTokens=:0$a:
    position=.0
    while. position<#y do.
        c=.position{y
        if. c=' ' do. position=.position+1 continue. end.
        start=.position
        if. c e.'0123456789' do.
            while. position<#y do.
                if. -. (position{y)e.'0123456789' do. break. end.
                position=.position+1
            end.
        elseif. c e.'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_' do.
            while. position<#y do.
                if. -. (position{y)e.'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789' do. break. end.
                position=.position+1
            end.
        else.
            position=.position+1
            if. position<#y do.
                if. (<(2{.start}.y))e.words '|| && == != <= >=' do. position=.position+1 end.
            end.
        end.
        ExprTokens=:ExprTokens,<(position-start){.start}.y
    end.
    ExprPosition=:0
    readLevel 0
)
readLevel =: 3 : 0
    if. y=5 do. readUnary'' return. end.
    left=.readLevel y+1
    select. y
    case. 0 do. operators=.words '||'
    case. 1 do. operators=.words '&&'
    case. 2 do. operators=.words '== != < <= > >='
    case. 3 do. operators=.words '+ -'
    case. 4 do. operators=.words '* / %'
    end.
    while. (<exprPeek'')e.operators do.
        op=.exprTake''
        right=.readLevel y+1
        left=.(<'binary'),(<op),(<0),<(<left),<right
    end.
    left
)
readUnary =: 3 : 0
    token=.exprTake''
    if. (<token)e.words '! -' do.
        operand=.readUnary''
        (<'unary'),(<token),(<0),<,<operand return.
    end.
    if. token-:,'(' do. result=.readLevel 0
        exprTake''
        result return. end.
    if. ({.token)e.'0123456789' do. (<'number'),(<''),(<0".token),<0$a: return. end.
    if. token-:'in' do.
        exprTake''
        name=.exprTake''
        exprTake''
        (<'state'),(<name),(<0),<0$a: return.
    end.
    if. token-:'_data' do. kind=.'data' else. kind=.'variable' end.
    (<kind),(<token),(<0),<0$a:
)
readActions =: 3 : 0
    result=.0$a:
    if. 0=#y do. result return. end.
    rest=.y
    while. 1 do.
        'item tail'=.'; 'cutOnce rest
        'word body'=.' 'cutOnce item
        name=.text=.''
        delay=.0
        expr=.i.0
        select. word
        case. 'raise' do.
            kind=.'raise'
            'name more'=.' 'cutOnce body
            if. #more do. expr=.readExpression more end.
        case. 'send' do.
            kind=.'send'
            'name more'=.' 'cutOnce body
            'number more'=.' 'cutOnce more
            delay=.0".number
            if. #more do. expr=.readExpression more end.
        case. 'cancel' do. kind=.'cancel'
            name=.body
        case. 'log' do.
            kind=.'log'
            if. DQ={.body do.
                closing=.1+(}.body)i.DQ
                text=.(closing-1){.}.body
                more=.(closing+2)}.body
                if. #more do. expr=.readExpression more end.
            else. expr=.readExpression body end.
        case. do. kind=.'assign'
            name=.word
            expr=.readExpression 2}.body
        end.
        result=.result,<(<kind),(<name),(<delay),(<text),<expr
        if. 0=#tail do. break. end.
        rest=.tail
    end.
    result
)
readTransition =: 3 : 0
    'source rest'=.' 'cutOnce 3}.y
    'trigger rest'=.' 'cutOnce rest
    kind=.'event'
    delay=.0
    if. trigger-:'always' do. kind=.'always'
    elseif. trigger-:'after' do. kind=.'timer'
        'number rest'=.' 'cutOnce rest
        delay=.0".number end.
    guard=.i.0
    if. #rest do.
        if. '['={.rest do.
            closing=.rest i.']'
            guard=.readExpression (closing-1){.}.rest
            rest=.(closing+2)}.rest
        end.
    end.
    target=.''
    localtarget=.0
    if. ((3{.rest)-:'-> ')+.(3{.rest)-:'~> ' do.
        localtarget=.'~'={.rest
        'target rest'=.' 'cutOnce 3}.rest
    end.
    list=.0$a:
    if. (2{.rest)-:'/ ' do. list=.readActions 2}.rest end.
    (<source),(<kind),(<trigger),(<delay),(<guard),(<target),(<localtarget),<list
)
stateIndex =: 3 : 0
    at=.StateNames i.<y
    if. at=#StateNames do. _1 else. at end.
)
childStates =: 3 : '(y{::Children)#~-. (y{::Children)e.I.StateKinds e.<''history'''
isCompound =: 3 : '(y=0)+.((''state''-:y{::StateKinds)*.0<#childStates y)'
isParallel =: 3 : '(''parallel''-:y{::StateKinds)*.0<#childStates y'
isAtomic =: 3 : '(-.''history''-:y{::StateKinds)*.0=#childStates y'
descendant =: 4 : 0
    current=.y{Parents
    while. current>:0 do.
        if. current=x do. 1 return. end.
        current=.current{Parents
    end.
    0
)
initialState =: 3 : 0
    name=.y{::InitialNames
    if. #name do. stateIndex name else. {.childStates y end.
)
defaultState =: 3 : 0
    name=.y{::DefaultNames
    if. #name do. stateIndex name else. initialState y{Parents end.
)
checkExpression =: 3 : 0
    if. 0=#y do. '' return. end.
    'kind text value children'=.y
    if. kind-:'variable' do.
        if. -.(<text)e.VariableNames do. 'unknown variable ',text return. end.
    elseif. kind-:'state' do.
        if. (stateIndex text)<0 do. 'unknown state ',text return. end.
    end.
    for_child. children do. error=.checkExpression >child
        if. #error do. error return. end. end.
    ''
)
checkActions =: 3 : 0
    for_item. y do.
        'kind name delay text expr'=.>item
        if. kind-:'assign' do.
            if. -.(<name)e.VariableNames do. 'unknown variable ',name return. end.
        end.
        error=.checkExpression expr
        if. #error do. error return. end.
    end.
    ''
)
visit =: 3 : 0
    DocOrder=:DocOrder,y
    for_child. y{::Children do. visit child end.
)
buildChart =: 3 : 0
    'DefinitionLines DefinitionTexts'=:y
    Errors=:(#DefinitionTexts)#<''
    StateAt=:(#DefinitionTexts)$0
    StateNames=:,<''
    StateKinds=:,<'root'
    Parents=:,_1
    Depths=:,0
    Children=:,<i.0
    InitialNames=:DefaultNames=:,<''
    Deep=:,0
    EntryLists=:ExitLists=:ByState=:,<0$a:
    VariableNames=:0$a:
    InitialValues=:i.0
    Transitions=:0$a:
    for_row. i.#DefinitionTexts do.
        fields=.words row{::DefinitionTexts
        kind=.0{::fields
        error=.''
        if. (<kind)e.words 'state parallel final history' do.
            name=.1{::fields
            parentname=.init=.fallback=.''
            deep=.0
            if. kind-:'state' do.
                at=.2
                if. (#fields)>2 do.
                    if. -.'initial'-:2{::fields do. parentname=.2{::fields
                        at=.3 end.
                end.
                if. at<#fields do. init=.(at+1){::fields end.
            elseif. kind-:'parallel' do.
                if. (#fields)=3 do. parentname=.2{::fields end.
            else. parentname=.2{::fields
                if. kind-:'history' do. deep=.'deep'-:3{::fields
                    if. (#fields)=5 do. fallback=.4{::fields end. end.
            end.
            if. #parentname do. parent=.stateIndex parentname else. parent=.0 end.
            if. (stateIndex name)>:0 do. error=.'duplicate state ',name
            elseif. parent<0 do. error=.'unknown state ',parentname
            elseif. (<parent{::StateKinds)e.words 'final history' do. error=.parentname,' cannot have children'
            else.
                index=.#StateNames
                StateAt=:index row}StateAt
                StateNames=:StateNames,<name
                StateKinds=:StateKinds,<kind
                Parents=:Parents,parent
                Depths=:Depths,1+parent{Depths
                Children=:(<(parent{::Children),index)parent}Children
                Children=:Children,<i.0
                InitialNames=:InitialNames,<init
                DefaultNames=:DefaultNames,<fallback
                Deep=:Deep,deep
                EntryLists=:EntryLists,<0$a:
                ExitLists=:ExitLists,<0$a:
                ByState=:ByState,<i.0
            end.
        elseif. kind-:'var' do.
            name=.1{::fields
            if. (<name)e.VariableNames do. error=.'duplicate variable ',name
            else. VariableNames=:VariableNames,<name
                InitialValues=:InitialValues,0".2{::fields end.
        end.
        Errors=:(<error)row}Errors
    end.
    for_row. i.#DefinitionTexts do.
        if. #row{::Errors do. continue. end.
        text=.row{::DefinitionTexts
        fields=.words text
        kind=.0{::fields
        error=.''
        if. (<kind)e.words 'state final history' do.
            index=.row{StateAt
            name=.index{::StateNames
            if. (kind-:'state')*.(0<#index{::InitialNames) do.
                childname=.index{::InitialNames
                child=.stateIndex childname
                if. child<0 do. error=.'unknown state ',childname
                elseif. ((child{Parents)~:index)+.'history'-:child{::StateKinds do. error=.childname,' is not a child of ',name end.
            elseif. (<kind)e.words 'final history' do.
                parent=.index{Parents
                if. (-.'state'-:parent{::StateKinds)+.0=#childStates parent do. error=.name,' needs a compound parent'
                elseif. (kind-:'history')*.(0<#index{::DefaultNames) do.
                    targetname=.index{::DefaultNames
                    target=.stateIndex targetname
                    if. target<0 do. error=.'unknown state ',targetname
                    elseif. (-.parent descendant target)+.'history'-:target{::StateKinds do. error=.targetname,' is not a descendant of ',parent{::StateNames end.
                end.
            end.
        elseif. (<kind)e.words 'entry exit' do.
            name=.1{::fields
            index=.stateIndex name
            if. index<0 do. error=.'unknown state ',name
            elseif. 'history'-:index{::StateKinds do. error=.name,' cannot have actions'
            else.
                list=.readActions 1{::' / 'cutOnce text
                error=.checkActions list
                if. 0=#error do.
                    if. kind-:'entry' do. EntryLists=:(<(index{::EntryLists),<list)index}EntryLists
                    else. ExitLists=:(<(index{::ExitLists),<list)index}ExitLists end.
                end.
            end.
        elseif. kind-:'on' do.
            'name typ descriptors delay guard targetname localtarget list'=.readTransition text
            index=.stateIndex name
            if. index<0 do. error=.'unknown state ',name
            elseif. (<index{::StateKinds)e.words 'final history' do. error=.name,' cannot have transitions'
            else.
                error=.checkExpression guard
                target=._1
                if. #targetname do. target=.stateIndex targetname
                    if. (0=#error)*.target<0 do. error=.'unknown state ',targetname end. end.
                if. 0=#error do. error=.checkActions list end.
                if. 0=#error do.
                    descriptors=.<;._1 '|',descriptors
                    transition=.(<index),(<typ),(<descriptors),(<delay),(<guard),(<target),(<localtarget),<list
                    ByState=:(<(index{::ByState),#Transitions)index}ByState
                    Transitions=:Transitions,<transition
                end.
            end.
        end.
        Errors=:(<error)row}Errors
    end.
    DocOrder=:i.0
    for_child. 0{::Children do. visit child end.
)
evaluate =: 3 : 0
    'kind text value children'=.y
    select. kind
    case. 'number' do. value return.
    case. 'variable' do. (VariableNames i.<text){VariableValues return.
    case. 'data' do. DataValue return.
    case. 'state' do. (stateIndex text)e.Configuration return.
    end.
    a=.evaluate 0{::children
    if. kind-:'unary' do.
        if. text-:,'!' do. a=0 else. -a end. return.
    end.
    if. (text-:'&&')*.a=0 do. 0 return. end.
    if. (text-:'||')*.a~:0 do. 1 return. end.
    b=.evaluate 1{::children
    if. (<text)e.words '&& ||' do. b~:0 return. end.
    if. 1=#text do. text=.{.text end.
    if. (<,text)e.words '/ %' do.
        if. b=0 do. throw. end.
        q=.<.(|a)%|b
        if. (a<0)~:b<0 do. q=.-q end.
        if. text-:'/' do. q else. a-b*q end. return.
    end.
    select. text
    case. '+' do. a+b
    case. '-' do. a-b
    case. '*' do. a*b
    case. '==' do. a=b
    case. '!=' do. a~:b
    case. '<' do. a<b
    case. '<=' do. a<:b
    case. '>' do. a>b
    case. '>=' do. a>:b
    end.
)
errorEvent =: 3 : 'Queue=:Queue,<( <''error.execution''),<0'
reserve =: 3 : 0
    'delay transition event value'=.y
    Serial=:Serial+1
    Reservations=:Reservations,<(<Clock+delay),(<Serial),(<transition),(<event),<value
)
performActions =: 3 : 0
    for_item. y do.
        'kind name delay text expr'=.>item
        value=.0
        if. #expr do.
            try. value=.evaluate expr
            catcht. errorEvent'' return. end.
        end.
        select. kind
        case. 'assign' do. VariableValues=:value (VariableNames i.<name)}VariableValues
        case. 'raise' do. Queue=:Queue,<(<name),<value
        case. 'send' do. reserve (<delay),(<_1),(<name),<value
        case. 'cancel' do.
            kept=.0$a:
            for_booking. Reservations do.
                booking=.>booking
                if. ((2{::booking)>:0)+.-.name-:3{::booking do. kept=.kept,<booking end.
            end.
            Reservations=:kept
        case. 'log' do.
            if. #expr do. say text,num value else. say text end.
        end.
    end.
)
closeEntries =: 3 : 0
    result=.~.y
    changed=.1
    while. changed do.
        before=.#result
        for_id. DocOrder do.
            if. -.id e.result do. continue. end.
            children=.childStates id
            if. isParallel id do. result=.~.result,children
            elseif. isCompound id do.
                if. -. +./children e.result do. result=.~.result,initialState id end.
            end.
        end.
        changed=.before~:#result
    end.
    result
)
completeState =: 3 : 0
    children=.childStates y
    if. isCompound y do.
        for_child. children do.
            if. ('final'-:child{::StateKinds)*.child e.Configuration do. 1 return. end.
        end.
    elseif. isParallel y do.
        for_child. children do. if. -.completeState child do. 0 return. end. end.
        1 return.
    end.
    0
)
enterStates =: 3 : 0
    for_id. DocOrder do.
        if. -.id e.y do. continue. end.
        Configuration=:~.Configuration,id
        Entered=:((id{Entered)+1)id}Entered
        EntryTimes=:Clock id}EntryTimes
        for_t. id{::ByState do.
            branch=.t{::Transitions
            if. 'timer'-:1{::branch do. reserve (<3{::branch),(<t),(<''),<0 end.
        end.
        for_list. id{::EntryLists do. performActions >list end.
        if. 'final'-:id{::StateKinds do.
            parent=.id{Parents
            Queue=:Queue,<(< 'done.state.',parent{::StateNames),<0
            grandparent=.parent{Parents
            if. grandparent>:0 do.
                if. isParallel grandparent do.
                    complete=.1
                    for_child. childStates grandparent do. if. -.completeState child do. complete=.0 end. end.
                    if. complete do. Queue=:Queue,<(< 'done.state.',grandparent{::StateNames),<0 end.
                end.
            end.
        end.
    end.
)
effectiveTargets =: 3 : 0
    target=.5{::y{::Transitions
    if. target<0 do. i.0 return. end.
    if. -.'history'-:target{::StateKinds do. ,target return. end.
    if. target{HistoryRecorded do. target{::HistoryLists else. ,defaultState target end.
)
transitionScope =: 3 : 0
    branch=.y{::Transitions
    if. (5{::branch)<0 do. _1 return. end.
    source=.0{::branch
    targets=.effectiveTargets y
    encloses=.1
    for_target. targets do. if. -.source descendant target do. encloses=.0 end. end.
    if. (6{::branch)*.(isCompound source)*.encloses do. source return. end.
    current=.source{Parents
    while. current>:0 do.
        encloses=.1
        for_target. targets do. if. -.current descendant target do. encloses=.0 end. end.
        if. (isCompound current)*.encloses do. current return. end.
        current=.current{Parents
    end.
    _1
)
exitSet =: 3 : 0
    bound=.transitionScope y
    result=.i.0
    if. bound<0 do. result return. end.
    for_id. Configuration do. if. bound descendant id do. result=.result,id end. end.
    result
)
matchesTrigger =: 4 : 0
    'kind event timer'=.y
    branch=.x{::Transitions
    if. kind-:'always' do. 'always'-:1{::branch return. end.
    if. kind-:'timer' do. x=timer return. end.
    if. -.'event'-:1{::branch do. 0 return. end.
    name=.0{::event
    for_descriptor. 2{::branch do.
        descriptor=.>descriptor
        if. (descriptor-:,'*')+.descriptor-:name do. 1 return. end.
        prefix=.descriptor,'.'
        if. prefix-:(#prefix){.name do. 1 return. end.
    end.
    0
)
guardAccepts =: 3 : 0
    guard=.4{::y{::Transitions
    if. 0=#guard do. 1 return. end.
    try. 0~:evaluate guard
    catcht. errorEvent''
        0 end.
)
selectTransitions =: 3 : 0
    candidates=.i.0
    for_atomic. DocOrder do.
        if. (-.atomic e.Configuration)+.-.isAtomic atomic do. continue. end.
        current=.atomic
        found=._1
        while. (current~:0)*.found<0 do.
            for_t. current{::ByState do.
                if. t matchesTrigger y do.
                    if. guardAccepts t do. found=.t break. end.
                end.
            end.
            current=.current{Parents
        end.
        if. found>:0 do. candidates=.~.candidates,found end.
    end.
    kept=.exiting=.i.0
    for_t. candidates do.
        proposed=.exitSet t
        if. -. +./proposed e.exiting do. kept=.kept,t
            exiting=.~.exiting,proposed end.
    end.
    kept
)
stateNames =: 3 : 'if. 0=#y do. ''-'' else. '',''join y{StateNames end.'
timerName =: 3 : 0
    branch=.y{::Transitions
    'after(',(num 3{::branch),')@',(0{::branch){::StateNames
)
eventName =: 3 : 0
    'name value'=.y
    if. value=0 do. name else. name,'=',num value end.
)
microStep =: 4 : 0
    if. Within=1000 do. say 'LIVELOCK t=',num Clock
        Halted=:1 return. end.
    Within=:Within+1
    Micros=:Micros+1
    scopes=.transitionScope"0 x
    exiting=.i.0
    for_t. x do. exiting=.~.exiting,exitSet t end.
    for_id. DocOrder do.
        if. -.id e.exiting do. continue. end.
        for_h. id{::Children do.
            if. -.'history'-:h{::StateKinds do. continue. end.
            remembered=.i.0
            for_s. DocOrder do.
                if. -.s e.Configuration do. continue. end.
                if. h{Deep do. belongs=.(isAtomic s)*.id descendant s
                else. belongs=.(s{Parents)=id end.
                if. belongs do. remembered=.remembered,s end.
            end.
            HistoryRecorded=:(1)h}HistoryRecorded
            HistoryLists=:(<remembered)h}HistoryLists
        end.
    end.
    seeds=.i.0
    for_i. i.#x do.
        t=.i{x
        if. (5{::t{::Transitions)<0 do. continue. end.
        bound=.i{scopes
        for_target. effectiveTargets t do.
            seeds=.seeds,target
            current=.target{Parents
            while. current~:bound do. seeds=.seeds,current
                current=.current{Parents end.
        end.
    end.
    entering=.closeEntries seeds
    if. Trace do.
        sources=.i.0
        for_t. x do. sources=.sources,0{::t{::Transitions end.
        say '[t=',(num Clock),'] ',y,' (',(stateNames sources),'): exit ',(stateNames |.DocOrder#~DocOrder e.exiting),'; enter ',stateNames DocOrder#~DocOrder e.entering
    end.
    for_id. |.DocOrder do.
        if. -.id e.exiting do. continue. end.
        for_list. id{::ExitLists do. performActions >list end.
        Configuration=:Configuration-.id
        Dwell=:((id{Dwell)+Clock-id{EntryTimes)id}Dwell
        kept=.0$a:
        for_booking. Reservations do.
            booking=.>booking
            transition=.2{::booking
            remove=.0
            if. transition>:0 do. remove=.id=0{::transition{::Transitions end.
            if. -.remove do. kept=.kept,<booking end.
        end.
        Reservations=:kept
    end.
    for_t. x do.
        branch=.t{::Transitions
        performActions 7{::branch
        source=.0{::branch
        Taken=:((source{Taken)+1)source}Taken
    end.
    enterStates entering
)
macroStep =: 3 : 0
    'kind event timer'=.y
    Macros=:Macros+1
    Within=:0
    DataValue=:1{::event
    if. kind-:'start' do. enterStates closeEntries ,initialState 0
    else.
        selected=.selectTransitions y
        if. #selected do.
            if. kind-:'timer' do. display=.timerName timer else. display=.eventName event end.
            selected microStep display
        end.
    end.
    while. -.Halted do.
        DataValue=:0
        selected=.selectTransitions (<'always'),(<(<''),<0),<_1
        if. #selected do. selected microStep 'always' continue. end.
        if. 0=#Queue do. break. end.
        queued=.0{::Queue
        Queue=:}.Queue
        DataValue=:1{::queued
        selected=.selectTransitions (<'event'),(<queued),<_1
        if. #selected do. selected microStep eventName queued end.
    end.
)
warnUnreachable =: 3 : 0
    reached=.,initialState 0
    changed=.1
    while. changed do.
        before=.#reached
        for_id. DocOrder do.
            if. -.id e.reached do. continue. end.
            parent=.id{Parents
            if. parent>0 do. reached=.~.reached,parent end.
            if. isCompound id do. reached=.~.reached,initialState id end.
            if. isParallel id do. reached=.~.reached,childStates id end.
            for_t. id{::ByState do.
                target=.5{::t{::Transitions
                if. target>:0 do.
                    if. 'history'-:target{::StateKinds do. target=.defaultState target end.
                    reached=.~.reached,target
                end.
            end.
        end.
        changed=.before~:#reached
    end.
    for_id. DocOrder do.
        if. (-.'history'-:id{::StateKinds)*.-.id e.reached do. say 'warning: unreachable state ',id{::StateNames end.
    end.
)
reservationOrder =: 3 : 0
    keys=.0 2$0
    for_booking. Reservations do. booking=.>booking
        keys=.keys,(0{::booking),1{::booking end.
    /:keys
)
writeDump =: 3 : 0
    say 'dump t=',num Clock
    for_id. DocOrder do.
        if. id e.Configuration do. say ((2*id{Depths)#' '),id{::StateNames end.
    end.
    for_at. /:VariableNames do. say '  var ',(at{::VariableNames),' = ',num at{VariableValues end.
    for_id. DocOrder do.
        if. id{HistoryRecorded do. say '  history ',(id{::StateNames),' = ',stateNames id{::HistoryLists end.
    end.
    for_index. reservationOrder'' do.
        booking=.index{::Reservations
        'due creation transition event value'=.booking
        if. transition<0 do. say '  send ',(num due),' ',event,' ',num value
        else. say '  timer ',(num due),' ',timerName transition end.
    end.
)
scriptLine =: 3 : 0
    fields=.words y
    command=.0{::fields
    select. command
    case. 'event' do.
        value=.0
        if. (#fields)=3 do. value=.0".2{::fields end.
        event=.(<1{::fields),<value
        macroStep (<'event'),(<event),<_1
    case. 'tick' do.
        finish=.Clock+0".1{::fields
        while. (-.Halted)*.0<#Reservations do.
            index=.{.reservationOrder''
            booking=.index{::Reservations
            'due creation transition event value'=.booking
            if. due>finish do. break. end.
            Reservations=:(index{.Reservations),(index+1)}.Reservations
            Clock=:due
            if. transition<0 do. kind=.'event' else. kind=.'timer' end.
            macroStep (<kind),(<(<event),<value),<transition
        end.
        if. -.Halted do. Clock=:finish end.
    case. 'set' do.
        name=.1{::fields
        index=.VariableNames i.<name
        if. index<#VariableNames do. VariableValues=:(0".2{::fields)index}VariableValues
        else. say 'error: unknown variable ',name end.
    case. 'trace' do. Trace=:'on'-:1{::fields
    case. 'dump' do. writeDump''
    case. 'eval' do.
        text=.5}.y
        expr=.readExpression text
        error=.checkExpression expr
        if. #error do. say 'error: ',error
        else.
            DataValue=:0
            try. value=.evaluate expr
                say text,' -> ',num value
            catcht. say 'error: division by zero' end.
        end.
    end.
)
runChart =: 3 : 0
    'name definitions scripts'=.y
    say 'chart ',name
    buildChart definitions
    invalid=.0
    for_row. i.#Errors do.
        if. #row{::Errors do. invalid=.1
            say 'error line ',(num row{DefinitionLines),': ',row{::Errors end.
    end.
    if. invalid do. return. end.
    warnUnreachable''
    Configuration=:i.0
    VariableValues=:InitialValues
    DataValue=:Clock=:Serial=:Trace=:Halted=:Macros=:Micros=:Within=:0
    Queue=:Reservations=:0$a:
    HistoryRecorded=:(#StateNames)$0
    HistoryLists=:(#StateNames)#<i.0
    Entered=:Taken=:Dwell=:EntryTimes=:(#StateNames)$0
    macroStep (<'start'),(<(<''),<0),<_1
    for_text. scripts do. if. Halted do. break. end.
        scriptLine >text end.
    say 'end t=',(num Clock),' macrosteps=',(num Macros),' microsteps=',num Micros
    for_id. DocOrder do.
        if. 'history'-:id{::StateKinds do. continue. end.
        total=.id{Dwell
        if. id e.Configuration do. total=.total+Clock-id{EntryTimes end.
        say '  ',(id{::StateNames),' entered=',(num id{Entered),' taken=',(num id{Taken),' time=',num total
    end.
)
main =: 3 : 0
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    position=.1
    for_chart. i.0".0{::lines do.
        name=.6}.position{::lines
        position=.position+1
        numbers=.i.0
        definitions=.scripts=.0$a:
        while. -.'RUN'-:position{::lines do.
            numbers=.numbers,position+1
            definitions=.definitions,<position{::lines
            position=.position+1
        end.
        position=.position+1
        while. -.'END'-:position{::lines do.
            scripts=.scripts,<position{::lines
            position=.position+1
        end.
        position=.position+1
        defs=.(<numbers),<definitions
        runChart (<name),(<defs),<scripts
    end.
)
main''
