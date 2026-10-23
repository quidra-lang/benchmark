LF =: 10{a.
DQ =: 34{a.
num =: 3 : ',''0'' 8!:2 y'
say =: 3 : '1!:2&2 y,LF'
words =: 3 : '(<;._1 '' '',y)-.<'''''
join =: 4 : '(#x)}.;(<x),&.>y'
Reserved =: words 'not mod count sum min max retract dump why forget listing strata stats check predicates undo halt'
Comparisons =: words '= != < <= > >='
Arithmetic =: words '+ - * / mod'
WordChars =: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'
EmptyBinding =: (<0$a:),<0$a:
fail =: 3 : 0
    Reason=:y
    throw.
)
digits =: 3 : '(0<#y)*.*./y e.''0123456789'''
value =: 4 : '(<x),<y'
valueText =: 3 : 0
    'kind data'=.y
    if. kind=0 do. num data return. end.
    plain=.0
    if. #data do. plain=.(({.data)e.'abcdefghijklmnopqrstuvwxyz')*.*./data e.WordChars end.
    if. plain*.-.(<data)e.Reserved do. data else. DQ,data,DQ end.
)
valueLess =: 4 : 0
    'a av'=.x
    'b bv'=.y
    if. a~:b do. a<b
    elseif. a=0 do. av<bv
    else. (-.av-:bv)*.0={./:av;bv end.
)
rowLess =: 4 : 0
    for_i. i.#x do.
        if. -.(i{::x)-:i{::y do. (i{::x)valueLess i{::y return. end.
    end.
    0
)
sortRows =: 3 : 0
    if. 2>#y do. y return. end.
    middle=.<.-:#y
    a=.sortRows middle{.y
    b=.sortRows middle}.y
    result=.0$a:
    i=.j=.0
    while. (i<#a)*.j<#b do.
        if. (j{::b)rowLess i{::a do. result=.result,j{b
            j=.>:j
        else. result=.result,i{a
            i=.>:i end.
    end.
    result,(i}.a),j}.b
)
tupleText =: 4 : 0
    if. 0=#y do. x else. x,'(',(', 'join valueText&.>y),')' end.
)
counted =: 4 : 0
    (num x),' ',(x~:1){::y
)
answerText =: 4 : 0
    parts=.0$a:
    for_i. i.#x do. parts=.parts,<(i{::x),' = ',valueText i{::y end.
    ', 'join parts
)
nodeKind =: 3 : '0{::y{::Nodes'
nodeText =: 3 : '1{::y{::Nodes'
nodeNumber =: 3 : '2{::y{::Nodes'
left =: 3 : '3{::y{::Nodes'
right =: 3 : '4{::y{::Nodes'
addNode =: 3 : 0
    result=.#Nodes
    Nodes=:Nodes,<y
    result
)
node =: 3 : 'addNode (<y),(<''''),(<0x),(<0),<0'
exprTerms =: 3 : 0
    k=.nodeKind y
    if. k=4 do. exprTerms left y
    elseif. k=5 do. (exprTerms left y),exprTerms right y
    else. ,y end.
)
literalTerms =: 3 : 0
    if. 2=0{::y do. (exprTerms 4{::y),exprTerms 5{::y else. 2{::y end.
)
variables =: 3 : 0
    result=.0$a:
    for_id. y do.
        if. 2=nodeKind id do. result=.result,<nodeText id end.
    end.
    result
)
bodyVariables =: 3 : 0
    result=.0$a:
    for_item. y do. result=.result,variables literalTerms >item end.
    ~.result
)
termValue =: 4 : 0
    k=.nodeKind y
    if. k=0 do. 0 value nodeNumber y
    elseif. k=1 do. 1 value nodeText y
    else. ((0{::x)i.<nodeText y){::1{::x
    end.
)
termText =: 4 : 0
    k=.nodeKind y
    if. k e.0 1 do. valueText x termValue y
    elseif. k=3 do. '_'
    else.
        index=.(0{::x)i.<nodeText y
        if. index<#0{::x do. valueText index{::1{::x else. nodeText y end.
    end.
)
exprText =: 4 : 0
    k=.nodeKind y
    if. k=4 do. '(',(x exprText left y),')'
    elseif. k=5 do. (x exprText left y),' ',(nodeText y),' ',x exprText right y
    else. x termText y end.
)
literalText =: 4 : 0
    'mode predicate terms operation first second'=.y
    if. mode=2 do. (x exprText first),' ',operation,' ',x exprText second return. end.
    text=.predicate
    if. #terms do. text=.text,'(',(', 'join (x&termText)&.> <"0 terms),')' end.
    if. mode=1 do. 'not ',text else. text end.
)
instantiate =: 4 : '(x&termValue)&.> <"0 2{::y'
unify =: 3 : 0
    'terms row binding'=.y
    'names values'=.binding
    for_i. i.#terms do.
        id=.i{terms
        datum=.i{::row
        k=.nodeKind id
        if. k e.0 1 do.
            if. -.datum-:binding termValue id do. 0$a: return. end.
        elseif. k=2 do.
            name=.nodeText id
            at=.names i.<name
            if. at<#names do.
                if. -.datum-:at{::values do. 0$a: return. end.
            else. names=.names,<name
                values=.values,<datum end.
        end.
    end.
    ,<(<names),<values
)
evaluate =: 4 : 0
    k=.nodeKind y
    if. k=4 do. x evaluate left y return. end.
    if. k~:5 do. ,<x termValue y return. end.
    a=.x evaluate left y
    b=.x evaluate right y
    if. (0=#a)+.0=#b do. 0$a: return. end.
    a=.0{::a
    b=.0{::b
    if. (0{::a)+.0{::b do. 0$a: return. end.
    av=.1{::a
    bv=.1{::b
    op=.nodeText y
    select. op
    case. ,'+' do. result=.av+bv
    case. ,'-' do. result=.av-bv
    case. ,'*' do. result=.av*bv
    case. do.
        if. bv=0 do. 0$a: return. end.
        quotient=.<.av%bv
        if. op-:,'/' do. result=.quotient else. result=.av-bv*quotient end.
    end.
    ,<0 value result
)
lex =: 3 : 0
    result=.0$a:
    i=.0
    while. i<#y do.
        c=.i{y
        pair=.2{.i}.y
        if. c=' ' do. i=.>:i
        elseif. c='%' do. break.
        elseif. c=DQ do.
            finish=.>:i
            while. finish<#y do.
                if. DQ=finish{y do. break. end.
                finish=.>:finish
            end.
            if. finish=#y do. fail 'unterminated string' end.
            result=.result,< (<'STRING'),(<((>:finish)-i){.i}.y),<0x
            i=.>:finish
        elseif. (<pair)e.words ':- ?- != <= >=' do.
            result=.result,<(<pair),(<pair),<0x
            i=.i+2
        elseif. c e.'(),.:=<>+-*/' do.
            result=.result,<(<,c),(<,c),<0x
            i=.>:i
        elseif. c e.WordChars do.
            finish=.>:i
            while. finish<#y do.
                if. -.(finish{y)e.WordChars do. break. end.
                finish=.>:finish
            end.
            text=.(finish-i){.i}.y
            number=.0x
            if. c e.'abcdefghijklmnopqrstuvwxyz' do.
                kind=.'NAME'
                if. (<text)e.Reserved do. kind=.text end.
            elseif. c e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ' do. kind=.'VARIABLE'
            elseif. text-:,'_' do. kind=.'ANONYMOUS'
            elseif. digits text do.
                number=.x:0".text
                if. number>1000000000 do. fail 'integer out of range ',(39{a.),text,39{a. end.
                kind=.'INTEGER'
            else. fail 'bad token ',(39{a.),text,39{a. end.
            result=.result,<(<kind),(<text),<number
            i=.finish
        else. fail 'bad character ',(39{a.),c,39{a. end.
    end.
    result
)
peek =: 3 : 0
    if. (Position+y)<#Tokens do. 0{::(Position+y){::Tokens else. '' end.
)
problem =: 3 : 0
    if. Position=#Tokens do. fail 'syntax error at end of line' end.
    fail 'syntax error at ',(39{a.),(1{::Position{::Tokens),39{a.
)
consume =: 3 : 0
    result=.Position{::Tokens
    Position=:>:Position
    result
)
accept =: 3 : 0
    if. -.(,y)-:peek 0 do. 0 return. end.
    Position=:>:Position
    1
)
expect =: 3 : 0
    if. -.(,y)-:peek 0 do. problem'' end.
    consume''
)
readTerm =: 3 : 0
    kind=.peek 0
    if. (<kind)e.words 'NAME STRING' do.
        token=.consume''
        text=.1{::token
        if. kind-:'STRING' do. text=.}._1}.text end.
        addNode (<1),(<text),(<0x),(<0),<0
    elseif. kind-:'INTEGER' do.
        token=.consume''
        addNode (<0),(<''),(<2{::token),(<0),<0
    elseif. kind-:,'-' do.
        consume''
        token=.expect 'INTEGER'
        addNode (<0),(<''),(<-2{::token),(<0),<0
    elseif. kind-:'VARIABLE' do.
        token=.consume''
        addNode (<2),(<1{::token),(<0x),(<0),<0
    elseif. kind-:'ANONYMOUS' do. consume''
        node 3
    else. problem'' end.
)
factor =: 3 : 0
    if. -.accept '(' do. readTerm'' return. end.
    inner=.expression''
    expect ')'
    addNode (<4),(<''),(<0x),(<inner),<0
)
product =: 3 : 0
    result=.factor''
    while. (<peek 0)e.words '* / mod' do.
        op=.0{::consume''
        other=.factor''
        result=.addNode (<5),(<op),(<0x),(<result),<other
    end.
    result
)
expression =: 3 : 0
    result=.product''
    while. (<peek 0)e.words '+ -' do.
        op=.0{::consume''
        other=.product''
        result=.addNode (<5),(<op),(<0x),(<result),<other
    end.
    result
)
atom =: 3 : 0
    token=.expect 'NAME'
    terms=.i.0
    if. accept '(' do.
        terms=.terms,readTerm''
        while. accept ',' do. terms=.terms,readTerm'' end.
        expect ')'
    end.
    (<y),(<1{::token),(<terms),(<''),(<0),<0
)
readLiteral =: 3 : 0
    if. accept 'not' do. atom 1 return. end.
    if. (('NAME'-:peek 0)*.-.(<peek 1)e.Comparisons,Arithmetic) do. atom 0 return. end.
    first=.expression''
    if. -.(<peek 0)e.Comparisons do. problem'' end.
    op=.0{::consume''
    second=.expression''
    (<2),(<''),(<i.0),(<op),(<first),<second
)
readBody =: 3 : 0
    result=.,<readLiteral''
    while. accept ',' do. result=.result,<readLiteral'' end.
    result
)
parse =: 3 : 0
    Tokens=:y
    Position=:0
    kind=.peek 0
    head=.(<0),(<''),(<i.0),(<''),(<0),<0
    body=.0$a:
    aggregate=.variable=.name=.''
    number=.0
    if. kind-:'NAME' do.
        kind=.'clause'
        head=.atom 0
        if. accept ':-' do. body=.readBody'' end.
    elseif. kind-:':-' do. consume''
        kind=.'clause'
        body=.readBody''
    elseif. kind-:'?-' do. consume''
        kind=.'query'
        if. (<peek 0)e.words 'count sum min max' do.
            aggregate=.0{::consume''
            if. -.aggregate-:'count' do.
                variable=.1{::expect 'VARIABLE'
                expect ':'
            end.
        end.
        body=.readBody''
    elseif. (<kind)e.words 'retract why' do. consume''
        head=.atom 0
    elseif. kind-:'dump' do. consume''
        name=.1{::expect 'NAME'
    elseif. kind-:'forget' do. consume''
        number=.2{::expect 'INTEGER'
    elseif. kind-:'listing' do. consume''
        if. 'NAME'-:peek 0 do. name=.1{::consume'' end.
    elseif. (<kind)e.words 'strata stats check predicates undo halt' do. consume''
    else. problem'' end.
    expect '.'
    if. Position<#Tokens do. problem'' end.
    (<kind),(<head),(<body),(<aggregate),(<variable),(<name),<number
)
predicateIndex =: 4 : 0
    for_i. i.#x do.
        if. (0{::i{::x)-:,y do. i return. end.
    end.
    #x
)
bodyAtoms =: 3 : 0
    result=.0$a:
    for_item. y do.
        if. 2~:0{::>item do. result=.result,item end.
    end.
    result
)
arityError =: 3 : 0
    'name expected actual'=.y
    fail 'arity mismatch for ',name,': expected ',(num expected),', got ',num actual
)
checkKnown =: 3 : 0
    for_atom. y do.
        atom=.>atom
        name=.1{::atom
        at=.Predicates predicateIndex name
        if. at=#Predicates do. fail 'unknown predicate ',name end.
        expected=.1{::at{::Predicates
        if. expected~:#2{::atom do. arityError (<name),(<expected),<#2{::atom end.
    end.
    i.0
)
checkSafety =: 3 : 0
    'head body first'=.y
    for_id. 2{::head do.
        if. 3=nodeKind id do. fail 'anonymous variable in head' end.
    end.
    bound=.0$a:
    for_item. body do.
        item=.>item
        if. 0=0{::item do. bound=.bound,variables 2{::item
        elseif. 2=0{::item do.
            for_id. literalTerms item do.
                if. 3=nodeKind id do. fail 'anonymous variable in comparison' end.
            end.
        end.
    end.
    candidates=.first
    for_item. body do.
        if. 0~:0{::>item do. candidates=.candidates,variables literalTerms >item end.
    end.
    for_name. candidates do.
        if. -.name e.bound do. fail 'unsafe variable ',>name end.
    end.
    i.0
)
strata =: 4 : 0
    levels=.(#x)$0
    changed=.1
    while. changed do.
        changed=.0
        for_rule. y do.
            rule=.>rule
            head=.1{::rule
            if. 0=#1{::head do. continue. end.
            at=.x predicateIndex 1{::head
            for_item. bodyAtoms 2{::rule do.
                item=.>item
                source=.x predicateIndex 1{::item
                required=.(source{levels)+1=0{::item
                if. required>at{levels do.
                    levels=.required at}levels
                    if. required>#x do. 0$a: return. end.
                    changed=.1
                end.
            end.
        end.
    end.
    ,<levels
)
recursiveFlags =: 3 : 0
    graph=.(#Predicates)#<i.0
    for_rule. Rules do.
        rule=.>rule
        head=.1{::rule
        if. 0=#1{::head do. continue. end.
        at=.Predicates predicateIndex 1{::head
        edges=.at{::graph
        for_item. bodyAtoms 2{::rule do.
            edges=.edges,Predicates predicateIndex 1{::>item
        end.
        graph=.(<edges)at}graph
    end.
    result=.(#Predicates)$0
    for_start. i.#Predicates do.
        pending=.start{::graph
        cursor=.0
        seen=.i.0
        while. cursor<#pending do.
            current=.cursor{pending
            cursor=.>:cursor
            if. current=start do. result=.(1)start}result
                break. end.
            if. -.current e.seen do. seen=.seen,current
                pending=.pending,current{::graph end.
        end.
    end.
    result
)
comparisonHolds =: 4 : 0
    a=.x evaluate 4{::y
    b=.x evaluate 5{::y
    if. (0=#a)+.0=#b do. 0 return. end.
    a=.0{::a
    b=.0{::b
    op=.3{::y
    if. op-:,'=' do. a-:b return. end.
    if. op-:'!=' do. -.a-:b return. end.
    if. (0{::a)+.0{::b do. 0 return. end.
    av=.1{::a
    bv=.1{::b
    select. op
    case. ,'<' do. av<bv
    case. '<=' do. av<:bv
    case. ,'>' do. av>bv
    case. '>=' do. av>:bv
    end.
)
holds =: 4 : 0
    if. 2=0{::y do. x comparisonHolds y return. end.
    at=.SearchNegative predicateIndex 1{::y
    for_row. 2{::at{::SearchNegative do.
        result=.unify (<2{::y),(< >row),<x
        if. #result do. 0 return. end.
    end.
    1
)
searchVisit =: 4 : 0
    for_item. x{::SearchChecks do.
        if. -.y holds >item do. i.0 return. end.
    end.
    if. x=#SearchPlans do.
        if. -.(<y)e.SearchResults do. SearchResults=:SearchResults,<y end.
        i.0 return. end.
    'atom positions keys groups'=.x{::SearchPlans
    key=.0$a:
    for_position. positions do. key=.key,<y termValue position{2{::atom end.
    at=.keys i.<key
    if. at<#keys do.
        seen=.0$a:
        for_row. at{::groups do.
            extended=.unify (<2{::atom),(< >row),<y
            if. #extended do.
                binding=.0{::extended
                if. -.(<binding)e.seen do.
                    seen=.seen,<binding
                    (>:x)searchVisit binding
                end.
            end.
        end.
    end.
    i.0
)
solveBody =: 3 : 0
    'body positive negative initial'=.y
    SearchNegative=:negative
    known=.0{::initial
    stages=.,<known
    SearchPlans=:0$a:
    for_atom. body do.
        atom=.>atom
        if. 0~:0{::atom do. continue. end.
        positions=.i.0
        terms=.2{::atom
        for_i. i.#terms do.
            id=.i{terms
            k=.nodeKind id
            if. (k e.0 1)+.((k=2)*.(<nodeText id)e.known) do. positions=.positions,i end.
        end.
        rows=.2{::(positive predicateIndex 1{::atom){::positive
        keyRows=.0$a:
        for_row. rows do. keyRows=.keyRows,<positions{>row end.
        keys=.~.keyRows
        groups=.keyRows </.rows
        SearchPlans=:SearchPlans,<(<atom),(<positions),(<keys),<groups
        known=.~.known,variables terms
        stages=.stages,<known
    end.
    SearchChecks=:(#stages)#<0$a:
    for_item. body do.
        item=.>item
        if. 0=0{::item do. continue. end.
        needed=.variables literalTerms item
        for_i. i.#stages do.
            if. *./needed e.i{::stages do.
                SearchChecks=:(<(i{::SearchChecks),<item)i}SearchChecks
                break.
            end.
        end.
    end.
    SearchResults=:0$a:
    0 searchVisit initial
    SearchResults
)
record =: 3 : 0
    History=:History,<(<y),(<Predicates),<Rules
    Cached=:0
    i.0
)
computeModel =: 3 : 0
    ModelRelations=:Predicates
    ModelRounds=:ModelRules=:(#Predicates)#<i.0
    for_i. i.#Predicates do.
        count=.#2{::i{::Predicates
        ModelRounds=:(<count$0)i}ModelRounds
        ModelRules=:(<count$0)i}ModelRules
    end.
    levels=.0{::Predicates strata Rules
    serial=.0
    ModelStats=:0$a:
    maximum=._1
    if. #levels do. maximum=.>./levels end.
    for_level. i.>:maximum do.
        rounds=.added=.0
        while. 1 do.
            pending=.(#Predicates)#<0$a:
            sources=.(#Predicates)#<i.0
            newCount=.0
            for_rule. Rules do.
                rule=.>rule
                head=.1{::rule
                if. 0=#1{::head do. continue. end.
                at=.Predicates predicateIndex 1{::head
                if. level~:at{levels do. continue. end.
                solutions=.solveBody (<2{::rule),(<ModelRelations),(<ModelRelations),<EmptyBinding
                rows=.2{::at{::ModelRelations
                for_binding. solutions do.
                    row=.(>binding)instantiate head
                    if. -.(<row)e.rows,at{::pending do.
                        pending=.(<(at{::pending),<row)at}pending
                        sources=.(<(at{::sources),0{::rule)at}sources
                        newCount=.>:newCount
                    end.
                end.
            end.
            if. newCount=0 do. break. end.
            serial=.>:serial
            rounds=.>:rounds
            added=.added+newCount
            for_i. i.#Predicates do.
                relation=.i{::ModelRelations
                new=.i{::pending
                relation=.(<(2{::relation),new)2}relation
                ModelRelations=:(<relation)i}ModelRelations
                ModelRounds=:(<(i{::ModelRounds),(#new)#serial)i}ModelRounds
                ModelRules=:(<(i{::ModelRules),i{::sources)i}ModelRules
            end.
        end.
        ModelStats=:ModelStats,<rounds,added
    end.
    Cached=:1
    i.0
)
getModel =: 3 : 0
    if. -.Cached do. computeModel'' end.
    i.0
)
answers =: 3 : 0
    names=.bodyVariables y
    solutions=.solveBody (<y),(<ModelRelations),(<ModelRelations),<EmptyBinding
    rows=.0$a:
    for_binding. solutions do.
        'bound values'=.>binding
        rows=.rows,<(bound i.names){values
    end.
    (<names),<sortRows ~.rows
)
addClause =: 4 : 0
    'kind head body aggregate variable name number'=.y
    atoms=.bodyAtoms body
    if. #1{::head do. atoms=.(<head),atoms end.
    proposed=.Predicates
    for_atom. atoms do.
        atom=.>atom
        predicate=.1{::atom
        arity=.#2{::atom
        at=.proposed predicateIndex predicate
        if. at=#proposed do.
            proposed=.proposed,<(<predicate),(<arity),<0$a:
        else.
            expected=.1{::at{::proposed
            if. expected~:arity do. arityError (<predicate),(<expected),<arity end.
        end.
    end.
    checkSafety (<head),(<body),<variables 2{::head
    if. 0=#body do.
        at=.proposed predicateIndex 1{::head
        relation=.at{::proposed
        row=.EmptyBinding instantiate head
        if. (<row)e.2{::relation do. 0$a: return. end.
        record x
        relation=.(<(2{::relation),<row)2}relation
        proposed=.(<relation)at}proposed
        Predicates=:proposed
        0$a: return.
    end.
    text=.', 'join (EmptyBinding&literalText)&.>body
    if. #1{::head do. text=.(EmptyBinding literalText head),' :- ',text,'.'
    else. text=.':- ',text,'.' end.
    for_rule. Rules do.
        rule=.>rule
        if. text-:3{::rule do. fail 'duplicate of rule ',num 0{::rule end.
    end.
    added=.(<NextRule),(<head),(<body),<text
    clauses=.Rules,<added
    if. #1{::head do.
        if. 0=#proposed strata clauses do. fail 'negative cycle through ',1{::head end.
    end.
    record x
    Predicates=:proposed
    Rules=:clauses
    NextRule=:>:NextRule
    occurrences=.variables 2{::head
    for_item. body do. occurrences=.occurrences,variables literalTerms >item end.
    output=.0$a:
    for_variable. ~.occurrences do.
        if. 1=+/occurrences e.variable do.
            output=.output,<'WARNING line ',(num x),': singleton variable ',>variable
        end.
    end.
    output
)
query =: 3 : 0
    'kind head body aggregate variable name number'=.y
    checkKnown bodyAtoms body
    first=.0$a:
    if. #variable do. first=.,<variable end.
    checkSafety (<head),(<body),<first
    getModel''
    'names rows'=.answers body
    if. aggregate-:'count' do. ,<num #rows return. end.
    if. 0=#aggregate do.
        if. 0=#names do.
            if. #rows do. ,<'true.' else. ,<'false.' end. return.
        end.
        output=.(names&answerText)&.>rows
        output,< (#rows)counted words 'answer answers' return.
    end.
    at=.names i.<variable
    values=.0$a:
    for_row. rows do. values=.values,at{>row end.
    if. aggregate-:'sum' do.
        total=.0x
        for_value. values do.
            datum=.>value
            if. 0{::datum do. fail 'non-integer value in sum' end.
            total=.total+1{::datum
        end.
        ,<num total return.
    end.
    if. 0=#values do. ,<'no answers' return. end.
    chosen=.0{::values
    for_value. }.values do.
        datum=.>value
        if. aggregate-:'min' do.
            if. datum valueLess chosen do. chosen=.datum end.
        else.
            if. chosen valueLess datum do. chosen=.datum end.
        end.
    end.
    ,<valueText chosen
)
prove =: 3 : 0
    'predicate row depth'=.y
    at=.ModelRelations predicateIndex predicate
    rows=.2{::at{::ModelRelations
    position=.rows i.<row
    level=.position{at{::ModelRounds
    ruleNumber=.position{at{::ModelRules
    title=.(2*depth)#' '
    title=.title,predicate tupleText row
    if. level=0 do. ,<title,' [fact]' return. end.
    selected=.0{::Rules
    for_rule. Rules do.
        if. ruleNumber=0{::>rule do. selected=.>rule
            break. end.
    end.
    'number head body notation'=.selected
    earlier=.0$a:
    for_i. i.#ModelRelations do.
        relation=.i{::ModelRelations
        keep=.I.level>i{::ModelRounds
        relation=.(<keep{2{::relation)2}relation
        earlier=.earlier,<relation
    end.
    initial=.0{::unify (<2{::head),(<row),<EmptyBinding
    order=.~.(variables 2{::head),bodyVariables body
    solutions=.solveBody (<body),(<earlier),(<ModelRelations),<initial
    first=.1
    for_binding. solutions do.
        'bound values'=.>binding
        key=.(bound i.order){values
        if. first do. best=.key
            theta=.>binding
            first=.0
        elseif. key rowLess best do. best=.key
            theta=.>binding end.
    end.
    output=.,<title,' [rule ',(num number),']'
    for_item. body do.
        item=.>item
        if. 0~:0{::item do.
            output=.output,<((2*>:depth)#' '),theta literalText item
        else.
            source=.earlier predicateIndex 1{::item
            candidates=.0$a:
            for_candidate. 2{::source{::earlier do.
                if. #unify (<2{::item),(< >candidate),<theta do. candidates=.candidates,candidate end.
            end.
            chosen=.0{::sortRows candidates
            output=.output,prove (<1{::item),(<chosen),<>:depth
        end.
    end.
    output
)
execute =: 4 : 0
    'kind head body aggregate variable name number'=.y
    select. kind
    case. 'clause' do. x addClause y return.
    case. 'query' do. query y return.
    case. 'undo' do.
        if. 0=#History do. fail 'nothing to undo' end.
        'line Predicates Rules'=:>{:History
        History=:}:History
        Cached=:0
        ,<'undid line ',num line return.
    case. 'forget' do.
        at=._1
        for_i. i.#Rules do.
            if. number=0{::i{::Rules do. at=.i
                break. end.
        end.
        if. at<0 do. fail 'no rule ',num number end.
        record x
        Rules=:((i.#Rules)-.at){Rules
        0$a: return.
    case. 'retract' do.
        checkKnown ,<head
        at=.Predicates predicateIndex 1{::head
        relation=.at{::Predicates
        kept=.0$a:
        removed=.0
        for_row. 2{::relation do.
            if. #unify (<2{::head),(< >row),<EmptyBinding do. removed=.>:removed
            else. kept=.kept,row end.
        end.
        if. removed=0 do. fail 'no matching facts' end.
        record x
        relation=.(<kept)2}relation
        Predicates=:(<relation)at}Predicates
        ,< (removed counted words 'fact facts'),' retracted' return.
    case. 'listing' do.
        if. #name do.
            if. (#Predicates)=Predicates predicateIndex name do. fail 'unknown predicate ',name end.
        end.
        output=.0$a:
        for_rule. Rules do.
            rule=.>rule
            if. (0=#name)+.name-:1{::1{::rule do.
                output=.output,<(num 0{::rule),': ',3{::rule
            end.
        end.
        if. #output do. output else. ,<'no rules' end. return.
    case. 'why' do.
        checkKnown ,<head
        for_id. 2{::head do.
            if. -. (nodeKind id)e.0 1 do. fail 'why needs a ground atom' end.
        end.
        getModel''
        at=.ModelRelations predicateIndex 1{::head
        row=.EmptyBinding instantiate head
        if. (<row)e.2{::at{::ModelRelations do.
            prove (<1{::head),(<row),<0
        else. ,<'false.' end. return.
    case. 'dump' do.
        at=.Predicates predicateIndex name
        if. at=#Predicates do. fail 'unknown predicate ',name end.
        getModel''
        rows=.sortRows 2{::at{::ModelRelations
        output=.0$a:
        for_row. rows do. output=.output,<(name tupleText >row),'.' end.
        output,< (#rows)counted words 'tuple tuples' return.
    case. 'check' do.
        getModel''
        output=.0$a:
        for_rule. Rules do.
            rule=.>rule
            if. #1{::1{::rule do. continue. end.
            'names rows'=.answers 2{::rule
            title=.'constraint ',(num 0{::rule),': '
            if. 0=#rows do. output=.output,<title,'ok'
            else.
                output=.output,<title,(#rows)counted words 'violation violations'
                if. #names do.
                    for_row. rows do. output=.output,<'  ',names answerText >row end.
                end.
            end.
        end.
        if. #output do. output else. ,<'no constraints' end. return.
    case. 'strata' do.
        if. 0=#Predicates do. ,<'no predicates' return. end.
        levels=.0{::Predicates strata Rules
        recursive=.recursiveFlags''
        output=.0$a:
        for_level. i.>:>./levels do.
            names=.0$a:
            for_i. i.#Predicates do.
                if. level=i{levels do.
                    text=.0{::i{::Predicates
                    if. i{recursive do. text=.text,'*' end.
                    names=.names,<text
                end.
            end.
            names=.(/:names){names
            output=.output,<'stratum ',(num level),': ', ', 'join names
        end.
        output return.
    end.
    getModel''
    if. kind-:'predicates' do.
        output=.0$a:
        names=.0$a:
        for_relation. Predicates do. names=.names,0{>relation end.
        names=.(/:names){names
        for_name. names do.
            at=.Predicates predicateIndex >name
            relation=.at{::Predicates
            ruleCount=.0
            for_rule. Rules do.
                if. name-:1{1{::>rule do. ruleCount=.>:ruleCount end.
            end.
            output=.output,<(>name),'/',(num 1{::relation),': facts ',(num #2{::relation),', rules ',(num ruleCount),', tuples ',num #2{::at{::ModelRelations
        end.
        if. #output do. output else. ,<'no predicates' end. return.
    end.
    factCount=.tupleCount=.ruleCount=.0
    for_i. i.#Predicates do.
        factCount=.factCount+#2{::i{::Predicates
        tupleCount=.tupleCount+#2{::i{::ModelRelations
    end.
    for_rule. Rules do.
        if. #1{::1{::>rule do. ruleCount=.>:ruleCount end.
    end.
    output=.,<'facts ',(num factCount),', rules ',(num ruleCount),', constraints ',(num (#Rules)-ruleCount),', tuples ',num tupleCount
    for_i. i.#ModelStats do.
        'rounds added'=.i{::ModelStats
        output=.output,<'stratum ',(num i),': rounds ',(num rounds),', new ',num added
    end.
    for_rule. Rules do.
        rule=.>rule
        if. 0=#1{::1{::rule do. continue. end.
        derived=.0
        for_ids. ModelRules do. derived=.derived++/ (0{::rule)= >ids end.
        output=.output,<'rule ',(num 0{::rule),': new ',num derived
    end.
    output
)
run =: 3 : 0
    Nodes=:Predicates=:Rules=:History=:0$a:
    NextRule=:1
    Cached=:0
    lines=.<;._2 (1!:1<'/dev/stdin'),LF
    lineNumber=.0
    for_line. lines do.
        lineNumber=.>:lineNumber
        try.
            tokens=.lex >line
            if. 0=#tokens do. continue. end.
            statement=.parse tokens
            if. 'halt'-:0{::statement do. break. end.
            output=.lineNumber execute statement
            for_text. output do. say >text end.
        catcht. say 'ERROR line ',(num lineNumber),': ',Reason
        end.
    end.
    i.0
)
run''
