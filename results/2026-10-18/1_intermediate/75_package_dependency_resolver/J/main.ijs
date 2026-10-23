LF =: 10{a.
SQ =: 39{a.
num =: 3 : ',''0'' 8!:2 y'
join =: 4 : '(#x)}.;(<x),&.>y'
fail =: 3 : 0
    Reason=:y
    throw.
)
check =: 4 : 'if. -.y do. fail x end.'
split =: 4 : 0
    x=.,x
    result=.0$a:
    at=.0
    start=.0
    while. at<:#y do.
        if. ((at+#x)<:#y)*.x-:(#x){.at}.y do.
            result=.result,<(at-start){.start}.y
            at=.at+#x
            start=.at
        else. at=.at+1 end.
    end.
    result,<start}.y
)
numberPart =: 3 : 0
    if. (0=#y)+.(#y)>4 do. 0 return. end.
    if. -. *./y e.'0123456789' do. 0 return. end.
    (1=#y)+.'0'~:{.y
)
numericText =: 3 : '(0<#y)*.*./y e.''0123456789'''
parseVersion =: 3 : 0
    halves=.'-'split y
    if. (#halves)>2 do. a: return. end.
    parts=.'.'split 0{::halves
    if. 3~:#parts do. a: return. end.
    if. -. *./numberPart&>parts do. a: return. end.
    pre=.0$a:
    if. 2=#halves do.
        pre=.'.'split 1{::halves
        for_item. pre do.
            item=.>item
            if. 0=#item do. a: return. end.
            if. -. *./item e.'0123456789abcdefghijklmnopqrstuvwxyz' do. a: return. end.
            if. numericText item do. if. -.numberPart item do. a: return. end. end.
        end.
    end.
    (<0".&>parts),<pre
)
versionText =: 3 : 0
    text=.'.'join num&.>0{::y
    if. #1{::y do. text=.text,'-','.'join 1{::y end.
    text
)
compareVersions =: 4 : 0
    a=.0{::x
    b=.0{::y
    for_i. i.3 do.
        if. (i{a)~:i{b do. (_1 1){~(i{a)>i{b return. end.
    end.
    a=.1{::x
    b=.1{::y
    if. (0=#a)~:0=#b do. (_1 1){~0=#a return. end.
    for_i. i.(#a)<.#b do.
        first=.i{::a
        second=.i{::b
        if. first-:second do. continue. end.
        an=.numericText first
        bn=.numericText second
        if. an~:bn do. (_1 1){~-.an return. end.
        if. an do. (_1 1){~(0".first)>0".second return. end.
        if. 0={./:first;second do. _1 else. 1 end. return.
    end.
    (*(#a)-#b)
)
upperVersion =: 4 : 0
    core=.0{::x
    core=.(1+y{core)y}core
    for_i. (y+1)+i.2-y do. core=.0 i}core end.
    (<core),<0$a:
)
parseTerm =: 3 : 0
    op=.''
    pattern=.y
    for_symbol. '>=';'<=';'>';'<';'=';'^';'~' do.
        symbol=.>symbol
        if. (,symbol)-:(#symbol){.y do. op=.symbol
            pattern=.(#symbol)}.y
            break. end.
    end.
    value=.parseVersion pattern
    lower=.(<0 0 0),<0$a:
    count=.0
    cores=.0$a:
    if. -.value-:a: do.
        if. #1{::value do. lower=.value
            count=.3
            cores=.,<0{::value end.
    end.
    if. 0=count do.
        parts=.'.'split pattern
        if. (#parts)>3 do. a: return. end.
        wildcard=.0
        core=.0 0 0
        for_part. parts do.
            part=.>part
            if. (numberPart part)*.-.wildcard do. core=.(0".part)count}core
                count=.count+1
            elseif. (<part)e.(<,'x'),<,'*' do. wildcard=.1
            else. a: return. end.
        end.
        lower=.(<core),<0$a:
    end.
    comparisons=.0$a:
    if. 0=count do.
        if. (<op)e.'>'; '<' do.
            bound=.(<0 0 0),<,<'0'
            comparisons=.,<((<'<'),<bound)
        end.
    elseif. (<op)e.'';'=' do.
        if. 3=count do. comparisons=.,<((<'='),<lower)
        else. comparisons=.(<((<'>='),<lower)),<((<'<'),<lower upperVersion count-1) end.
    elseif. op-:'>' do.
        if. 3=count do. comparisons=.,<((<'>'),<lower)
        else. comparisons=.,<((<'>='),<lower upperVersion count-1) end.
    elseif. op-:'<=' do.
        if. 3=count do. comparisons=.,<((<'<='),<lower)
        else. comparisons=.,<((<'<'),<lower upperVersion count-1) end.
    elseif. (<op)e.'>=';'<' do. comparisons=.,<((<op),<lower)
    else.
        core=.0{::lower
        if. op-:'~' do. index=.1~:count
        elseif. (0~:0{core)+.count=1 do. index=.0
        elseif. (0~:1{core)+.count=2 do. index=.1
        else. index=.2 end.
        comparisons=.(<((<'>='),<lower)),<((<'<'),<lower upperVersion index)
    end.
    (<comparisons),<cores
)
parseConstraint =: 3 : 0
    alternatives=.0$a:
    for_part. ' || 'split y do.
        comparisons=.0$a:
        cores=.0$a:
        for_term. ' 'split >part do.
            parsed=.parseTerm >term
            if. parsed-:a: do. a: return. end.
            comparisons=.comparisons,0{::parsed
            cores=.cores,1{::parsed
        end.
        alternatives=.alternatives,<(<comparisons),<cores
    end.
    (<y),<alternatives
)
allows =: 4 : 0
    for_alt. 1{::x do.
        alt=.>alt
        if. #1{::y do. if. -.(<0{::y)e.1{::alt do. continue. end. end.
        accepted=.1
        for_comparison. 0{::alt do.
            comparison=.>comparison
            op=.0{::comparison
            cmp=.y compareVersions 1{::comparison
            select. op
            case. '=' do. good=.cmp=0
            case. '>' do. good=.cmp>0
            case. '>=' do. good=.cmp>:0
            case. '<' do. good=.cmp<0
            case. '<=' do. good=.cmp<:0
            end.
            if. -.good do. accepted=.0 break. end.
        end.
        if. accepted do. 1 return. end.
    end.
    0
)
normalForm =: 3 : 0
    alternatives=.0$a:
    for_alt. 1{::y do.
        parts=.0$a:
        for_comparison. 0{::>alt do. comparison=.>comparison
            parts=.parts,<(0{::comparison),versionText 1{::comparison end.
        if. #parts do. text=.' 'join parts else. text=.'*' end.
        alternatives=.alternatives,<text
    end.
    ' || 'join alternatives
)
requireVersion =: 3 : 0
    result=.parseVersion y
    ('invalid version ',SQ,y,SQ)check -.result-:a:
    result
)
requireConstraint =: 3 : 0
    result=.parseConstraint y
    ('invalid constraint ',SQ,y,SQ)check -.result-:a:
    result
)
knownNames =: 3 : 0
    names=.0$a:
    for_item. Registry do. names=.names,<0{::>item end.
    /:~~.names
)
newest =: 3 : 0
    result=.i.0
    for_i. i.#Registry do.
        item=.i{::Registry
        if. -.y-:0{::item do. continue. end.
        at=.0
        while. at<#result do.
            if. 0>(2{::item)compareVersions 2{::(at{result){::Registry do. at=.at+1 else. break. end.
        end.
        result=.(at{.result),i,at}.result
    end.
    result
)
indexFor =: 4 : 0
    at=.(0{::x)i.<y
    if. at=#0{::x do. _1 else. at{1{::x end.
)
installedIndex =: 3 : 'Installed indexFor y'
requireInstalled =: 3 : 0
    index=.installedIndex y
    (y,' is not installed')check index>:0
    index
)
findRelease =: 4 : 0
    for_i. i.#Registry do.
        item=.i{::Registry
        if. ((0{::item)-:x)*.(1{::item)-:y do. i return. end.
    end.
    fail x,'@',y,' is not registered'
)
advisoryIds =: 3 : 0
    item=.y{::Registry
    result=.0$a:
    for_at. /:AdvisoryNames do.
        'name constraint'=.at{::Advisories
        if. name-:0{::item do.
            if. constraint allows 2{::item do. result=.result,at{AdvisoryNames end.
        end.
    end.
    result
)
displayRelease =: 3 : 0
    item=.y{::Registry
    notes=.0$a:
    if. 5{::item do. notes=.notes,<'yanked' end.
    if. y=installedIndex 0{::item do. notes=.notes,<'installed' end.
    text=.(0{::item),'@',1{::item
    if. #notes do. text=.text,' (',(', 'join notes),')' end.
    text
)
dependencyNames =: 4 : 0
    item=.(x indexFor y){::Registry
    names=.0$a:
    for_link. 3{::item do. names=.names,<0{::>link end.
    names
)
usable =: 3 : 0
    item=.y{::Registry
    if. (5{::item)*.y~:installedIndex 0{::item do. 0 return. end.
    if. AuditMode do. if. #advisoryIds y do. 0 return. end. end.
    1
)
recordFailure =: 3 : 0
    'chain reason culprit'=.y
    if. (#SelectionNames)>FailureSize do.
        FailureSize=:#SelectionNames
        Failure=: (<'UNSATISFIABLE'),((<'  '),&.>chain),<'  ',reason
        if. #culprit do.
            old=.(SelectionNames i.<culprit){::SelectionChains
            Failure=:Failure,(<'    '),&.>old
        end.
    end.
    0
)
search =: 3 : 0
    if. 0=#y do. 1 return. end.
    'link chain'=.0{::y
    'name constraint'=.link
    rest=.}.y
    at=.SelectionNames i.<name
    if. at<#SelectionNames do.
        item=.(at{SelectionIDs){::Registry
        if. constraint allows 2{::item do. search rest return. end.
        recordFailure (<chain),(<name,'@',(1{::item),' was selected by:'),<name return.
    end.
    if. (<name)e.Held do.
        index=.installedIndex name
        item=.index{::Registry
        if. (-.constraint allows 2{::item)+.-.usable index do.
            recordFailure (<chain),(<name,'@',(1{::item),' is held'),<'' return.
        end.
        candidates=.,index
    else.
        candidates=.i.0
        for_index. newest name do.
            if. (constraint allows 2{::index{::Registry)*.usable index do. candidates=.candidates,index end.
        end.
        previous=.installedIndex name
        if. ((<name)e.Preferred)*.previous e.candidates do. candidates=.previous,candidates-.previous end.
        if. 0=#candidates do. recordFailure (<chain),(< 'no version of ',name,' matches ',0{::constraint),<'' return. end.
    end.
    for_index. candidates do.
        item=.index{::Registry
        culprit=.''
        for_other. /:~SelectionNames do.
            old=.(SelectionIDs{~SelectionNames i.other){::Registry
            conflict=.0
            for_decl. 4{::item do.
                'target condition'=.>decl
                if. target-:>other do. if. condition allows 2{::old do. conflict=.1 end. end.
            end.
            for_decl. 4{::old do.
                'target condition'=.>decl
                if. target-:name do. if. condition allows 2{::item do. conflict=.1 end. end.
            end.
            if. conflict do. culprit=.>other break. end.
        end.
        if. #culprit do.
            old=.(SelectionIDs{~SelectionNames i.<culprit){::Registry
            recordFailure (<chain),(<name,'@',(1{::item),' conflicts with ',culprit,'@',(1{::old),', which was selected by:'),<culprit
            continue.
        end.
        SelectionNames=:SelectionNames,<name
        SelectionIDs=:SelectionIDs,index
        SelectionChains=:SelectionChains,<chain
        following=.0$a:
        for_dep. 3{::item do.
            dep=.>dep
            nextchain=.chain, <name,'@',(1{::item),' requires ',(0{::dep),' ',0{::1{::dep
            following=.following,<(<dep),<nextchain
        end.
        if. search following,rest do. 1 return. end.
        SelectionNames=:}:SelectionNames
        SelectionIDs=:}:SelectionIDs
        SelectionChains=:}:SelectionChains
    end.
    0
)
plan =: 3 : 0
    lines=.0$a:
    counts=.4$0
    pending=./:~0{::y
    while. #pending do.
        chosen=.''
        for_name. pending do.
            if. -. +./(y dependencyNames >name)e.pending do. chosen=.>name break. end.
        end.
        pending=.pending-.<chosen
        index=.y indexFor chosen
        item=.index{::Registry
        old=.installedIndex chosen
        if. old<0 do. lines=.lines,<'install ',chosen,'@',1{::item
            counts=.(1+0{counts)0}counts
        elseif. old~:index do.
            previous=.old{::Registry
            if. 0<(2{::item)compareVersions 2{::previous do. word=.'upgrade'
                column=.1
            else. word=.'downgrade'
                column=.2 end.
            lines=.lines,<word,' ',chosen,' ',(1{::previous),' -> ',1{::item
            counts=.(1+column{counts)column}counts
        end.
    end.
    pending=./:~(0{::Installed)-.0{::y
    while. #pending do.
        chosen=.''
        for_name. pending do.
            ready=.1
            for_other. pending do.
                if. name e.Installed dependencyNames >other do. ready=.0 break. end.
            end.
            if. ready do. chosen=.>name break. end.
        end.
        pending=.pending-.<chosen
        lines=.lines,<'remove ',chosen,'@',1{::(installedIndex chosen){::Registry
        counts=.(1+3{counts)3}counts
    end.
    if. 0=#lines do. ,<'no changes' return. end.
    lines,<(num 0{counts),' installed, ',(num 1{counts),' upgraded, ',(num 2{counts),' downgraded, ',(num 3{counts),' removed'
)
updateState =: 4 : 0
    History=:History,<(<Requests),<Installed
    Requests=:x
    Installed=:y
    Held=:Held#~Held e.0{::Installed
)
resolveRequests =: 4 : 0
    'preferred audit apply'=.y
    Preferred=:preferred
    AuditMode=:audit
    SelectionNames=:SelectionChains=:0$a:
    SelectionIDs=:i.0
    FailureSize=:_1
    Failure=:0$a:
    pending=.0$a:
    for_link. x do.
        link=.>link
        chain=.,<'requested ',(0{::link),' ',0{::1{::link
        pending=.pending,<(<link),<chain
    end.
    if. -.search pending do. Failure return. end.
    installation=.(<SelectionNames),<SelectionIDs
    lines=.plan installation
    if. apply do. x updateState installation end.
    lines
)
firstDependent =: 3 : 0
    for_name. /:~0{::Installed do.
        if. (<y)e.Installed dependencyNames >name do. >name return. end.
    end.
    ''
)
reachable =: 3 : 0
    found=.0$a:
    queue=.y
    at=.0
    while. at<#queue do.
        name=.at{::queue
        at=.at+1
        if. -.(<name)e.found do. found=.found,<name
            queue=.queue,Installed dependencyNames name end.
    end.
    found
)
treeBranch =: 3 : 0
    'name constraint prefix indent'=.y
    item=.(installedIndex name){::Registry
    body=.prefix,name,'@',1{::item
    if. #constraint do. body=.body,' [',constraint,']' end.
    if. (<name)e.Shown do. ,<body,' (*)' return. end.
    Shown=:Shown,<name
    lines=.,<body
    deps=.3{::item
    for_i. i.#deps do.
        dep=.i{::deps
        if. i=<:#deps do. branch=.'`-- '
            extension=.'    '
        else. branch=.'|-- '
            extension=.'|   ' end.
        lines=.lines,treeBranch (0{dep),(<0{::1{::dep),(<indent,branch),<indent,extension
    end.
    lines
)
execute =: 3 : 0
    words=.' 'split y
    command=.0{::words
    args=.}.words
    rest=.' 'join args
    name=.''
    if. #args do. name=.0{::args end.
    lines=.0$a:
    select. command
    case. 'PKG' do.
        clauses=.'; 'split rest
        head=.' 'split 0{::clauses
        text=.1{::head
        value=.requireVersion text
        for_item. Registry do.
            item=.>item
            (name,'@',text,' is already registered')check -.((0{::item)-:name)*.(1{::item)-:text
        end.
        deps=.conflicts=.0$a:
        for_clause. }.clauses do.
            parts=.' 'split >clause
            condition=.requireConstraint ' 'join 2}.parts
            link=.(1{parts),<condition
            if. 'DEP'-:0{::parts do. deps=.deps,<link else. conflicts=.conflicts,<link end.
        end.
        item=.(<name),(<text),(<value),(<deps),(<conflicts),<0
        Registry=:Registry,<item
        ,<'registered ',name,'@',text
    case. 'YANK';'INFO' do.
        text=.1{::args
        index=.name findRelease text
        item=.index{::Registry
        if. command-:'YANK' do.
            (name,'@',text,' is already yanked')check -.5{::item
            Registry=:(<(<1)5}item)index}Registry
            ,<'yanked ',name,'@',text return.
        end.
        lines=.,<displayRelease index
        for_dep. 3{::item do. dep=.>dep
            lines=.lines,<'  requires ',(0{::dep),' ',0{::1{::dep end.
        for_dep. 4{::item do. dep=.>dep
            lines=.lines,<'  conflicts with ',(0{::dep),' ',0{::1{::dep end.
        for_identifier. advisoryIds index do. lines=.lines,<'  advisory ',>identifier end.
        lines
    case. 'VERSIONS' do.
        filtered=.1<#args
        constraint=.requireConstraint '*'
        if. filtered do. constraint=.requireConstraint ' 'join }.args end.
        ('unknown package ',name)check (<name)e.knownNames''
        for_index. newest name do.
            if. -.filtered do. lines=.lines,<displayRelease index
            elseif. constraint allows 2{::index{::Registry do. lines=.lines,<displayRelease index end.
        end.
        if. #lines do. lines else. ,<'no matching versions' end.
    case. 'DEPENDENTS' do.
        filtered=.1<#args
        value=.requireVersion '0.0.0'
        if. filtered do. value=.requireVersion 1{::args end.
        for_other. knownNames'' do.
            for_index. newest >other do.
                item=.index{::Registry
                for_dep. 3{::item do.
                    dep=.>dep
                    if. -.name-:0{::dep do. continue. end.
                    accepted=.1
                    if. filtered do. accepted=.(1{::dep)allows value end.
                    if. accepted do. lines=.lines,<(>other),'@',(1{::item),' requires ',name,' ',0{::1{::dep end.
                end.
            end.
        end.
        if. #lines do. lines else. ,<'no dependents' end.
    case. 'COMPARE' do.
        first=.requireVersion name
        second=.requireVersion 1{::args
        cmp=.first compareVersions second
        symbol=.(1+*cmp){::'<';'=';'>'
        ,<name,' ',symbol,' ',1{::args
    case. 'MATCH' do.
        value=.requireVersion name
        constraint=.requireConstraint ' 'join }.args
        if. constraint allows value do. ,<'yes' else. ,<'no' end.
    case. 'RANGE' do. ,<normalForm requireConstraint rest
    case. 'INSTALL';'SIMULATE' do.
        text=.'*'
        if. 1<#args do. text=.' 'join }.args end.
        constraint=.requireConstraint text
        ('unknown package ',name)check (<name)e.knownNames''
        requests=.Requests
        at=.#requests
        for_i. i.#requests do. if. name-:0{::i{::requests do. at=.i break. end. end.
        link=.(<name),<constraint
        if. at=#requests do. requests=.requests,<link else. requests=.(<link)at}requests end.
        requests resolveRequests (<0{::Installed),(<0),<command-:'INSTALL'
    case. 'REMOVE' do.
        requested=.0
        requests=.0$a:
        for_link. Requests do. link=.>link
            if. name-:0{::link do. requested=.1 else. requests=.requests,<link end.
        end.
        if. -.requested do.
            if. (installedIndex name)>:0 do. fail name,' is required by ',firstDependent name end.
            fail name,' is not installed'
        end.
        roots=.0$a:
        for_link. requests do. roots=.roots,<0{::>link end.
        kept=.reachable roots
        if. (<name)e.kept do.
            lines=.,<name,'@',(1{::(installedIndex name){::Registry),' is still required by ',firstDependent name
            installation=.Installed
        else.
            mask=.(0{::Installed)e.kept
            installation=.(<mask#0{::Installed),<mask#1{::Installed
            lines=.plan installation
        end.
        requests updateState installation
        lines
    case. 'UPGRADE' do.
        preferred=.0$a:
        if. #name do. requireInstalled name
            preferred=.(0{::Installed)-.<name end.
        Requests resolveRequests (<preferred),(<0),<1
    case. 'ROLLBACK' do.
        'nothing to roll back'check 0<#History
        'requests installation'=.>{:History
        lines=.plan installation
        History=:}:History
        Requests=:requests
        Installed=:installation
        Held=:Held#~Held e.0{::Installed
        lines
    case. 'HOLD' do.
        index=.requireInstalled name
        (name,' is already held')check -.(<name)e.Held
        Held=:Held,<name
        ,<'held ',name,'@',1{::index{::Registry
    case. 'UNHOLD' do.
        (name,' is not held')check (<name)e.Held
        Held=:Held-.<name
        ,<'released ',name
    case. 'WHY' do.
        index=.requireInstalled name
        roots=.0$a:
        for_link. Requests do. roots=.roots,<0{::>link end.
        if. (<name)e.roots do. ,<name,'@',(1{::index{::Registry),' is explicitly installed' return. end.
        queue=./:~roots
        parents=.(#queue)$<''
        at=.0
        while. at<#queue do.
            current=.at{::queue
            at=.at+1
            for_dep. /:~Installed dependencyNames current do.
                if. -.dep e.queue do. queue=.queue,dep
                    parents=.parents,<current end.
            end.
        end.
        path=.,<name
        current=.name
        while. 1 do.
            parent=.(queue i.<current){::parents
            if. 0=#parent do. break. end.
            path=.path,<parent
            current=.parent
        end.
        entries=.0$a:
        for_other. |.path do. entries=.entries,<(>other),'@',1{::(installedIndex >other){::Registry end.
        ,<' -> 'join entries
    case. 'TREE' do.
        roots=.0$a:
        if. #name do. requireInstalled name
            roots=.,<name
        else.
            for_link. Requests do. roots=.roots,<0{::>link end.
            roots=./:~roots
        end.
        Shown=:0$a:
        for_root. roots do.
            constraint=.''
            for_link. Requests do. link=.>link
                if. root-:0{link do. constraint=.0{::1{::link end.
            end.
            lines=.lines,treeBranch root,(<constraint),(<''),<''
        end.
        if. #lines do. lines else. ,<'(empty)' end.
    case. 'OUTDATED' do.
        for_other. /:~0{::Installed do.
            other=.>other
            current=.installedIndex other
            constraints=.0$a:
            for_link. Requests do. link=.>link
                if. other-:0{::link do. constraints=.constraints,1{link end.
            end.
            for_index. 1{::Installed do.
                for_dep. 3{::index{::Registry do. dep=.>dep
                    if. other-:0{::dep do. constraints=.constraints,1{dep end.
                end.
            end.
            wanted=.current
            wantedset=.0
            latest=._1
            for_index. newest other do.
                item=.index{::Registry
                accepted=.(-.5{::item)+.index=current
                for_condition. constraints do.
                    if. -.(>condition)allows 2{::item do. accepted=.0 end.
                end.
                if. accepted*.-.wantedset do. wanted=.index
                    wantedset=.1 end.
                if. latest<0 do.
                    if. (0=#1{::2{::item)*.-.5{::item do. latest=.index end.
                end.
            end.
            show=.wanted~:current
            latesttext=.'-'
            if. latest>:0 do.
                latesttext=.1{::latest{::Registry
                show=.show+.0<(2{::latest{::Registry)compareVersions 2{::current{::Registry
            end.
            if. show do. lines=.lines,<other,' ',(1{::current{::Registry),' ',(1{::wanted{::Registry),' ',latesttext end.
        end.
        if. #lines do. lines else. ,<'all packages are up to date' end.
    case. 'LOCK' do.
        for_other. /:~0{::Installed do. lines=.lines,<(>other),'@',1{::(installedIndex >other){::Registry end.
        if. #lines do. lines else. ,<'(empty)' end.
    case. 'STATUS' do.
        for_link. Requests do. link=.>link
            lines=.lines,<(0{::link),' ',(0{::1{::link),' -> ',1{::(installedIndex 0{::link){::Registry end.
        if. 0=#lines do. lines=.,<'no requests' end.
        lines,<(num #0{::Installed),' installed, ',(num #Held),' held, ',(num #History),' snapshots'
    case. 'ADVISORY' do.
        ('advisory ',name,' already exists')check -.(<name)e.AdvisoryNames
        constraint=.requireConstraint ' 'join 2}.args
        AdvisoryNames=:AdvisoryNames,<name
        Advisories=:Advisories,<(1{args),<constraint
        ,<'advisory ',name,' recorded'
    case. 'AUDIT' do.
        if. name-:'FIX' do. Requests resolveRequests (<0{::Installed),(<1),<1 return. end.
        for_other. /:~0{::Installed do.
            current=.installedIndex >other
            ids=.advisoryIds current
            if. 0=#ids do. continue. end.
            fix=.'no fix'
            for_index. |.newest >other do.
                item=.index{::Registry
                if. (0<(2{::item)compareVersions 2{::current{::Registry)*.(0=#1{::2{::item)*.-.5{::item do.
                    if. 0=#advisoryIds index do. fix=.'fix: ',1{::item break. end.
                end.
            end.
            lines=.lines,<(>other),'@',(1{::current{::Registry),': ',(', 'join ids),' (',fix,')'
        end.
        if. #lines do. lines else. ,<'no known vulnerabilities' end.
    end.
)
main =: 3 : 0
    Registry=:Requests=:Held=:History=:AdvisoryNames=:Advisories=:0$a:
    Installed=:(<0$a:),<i.0
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    count=.0".0{::lines
    for_i. i.count do.
        try. output=.execute (i+1){::lines
        catcht. output=.,<'error: ',Reason end.
        1!:2&2 ;output,&.><LF
    end.
)
main''
