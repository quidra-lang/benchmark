LF =: 10{a.
Output =: 0$a:
num =: 3 : ',''0'' 8!:2 y'
emit =: 3 : 'Output=:Output,<y'
join =: 4 : '(#x)}.;(<x),&.>y'
split =: 4 : 0
    parts=.0$a:
    start=.0
    for_i. i.#y do.
        if. x=i{y do. parts=.parts,<(i-start){.start}.y
            start=.i+1 end.
    end.
    parts,<start}.y
)
fail =: 3 : 0
    Reason=:y
    throw.
)
check =: 4 : 'if. -.y do. fail x end.'
EmptyTree =: (<0$a:),<0$a:
tKeys =: 3 : '0{::y'
tValues =: 3 : '1{::y'
tHas =: 4 : '(<y)e.tKeys x'
tGet =: 4 : 0
    at=.(tKeys x)i.<y
    if. at<#tKeys x do. at{::tValues x else. a: end.
)
tPut =: 4 : 0
    'path text'=.y
    ks=.tKeys x
    vs=.tValues x
    at=.ks i.<path
    if. at=#ks do. ks=.ks,<path
        vs=.vs,<text
    else. vs=.(<text)at}vs end.
    (<ks),<vs
)
tErase =: 4 : 0
    mask=.(tKeys x)~:<y
    (<mask#tKeys x),<mask#tValues x
)
copyPath =: 4 : 0
    'source path'=.y
    if. source tHas path do. x tPut path;<source tGet path else. x tErase path end.
)
allPaths =: 3 : '/:~~.;tKeys&.>y'
agree =: 4 : 0
    'a b'=.x
    (a tGet y)-:b tGet y
)
differing =: 4 : 0
    out=.0$a:
    for_path. allPaths (<x),<y do.
        if. -. (x;<y)agree >path do. out=.out,path end.
    end.
    out
)
equalTrees =: 4 : '0=#x differing y'
changes =: 4 : 0
    out=.0$a:
    for_path. x differing y do.
        path=.>path
        if. -.x tHas path do. text=.'A ',path,': ',y tGet path
        elseif. -.y tHas path do. text=.'D ',path,': ',x tGet path
        else. text=.'M ',path,': ',(x tGet path),' -> ',y tGet path end.
        out=.out,<text
    end.
    if. #out do. out else. ,<'(no changes)' end.
)
mergeTrees =: 3 : 0
    'base ours theirs'=.y
    merged=.EmptyTree
    conflicts=.0$a:
    for_path. allPaths y do.
        path=.>path
        if. ((theirs;<base)agree path)+.(ours;<theirs)agree path do. merged=.merged copyPath (<ours),<path
        elseif. (ours;<base)agree path do. merged=.merged copyPath (<theirs),<path
        else. conflicts=.conflicts,<path
            merged=.merged copyPath (<ours),<path end.
    end.
    (<merged),<conflicts
)
globMatch =: 4 : 0
    previous=.(1+#x)$0
    previous=.1 0}previous
    for_c. y do.
        next=.(1+#x)$0
        if. c='*' do. next=.(0{previous)0}next end.
        for_i. i.#x do.
            if. c='*' do. value=.((i+1){previous)+.i{next
            else. value=.(i{previous)*.(c='?')+.c=i{x end.
            next=.value (i+1)}next
        end.
        previous=.next
    end.
    {:previous
)
head =: 3 : 'if. #Branch do. (BranchNames i.<Branch){BranchRefs else. Detached end.'
cTree =: 3 : '3{::y{::Commits'
cParents =: 3 : '2{::y{::Commits'
cId =: 3 : '0{::y{::Commits'
cMessage =: 3 : '4{::y{::Commits'
parentTree =: 3 : 'if. #cParents y do. cTree {.cParents y else. EmptyTree end.'
moveHead =: 3 : 0
    if. #Branch do. BranchRefs=:y (BranchNames i.<Branch)}BranchRefs else. Detached=:y end.
)
create =: 3 : 0
    'parents tree message'=.y
    sequence=.#Commits
    canonical=.'commit ',(num sequence),LF
    for_parent. parents do. canonical=.canonical,'parent ',(cId parent),LF end.
    for_path. /:~tKeys tree do. canonical=.canonical,'file ',(>path),' ',(tree tGet >path),LF end.
    canonical=.canonical,'message ',message,LF
    hash=.0
    for_c. a.i.canonical do. hash=.2147483647|c+131*hash end.
    id=.'0123456789abcdef'{~(8#16)#:hash
    record=.(<id),(<sequence),(<parents),(<tree),<message
    Commits=:Commits,<record
    Alive=:Alive,1
    sequence
)
resolve =: 3 : 0
    parts=.'~'split y
    anchor=.0{::parts
    number=._1
    if. anchor-:'HEAD' do. number=.head''
    elseif. (<anchor)e.BranchNames do. number=.(BranchNames i.<anchor){BranchRefs
    elseif. (<anchor)e.TagNames do. number=.(TagNames i.<anchor){TagRefs
    else.
        for_i. i.#Commits do.
            if. (i{Alive)*.anchor-:cId i do. number=.i break. end.
        end.
    end.
    ('unknown revision ''',y,'''')check number>:0
    steps=.0
    if. 2=#parts do. steps=.0".1{::parts end.
    for_i. i.steps do.
        parents=.cParents number
        ('unknown revision ''',y,'''')check 0<#parents
        number=.{.parents
    end.
    number
)
distances =: 3 : 0
    result=.(#Commits)$_1
    result=.0 y}result
    queue=.,y
    at=.0
    while. at<#queue do.
        c=.at{queue
        at=.at+1
        for_parent. cParents c do.
            if. 0>parent{result do. result=.(1+c{result)parent}result
                queue=.queue,parent end.
        end.
    end.
    result
)
ancestor =: 4 : '0<:x{distances y'
mergeBase =: 4 : 0
    a=.distances x
    b=.distances y
    common=.I.(a>:0)*.b>:0
    excluded=.(#Commits)$0
    for_c. common do. for_parent. cParents c do. excluded=.1 parent}excluded end. end.
    best=._1
    score=._1
    for_c. common do.
        if. c{excluded do. continue. end.
        value=.(c{a)>.c{b
        if. (best<0)+.(value<score)+.(value=score)*.c>best do. best=.c
            score=.value end.
    end.
    best
)
reachable =: 3 : 0
    result=.(#Commits)$0
    for_c. y do. result=.result+.0<:distances c end.
    result
)
summary =: 3 : 0
    refs=.0$a:
    if. y=head'' do.
        if. #Branch do. refs=.,<'HEAD -> ',Branch else. refs=.,<'HEAD' end.
    end.
    for_i. /:BranchNames do.
        name=.i{::BranchNames
        if. (y=i{BranchRefs)*.-.name-:Branch do. refs=.refs,<name end.
    end.
    for_i. /:TagNames do. if. y=i{TagRefs do. refs=.refs,<'tag: ',i{::TagNames end. end.
    suffix=.''
    if. #refs do. suffix=.' (',(', 'join refs),')' end.
    (cId y),suffix,' ',cMessage y
)
ignored =: 3 : 0
    if. (Index tHas y)+.(<y)e.Conflicts do. 0 return. end.
    for_pattern. Ignores do. if. y globMatch >pattern do. 1 return. end. end.
    0
)
checkProgress =: 3 : 'if. #OpKind do. fail OpKind,'' in progress'' end.'
uncommitted =: 3 : 0
    h=.cTree head''
    if. -.Index equalTrees h do. 1 return. end.
    for_path. tKeys Index do. if. -. (Work;<Index)agree >path do. 1 return. end. end.
    0
)
checkClean =: 3 : '''uncommitted changes''check -.uncommitted'''
checkOverwrite =: 3 : 0
    h=.cTree head''
    for_path. /:~~.y do.
        path=.>path
        ('local changes to ''',path,''' would be overwritten')check ((Index;<h)agree path)*.(Work;<h)agree path
    end.
)
switchTree =: 3 : 0
    selected=.(cTree head'')differing y
    checkOverwrite selected
    for_path. selected do.
        Index=:Index copyPath (<y),path
        Work=:Work copyPath (<y),path
    end.
)
recordCommit =: 3 : 0
    'parents tree message'=.y
    c=.create y
    moveHead c
    old=.cTree {.parents
    added=.modified=.deleted=.0
    for_path. allPaths (<old),<tree do.
        path=.>path
        if. -.old tHas path do. added=.added+1
        elseif. -.tree tHas path do. deleted=.deleted+1
        elseif. -. (old;<tree)agree path do. modified=.modified+1 end.
    end.
    location=.Branch
    if. 0=#location do. location=.'detached HEAD' end.
    emit '[',location,' ',(cId c),'] ',message,' (',(num added),' added, ',(num modified),' modified, ',(num deleted),' deleted)'
)
applyChange =: 3 : 0
    'base theirs kind target message parents common'=.y
    h=.cTree head''
    'merged conflicts'=.mergeTrees (<base),(<h),<theirs
    selected=.h differing merged
    checkOverwrite selected,conflicts
    if. kind-:'merge' do. emit 'Merge base ',cId common
    elseif. (0=#conflicts)*.merged equalTrees h do. emit 'nothing to commit' return. end.
    for_path. selected do.
        Index=:Index copyPath (<merged),path
        Work=:Work copyPath (<merged),path
    end.
    if. 0=#conflicts do. recordCommit (<parents),(<merged),<message return. end.
    for_path. conflicts do.
        path=.>path
        ours=.'(deleted)'
        other=.ours
        if. h tHas path do. ours=.h tGet path end.
        if. theirs tHas path do. other=.theirs tGet path end.
        Work=:Work tPut path;<'<<<<<<< ',ours,' ======= ',other,' >>>>>>>'
        emit 'CONFLICT ',path
    end.
    Conflicts=:conflicts
    OpKind=:kind
    OpTarget=:target
    if. kind-:'merge' do. emit 'Automatic merge failed; fix conflicts and then commit the result.'
    elseif. kind-:'revert' do. emit 'error: could not revert ',cId target
    else. emit 'error: could not apply ',cId target end.
)
showStatus =: 3 : 0
    h=.head''
    tree=.cTree h
    if. #Branch do. emit 'On branch ',Branch else. emit 'HEAD detached at ',cId h end.
    if. #OpKind do.
        title=.('merge';'revert';'cherry-pick')i.<OpKind
        emit (title{::'Merging';'Reverting';'Cherry-picking'),' ',cId OpTarget
    end.
    lines=.0$a:
    for_path. /:~~.(allPaths (<tree),(<Index),<Work),Conflicts do.
        path=.>path
        if. (<path)e.Conflicts do. lines=.lines,<'UU ',path
        elseif. Index tHas path do.
            x=.'A'
            if. tree tHas path do. x=.((tree;<Index)agree path){'M.' end.
            y=.'D'
            if. Work tHas path do. y=.((Work;<Index)agree path){'M.' end.
            if. -. (x,y)-:'..' do. lines=.lines,<x,y,' ',path end.
        else.
            if. tree tHas path do. lines=.lines,<'D. ',path end.
            if. Work tHas path do. if. -.ignored path do. lines=.lines,<'?? ',path end. end.
        end.
    end.
    if. #lines do. emit&>lines else. emit 'nothing to commit, working tree clean' end.
)
execute =: 3 : 0
    space=.y i.' '
    command=.space{.y
    argument=.((space+1)<.#y)}.y
    if. #argument do. args=.' 'split argument else. args=.0$a: end.
    if. (<command)e.'COMMIT';'AMEND' do. args=.,<argument
    elseif. command-:'WRITE' do.
        at=.argument i.' '
        args=.(<at{.argument),<(at+1)}.argument
    end.
    h=.head''
    tree=.cTree h
    select. command
    case. 'WRITE' do. Work=:Work tPut args
    case. 'REMOVE' do.
        path=.0{::args
        ('no such file ''',path,'''')check Work tHas path
        Work=:Work tErase path
    case. 'IGNORE' do. Ignores=:Ignores,args
    case. 'ADD' do.
        path=.0{::args
        if. path-:'ALL' do.
            selected=.0$a:
            for_p. allPaths (<Work),<Index do. if. -.ignored >p do. selected=.selected,p end. end.
            for_p. selected do. Index=:Index copyPath (<Work),p end.
            Conflicts=:0$a:
        else.
            if. Work tHas path do. ('path ''',path,''' is ignored')check -.ignored path end.
            ('pathspec ''',path,''' did not match any files')check (Work tHas path)+.(Index tHas path)+.(<path)e.Conflicts
            Index=:Index copyPath (<Work),<path
            Conflicts=:Conflicts-.<path
        end.
    case. 'RM' do.
        path=.0{::args
        ('pathspec ''',path,''' did not match any files')check Index tHas path
        Index=:Index tErase path
        Work=:Work tErase path
        Conflicts=:Conflicts-.<path
    case. 'UNSTAGE' do.
        path=.0{::args
        ('pathspec ''',path,''' did not match any files')check (Index tHas path)+.tree tHas path
        Index=:Index copyPath (<tree),<path
    case. 'RESTORE';'CAT' do.
        path=.0{::args
        if. 2=#args do. source=.cTree resolve 1{::args
        elseif. command-:'RESTORE' do. source=.Index else. source=.Work end.
        if. -.source tHas path do.
            if. 2=#args do. fail 'path ''',path,''' does not exist in ''',(1{::args),''''
            elseif. command-:'CAT' do. fail 'no such file ''',path,''''
            else. fail 'pathspec ''',path,''' did not match any files' end.
        end.
        if. command-:'CAT' do. emit source tGet path
        else.
            Work=:Work tPut path;<source tGet path
            if. 2=#args do. Index=:Index tPut path;<source tGet path
                Conflicts=:Conflicts-.<path end.
        end.
    case. 'COMMIT' do.
        'unresolved conflicts'check 0=#Conflicts
        if. OpKind-:'merge' do. recordCommit (<h,OpTarget),(<Index),<argument
            OpKind=:''
        elseif. Index equalTrees tree do. emit 'nothing to commit'
        else. recordCommit (<,h),(<Index),<argument
            OpKind=:'' end.
    case. 'AMEND' do.
        checkProgress''
        'cannot amend the root commit'check 0<#cParents h
        recordCommit (<cParents h),(<Index),<argument
    case. 'STATUS' do. showStatus''
    case. 'LS' do.
        if. #args do. target=.cTree resolve 0{::args else. target=.Work end.
        if. 0=#tKeys target do. emit '(empty)' end.
        for_path. /:~tKeys target do. emit (>path),' ',target tGet >path end.
    case. 'DIFF' do.
        if. 0=#args do.
            target=.EmptyTree
            for_path. tKeys Index do. target=.target copyPath (<Work),path end.
            emit&>Index changes target
        elseif. 'STAGED'-:0{::args do. emit&>tree changes Index
        else.
            first=.resolve 0{::args
            second=.resolve 1{::args
            emit&>(cTree first)changes cTree second
        end.
    case. 'LOG' do.
        limit=.#Commits
        if. #args do. limit=.0".0{::args end.
        c=.h
        printed=.0
        while. 1 do.
            emit summary c
            printed=.printed+1
            if. (0=#cParents c)+.printed=limit do. break. end.
            c=.{.cParents c
        end.
    case. 'SHOW' do.
        rev=.'HEAD'
        if. #args do. rev=.0{::args end.
        c=.resolve rev
        emit 'commit ',summary c
        parents=.cParents c
        if. #parents do. parenttext=.' 'join cId&.>parents else. parenttext=.'none' end.
        emit 'parents: ',parenttext
        emit&>(parentTree c)changes cTree c
    case. 'BLAME' do.
        path=.0{::args
        ('path ''',path,''' does not exist in ''HEAD''')check tree tHas path
        text=.tree tGet path
        c=.h
        while. #cParents c do.
            parent=.{.cParents c
            if. -.text-:(cTree parent)tGet path do. break. end.
            c=.parent
        end.
        emit (cId c),' (',(cMessage c),') ',text
    case. 'BRANCH';'TAG' do.
        tag=.command-:'TAG'
        remove=.'-d'-:0{::args
        name=.remove{::args
        if. tag do. names=.TagNames
            refs=.TagRefs
            noun=.'tag'
        else. names=.BranchNames
            refs=.BranchRefs
            noun=.'branch' end.
        at=.names i.<name
        if. remove do.
            ('no such ',noun,' ''',name,'''')check at<#names
            c=.at{refs
            if. -.tag do.
                ('cannot delete current branch ''',name,'''')check -.name-:Branch
                ('branch ''',name,''' is not fully merged')check c ancestor h
            end.
            names=.((i.#names)~:at)#names
            refs=.((i.#refs)~:at)#refs
            emit 'Deleted ',noun,' ',name,' (was ',(cId c),')'
        else.
            (noun,' ''',name,''' already exists')check at=#names
            rev=.'HEAD'
            if. 2=#args do. rev=.1{::args end.
            c=.resolve rev
            names=.names,<name
            refs=.refs,c
            emit 'Created ',noun,' ',name,' at ',cId c
        end.
        if. tag do. TagNames=:names
            TagRefs=:refs
        else. BranchNames=:names
            BranchRefs=:refs end.
    case. 'BRANCHES' do.
        if. 0=#Branch do. emit '* (HEAD detached at ',(cId h),')' end.
        for_i. /:BranchNames do.
            name=.i{::BranchNames
            c=.i{BranchRefs
            mark=.' '
            if. name-:Branch do. mark=.'*' end.
            emit mark,' ',name,' ',(cId c),' ',cMessage c
        end.
    case. 'TAGS' do.
        if. 0=#TagNames do. emit '(no tags)' end.
        for_i. /:TagNames do.
            c=.i{TagRefs
            emit (i{::TagNames),' ',(cId c),' ',cMessage c
        end.
    case. 'SWITCH' do.
        name=.0{::args
        ('no such branch ''',name,'''')check (<name)e.BranchNames
        if. name-:Branch do. emit 'Already on ''',name,''''
        else. checkProgress''
            switchTree cTree (BranchNames i.<name){BranchRefs
            Branch=:name
            emit 'Switched to branch ''',name,'''' end.
    case. 'DETACH' do.
        c=.resolve 0{::args
        checkProgress''
        switchTree cTree c
        Branch=:''
        Detached=:c
        emit 'HEAD is now at ',(cId c),' ',cMessage c
    case. 'MERGEBASE' do.
        first=.resolve 0{::args
        second=.resolve 1{::args
        emit cId first mergeBase second
    case. 'MERGE' do.
        c=.resolve 0{::args
        checkProgress''
        if. c ancestor h do. emit 'Already up to date'
        elseif. h ancestor c do.
            switchTree cTree c
            moveHead c
            emit 'Fast-forward ',(cId h),'..',cId c
        else.
            checkClean''
            common=.h mergeBase c
            applyChange (<cTree common),(<cTree c),(<'merge'),(<c),(<'Merge ',0{::args),(<h,c),<common
        end.
    case. 'REVERT';'CHERRYPICK' do.
        c=.resolve 0{::args
        checkProgress''
        checkClean''
        if. command-:'REVERT' do. base=.cTree c
            target=.parentTree c
            kind=.'revert'
            message=.'Revert "',(cMessage c),'"'
        else. base=.parentTree c
            target=.cTree c
            kind=.'cherry-pick'
            message=.cMessage c end.
        applyChange (<base),(<target),(<kind),(<c),(<message),(<,h),<0
    case. 'RESET' do.
        c=.resolve 1{::args
        target=.cTree c
        mode=.0{::args
        if. mode-:'HARD' do.
            for_path. /:~~.(allPaths (<Index),<target),Conflicts do. Work=:Work copyPath (<target),path end.
        end.
        if. -.mode-:'SOFT' do. Index=:target end.
        moveHead c
        Conflicts=:0$a:
        OpKind=:''
        emit 'HEAD is now at ',(cId c),' ',cMessage c
    case. 'REBASE' do.
        upstream=.resolve 0{::args
        checkProgress''
        if. upstream ancestor h do. emit 'Already up to date' return. end.
        checkClean''
        ds=.distances upstream
        replay=.i.0
        c=.h
        while. (c{ds)<0 do. replay=.replay,c
            c=.{.cParents c end.
        replay=.|.replay
        target=.cTree upstream
        plans=.0$a:
        for_c. replay do.
            'merged conflicts'=.mergeTrees (<parentTree c),(<target),<cTree c
            if. #conflicts do. fail 'could not rebase ',(cId c),': conflict in ''',(0{::conflicts),'''' end.
            if. merged equalTrees target do. plans=.plans,<a:
            else. plans=.plans,<merged
                target=.merged end.
        end.
        switchTree target
        tip=.upstream
        for_i. i.#replay do.
            c=.i{replay
            picked=.i{::plans
            if. picked-:a: do. emit 'skip ',(cId c),' ',cMessage c
            else.
                next=.create (<,tip),(<picked),<cMessage c
                emit 'pick ',(cId c),' -> ',(cId next),' ',cMessage c
                tip=.next
            end.
        end.
        moveHead tip
        emit 'HEAD is now at ',(cId tip),' ',cMessage tip
    case. 'STASH' do.
        option=.''
        if. #args do. option=.0{::args end.
        if. option-:'LIST' do.
            if. 0=#Stash do. emit '(no stash entries)' end.
            for_i. i.#Stash do. emit 'stash@{',(num i),'}: ',0{::i{::Stash end.
        elseif. (<option)e.'DROP';'POP' do.
            'no stash entries'check 0<#Stash
            entry=.0{::Stash
            label=.0{::entry
            if. option-:'POP' do.
                checkProgress''
                checkClean''
                'merged conflicts'=.mergeTrees (<cTree 1{::entry),(<tree),<2{::entry
                if. #conflicts do. fail 'stash conflict in ''',(0{::conflicts),'''' end.
                selected=.tree differing merged
                checkOverwrite selected
                for_path. selected do. Work=:Work copyPath (<merged),path end.
                Stash=:}.Stash
                emit 'Restored stash@{0}: ',label
                emit&>tree changes merged
            else. Stash=:}.Stash
                emit 'Dropped stash@{0}: ',label end.
        else.
            checkProgress''
            if. -.uncommitted'' do. emit 'No local changes to save' return. end.
            tracked=.allPaths (<Index),<tree
            saved=.EmptyTree
            for_path. tracked do. saved=.saved copyPath (<Work),path
                Work=:Work copyPath (<tree),path end.
            Index=:tree
            location=.Branch
            if. 0=#location do. location=.'(no branch)' end.
            label=.'WIP on ',location,': ',(cId h),' ',cMessage h
            entry=.(<label),(<h),<saved
            Stash=.(<entry),Stash
            emit 'Saved stash@{0}: ',label
        end.
    case. 'DESCRIBE' do.
        rev=.'HEAD'
        if. #args do. rev=.0{::args end.
        c=.resolve rev
        ds=.distances c
        best=.''
        distance=.0
        for_i. /:TagNames do.
            target=.i{TagRefs
            d=.target{ds
            if. d>:0 do.
                if. (0=#best)+.d<distance do. best=.i{::TagNames
                    distance=.d end.
            end.
        end.
        ('no tag can describe ''',(cId c),'''')check 0<#best
        if. distance=0 do. emit best else. emit best,'-',(num distance),'-g',cId c end.
    case. 'GRAPH';'GC' do.
        roots=.h,BranchRefs,TagRefs
        if. command-:'GC' do.
            for_entry. Stash do. roots=.roots,1{::>entry end.
            if. #OpKind do. roots=.roots,OpTarget end.
            kept=.reachable roots
            removed=.+/Alive*.-.kept
            Alive=:Alive*.kept
            emit 'Removed unreachable commits: ',num removed
        else.
            kept=.reachable roots
            lanes=.i.0
            for_c. |.I.kept do.
                if. -.c e.lanes do. lanes=.lanes,c end.
                at=.lanes i.c
                symbols=.'|'#~#lanes
                symbols=.'/' (I.lanes=c)}symbols
                symbols=.'*' at}symbols
                emit (' 'join <"0 symbols),' ',summary c
                lanes=.lanes#~((i.#lanes)=at)+.lanes~:c
                parents=.cParents c
                if. 0=#parents do. lanes=.((i.#lanes)~:at)#lanes
                else.
                    lanes=.({.parents)at}lanes
                    if. 2=#parents do.
                        if. -.(1{parents)e.lanes do. lanes=.((at+1){.lanes),(1{parents),(at+1)}.lanes end.
                    end.
                end.
            end.
        end.
    end.
)
main =: 3 : 0
    Commits=:0$a:
    Alive=:i.0
    Branch=:'main'
    Detached=:0
    BranchNames=:,<'main'
    BranchRefs=:,0
    TagNames=:0$a:
    TagRefs=:i.0
    Work=:Index=:EmptyTree
    Conflicts=:Stash=:Ignores=:0$a:
    OpKind=:''
    OpTarget=:0
    root=.create (<i.0),(<EmptyTree),<'init'
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    for_line. lines do.
        line=.>line
        if. line-:'EXIT' do. break. end.
        try. execute line catcht. emit 'error: ',Reason end.
    end.
    if. #Output do. 1!:2&2 ;Output,&.><LF end.
)
main''
