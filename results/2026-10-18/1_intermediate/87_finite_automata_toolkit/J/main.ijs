LF =: 10{a.
num =: 3 : ',''0'' 8!:2 y'
say =: 3 : '1!:2&2 y,LF'
words =: 3 : '(<;._1 '' '',y)-.<'''''
split =: 4 : '<;._1 x,y'
join =: 4 : '(#x)}.;(<x),&.>y'
fail =: 3 : 0
    Reason=:y
    throw.
)
series =: 4 : 0
    result=.0$a:
    for_i. i.y do. result=.result,<x,num i end.
    result
)
wordText =: 3 : 0
    if. #y do. y else. ,'e' end.
)
ordered =: 3 : '/:~~.y'
kind =: 3 : '0{::y'
states =: 3 : '1{::y'
alphabet =: 3 : '2{::y'
start =: 3 : '3{::y'
accepting =: 3 : '4{::y'
cells =: 3 : '5{::y'
cell =: 4 : '> (<y){cells x'
delta =: 4 : '{.x cell y'
accepts =: 4 : '+./y e.accepting x'
mkMachine =: 3 : 0
    'tag names symbols initial finals edges'=.y
    table=.((#names),>:#symbols)$<i.0
    for_edge. edges do.
        'source column target'=.edge
        old=.>(<source,column){table
        table=.(<ordered old,target)(<source,column)}table
    end.
    (<tag),(<names),(<symbols),(<initial),(<ordered finals),<table
)
summary =: 4 : 0
    (kind x),' ',y,': alphabet=',(alphabet x),' states=',(num #states x),' accepting=',(num #accepting x),' transitions=',num +/#&>,cells x
)
setText =: 4 : '''{'',('',''join (ordered y){states x),''}'''
listText =: 4 : 0
    if. #y do. ','join (ordered y){states x else. 'none' end.
)
closure =: 4 : 0
    seen=.(#states x)$0
    pending=.ordered y
    seen=.(1)pending}seen
    cursor=.0
    while. cursor<#pending do.
        current=.cursor{pending
        cursor=.>:cursor
        for_target. x cell current,#alphabet x do.
            if. -.target{seen do.
                seen=.(1)target}seen
                pending=.pending,target
            end.
        end.
    end.
    I.seen
)
destination =: 4 : 0
    'sources column'=.y
    targets=.i.0
    for_source. sources do. targets=.targets,x cell source,column end.
    x closure targets
)
allEdges =: 4 : 0
    result=.0 3$0
    for_source. i.#states y do.
        for_column. i.>:#alphabet y do.
            for_target. y cell source,column do.
                result=.result,(source+x),column,target+x
            end.
        end.
    end.
    result
)
reachable =: 3 : 0
    seen=.(#states y)$0
    pending=.,start y
    seen=.(1)pending}seen
    cursor=.0
    while. cursor<#pending do.
        current=.cursor{pending
        cursor=.>:cursor
        for_column. i.>:#alphabet y do.
            for_target. y cell current,column do.
                if. -.target{seen do.
                    seen=.(1)target}seen
                    pending=.pending,target
                end.
            end.
        end.
    end.
    I.seen
)
live =: 3 : 0
    back=.(#states y)#<i.0
    for_edge. 0 allEdges y do.
        'source column target'=.edge
        back=.(<(target{::back),source)target}back
    end.
    seen=.(#states y)$0
    pending=.accepting y
    seen=.(1)pending}seen
    cursor=.0
    while. cursor<#pending do.
        current=.cursor{pending
        cursor=.>:cursor
        for_source. current{::back do.
            if. -.source{seen do.
                seen=.(1)source}seen
                pending=.pending,source
            end.
        end.
    end.
    I.seen
)
epsilonCount =: 3 : 0
    result=.0
    for_item. i.#states y do. result=.result+#y cell item,#alphabet y end.
    result
)
determinize =: 3 : 0
    subsets=.,<y closure ,start y
    edges=.0 3$0
    finals=.i.0
    cursor=.0
    while. cursor<#subsets do.
        current=.cursor{::subsets
        if. y accepts current do. finals=.finals,cursor end.
        for_column. i.#alphabet y do.
            target=.y destination (<current),<column
            at=.subsets i.<target
            if. at=#subsets do. subsets=.subsets,<target end.
            edges=.edges,cursor,column,at
        end.
        cursor=.>:cursor
    end.
    names=.'D'series #subsets
    details=.0$a:
    for_i. i.#subsets do. details=.details,<'  ',(i{::names),' = ',y setText i{::subsets end.
    machine=.mkMachine (<'DFA'),(<names),(<alphabet y),(<0),(<finals),<edges
    (<machine),<details
)
minimize =: 3 : 0
    reach=.reachable y
    positive=.reach#~reach e.accepting y
    negative=.reach-.accepting y
    blocks=.0$a:
    for_item. reach do.
        group=.positive
        if. -.item e.positive do. group=.negative end.
        if. -.(<group)e.blocks do. blocks=.blocks,<group end.
    end.
    details=.(<'  unreachable: ',y listText (i.#states y)-.reach),<'  round 0: ',' 'join (y&setText)&.>blocks
    round=.1
    membership=.(#states y)$0
    while. 1 do.
        for_i. i.#blocks do. membership=.i(i{::blocks)}membership end.
        signatures=.refined=.0$a:
        for_item. reach do.
            signature=.,item{membership
            for_column. i.#alphabet y do. signature=.signature,membership{~y delta item,column end.
            at=.signatures i.<signature
            if. at=#signatures do.
                signatures=.signatures,<signature
                refined=.refined,<i.0
            end.
            refined=.(<(at{::refined),item)at}refined
        end.
        if. (#refined)=#blocks do. break. end.
        blocks=.refined
        details=.details,<'  round ',(num round),': ',' 'join (y&setText)&.>blocks
        round=.>:round
    end.
    order=.,(start y){membership
    renamed=.(#blocks)$#blocks
    renamed=.(0)order}renamed
    edges=.0 3$0
    finals=.i.0
    cursor=.0
    while. cursor<#order do.
        old=.cursor{order
        representative=.{.old{::blocks
        if. y accepts ,representative do. finals=.finals,cursor end.
        details=.details,<'  M',(num cursor),' = ',y setText old{::blocks
        for_column. i.#alphabet y do.
            target=.membership{~y delta representative,column
            if. (#blocks)=target{renamed do.
                renamed=.(#order)target}renamed
                order=.order,target
            end.
            edges=.edges,cursor,column,target{renamed
        end.
        cursor=.>:cursor
    end.
    machine=.mkMachine (<'DFA'),(<'M'series #order),(<alphabet y),(<0),(<finals),<edges
    (<machine),<details
)
nextChar =: 3 : 0
    if. RCursor=#RText do. '' else. RCursor{RText end.
)
rproblem =: 3 : 'fail ''syntax error at '',num >:RCursor'
rnode =: 3 : 0
    result=.#RNodes
    RNodes=:RNodes,<y
    result
)
ratom =: 3 : 0
    character=.nextChar''
    if. #character do.
        if. character e.'abcdefghijklmnopqrstuvwxyz0123456789' do.
            RCursor=:>:RCursor
            rnode (<0),(<character),<i.0 return.
        end.
    end.
    if. -.character-:'(' do. rproblem'' end.
    RCursor=:>:RCursor
    result=.ralternate''
    if. -.(nextChar'')-:')' do. rproblem'' end.
    RCursor=:>:RCursor
    result
)
rfactor =: 3 : 0
    result=.ratom''
    while. 1 do.
        character=.nextChar''
        if. 0=#character do. break. end.
        if. -.character e.'*+?' do. break. end.
        RCursor=:>:RCursor
        result=.rnode (<3+'*+?'i.character),(<''),<,result
    end.
    result
)
rconcat =: 3 : 0
    parts=.,rfactor''
    while. 1 do.
        character=.nextChar''
        if. 0=#character do. break. end.
        if. -.character e.'abcdefghijklmnopqrstuvwxyz0123456789(' do. break. end.
        parts=.parts,rfactor''
    end.
    if. 1=#parts do. {.parts else. rnode (<1),(<''),<parts end.
)
ralternate =: 3 : 0
    parts=.,rconcat''
    while. (nextChar'')-:'|' do.
        RCursor=:>:RCursor
        parts=.parts,rconcat''
    end.
    if. 1=#parts do. {.parts else. rnode (<2),(<''),<parts end.
)
tallocate =: 3 : 0
    result=.TCount
    TCount=:>:TCount
    result
)
tedge =: 3 : 'TEdges=:TEdges,y'
tbuild =: 3 : 0
    'operation symbol children'=.y{::RNodes
    epsilon=.#TSymbols
    if. operation=0 do.
        entry=.tallocate''
        exit=.tallocate''
        column=.epsilon
        if. symbol~:'e' do. column=.TSymbols i.symbol end.
        tedge entry,column,exit
        entry,exit return.
    end.
    if. operation=1 do.
        first=.tbuild {.children
        last=.{:first
        for_child. }.children do.
            part=.tbuild child
            tedge last,epsilon,{.part
            last=.{:part
        end.
        ({.first),last return.
    end.
    entry=.tallocate''
    if. operation=2 do.
        parts=.0 2$0
        for_child. children do. parts=.parts,tbuild child end.
        exit=.tallocate''
        for_part. parts do.
            tedge entry,epsilon,{.part
            tedge ({:part),epsilon,exit
        end.
        entry,exit return.
    end.
    inner=.tbuild {.children
    exit=.tallocate''
    tedge entry,epsilon,{.inner
    tedge ({:inner),epsilon,exit
    if. operation~:5 do. tedge ({:inner),epsilon,{.inner end.
    if. operation~:4 do. tedge entry,epsilon,exit end.
    entry,exit
)
languageStatus =: 3 : 0
    useful=.(#states y)$0
    useful=.(1)(live y)}useful
    if. -.(start y){useful do. 1 0 return. end.
    degree=.(#states y)$0
    for_source. I.useful do.
        for_column. i.#alphabet y do.
            target=.y delta source,column
            if. target{useful do. degree=.(>:(target{degree))target}degree end.
        end.
    end.
    pending=.I.useful*.degree=0
    cursor=.0
    while. cursor<#pending do.
        source=.cursor{pending
        cursor=.>:cursor
        for_column. i.#alphabet y do.
            target=.y delta source,column
            if. target{useful do.
                degree=.(<:target{degree)target}degree
                if. 0=target{degree do. pending=.pending,target end.
            end.
        end.
    end.
    0,((#pending)~:+/useful)
)
nextCounts =: 4 : 0
    result=.(#states x)$0
    for_source. i.#states x do.
        for_column. i.#alphabet x do.
            target=.x delta source,column
            result=.((target{result)+source{y)target}result
        end.
    end.
    result
)
acceptedCount =: 4 : '+/(accepting x){y'
smallestWord =: 3 : 0
    seen=.(#states y)$0
    pending=.,start y
    labels=.,<''
    seen=.(1)pending}seen
    cursor=.0
    while. cursor<#pending do.
        current=.cursor{pending
        label=.cursor{::labels
        cursor=.>:cursor
        if. y accepts ,current do. <label return. end.
        for_column. i.#alphabet y do.
            target=.y delta current,column
            if. -.target{seen do.
                seen=.(1)target}seen
                pending=.pending,target
                labels=.labels,<label,column{alphabet y
            end.
        end.
    end.
    0$a:
)
product =: 3 : 0
    'a b operation'=.y
    pairs=.,:(start a),start b
    indices=.((#states a),#states b)$_1
    indices=.(0)(<0{pairs)}indices
    edges=.0 3$0
    finals=.i.0
    details=.0$a:
    cursor=.0
    while. cursor<#pairs do.
        'p q'=.cursor{pairs
        first=.a accepts ,p
        second=.b accepts ,q
        final=.first*.-.second
        if. operation-:'UNION' do. final=.first+.second end.
        if. operation-:'INTERSECT' do. final=.first*.second end.
        if. final do. finals=.finals,cursor end.
        details=.details,<'  P',(num cursor),' = (',(p{::states a),',',(q{::states b),')'
        for_column. i.#alphabet a do.
            target=.(a delta p,column),b delta q,column
            at=.(<target){indices
            if. at=_1 do.
                at=.#pairs
                pairs=.pairs,target
                indices=.at(<target)}indices
            end.
            edges=.edges,cursor,column,at
        end.
        cursor=.>:cursor
    end.
    machine=.mkMachine (<'DFA'),(<'P'series #pairs),(<alphabet a),(<0),(<finals),<edges
    (<machine),<details
)
equivalent =: 3 : 0
    'a b firstName secondName'=.y
    pairs=.,:(start a),start b
    labels=.,<''
    seen=.((#states a),#states b)$0
    seen=.(1)(<0{pairs)}seen
    cursor=.0
    while. cursor<#pairs do.
        'p q'=.cursor{pairs
        label=.cursor{::labels
        cursor=.>:cursor
        first=.a accepts ,p
        second=.b accepts ,q
        if. first~:second do.
            owner=.secondName
            if. first do. owner=.firstName end.
            'NOT EQUIVALENT: ',(wordText label),' is accepted only by ',owner return.
        end.
        for_column. i.#alphabet a do.
            target=.(a delta p,column),b delta q,column
            if. -.(<target){seen do.
                seen=.(1)(<target)}seen
                pairs=.pairs,target
                labels=.labels,<label,column{alphabet a
            end.
        end.
    end.
    'EQUIVALENT'
)
synchronize =: 3 : 0
    subsets=.,<i.#states y
    labels=.,<''
    cursor=.0
    while. cursor<#subsets do.
        current=.cursor{::subsets
        label=.cursor{::labels
        cursor=.>:cursor
        if. 1=#current do.
            'SYNCHRONIZING ',(wordText label),' -> ',({.current){::states y return.
        end.
        for_column. i.#alphabet y do.
            target=.i.0
            for_item. current do. target=.target,y delta item,column end.
            target=.ordered target
            if. -.(<target)e.subsets do.
                subsets=.subsets,<target
                labels=.labels,<label,column{alphabet y
            end.
        end.
    end.
    'NOT SYNCHRONIZING'
)
tableLines =: 3 : 0
    count=.#alphabet y
    if. (kind y)-:'NFA' do.
        if. epsilonCount y do. count=.>:count end.
    end.
    header=.,<''
    for_column. i.count do.
        if. column=#alphabet y do. header=.header,<,'e'
        else. header=.header,<,column{alphabet y end.
    end.
    rows=.,<header
    for_item. i.#states y do.
        label=.'  '
        if. item=start y do. label=.'->' end.
        label=.label,(item e.accepting y){' *'
        row=.,<label,item{::states y
        for_column. i.count do.
            targets=.y cell item,column
            if. (kind y)-:'DFA' do. value=.({.targets){::states y
            elseif. #targets do. value=.y setText targets
            else. value=.,'-' end.
            row=.row,<value
        end.
        rows=.rows,<row
    end.
    widths=.(>:count)$0
    for_row. rows do. widths=.widths>.#&> >row end.
    output=.0$a:
    for_row. rows do.
        row=.>row
        padded=.0$a:
        for_column. i.>:count do.
            value=.column{::row
            padded=.padded,<value,((column{widths)-#value)#' '
        end.
        text=.'  'join padded
        while. #text do.
            if. ' '~:{:text do. break. end.
            text=.}:text
        end.
        output=.output,<text
    end.
    output
)
showLine =: 4 : 0
    final=.'-'
    if. #accepting x do. final=.','join (accepting x){states x end.
    parts=.(<kind x),(<y),(<','join states x),(<alphabet x),(<(start x){::states x),<final
    for_edge. 0 allEdges x do.
        'source column target'=.edge
        symbol=.,'e'
        if. column<#alphabet x do. symbol=.,column{alphabet x end.
        parts=.parts,<(source{::states x),':',symbol,':',target{::states x
    end.
    ' 'join parts
)
register =: 3 : 0
    'name machine details'=.y
    Names=:Names,<name
    Machines=:Machines,<machine
    (<machine summary name),details
)
defineMachine =: 4 : 0
    if. 5>#y do. fail 'wrong number of arguments' end.
    name=.0{::y
    if. (<name)e.Names do. fail name,' already exists' end.
    names=.','split 1{::y
    seen=.0$a:
    for_item. names do.
        if. item e.seen do. fail 'duplicate state ',>item end.
        seen=.seen,item
    end.
    symbols=./:~2{::y
    initial=.names i.3{y
    if. initial=#names do. fail 'unknown state ',3{::y end.
    finals=.i.0
    if. -.(4{::y)-:,'-' do.
        for_item. ','split 4{::y do.
            at=.names i.item
            if. at=#names do. fail 'unknown state ',>item end.
            if. at e.finals do. fail 'duplicate state ',>item end.
            finals=.finals,at
        end.
    end.
    edges=.0 3$0
    seenWords=.seenPairs=.0$a:
    for_item. 5}.y do.
        word=.>item
        'p symbol q'=. ':'split word
        source=.names i.<p
        if. source=#names do. fail 'unknown state ',p end.
        if. (symbol-:,'e')*.x-:'DFA' do. fail 'epsilon transition in DFA' end.
        if. -.symbol-:,'e' do.
            if. -.({.symbol)e.symbols do. fail 'unknown symbol ',symbol end.
        end.
        target=.names i.<q
        if. target=#names do. fail 'unknown state ',q end.
        if. (<word)e.seenWords do. fail 'duplicate transition ',word end.
        key=.p,':',symbol
        if. x-:'DFA' do.
            if. (<key)e.seenPairs do. fail 'conflicting transition ',word end.
        end.
        seenWords=.seenWords,<word
        seenPairs=.seenPairs,<key
        column=.#symbols
        if. -.symbol-:,'e' do. column=.symbols i.{.symbol end.
        edges=.edges,source,column,target
    end.
    if. x-:'DFA' do.
        for_item. names do.
            for_symbol. symbols do.
                key=.(>item),':',symbol
                if. -.(<key)e.seenPairs do. fail 'missing transition ',key end.
            end.
        end.
    end.
    machine=.mkMachine (<x),(<names),(<symbols),(<initial),(<finals),<edges
    register (<name),(<machine),<0$a:
)
defineRegex =: 3 : 0
    if. 3~:#y do. fail 'wrong number of arguments' end.
    name=.0{::y
    if. (<name)e.Names do. fail name,' already exists' end.
    symbols=./:~1{::y
    expression=.2{::y
    for_character. expression do.
        if. (character~:'e')*.character e.'abcdefghijklmnopqrstuvwxyz0123456789' do.
            if. -.character e.symbols do. fail 'unknown symbol ',character end.
        end.
    end.
    RText=:expression
    RCursor=:0
    RNodes=:0$a:
    root=.ralternate''
    if. RCursor~:#RText do. rproblem'' end.
    TCount=:0
    TEdges=:0 3$0
    TSymbols=:symbols
    whole=.tbuild root
    machine=.mkMachine (<'NFA'),(<'N'series TCount),(<symbols),(<{.whole),(<,{:whole),<TEdges
    register (<name),(<machine),<0$a:
)
command =: 3 : 0
    parts=.words y
    operation=.0{::parts
    args=.}.parts
    if. -.(<operation)e.Commands do. fail 'unknown command ',operation end.
    if. (<operation)e.'DFA';'NFA' do. operation defineMachine args return. end.
    if. operation-:'REGEX' do. defineRegex args return. end.
    expected=.2
    if. (<operation)e.words 'EMPTY FINITE INFO TABLE SHOW SYNC DELETE' do. expected=.1 end.
    if. (<operation)e.words 'UNION INTERSECT DIFF CONCAT' do. expected=.3 end.
    if. operation-:'LIST' do. expected=.0 end.
    if. expected~:#args do. fail 'wrong number of arguments' end.
    if. operation-:'LIST' do.
        if. 0=#Names do. <'(none)' return. end.
        output=.0$a:
        for_i. i.#Names do. output=.output,<(i{::Machines)summary i{::Names end.
        output return.
    end.
    paired=.(<operation)e.words 'EQUIV UNION INTERSECT DIFF CONCAT'
    references=.>:paired
    for_i. i.references do.
        if. -.(i{args)e.Names do. fail 'unknown automaton ',i{::args end.
    end.
    creates=.(<operation)e.words 'TODFA EPSFREE MINIMIZE UNION INTERSECT DIFF COMPLEMENT REVERSE CONCAT STAR'
    newName=.>{:args
    if. creates do.
        if. (<newName)e.Names do. fail newName,' already exists' end.
    end.
    needsDfa=.(<operation)e.words 'MINIMIZE COMPLEMENT UNION INTERSECT DIFF SYNC'
    if. needsDfa do.
        for_i. i.references do.
            machine=.(Names i.i{args){::Machines
            if. -.(kind machine)-:'DFA' do. fail (i{::args),' is not a DFA' end.
        end.
    end.
    at=.Names i.0{args
    machine=.at{::Machines
    other=.machine
    if. paired do. other=.(Names i.1{args){::Machines end.
    if. paired do.
        if. -.(alphabet machine)-:alphabet other do. fail 'alphabets differ' end.
    end.
    if. operation-:'DELETE' do.
        Names=:(at{.Names),(>:at)}.Names
        Machines=:(at{.Machines),(>:at)}.Machines
        <'deleted ',0{::args return.
    end.
    if. operation-:'ACCEPT' do.
        word=.1{::args
        if. word-:,'e' do. word=.'' end.
        for_symbol. word do.
            if. -.symbol e.alphabet machine do. fail 'unknown symbol ',symbol end.
        end.
        current=.machine closure ,start machine
        if. (kind machine)-:'DFA' do. path=.({.current){::states machine
        else. path=.machine setText current end.
        for_symbol. word do.
            column=.(alphabet machine)i.symbol
            current=.machine destination (<current),<column
            if. (kind machine)-:'DFA' do. label=.({.current){::states machine
            else. label=.machine setText current end.
            path=.path,' -',symbol,'-> ',label
        end.
        verdict=.'REJECT '
        if. machine accepts current do. verdict=.'ACCEPT ' end.
        <verdict,path return.
    end.
    if. operation-:'CLOSURE' do.
        seeds=.i.0
        for_item. ','split 1{::args do.
            index=.(states machine)i.item
            if. index=#states machine do. fail 'unknown state ',>item end.
            seeds=.seeds,index
        end.
        <machine setText machine closure seeds return.
    end.
    if. (<operation)e.'TODFA';'MINIMIZE' do.
        if. operation-:'TODFA' do. 'result details'=.determinize machine
        else. 'result details'=.minimize machine end.
        register (<newName),(<result),<details return.
    end.
    if. operation-:'EPSFREE' do.
        edges=.0 3$0
        finals=.i.0
        for_item. i.#states machine do.
            expanded=.machine closure ,item
            if. machine accepts expanded do. finals=.finals,item end.
            for_column. i.#alphabet machine do.
                for_target. machine destination (<expanded),<column do. edges=.edges,item,column,target end.
            end.
        end.
        result=.mkMachine (<'NFA'),(<states machine),(<alphabet machine),(<start machine),(<finals),<edges
        register (<newName),(<result),<0$a: return.
    end.
    if. operation-:'EQUIV' do.
        a=.0{::determinize machine
        b=.0{::determinize other
        <equivalent (<a),(<b),(0{args),1{args return.
    end.
    if. (<operation)e.words 'UNION INTERSECT DIFF' do.
        'result details'=.product (<machine),(<other),<operation
        register (<newName),(<result),<details return.
    end.
    if. operation-:'COMPLEMENT' do.
        finals=.(i.#states machine)-.accepting machine
        result=.mkMachine (<'DFA'),(<states machine),(<alphabet machine),(<start machine),(<finals),<0 allEdges machine
        register (<newName),(<result),<0$a: return.
    end.
    if. (<operation)e.words 'REVERSE STAR CONCAT' do.
        offset=.1
        count=.>:#states machine
        if. operation-:'CONCAT' do. offset=.0
            count=.(#states machine)+#states other end.
        edges=.offset allEdges machine
        finals=.i.0
        initial=.0
        epsilon=.#alphabet machine
        if. operation-:'REVERSE' do.
            edges=.2 1 0{"1 edges
            for_item. accepting machine do. edges=.edges,0,epsilon,>:item end.
            finals=.,>:start machine
        elseif. operation-:'STAR' do.
            edges=.edges,0,epsilon,>:start machine
            finals=.0,>:accepting machine
            for_item. accepting machine do. edges=.edges,(>:item),epsilon,>:start machine end.
        else.
            shift=.#states machine
            edges=.edges,shift allEdges other
            for_item. accepting machine do. edges=.edges,item,epsilon,shift+start other end.
            finals=.shift+accepting other
            initial=.start machine
        end.
        result=.mkMachine (<'NFA'),(<'N'series count),(<alphabet machine),(<initial),(<finals),<edges
        register (<newName),(<result),<0$a: return.
    end.
    if. operation-:'SYNC' do. <synchronize machine return. end.
    if. operation-:'TABLE' do. tableLines machine return. end.
    if. operation-:'SHOW' do. <machine showLine 0{::args return. end.
    dfa=.0{::determinize machine
    if. (<operation)e.'COUNT';'FINITE' do.
        limit=.<:#states machine
        if. operation-:'COUNT' do. limit=.0".1{::args
        elseif. {:languageStatus dfa do. <'INFINITE' return. end.
        counts=.(#states dfa)$0
        counts=.(1)(start dfa)}counts
        total=.0
        if. operation-:'FINITE' do. total=.dfa acceptedCount counts end.
        for_i. i.limit do.
            counts=.dfa nextCounts counts
            if. operation-:'FINITE' do. total=.total+dfa acceptedCount counts end.
        end.
        if. operation-:'COUNT' do. <num dfa acceptedCount counts
        else. <'FINITE ',num total end. return.
    end.
    if. operation-:'ENUM' do.
        limit=.0".1{::args
        pending=.,start dfa
        labels=.,<''
        cursor=.total=.0
        shown=.0$a:
        while. cursor<#pending do.
            current=.cursor{pending
            label=.cursor{::labels
            cursor=.>:cursor
            if. dfa accepts ,current do.
                total=.>:total
                if. 50>#shown do. shown=.shown,<wordText label end.
            end.
            if. limit>#label do.
                for_column. i.#alphabet dfa do.
                    pending=.pending,dfa delta current,column
                    labels=.labels,<label,column{alphabet dfa
                end.
            end.
        end.
        text=.num total
        if. #shown do. text=.text,' ',' 'join shown end.
        if. total>50 do. text=.text,' ...' end.
        <text return.
    end.
    if. operation-:'EMPTY' do.
        found=.smallestWord dfa
        if. #found do. <'NOT EMPTY ',wordText 0{::found else. <'EMPTY' end. return.
    end.
    'empty infinite'=.languageStatus dfa
    epsilon=.epsilonCount machine
    deterministic=.epsilon=0
    complete=.1
    for_item. i.#states machine do.
        for_column. i.#alphabet machine do.
            size=.#machine cell item,column
            deterministic=.deterministic*.size<:1
            complete=.complete*.size>0
        end.
    end.
    language=.'finite'
    if. empty do. language=.'empty' elseif. infinite do. language=.'infinite' end.
    minimal=.0{::minimize dfa
    (<machine summary 0{::args),(<'  epsilon transitions: ',num epsilon),(<'  reachable: ',machine listText reachable machine),(<'  live: ',machine listText live machine),(<'  deterministic: ',deterministic{::'no';'yes'),(<'  complete: ',complete{::'no';'yes'),(<'  language: ',language),<'  minimal DFA states: ',num #states minimal
)
Commands =: words 'DFA NFA REGEX ACCEPT CLOSURE TODFA EPSFREE MINIMIZE EQUIV UNION INTERSECT DIFF COMPLEMENT REVERSE CONCAT STAR ENUM COUNT EMPTY FINITE INFO TABLE SHOW SYNC LIST DELETE'
Names =: Machines =: 0$a:
lines =: <;._2 (1!:1 <'/dev/stdin'),LF
count =: 0".0{::lines
for_i. i.count do.
    line=. (>:i){::lines
    if. '#'={.line do. continue. end.
    try.
        output=.command line
        for_text. output do. say >text end.
    catcht. say 'error: ',Reason
    end.
end.
