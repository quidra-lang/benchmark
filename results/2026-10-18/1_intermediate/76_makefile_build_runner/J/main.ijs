LF =: 10{a.
SQ =: 39{a.
BS =: 92{a.
num =: 3 : ',''0'' 8!:2 y'
join =: 4 : '(#x)}.;(<x),&.>y'
say =: 3 : '1!:2&2 y,LF'
fail =: 3 : 0
    Reason=:y
    throw.
)
trimLeft =: 3 : '((y~:'' '')i.1)}.y'
trimRight =: 3 : '|.trimLeft |.y'
trim =: 3 : 'trimRight trimLeft y'
words =: 3 : '(<;._1 '' '',y)-.<'''''
numericText =: 3 : '(0<#y)*.*./y e.''0123456789'''
lastChar =: 4 : 0
    positions=.I.y=x
    if. #positions do. {:positions else. _1 end.
)
closingIndex =: 4 : 0
    opening=.x{y
    if. opening='(' do. closing=.')' else. closing=.'}' end.
    depth=.0
    for_i. x+i.(#y)-x do.
        ch=.i{y
        if. ch=opening do. depth=.depth+1
        elseif. ch=closing do. depth=.depth-1
            if. 0=depth do. i return. end.
        end.
    end.
    _1
)
outsideIndex =: 4 : 0
    found=._1
    at=.0
    while. at<#y do.
        if. '$'~:at{y do.
            if. (found<0)*.x=at{y do. found=.at end.
            at=.at+1
        elseif. (at+1)<#y do.
            if. ((at+1){y)e.'({' do.
                close=.(at+1)closingIndex y
                if. close<0 do. fail 'unterminated variable reference' end.
                at=.close+1
            else. at=.at+2 end.
        else. at=.at+2 end.
    end.
    found
)
patternStem =: 4 : 0
    at=.x i.'%'
    if. at=#x do. if. x-:y do. '' else. a: end. return. end.
    prefix=.at{.x
    suffix=.(at+1)}.x
    if. (#y)<(#prefix)+#suffix do. a: return. end.
    if. (-.prefix-:(#prefix){.y)+.-.suffix-:(-#suffix){.y do. a: return. end.
    ((#y)-(#prefix)+#suffix){.(#prefix)}.y
)
substitute =: 4 : 0
    at=.x i.'%'
    if. at=#x do. x else. (at{.x),y,(at+1)}.x end.
)
replaceWord =: 3 : 0
    'word pattern replacement'=.y
    stem=.pattern patternStem word
    if. stem-:a: do. word
    elseif. '%'e.pattern do. replacement substitute stem
    else. replacement end.
)
splitArguments =: 3 : 0
    'text opening limit'=.y
    if. opening='(' do. closing=.')' else. closing=.'}' end.
    depth=.0
    start=.0
    result=.0$a:
    for_i. i.#text do.
        ch=.i{text
        if. ch=opening do. depth=.depth+1
        elseif. ch=closing do. depth=.depth-1
        elseif. (ch=',')*.depth=0 do.
            if. (limit=0)+.(#result)<limit-1 do.
                result=.result,<(i-start){.start}.text
                start=.i+1
            end.
        end.
    end.
    result,<start}.text
)
globMatches =: 4 : 0
    previous=.(1+#y)$0
    previous=.(1)0}previous
    for_token. x do.
        next=.(1+#y)$0
        if. token='*' do. next=.({.previous)0}next end.
        for_i. i.#y do.
            ch=.i{y
            if. token='*' do. value=.((i+1){previous)+.(ch~:'/')*.i{next
            else. value=.(i{previous)*.(token=ch)+.(token='?')*.ch~:'/' end.
            next=.value(i+1)}next
        end.
        previous=.next
    end.
    {:previous
)
FunctionNames =: ;:'subst patsubst strip findstring filter filter-out sort word wordlist words firstword lastword dir notdir suffix basename addsuffix addprefix wildcard foreach if call value info warning error'
functionMinimum =: 3 : 0
    if. (<y)e.;:'subst patsubst wordlist foreach' do. 3
    elseif. (<y)e.;:'findstring filter filter-out word addsuffix addprefix if' do. 2
    else. 1 end.
)
functionMaximum =: 3 : 'if. y-:''call'' do. 0 elseif. y-:''if'' do. 3 else. functionMinimum y end.'
clearMakefile =: 3 : 0
    Loaded=:0
    VariableNames=:Variables=:RuleNames=:Rules=:Patterns=:Recipes=:Phony=:0$a:
    Goal=:''
    CurrentGroup=:(<0$a:),(<i.0),<_1
    HasGroup=:0
)
fileTime =: 3 : 0
    at=.FileNames i.<y
    if. at<#FileNames do. at{FileTimes else. _1 end.
)
giveTime =: 3 : 0
    Clock=:Clock+1
    at=.FileNames i.<y
    if. at=#FileNames do. FileNames=:FileNames,<y
        FileTimes=:FileTimes,Clock
    else. FileTimes=:Clock at}FileTimes end.
)
removeFile =: 3 : 0
    mask=.FileNames~:<y
    FileNames=:mask#FileNames
    FileTimes=:mask#FileTimes
)
wildcardNames =: 3 : 0
    if. +./y e.'*?' do.
        result=.0$a:
        for_name. /:~FileNames do.
            if. y globMatches >name do. result=.result,name end.
        end.
        result
    elseif. (<y)e.FileNames do. ,<y
    else. 0$a: end.
)
expand =: 3 : 0
    result=.''
    at=.0
    while. at<#y do.
        ch=.at{y
        if. ch~:'$' do. result=.result,ch
            at=.at+1
        elseif. (at+1)=#y do. break.
        elseif. '$'=(at+1){y do. result=.result,'$'
            at=.at+2
        elseif. ((at+1){y)e.'({' do.
            close=.(at+1)closingIndex y
            if. close<0 do. fail 'unterminated variable reference' end.
            result=.result,reference (<(close-at+2){.(at+2)}.y),<(at+1){y
            at=.close+1
        else. result=.result,referenceValue ,(at+1){y
            at=.at+2 end.
    end.
    result
)
reference =: 3 : 0
    'content opening'=.y
    space=.content i.' '
    if. space<#content do.
        name=.space{.content
        if. (<name)e.FunctionNames do. callFunction (<name),(<trimLeft (space+1)}.content),<opening return. end.
    end.
    name=.expand content
    colon=.name i.':'
    if. colon<#name do.
        tail=.(colon+1)}.name
        equals=.tail i.'='
        if. equals<#tail do.
            pattern=.equals{.tail
            replacement=.(equals+1)}.tail
            if. -. '%'e.pattern do. pattern=.'%',pattern
                replacement=.'%',replacement end.
            value=.referenceValue colon{.name
            parts=.0$a:
            for_word. words value do. parts=.parts,<replaceWord word,(<pattern),<replacement end.
            ' 'join parts return.
        end.
    end.
    referenceValue name
)
referenceValue =: 3 : 0
    for_scope. |.Scopes do.
        'call name values'=.>scope
        if. -.call do.
            if. name-:y do. 0{::values return. end.
        elseif. numericText y do.
            index=.0".y
            if. index<#values do. index{::values else. '' end. return.
        end.
    end.
    at=.AutomaticNames i.<y
    if. at<#AutomaticNames do. at{::AutomaticValues else. variableValue y end.
)
variableValue =: 3 : 0
    at=.VariableNames i.<y
    if. at=#VariableNames do. '' return. end.
    'recursive value'=.at{::Variables
    if. -.recursive do. value return. end.
    if. (<y)e.Expanding do. fail 'Recursive variable ',SQ,y,SQ,' references itself (eventually)' end.
    Expanding=:Expanding,<y
    try. result=.expand value
    catcht. Expanding=:}:Expanding
        throw. end.
    Expanding=:}:Expanding
    result
)
callFunction =: 3 : 0
    'name argument opening'=.y
    args=.splitArguments (<argument),(<opening),<functionMaximum name
    if. (#args)<functionMinimum name do. fail 'insufficient number of arguments (',(num #args),') to function ',SQ,name,SQ end.
    if. name-:'foreach' do.
        variable=.trim expand 0{::args
        list=.words expand 1{::args
        parts=.0$a:
        for_word. list do.
            scope=.(<0),(<variable),<,word
            Scopes=:Scopes,<scope
            try. value=.expand 2{::args
            catcht. Scopes=:}:Scopes
                throw. end.
            Scopes=:}:Scopes
            parts=.parts,<value
        end.
        ' 'join parts return.
    elseif. name-:'if' do.
        if. #trim expand 0{::args do. expand 1{::args
        elseif. 3=#args do. expand 2{::args
        else. '' end. return.
    end.
    values=.0$a:
    for_arg. args do.
        value=.expand >arg
        if. -.(<name)e.'subst';'call' do. value=.trim value end.
        values=.values,<value
    end.
    select. name
    case. 'subst' do.
        'old new text'=.values
        if. 0=#old do. text return. end.
        result=.''
        at=.0
        while. at<#text do.
            if. ((at+#old)<:#text)*.old-:(#old){.at}.text do. result=.result,new
                at=.at+#old
            else. result=.result,at{text
                at=.at+1 end.
        end.
        result
    case. 'patsubst' do.
        result=.0$a:
        for_word. words 2{::values do. result=.result,<replaceWord word,(0{values),1{values end.
        ' 'join result
    case. 'strip' do. ' 'join words 0{::values
    case. 'findstring' do.
        'find text'=.values
        if. 0=#find do. find elseif. +./find E.text do. find else. '' end.
    case. 'filter';'filter-out' do.
        patterns=.words 0{::values
        result=.0$a:
        for_word. words 1{::values do.
            matched=.0
            for_pattern. patterns do.
                if. -.((>pattern)patternStem >word)-:a: do. matched=.1 end.
            end.
            if. matched=name-:'filter' do. result=.result,word end.
        end.
        ' 'join result
    case. 'sort' do. ' 'join /:~~.words 0{::values
    case. 'word' do.
        'index text'=.values
        if. -.numericText index do. fail 'non-numeric first argument to ',SQ,'word',SQ,' function: ',SQ,index,SQ end.
        index=.0".index
        if. index=0 do. fail 'first argument to ',SQ,'word',SQ,' function must be greater than 0' end.
        items=.words text
        if. index<:#items do. (index-1){::items else. '' end.
    case. 'wordlist' do.
        'first last text'=.values
        if. -.numericText first do. fail 'non-numeric first argument to ',SQ,'wordlist',SQ,' function: ',SQ,first,SQ end.
        if. -.numericText last do. fail 'non-numeric second argument to ',SQ,'wordlist',SQ,' function: ',SQ,last,SQ end.
        if. 0=0".first do. fail 'invalid first argument to ',SQ,'wordlist',SQ,' function: ',SQ,first,SQ end.
        start=.<:0".first
        items=.words text
        finish=.(#items)<.0".last
        if. start>:finish do. '' else. ' 'join (finish-start){.start}.items end.
    case. 'words' do. num #words 0{::values
    case. 'firstword';'lastword' do.
        items=.words 0{::values
        if. 0=#items do. '' elseif. name-:'firstword' do. 0{::items else. >{:items end.
    case. 'dir';'notdir';'suffix';'basename' do.
        result=.0$a:
        for_word. words 0{::values do.
            word=.>word
            slash=.'/'lastChar word
            dot=. '.'lastChar word
            if. name-:'dir' do.
                if. slash<0 do. part=.'./' else. part=.(slash+1){.word end.
            elseif. name-:'notdir' do. part=.(slash+1)}.word
            elseif. name-:'suffix' do.
                if. dot<:slash do. continue. end.
                part=.dot}.word
            else.
                if. dot>slash do. part=.dot{.word else. part=.word end.
            end.
            result=.result,<part
        end.
        ' 'join result
    case. 'addsuffix';'addprefix' do.
        result=.0$a:
        for_word. words 1{::values do.
            if. name-:'addsuffix' do. result=.result,<(>word),0{::values
            else. result=.result,<(0{::values),>word end.
        end.
        ' 'join result
    case. 'wildcard' do.
        result=.0$a:
        for_pattern. words 0{::values do. result=.result,wildcardNames >pattern end.
        ' 'join result
    case. 'call' do.
        variable=.trim 0{::values
        at=.VariableNames i.<variable
        if. at=#VariableNames do. '' return. end.
        'recursive value'=.at{::Variables
        if. -.recursive do. value return. end.
        scope=.(<1),( <''),<(<variable),}.values
        Scopes=:Scopes,<scope
        try. result=.expand value
        catcht. Scopes=:}:Scopes
            throw. end.
        Scopes=:}:Scopes
        result
    case. 'value' do.
        at=.VariableNames i.0{values
        if. at=#VariableNames do. '' else. 1{::at{::Variables end.
    case. 'info' do. say 0{::values
        ''
    case. 'warning' do. say Location,': ',0{::values
        ''
    case. 'error' do. fail 0{::values
    end.
)
conditionsActive =: 3 : 0
    if. 0=#y do. 1 else. (0{::>{:y)*.1{::>{:y end.
)
evaluateCondition =: 4 : 0
    if. (<x)e.'ifdef';'ifndef' do.
        name=.trim expand y
        at=.VariableNames i.<name
        defined=.0
        if. at<#VariableNames do. defined=.0<#1{::at{::Variables end.
        defined=x-:'ifdef' return.
    end.
    if. (#y)<2 do. fail 'invalid syntax in conditional' end.
    if. ('('~:{.y)+.')'~:{:y do. fail 'invalid syntax in conditional' end.
    inner=.}.}:y
    depth=.0
    for_i. i.#inner do.
        ch=.i{inner
        if. ch='(' do. depth=.depth+1
        elseif. ch=')' do. depth=.depth-1
        elseif. (ch=',')*.depth=0 do.
            first=.trim expand i{.inner
            second=.trim expand (i+1)}.inner
            (first-:second)=x-:'ifeq' return.
        end.
    end.
    fail 'invalid syntax in conditional'
)
assignVariable =: 4 : 0
    equals=.x
    op=.''
    if. equals>0 do.
        if. ((equals-1){y)e.':+?' do. op=.,(equals-1){y end.
    end.
    name=.trim (equals-#op){.y
    value=.trim (equals+1)}.y
    if. 0=#name do. fail 'empty variable name' end.
    at=.VariableNames i.<name
    if. op-:':' do. entry=.(<0),<expand value
    elseif. (op-:'+')*.at<#VariableNames do.
        'recursive old'=.at{::Variables
        addition=.value
        if. -.recursive do. addition=.expand value end.
        if. #old do. addition=.old,' ',addition end.
        entry=.(<recursive),<addition
    elseif. (op-:'?')*.at<#VariableNames do. return.
    else. entry=.(<1),<value end.
    if. at=#VariableNames do. VariableNames=:VariableNames,<name
        Variables=:Variables,<entry
    else. Variables=:(<entry)at}Variables end.
)
ruleEntry =: 3 : 0
    at=.RuleNames i.<y
    if. at<#RuleNames do. at{::Rules else. (<0$a:),(<_1),<'' end.
)
setRule =: 4 : 0
    at=.RuleNames i.<x
    if. at=#RuleNames do. RuleNames=:RuleNames,<x
        Rules=:Rules,<y
    else. Rules=:(<y)at}Rules end.
)
registerTarget =: 4 : 0
    entry=.ruleEntry x
    entry=.(<~.(0{::entry),y)0}entry
    x setRule entry
    if. (0=#Goal)*.'.'~:{.x do. Goal=:x end.
)
addRecipe =: 4 : 0
    group=.x
    id=.2{::group
    if. id<0 do.
        id=.#Recipes
        group=.(<id)2}group
        Recipes=:Recipes,<0$a:
        for_target. 0{::group do.
            target=.>target
            entry=.ruleEntry target
            old=.1{::entry
            if. old>:0 do.
                say 'Makefile:',(num 0{::y),': warning: overriding recipe for target ',SQ,target,SQ
                say 'Makefile:',(num 0{::0{::old{::Recipes),': warning: ignoring old recipe for target ',SQ,target,SQ
            end.
            target setRule (<id)1}entry
        end.
        for_index. 1{::group do.
            entry=.index{::Patterns
            Patterns=:(<(<id)2}entry)index}Patterns
        end.
    end.
    recipe=.(id{::Recipes),<y
    Recipes=:(<recipe)id}Recipes
    group
)
defineRule =: 3 : 0
    'targettext rest number'=.y
    targets=.~.words expand targettext
    hasinline=.0
    inline=.''
    semicolon=.';'outsideIndex rest
    if. semicolon>:0 do. hasinline=.1
        inline=.trimLeft (semicolon+1)}.rest
        rest=.semicolon{.rest end.
    colon=.':'outsideIndex rest
    isstatic=.colon>:0
    pattern=.''
    if. isstatic do. pattern=.trim expand colon{.rest
        rest=.(colon+1)}.rest end.
    prerequisites=.words expand rest
    group=.(<0$a:),(<i.0),<_1
    if. targets-:,<'.PHONY' do. Phony=:~.Phony,prerequisites
    elseif. isstatic do.
        if. -. '%'e.pattern do. fail 'target pattern contains no ',SQ,'%',SQ end.
        kept=.0$a:
        for_target. targets do.
            target=.>target
            stem=.pattern patternStem target
            if. stem-:a: do. stem=.'' end.
            if. 0=#stem do. say 'Makefile:',(num number),': target ',SQ,target,SQ,' doesn',SQ,'t match the target pattern'
            else.
                deps=.0$a:
                for_item. prerequisites do. deps=.deps,< (>item)substitute stem end.
                target registerTarget deps
                entry=.ruleEntry target
                target setRule (<stem)2}entry
                kept=.kept,<target
            end.
        end.
        group=.(<kept)0}group
    else.
        patterned=.0
        normal=.0
        for_target. targets do.
            if. '%'e.>target do. patterned=.1 else. normal=.1 end.
        end.
        if. patterned*.normal do. fail 'mixed implicit and normal rules' end.
        if. patterned do.
            indices=.i.0
            for_target. targets do.
                indices=.indices,#Patterns
                Patterns=:Patterns,<target,(<prerequisites),<_1
            end.
            group=.(<indices)1}group
        else.
            for_target. targets do. (>target)registerTarget prerequisites end.
            group=.(<targets)0}group
        end.
    end.
    if. hasinline do. group=.group addRecipe (<number),<inline end.
    group
)
loadBody =: 3 : 0
    conditions=.0$a:
    at=.0
    while. at<#y do.
        number=.at+1
        line=.at{::y
        at=.at+1
        Location=:'Makefile:',num number
        if. '>'={.line do.
            if. conditionsActive conditions do.
                if. -.HasGroup do. fail 'recipe commences before first target' end.
                CurrentGroup=:CurrentGroup addRecipe (<number),<trimLeft }.line
            end.
            continue.
        end.
        while. (at<#y)*.BS={:line do.
            line=.(trimRight }:line),' ',trimLeft at{::y
            at=.at+1
        end.
        text=.trim (line i.'#'){.line
        space=.text i.' '
        keyword=.space{.text
        rest=.trim (space+1)}.text
        if. (<keyword)e.;:'ifeq ifneq ifdef ifndef else endif' do.
            if. keyword-:'else' do.
                if. 0=#conditions do. fail 'extraneous ',SQ,'else',SQ end.
                entry=.>{:conditions
                if. 3{::entry do. fail 'only one ',SQ,'else',SQ,' per conditional' end.
                entry=.(<-.1{::entry)1}entry
                entry=.(<1)3}entry
                conditions=.(<entry)(<:#conditions)}conditions
            elseif. keyword-:'endif' do.
                if. 0=#conditions do. fail 'extraneous ',SQ,'endif',SQ end.
                conditions=.}:conditions
            else.
                outer=.conditionsActive conditions
                value=.0
                if. outer do. value=.keyword evaluateCondition rest end.
                conditions=.conditions,<(<outer),(<value),(<number),<0
            end.
        elseif. (#text)*.conditionsActive conditions do.
            equals=.'='outsideIndex text
            colon=.':'outsideIndex text
            if. (equals>:0)*.(colon<0)+.colon>:equals-1 do.
                equals assignVariable text
                HasGroup=:0
            elseif. colon>:0 do.
                CurrentGroup=:defineRule (<colon{.text),(<(colon+1)}.text),<number
                HasGroup=:1
            elseif. #trim expand text do. fail 'missing separator' end.
        end.
    end.
    if. #conditions do.
        Location=:'Makefile:',num 2{::>{:conditions
        fail 'missing ',SQ,'endif',SQ
    end.
)
loadMakefile =: 3 : 0
    clearMakefile''
    try.
        loadBody y
        Loaded=:1
        count=.0
        for_entry. Patterns do. count=.count+(2{::>entry)>:0 end.
        goal=.Goal
        if. 0=#goal do. goal=.'(none)' end.
        say 'Makefile loaded: lines=',(num #y),' variables=',(num #VariableNames),' targets=',(num #RuleNames),' patterns=',(num count),' goal=',goal
    catcht.
        say Location,': *** ',Reason,'.  Stop.'
        clearMakefile''
    end.
    Location=:'make'
)
resolveRule =: 3 : 0
    explicit=.(<y)e.RuleNames
    entry=.ruleEntry y
    if. explicit*.(1{::entry)>:0 do. entry,<0 return. end.
    if. -.(<y)e.Phony do.
        candidates=.i.0
        stems=.0$a:
        for_i. i.#Patterns do.
            pattern=.i{::Patterns
            if. (2{::pattern)<0 do. continue. end.
            stem=.(0{::pattern)patternStem y
            if. stem-:a: do. continue. end.
            if. 0=#stem do. continue. end.
            at=.0
            while. at<#stems do.
                if. (#at{::stems)<:#stem do. at=.at+1 else. break. end.
            end.
            candidates=.(at{.candidates),i,at}.candidates
            stems=.(at{.stems),(<stem),at}.stems
        end.
        for_i. i.#candidates do.
            pattern=.(i{candidates){::Patterns
            stem=.i{::stems
            deps=.0$a:
            usable=.1
            for_item. 1{::pattern do.
                item=.(>item)substitute stem
                deps=.deps,<item
                if. -.((<item)e.FileNames)+.(<item)e.RuleNames do. usable=.0 end.
            end.
            if. usable do.
                if. explicit do. deps=.deps,0{::entry end.
                (<~.deps),(2{pattern),(<stem),<0 return.
            end.
        end.
    end.
    if. explicit+.(<y)e.Phony do. entry,<0
    elseif. (<y)e.FileNames do. (<0$a:),(<_1),( <''),<1
    else. a: end.
)
targetTime =: 3 : 'if. (<y)e.Phony do. _1 else. fileTime y end.'
executeRecipe =: 3 : 0
    parts=.words y
    name=.0{::parts
    args=.}.parts
    select. name
    case. 'echo' do. say ' 'join args
    case. 'touch' do. for_arg. args do. giveTime >arg end.
    case. 'false' do. 1 return.
    case. 'exit' do. if. #args do. 0".0{::args else. 0 end. return.
    case. 'rm' do.
        forced=.0
        if. #args do. forced=.'-f'-:0{::args end.
        if. forced do. args=.}.args end.
        status=.0
        for_arg. args do.
            matches=.wildcardNames >arg
            if. 0=#matches do. matches=.,arg end.
            for_item. matches do.
                if. item e.FileNames do. removeFile >item
                elseif. -.forced do. say 'rm: cannot remove ',SQ,(>item),SQ,': No such file or directory'
                    status=.1 end.
            end.
        end.
        status return.
    end.
    0
)
runRecipe =: 3 : 0
    'target rule prerequisites changed'=.y
    first=.''
    if. #prerequisites do. first=.0{::prerequisites end.
    AutomaticNames=:('@';'<';'^';'?';'*')
    AutomaticValues=:(<target),(<first),(< ' 'join prerequisites),(< ' 'join changed),2{rule
    recipe=.(1{::rule){::Recipes
    expanded=.0$a:
    failed=.0
    try.
        for_line. recipe do.
            line=.>line
            Location=:'Makefile:',num 0{::line
            expanded=.expanded,<expand 1{::line
        end.
    catcht. say Location,': *** ',Reason,'.  Stop.'
        failed=.1 end.
    AutomaticNames=:AutomaticValues=:0$a:
    Location=:'make'
    if. failed do. Aborted=:1
        0 return. end.
    for_i. i.#expanded do.
        text=.i{::expanded
        start=.0
        while. start<#text do.
            if. (start{text)e.' @-' do. start=.start+1 else. break. end.
        end.
        prefix=.start{.text
        command=.trimRight start}.text
        if. 0=#command do. continue. end.
        if. ('n'e.Options)+.(-.'@'e.prefix)*.-.'s'e.Options do. say command end.
        if. 'n'e.Options do. continue. end.
        status=.executeRecipe command
        if. 0=status do. continue. end.
        location=.'Makefile:',(num 0{::i{::recipe),': ',target
        if. ('-'e.prefix)+.'i'e.Options do. say 'make: [',location,'] Error ',(num status),' (ignored)'
        else.
            say 'make: *** [',location,'] Error ',num status
            if. -.'k'e.Options do. Aborted=:1 end.
            0 return.
        end.
    end.
    1
)
buildTarget =: 4 : 0
    target=.y
    parent=.x
    at=.ResultNames i.<target
    if. at<#ResultNames do. at{::Results return. end.
    rule=.resolveRule target
    if. rule-:a: do.
        ResultNames=:ResultNames,<target
        Results=:Results,<'failure'
        message=.'make: *** No rule to make target ',SQ,target,SQ
        if. #parent do. message=.message,', needed by ',SQ,parent,SQ,'.' else. message=.message,'.' end.
        if. -.'k'e.Options do. message=.message,'  Stop.'
            Aborted=:1 end.
        say message
        'failure' return.
    end.
    ResolvedNames=:ResolvedNames,<target
    ResolvedRules=:ResolvedRules,<rule
    if. 3{::rule do.
        ResultNames=:ResultNames,<target
        Results=:Results,<'success'
        'success' return.
    end.
    Building=:Building,<target
    prerequisites=.0$a:
    failed=.0
    for_dep. 0{::rule do.
        if. dep e.Building do. say 'make: Circular ',target,' <- ',(>dep),' dependency dropped.'
            continue. end.
        prerequisites=.prerequisites,dep
        result=.target buildTarget >dep
        if. Aborted do. 'failure' return. end.
        if. -.result-:'success' do. failed=.1 end.
    end.
    Building=:Building-.<target
    result=.'success'
    if. failed do. result=.'dependency'
    else.
        timestamp=.targetTime target
        changed=.0$a:
        for_dep. prerequisites do.
            value=.targetTime >dep
            if. ('B'e.Options)+.(timestamp<0)+.(value<0)+.value>timestamp do. changed=.changed,dep end.
        end.
        if. (1{::rule)>:0 do.
            if. ('B'e.Options)+.(timestamp<0)+.0<#changed do.
                RecipeRuns=:RecipeRuns+1
                if. runRecipe (<target),(<rule),(<prerequisites),<changed do.
                    if. -.(<target)e.Phony do. giveTime target end.
                else. result=.'failure' end.
            end.
        end.
    end.
    ResultNames=:ResultNames,<target
    Results=:Results,<result
    result
)
runMake =: 3 : 0
    Options=:''
    goals=.0$a:
    for_arg. y do.
        arg=.>arg
        if. '-'~:{.arg do. goals=.goals,<arg
        else.
            for_option. }.arg do.
                if. -.option e.'nBkis' do. say 'make: invalid option -- ',SQ,option,SQ
                    return. end.
                Options=:Options,option
            end.
        end.
    end.
    if. 0=#goals do.
        if. -.Loaded do. say 'make: *** No targets specified and no makefile found.  Stop.'
            return. end.
        if. 0=#Goal do. say 'make: *** No targets.  Stop.'
            return. end.
        goals=.,<Goal
    end.
    savednames=.FileNames
    savedtimes=.FileTimes
    savedclock=.Clock
    ResultNames=:Results=:ResolvedNames=:ResolvedRules=:Building=:0$a:
    RecipeRuns=:0
    Aborted=:0
    for_goal. goals do.
        goal=.>goal
        before=.RecipeRuns
        result=.''buildTarget goal
        if. Aborted do. break. end.
        if. (result-:'success')*.before=RecipeRuns do.
            rule=.(ResolvedNames i.<goal){::ResolvedRules
            if. ((<goal)e.Phony)+.(1{::rule)<0 do. say 'make: Nothing to be done for ',SQ,goal,SQ,'.'
            else. say 'make: ',SQ,goal,SQ,' is up to date.' end.
        elseif. result-:'dependency' do. say 'make: Target ',SQ,goal,SQ,' not remade because of errors.' end.
    end.
    if. 'n'e.Options do. FileNames=:savednames
        FileTimes=:savedtimes
        Clock=:savedclock end.
)
printRule =: 3 : 0
    'target prerequisites id'=.y
    say ' 'join (<target,':'),prerequisites
    if. id>:0 do. for_line. id{::Recipes do. say '>',1{::>line end. end.
)
execute =: 3 : 0
    space=.y i.' '
    command=.space{.y
    rest=.(space+1)}.y
    select. command
    case. 'MAKE' do. runMake words rest
    case. 'TOUCH' do. for_name. words rest do. giveTime >name end.
    case. 'RM' do.
        for_name. words rest do.
            if. name e.FileNames do. removeFile >name
            else. say 'rm: cannot remove ',SQ,(>name),SQ,': No such file or directory' end.
        end.
    case. 'FILES' do.
        say 'clock ',num Clock
        for_name. /:~FileNames do. say (>name),' ',num fileTime >name end.
    case. 'VARS' do.
        try.
            for_name. /:~VariableNames do.
                entry=.(VariableNames i.name){::Variables
                if. 0{::entry do. symbol=.'=' else. symbol=.':=' end.
                value=.trim variableValue >name
                text=.(>name),' ',symbol
                if. #value do. text=.text,' ',value end.
                say text
            end.
        catcht. say 'make: *** ',Reason,'.  Stop.' end.
    case. 'RULES' do.
        for_target. /:~RuleNames do. entry=.ruleEntry >target
            printRule target,(0{entry),1{entry end.
        for_entry. Patterns do. entry=.>entry
            if. (2{::entry)>:0 do. printRule entry end.
        end.
        if. #Phony do. say ' 'join (<'.PHONY:'),/:~Phony end.
    case. 'EXPAND' do.
        try. value=.expand rest
            say '[',value,']'
        catcht. say 'make: *** ',Reason,'.  Stop.' end.
    end.
)
main =: 3 : 0
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    FileNames=:0$a:
    FileTimes=:i.0
    Clock=:0
    Scopes=:Expanding=:AutomaticNames=:AutomaticValues=:0$a:
    Location=:'make'
    clearMakefile''
    at=.1
    while. -.('END FILES'-:at{::lines) do.
        'name timestamp'=.words at{::lines
        FileNames=:FileNames,<name
        FileTimes=:FileTimes,0".timestamp
        Clock=:Clock>.0".timestamp
        at=.at+1
    end.
    at=.at+1
    while. 1 do.
        line=.at{::lines
        at=.at+1
        if. line-:'QUIT' do. break. end.
        say '$ ',line
        if. line-:'MAKEFILE' do.
            body=.0$a:
            while. -.('END MAKEFILE'-:at{::lines) do. body=.body,at{lines
                at=.at+1 end.
            at=.at+1
            loadMakefile body
        else. execute line end.
    end.
)
main''
