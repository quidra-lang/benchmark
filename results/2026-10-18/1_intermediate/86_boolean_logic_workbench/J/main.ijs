LF =: 10{a.
BSLASH =: 92{a.
SQ =: 39{a.
num =: 3 : ',''0'' 8!:2 y'
say =: 3 : '1!:2&2 y,LF'
words =: 3 : '(<;._1 '' '',y)-.<'''''
join =: 4 : '(#x)}.;(<x),&.>y'
Commands =: words 'DEF DEFSUM DEL LIST PRINT TABLE MINTERMS MAXTERMS DNF CNF NNF DUAL ANF SIMPLIFY RESTRICT COFACTOR MINIMIZE MINDC MINPOS KMAP SAT TAUT COUNT EQUIV IMPLIES PROPS BDD CLAUSES DP'
TableCommands =: words 'TABLE MINTERMS MAXTERMS DNF CNF ANF SAT TAUT COUNT EQUIV IMPLIES PROPS KMAP BDD MINIMIZE MINDC MINPOS'
Operations =: words '<-> -> | ^ &'
fail =: 3 : 0
    Reason=:y
    throw.
)
validName =: 3 : 0
    if. (0=#y)+.8<#y do. 0 return. end.
    (({.y)e.'abcdefghijklmnopqrstuvwxyz')*.*./y e.'abcdefghijklmnopqrstuvwxyz0123456789'
)
isVariable =: 3 : '(1=#y)*.*./y e.''ABCDEFGHIJKLMNOPQRSTUVWXYZ'''
digits =: 3 : '(0<#y)*.*./y e.''0123456789'''
kind =: 3 : '0{::y{::Nodes'
textOf =: 3 : '1{::y{::Nodes'
left =: 3 : '2{::y{::Nodes'
right =: 3 : '3{::y{::Nodes'
addNode =: 3 : 0
    result=.#Nodes
    Nodes=:Nodes,<y
    NnfPositive=:NnfPositive,_1
    NnfNegative=:NnfNegative,_1
    result
)
leaf =: 3 : 0
    op=.,'V'
    if. (<,y)e.words '0 1' do. op=.,'C' end.
    addNode (<op),(<,y),(<0),<0
)
unary =: 3 : 'addNode (<,''~''),(<''''),(<y),<0'
binary =: 3 : 'addNode (0{y),(<''''),1 2{y'
precedence =: 3 : 0
    index=.Operations i.<kind y
    if. index=#Operations do. 6 else. >:index end.
)
notation =: 3 : 0
    op=.kind y
    if. (<op)e.words 'V C' do. textOf y return. end.
    a=.left y
    first=.notation a
    if. op-:,'~' do.
        if. 6>precedence a do. '~(',first,')' else. '~',first end. return.
    end.
    b=.right y
    second=.notation b
    if. ((precedence a)<precedence y)+.((op-:'->')*.(kind a)-:'->') do. first=.'(',first,')' end.
    if. ((precedence b)<precedence y)+.((-.op-:'->')*.(kind b)-:op) do. second=.'(',second,')' end.
    first,' ',op,' ',second
)
variables =: 3 : 0
    op=.kind y
    if. op-:,'C' do. 0$a: return. end.
    if. op-:,'V' do. ,<textOf y return. end.
    names=.variables left y
    if. -.op-:,'~' do. names=.~.names,variables right y end.
    (/:names){names
)
treeSize =: 3 : 0
    if. (<kind y)e.words 'V C' do. 1 return. end.
    result=.1+treeSize left y
    if. -. (kind y)-:,'~' do. result=.result+treeSize right y end.
    result
)
treeDepth =: 3 : 0
    if. (<kind y)e.words 'V C' do. 1 return. end.
    result=.treeDepth left y
    if. -. (kind y)-:,'~' do. result=.result>.treeDepth right y end.
    >:result
)
sameTree =: 4 : 0
    if. x=y do. 1 return. end.
    if. (-.(kind x)-:kind y)+.-.(textOf x)-:textOf y do. 0 return. end.
    if. (<kind x)e.words 'V C' do. 1 return. end.
    if. -.(left x)sameTree left y do. 0 return. end.
    if. (kind x)-:,'~' do. 1 else. (right x)sameTree right y end.
)
negate =: 3 : 0
    if. (kind y)-:,'C' do. leaf num 1-0".textOf y
    elseif. (kind y)-:,'~' do. left y
    else. unary y end.
)
combine =: 3 : 0
    'op a b'=.y
    a0=.((kind a)-:,'C')*.(textOf a)-:,'0'
    a1=.((kind a)-:,'C')*.(textOf a)-:,'1'
    b0=.((kind b)-:,'C')*.(textOf b)-:,'0'
    b1=.((kind b)-:,'C')*.(textOf b)-:,'1'
    equal=.a sameTree b
    complementary=.0
    if. (kind a)-:,'~' do. complementary=.(left a)sameTree b end.
    if. (kind b)-:,'~' do. complementary=.complementary+.a sameTree left b end.
    select. op
    case. ,'&' do.
        if. a0+.b0 do. leaf '0' return. end.
        if. a1 do. b return. end.
        if. b1+.equal do. a return. end.
        if. complementary do. leaf '0' return. end.
    case. ,'|' do.
        if. a1+.b1 do. leaf '1' return. end.
        if. a0 do. b return. end.
        if. b0+.equal do. a return. end.
        if. complementary do. leaf '1' return. end.
    case. ,'^' do.
        if. a0 do. b return. end.
        if. b0 do. a return. end.
        if. a1 do. negate b return. end.
        if. b1 do. negate a return. end.
        if. equal do. leaf '0' return. end.
        if. complementary do. leaf '1' return. end.
    case. '->' do.
        if. a0+.b1 do. leaf '1' return. end.
        if. a1 do. b return. end.
        if. b0 do. negate a return. end.
        if. equal do. leaf '1' return. end.
        if. complementary do. b return. end.
    case. '<->' do.
        if. a1 do. b return. end.
        if. b1 do. a return. end.
        if. a0 do. negate b return. end.
        if. b0 do. negate a return. end.
        if. equal do. leaf '1' return. end.
        if. complementary do. leaf '0' return. end.
    end.
    binary y
)
simplify =: 4 : 0
    op=.kind y
    if. op-:,'V' do.
        at=.(0{::x)i.<textOf y
        if. at<#0{::x do. leaf num at{1{::x else. y end. return.
    end.
    if. op-:,'C' do. y return. end.
    a=.x simplify left y
    if. op-:,'~' do. negate a return. end.
    b=.x simplify right y
    combine (<op),(<a),<b
)
nnf =: 4 : 0
    if. x do. cached=.y{NnfPositive else. cached=.y{NnfNegative end.
    if. cached>:0 do. cached return. end.
    op=.kind y
    if. op-:,'V' do.
        if. x do. result=.y else. result=.unary y end.
    elseif. op-:,'C' do.
        if. x do. result=.y else. result=.negate y end.
    elseif. op-:,'~' do. result=.(-.x)nnf left y
    elseif. (<op)e.words '& |' do.
        operation=.op
        if. -.x do.
            if. op-:,'&' do. operation=.,'|' else. operation=.,'&' end.
        end.
        a=.x nnf left y
        b=.x nnf right y
        result=.binary (<operation),(<a),<b
    elseif. op-:'->' do.
        a=.(-.x)nnf left y
        b=.x nnf right y
        if. x do. operation=.,'|' else. operation=.,'&' end.
        result=.binary (<operation),(<a),<b
    else.
        a=.1 nnf left y
        na=.0 nnf left y
        b=.1 nnf right y
        nb=.0 nnf right y
        if. x=(op-:'<->') do.
            first=.binary (<,'&'),(<a),<b
            second=.binary (<,'&'),(<na),<nb
        else.
            first=.binary (<,'&'),(<a),<nb
            second=.binary (<,'&'),(<na),<b
        end.
        result=.binary (<,'|'),(<first),<second
    end.
    if. x do. NnfPositive=:result y}NnfPositive else. NnfNegative=:result y}NnfNegative end.
    result
)
dual =: 3 : 0
    op=.kind y
    if. op-:,'V' do. y return. end.
    if. op-:,'C' do. negate y return. end.
    a=.dual left y
    if. op-:,'~' do. unary a return. end.
    b=.dual right y
    if. op-:'->' do. binary (<,'&'),(<unary a),<b return. end.
    choices=.words '| <-> & ^'
    at=.(words '& ^ | <->')i.<op
    binary (at{choices),(<a),<b
)
lex =: 4 : 0
    tokens=.0$a:
    i=.0
    while. i<#y do.
        c=.i{y
        if. c=' ' do. i=.>:i
            continue. end.
        length=.1
        if. '<->'-:3{.i}.y do. length=.3
        elseif. '->'-:2{.i}.y do. length=.2
        elseif. c e.'abcdefghijklmnopqrstuvwxyz' do.
            while. (i+length)<#y do.
                if. -.((i+length){y)e.'abcdefghijklmnopqrstuvwxyz0123456789' do. break. end.
                length=.>:length
            end.
        elseif. -.c e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ01~&^|()' do.
            fail 'invalid character ',SQ,c,SQ,' at ',num x+i
        end.
        tokens=.tokens,<(<length{.i}.y),<x+i
        i=.i+length
    end.
    tokens,<(<''),<x+#y
)
peek =: 3 : '0{::Position{::Tokens'
problem =: 3 : 0
    'text position'=.Position{::Tokens
    if. 0=#text do. fail 'unexpected end of formula at ',num position end.
    fail 'unexpected ',SQ,text,SQ,' at ',num position
)
readLevel =: 3 : 0
    if. y=5 do.
        token=.peek''
        if. token-:,'~' do. Position=:>:Position
            unary readLevel 5 return. end.
        if. token-:,'(' do.
            Position=:>:Position
            result=.readLevel 0
            if. -. (peek'')-:,')' do. problem'' end.
            Position=:>:Position
            result return.
        end.
        if. ((<token)e.words '0 1')+.isVariable token do.
            Position=:>:Position
            leaf token return.
        end.
        if. #token do.
            if. ({.token)e.'abcdefghijklmnopqrstuvwxyz' do.
                at=.DefinitionNames i.<token
                if. at=#DefinitionNames do.
                    fail 'undefined name ',SQ,token,SQ,' at ',num 1{::Position{::Tokens
                end.
                Position=:>:Position
                at{DefinitionTerms return.
            end.
        end.
        problem''
    end.
    operation=.y{::Operations
    result=.readLevel >:y
    while. operation-:peek'' do.
        Position=:>:Position
        level=.>:y
        if. y=1 do. level=.y end.
        other=.readLevel level
        result=.binary (<operation),(<result),<other
        if. y=1 do. break. end.
    end.
    result
)
parse =: 4 : 0
    Tokens=:x lex y
    Position=:0
    result=.readLevel 0
    if. #peek'' do. problem'' end.
    result
)
rowPattern =: 4 : 0
    if. x=0 do. '' else. '01'{~(x#2)#:y end.
)
swapPattern =: 3 : '''10-''{~''01-''i.y'
patternKey =: 3 : '''012''{~''10-''i.y'
orderPatterns =: 3 : 0
    patterns=.~.y
    (/:patternKey&.>patterns){patterns
)
literalCount =: 3 : '+/y~:''-'''
containsRow =: 4 : '*./(x=''-'')+.x=y'
patternText =: 4 : 0
    'pattern clause'=.y
    literals=.0$a:
    for_i. i.#pattern do.
        c=.i{pattern
        if. c='-' do. continue. end.
        text=.i{::x
        if. c='0' do. text=.'~',text end.
        literals=.literals,<text
    end.
    if. 0=#literals do.
        if. clause do. '0' else. '1' end.
    elseif. clause do. ' | 'join literals
    else. ' & 'join literals end.
)
products =: 4 : 0
    'patterns clauses'=.y
    parts=.0$a:
    for_pattern. patterns do.
        text=.x patternText (< >pattern),<clauses
        if. clauses*.2<:#patterns do.
            if. 2<:literalCount >pattern do. text=.'(',text,')' end.
        end.
        parts=.parts,<text
    end.
    if. 0=#parts do.
        if. clauses do. '1' else. '0' end.
    elseif. clauses do. ' & 'join parts
    else. ' | 'join parts end.
)
assignment =: 4 : 0
    bits=.(#y)rowPattern x
    parts=.0$a:
    for_i. i.#y do. parts=.parts,<(i{::y),'=',i{bits end.
    '{',(' 'join parts),'}'
)
evaluate =: 4 : 0
    'varlist row'=.x
    op=.kind y
    if. op-:,'C' do. 0".textOf y return. end.
    if. op-:,'V' do.
        at=.varlist i.<textOf y
        2|<.row%2^((#varlist)-(>:at)) return.
    end.
    a=.x evaluate left y
    if. op-:,'~' do. -.a return. end.
    b=.x evaluate right y
    select. Operations i.<op
    case. 4 do. a*.b
    case. 3 do. a~:b
    case. 2 do. a+.b
    case. 1 do. (-.a)+.b
    case. 0 do. a=b
    end.
)
truthValues =: 4 : 0
    result=.i.0
    for_row. i.2^#x do. result=.result,((<x),<row)evaluate y end.
    result
)
anfCoefficients =: 3 : 0
    result=.y
    bit=.1
    while. bit<#result do.
        for_row. i.#result do.
            if. 2|<.row%bit do. result=.((row{result)~:(row-bit){result)row}result end.
        end.
        bit=.2*bit
    end.
    result
)
mergePatterns =: 4 : 0
    result=.x
    for_i. i.#x do.
        a=.i{x
        b=.i{y
        if. (a~:'-')*.(b~:'-')*.a~:b do. 0$a: return. end.
        if. a='-' do. result=.b i}result end.
    end.
    ,<result
)
properContains =: 4 : 0
    if. x-:y do. 0 return. end.
    *./(y='-')+.x=y
)
tidy =: 3 : 0
    patterns=.~.y
    result=.0$a:
    for_pattern. patterns do.
        keep=.1
        for_other. patterns do.
            if. (>pattern)properContains >other do. keep=.0
                break. end.
        end.
        if. keep do. result=.result,pattern end.
    end.
    result
)
clausesOf =: 3 : 0
    at=.ClauseIds i.y
    if. at<#ClauseIds do. at{::ClauseSets return. end.
    op=.kind y
    result=.0$a:
    if. op-:,'C' do.
        if. (textOf y)-:,'0' do. result=.,<(#ClauseVariables)#'-' end.
    elseif. (<op)e.words 'V ~' do.
        if. op-:,'V' do. name=.textOf y
            sign=.'1'
        else. name=.textOf left y
            sign=.'0' end.
        pattern=.(#ClauseVariables)#'-'
        index=.ClauseVariables i.<name
        pattern=.sign index}pattern
        result=.,<pattern
    else.
        a=.clausesOf left y
        b=.clausesOf right y
        if. op-:,'&' do. result=.tidy a,b
        else.
            for_first. a do.
                for_second. b do. result=.result,(>first)mergePatterns >second end.
            end.
            result=.tidy result
        end.
    end.
    ClauseIds=:ClauseIds,y
    ClauseSets=:ClauseSets,<result
    result
)
buildBDD =: 4 : 0
    if. 1=#y do. {.y return. end.
    half=.<.-:#y
    low=.(>:x)buildBDD half{.y
    high=.(>:x)buildBDD half}.y
    if. low=high do. low return. end.
    triple=.x,low,high
    at=.(<"1 BddNodes)i.<triple
    if. at=#BddNodes do. BddNodes=:BddNodes,1 3$triple end.
    at+2
)
minimize =: 3 : 0
    'on dc n swapped'=.y
    stage=.(n&rowPattern)&.> <"0 ~.on,dc
    statistics=.primes=.0$a:
    while. 1 do.
        merged=.0$a:
        combined=.(#stage)$0
        for_j. i.#stage do.
            pattern=.j{::stage
            for_i. i.n do.
                c=.i{pattern
                if. c='-' do. continue. end.
                if. c='0' do. other=.'1' else. other=.'0' end.
                partner=.other i}pattern
                if. (<partner)e.stage do.
                    combined=.(1)j}combined
                    merged=.merged,<('-')i}pattern
                end.
            end.
        end.
        uncombined=.(-.combined)#stage
        primes=.primes,uncombined
        statistics=.statistics,< (#stage),#uncombined
        merged=.~.merged
        if. 0=#merged do. break. end.
        stage=.merged
    end.
    targets=.coverage=.0$a:
    for_pattern. orderPatterns primes do.
        covered=.i.0
        for_i. i.#on do.
            if. (>pattern)containsRow n rowPattern i{on do. covered=.covered,i end.
        end.
        if. #covered do. targets=.targets,pattern
            coverage=.coverage,<covered end.
    end.
    essentialIds=.i.0
    for_i. i.#on do.
        choices=.i.0
        for_j. i.#targets do.
            if. i e.j{::coverage do. choices=.choices,j end.
        end.
        if. 1=#choices do. essentialIds=.~.essentialIds,choices end.
    end.
    essential=.essentialIds{targets
    optional=.(i.#targets)-.essentialIds
    initial=.(#on)$0
    for_id. essentialIds do. initial=.(1)(id{::coverage)}initial end.
    found=.0
    best=.0$a:
    for_mask. i.2^#optional do.
        ids=.essentialIds
        covered=.initial
        for_i. i.#optional do.
            if. 2|<.mask%2^i do.
                id=.i{optional
                ids=.ids,id
                covered=.(1)(id{::coverage)}covered
            end.
        end.
        if. -. *./covered do. continue. end.
        candidate=.ids{targets
        literals=.+/literalCount&>candidate
        shown=.candidate
        if. swapped do. shown=.swapPattern&.>shown end.
        key=.''join patternKey&.>orderPatterns shown
        better=.-.found
        if. found do.
            if. (#candidate)<#best do. better=.1
            elseif. (#candidate)=#best do.
                if. literals<bestLiterals do. better=.1
                elseif. literals=bestLiterals do. better=.(-.key-:bestKey)*.0={./:key;bestKey end.
            end.
        end.
        if. better do. found=.1
            best=.orderPatterns candidate
            bestLiterals=.literals
            bestKey=.key end.
    end.
    (<statistics),(<orderPatterns targets),(<orderPatterns essential),<best
)
assignDefinition =: 4 : 0
    at=.DefinitionNames i.<x
    verb=.'defined '
    if. at<#DefinitionNames do. verb=.'redefined '
        DefinitionTerms=:y at}DefinitionTerms
    else. DefinitionNames=:DefinitionNames,<x
        DefinitionTerms=:DefinitionTerms,y end.
    ,<verb,x,' = ',notation y
)
command =: 3 : 0
    at=.y i.' '
    name=.at{.y
    hasArgument=.at<#y
    argument=.((>:at)<.#y)}.y
    if. -.(<name)e.Commands do. fail 'unknown command ',name end.
    if. name-:'LIST' do.
        if. hasArgument do. fail 'unexpected argument' end.
        output=.,<'names: ',num #DefinitionNames
        for_i. /:DefinitionNames do.
            output=.output,<(i{::DefinitionNames),' = ',notation i{DefinitionTerms
        end.
        output return.
    end.
    if. -.hasArgument do. fail 'missing argument' end.
    if. name-:'DEL' do.
        if. -.validName argument do. fail 'invalid name ',SQ,argument,SQ end.
        at=.DefinitionNames i.<argument
        if. at=#DefinitionNames do. fail 'undefined name ',SQ,argument,SQ end.
        DefinitionNames=:((i.#DefinitionNames)-.at){DefinitionNames
        DefinitionTerms=:((i.#DefinitionTerms)-.at){DefinitionTerms
        ,<'deleted ',argument return.
    end.
    if. name-:'DEF' do.
        at=.argument i.' '
        if. at=#argument do. fail 'missing argument' end.
        variable=.at{.argument
        if. -.validName variable do. fail 'invalid name ',SQ,variable,SQ end.
        root=.((#variable)+6)parse (>:at)}.argument
        variable assignDefinition root return.
    end.
    if. name-:'DEFSUM' do.
        semi=.argument i.';'
        if. semi=#argument do. fail 'missing '';''' end.
        parts=.words semi{.argument
        if. 0=#parts do. fail 'missing argument' end.
        variable=.0{::parts
        if. -.validName variable do. fail 'invalid name ',SQ,variable,SQ end.
        vars=.}.parts
        if. 0=#vars do. fail 'bad variable list' end.
        for_i. i.#vars do.
            if. -.isVariable i{::vars do. fail 'bad variable list' end.
            if. i>0 do.
                if. -.({.i{::vars)>{.(i-1){::vars do. fail 'bad variable list' end.
            end.
        end.
        if. 9<:#vars do. fail 'too many variables: ',num #vars end.
        rows=.i.0
        for_word. words (>:semi)}.argument do.
            word=.>word
            if. -.digits word do. fail 'bad minterm ',SQ,word,SQ end.
            if. 1<#word do.
                if. '0'={.word do. fail 'bad minterm ',SQ,word,SQ end.
            end.
            row=.0".word
            if. row>:2^#vars do. fail 'bad minterm ',SQ,word,SQ end.
            if. #rows do.
                if. row<:{:rows do. fail 'bad minterm ',SQ,word,SQ end.
            end.
            rows=.rows,row
        end.
        terms=.i.0
        for_row. rows do.
            bits=.(#vars)rowPattern row
            for_i. i.#vars do.
                factor=.leaf i{::vars
                if. '0'=i{bits do. factor=.unary factor end.
                if. i=0 do. term=.factor
                else. term=.binary (<,'&'),(<term),<factor end.
            end.
            terms=.terms,term
        end.
        if. 0=#terms do. root=.leaf '0'
        else. root=.{.terms
            for_term. }.terms do. root=.binary (<,'|'),(<root),<term end.
        end.
        variable assignDefinition root return.
    end.
    start=.(#name)+2
    front=.argument
    back=.''
    splitCommand=.(<name)e.words 'RESTRICT COFACTOR MINDC EQUIV IMPLIES'
    if. splitCommand do.
        semi=.argument i.';'
        if. semi=#argument do. fail 'missing '';''' end.
        front=.semi{.argument
        back=.(>:semi)}.argument
    end.
    root=.start parse front
    pairCommand=.(<name)e.words 'MINDC EQUIV IMPLIES'
    other=.root
    if. pairCommand do. other=.(start+semi+1)parse back end.
    assigned=.(<0$a:),<i.0
    if. name-:'RESTRICT' do.
        parts=.words back
        if. 0=#parts do. fail 'missing assignment' end.
        vars=.0$a:
        values=.i.0
        for_word. parts do.
            word=.>word
            if. 3~:#word do. fail 'bad assignment ',SQ,word,SQ end.
            if. (-.isVariable ,0{word)+.('='~:1{word)+.-.(2{word)e.'01' do.
                fail 'bad assignment ',SQ,word,SQ
            end.
            variable=.,0{word
            if. (<variable)e.vars do. fail 'duplicate variable ',variable end.
            vars=.vars,<variable
            values=.values,'01'i.2{word
        end.
        result=.((<vars),<values)simplify root
        ,<'restricted: ',notation result return.
    end.
    if. name-:'COFACTOR' do.
        parts=.words back
        if. 1~:#parts do. fail 'bad variable' end.
        variable=.0{::parts
        if. -.isVariable variable do. fail 'bad variable' end.
        high=.((<,<variable),<,1)simplify root
        low=.((<,<variable),<,0)simplify root
        result=.combine (<,'^'),(<high),<low
        (<'cofactor ',variable,'=1: ',notation high),(<'cofactor ',variable,'=0: ',notation low),<'difference: ',notation result return.
    end.
    vars=.variables root
    if. pairCommand do. vars=.~.vars,variables other
        vars=.(/:vars){vars end.
    if. ((<name)e.TableCommands)*.9<:#vars do. fail 'too many variables: ',num #vars end.
    select. name
    case. 'PRINT' do.
        text=.'none'
        if. #vars do. text=.' 'join vars end.
        (<'formula: ',notation root),(<'variables: ',text),<'size ',(num treeSize root),' depth ',num treeDepth root return.
    case. 'NNF' do. ,<'nnf: ',notation 1 nnf root return.
    case. 'DUAL' do. ,<'dual: ',notation dual root return.
    case. 'SIMPLIFY' do. ,<'simplified: ',notation assigned simplify root return.
    case. 'CLAUSES';'DP' do.
        ClauseIds=:i.0
        ClauseSets=:0$a:
        ClauseVariables=:vars
        clauses=.clausesOf 1 nnf root
        if. name-:'CLAUSES' do. ,<'clauses: ',vars products (<orderPatterns clauses),<1 return. end.
        output=.,<'start: clauses ',num #clauses
        empty=.(#vars)#'-'
        for_i. i.#vars do.
            if. (0=#clauses)+.(<empty)e.clauses do. break. end.
            positive=.negative=.kept=.0$a:
            for_clause. clauses do.
                c=.i{>clause
                if. c='1' do. positive=.positive,clause
                elseif. c='0' do. negative=.negative,clause
                else. kept=.kept,clause end.
            end.
            resolvents=.0$a:
            for_a. positive do.
                first=.('-')i}>a
                for_b. negative do.
                    second=.('-')i}>b
                    resolvents=.resolvents,first mergePatterns second
                end.
            end.
            resolvents=.~.resolvents
            clauses=.tidy kept,resolvents
            output=.output,<'eliminate ',(i{::vars),': resolvents ',(num #resolvents),' clauses ',num #clauses
        end.
        if. (<empty)e.clauses do. output,<'result: unsatisfiable'
        else. output,<'result: satisfiable' end. return.
    end.
    values=.vars truthValues root
    others=.i.0
    if. pairCommand do. others=.vars truthValues other end.
    on=.I.values
    off=.I.-.values
    select. name
    case. 'TABLE' do.
        label=.''
        if. #vars do. label=.(' 'join vars),' ' end.
        output=.,<label,'| F'
        for_row. i.#values do.
            bits=.(#vars)rowPattern row
            text=.''
            if. #bits do. text=.(' 'join <"0 bits),' ' end.
            output=.output,<text,'| ',num row{values
        end.
        output return.
    case. 'MINTERMS';'MAXTERMS' do.
        if. name-:'MINTERMS' do. rows=.on
            label=.'minterms: '
        else. rows=.off
            label=.'maxterms: ' end.
        if. #rows do. ,<label,' 'join num&.> <"0 rows else. ,<label,'none' end. return.
    case. 'DNF';'CNF' do.
        clause=.name-:'CNF'
        if. clause do. rows=.off
            label=.'cnf: '
        else. rows=.on
            label=.'dnf: ' end.
        patterns=.((#vars)&rowPattern)&.> <"0 rows
        if. clause do. patterns=.swapPattern&.>patterns end.
        ,<label,vars products (<patterns),<clause return.
    case. 'SAT' do.
        if. #on do. ,<'satisfiable: ',({.on)assignment vars
        else. ,<'unsatisfiable' end. return.
    case. 'TAUT' do.
        if. #off do. ,<'not a tautology: ',({.off)assignment vars
        else. ,<'tautology' end. return.
    case. 'COUNT' do. ,<'models: ',(num #on),' of ',num #values return.
    case. 'EQUIV';'IMPLIES' do.
        if. name-:'EQUIV' do.
            differences=.I.values~:others
            if. #differences do.
                row=.{.differences
                ,<'not equivalent: ',(row assignment vars),' f=',(num row{values),' g=',num row{others
            else. ,<'equivalent' end.
        else.
            differences=.I.values*.-.others
            if. #differences do. ,<'does not imply: ',({.differences)assignment vars
            else. ,<'implies' end.
        end. return.
    case. 'KMAP' do.
        n=.#vars
        if. (n<2)+.n>4 do. fail 'kmap needs 2 to 4 variables' end.
        p=.<.n%2
        q=.n-p
        label=.(;p{.vars),BSLASH,;p}.vars
        columns=.0$a:
        for_i. i.2^q do. columns=.columns,<q rowPattern i(22 b.)<.i%2 end.
        output=.,<label,' ',' 'join columns
        for_i. i.2^p do.
            gray=.i(22 b.)<.i%2
            row=.(p rowPattern gray),((#label)-p)#' '
            for_j. i.2^q do.
                column=.j(22 b.)<.j%2
                row=.row,(q#' '),num ((gray*2^q)+column){values
            end.
            output=.output,<row
        end.
        output return.
    case. 'BDD' do.
        BddNodes=:0 3$0
        result=.0 buildBDD values
        paths=.0 1
        output=.,<'nodes: ',num #BddNodes
        for_i. i.#BddNodes do.
            'level low high'=.i{BddNodes
            paths=.paths,(low{paths)+high{paths
            output=.output,<(num i+2),' = ite(',(level{::vars),', ',(num high),', ',(num low),')'
        end.
        output,(<'root: ',num result),<'paths: ',num result{paths return.
    end.
    coefficients=.anfCoefficients values
    if. name-:'ANF' do.
        patterns=.0$a:
        for_degree. i.>:#vars do.
            selected=.0$a:
            for_row. I.coefficients do.
                if. degree=+/#:row do.
                    bits=.(#vars)rowPattern row
                    bits=.('-')(I.bits='0')}bits
                    selected=.selected,<bits
                end.
            end.
            patterns=.patterns,orderPatterns selected
        end.
        terms=.0$a:
        for_pattern. patterns do. terms=.terms,<vars patternText (< >pattern),<0 end.
        if. #terms do. ,<'anf: ',' ^ 'join terms else. ,<'anf: 0' end. return.
    end.
    if. name-:'PROPS' do.
        depends=.0$a:
        monotone=.1
        for_i. i.#vars do.
            bit=.2^(#vars)-(>:i)
            changes=.0
            for_row. i.#values do.
                flipped=.row(22 b.)bit
                if. (row{values)~:flipped{values do. changes=.1 end.
                if. 0=2|<.row%bit do.
                    if. (row{values)>(row+bit){values do. monotone=.0 end.
                end.
            end.
            if. changes do. depends=.depends,i{vars end.
        end.
        selfDual=.*./values~:|.values
        linear=.symmetric=.1
        for_row. i.#values do.
            count=.+/#:row
            if. (row{coefficients)*.count>1 do. linear=.0 end.
            if. (row{values)~:((2^count)-1){values do. symmetric=.0 end.
        end.
        labels=.words 'zero-preserving one-preserving self-dual monotone linear symmetric'
        properties=.(-.{.values),({:values),selfDual,monotone,linear,symmetric
        if. #depends do. text=.' 'join depends else. text=.'none' end.
        output=.,<'depends: ',text
        for_i. i.#labels do.
            if. i{properties do. text=.'yes' else. text=.'no' end.
            output=.output,<(i{::labels),': ',text
        end.
        output return.
    end.
    dc=.i.0
    if. name-:'MINDC' do. dc=.I.others
        on=.on-.dc end.
    product=.name-:'MINPOS'
    if. product do. targets=.off else. targets=.on end.
    'stages primes essential cover'=.minimize (<targets),(<dc),(<#vars),<product
    literals=.+/literalCount&>cover
    if. product do.
        shown=.orderPatterns swapPattern&.>cover
        (<'minimal: ',vars products (<shown),<1),<'clauses ',(num #cover),' literals ',num literals return.
    end.
    output=.0$a:
    for_i. i.#stages do.
        'count primeCount'=.i{::stages
        output=.output,<'stage ',(num i),': implicants ',(num count),' primes ',num primeCount
    end.
    texts=.0$a:
    for_patterns. (<primes),<essential do.
        parts=.0$a:
        for_pattern. >patterns do. parts=.parts,<vars patternText (< >pattern),<0 end.
        if. #parts do. text=.', 'join parts else. text=.'none' end.
        texts=.texts,<text
    end.
    output,(<'primes: ',0{::texts),(<'essential: ',1{::texts),(<'minimal: ',vars products (<cover),<0),<'terms ',(num #cover),' literals ',num literals
)
run =: 3 : 0
    Nodes=:DefinitionNames=:0$a:
    DefinitionTerms=:NnfPositive=:NnfNegative=:i.0
    lines=.<;._2 (1!:1<'/dev/stdin'),LF
    count=.0".0{::lines
    for_i. i.count do.
        try. output=.command (>:i){::lines
        catcht. output=.,<'error: ',Reason end.
        for_text. output do. say >text end.
    end.
    i.0
)
run''
