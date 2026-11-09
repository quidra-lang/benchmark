LF =: 10{a.
num =: 3 : ',''0'' 8!:2 y'
eq =: 4 : '(,x)-:,y'
split =: 4 : '<;._1 x,y'
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
words =: 3 : 0
    result =. 0$a:
    for_v. y do.
        v =. >v
        if. 2 ~: 3!:0 v do. v =. num v end.
        result =. result,<,v
    end.
    ' ' join result
)
emit =: 3 : 'Output =: Output,<y'
say =: 3 : 'emit words y'
vec =: 3 : '''('',('','' join num each <"0 y),'')'''
pname =: 3 : '''P'',num y'
pnames =: 3 : ''' '' join pname each <"0 y'
fits =: 4 : '*./x<:y'
zero =: 3 : '*./0=y'
fail =: 3 : 0
    emit 'error: ',y
    throw.
)
Kinds =: ;:'granted blocked unblocked released finished aborted cancelled'
Mode =: 'AVOID'
Policy =: 'ALLOC'
Trace =: 0
Auto =: 0
SnapNames =: 0$a:
Snapshots =: 0$a:
Output =: 0$a:
Total =: i.0
Avail =: i.0
Exists =: 100#0
Max =: Alloc =: 100 0$0
Born =: 100#0
Queue =: History =: 0$a:
blocked =: 3 : 0
    for_q. Queue do.
        if. y=0{::>q do. 1 return. end.
    end.
    0
)
request =: 3 : 0
    for_q. Queue do.
        if. y=0{::>q do. 1{::>q return. end.
    end.
    (#Total)#0
)
need =: 3 : '(y{Max)-y{Alloc'
save =: 3 : 'Total;Avail;Exists;Max;Alloc;Born;Queue;<History'
restore =: 3 : 0
    'Total Avail Exists Max Alloc Born Queue History' =: y
)
record =: 3 : 0
    'kind id v wait' =. y
    History =: History,<Time;kind;id;v;wait
)
check =: 3 : 0
    'detect verbose' =. y
    work =. Avail
    ids =. I.Exists
    idle =. i.0
    if. detect do. idle =. ids#~zero"1 ids{Alloc end.
    remaining =. ids-.idle
    sequence =. i.0
    tag =. '[safety]'
    if. detect do. tag =. '[detect]' end.
    if. verbose do.
        text =. tag,' start work=',vec work
        if. #idle do. text =. text,' idle ',pnames idle end.
        emit text
    end.
    while. 1 do.
        chosen =. _1
        for_p. remaining do.
            if. detect do. v =. request p else. v =. need p end.
            if. v fits work do. chosen =. p break. end.
        end.
        if. chosen=_1 do. break. end.
        work =. work+chosen{Alloc
        sequence =. sequence,chosen
        remaining =. remaining-.chosen
        if. verbose do. emit tag,' ',(pname chosen),' can finish, work=',vec work end.
    end.
    if. verbose *. 0<#remaining do.
        emit tag,' stuck work=',(vec work),' remaining ',pnames remaining
    end.
    sequence;remaining
)
decide =: 3 : 0
    'id v reject verbose' =. y
    reason =. ''
    if. reject do.
        if. blocked id do. reason =. 'process ',(pname id),' is blocked'
        elseif. zero v do. reason =. 'zero vector'
        elseif. -.v fits need id do. reason =. 'request exceeds need'
        elseif. ('ORDER' eq Mode) *. -.zero id{Alloc do.
            last =. >./I.0<id{Alloc
            if. +./(v>0)*.(i.#v)<:last do. reason =. 'resource order violation' end.
        end.
    end.
    if. #reason do. 'rejected';reason;i.0 return. end.
    if. -.v fits Avail do. 'blocked';'insufficient resources';i.0 return. end.
    sequence =. i.0
    if. 'AVOID' eq Mode do.
        Alloc =: ((id{Alloc)+v) id}Alloc
        Avail =: Avail-v
        'sequence remaining' =. check 0,verbose
        Alloc =: ((id{Alloc)-v) id}Alloc
        Avail =: Avail+v
        if. #remaining do. 'blocked';'unsafe state';sequence return. end.
    end.
    'granted';'';sequence
)
allocate =: 3 : 0
    'id v' =. y
    Alloc =: ((id{Alloc)+v) id}Alloc
    Avail =: Avail-v
)
dequeue =: 3 : 0
    kept =. 0$a:
    for_q. Queue do.
        if. y~:0{::>q do. kept =. kept,q end.
    end.
    Queue =: kept
)
retry =: 3 : 0
    pending =. Queue
    for_q. pending do.
        'id v since' =. >q
        d =. decide id;v;0;Trace
        if. 'granted' eq 0{::d do.
            allocate id;v
            dequeue id
            say 'unblocked';(pname id);vec v
            record 'unblocked';id;v;Time-since
        end.
    end.
)
terminate =: 3 : 0
    'id kind retries' =. y
    v =. id{Alloc
    Avail =: Avail+v
    Exists =: 0 id}Exists
    Alloc =: ((#Total)#0) id}Alloc
    dequeue id
    say kind;(pname id);'released';vec v
    record kind;id;v;0
    if. retries do. retry'' end.
)
sequenceWalk =: 3 : 0
    'rest work path' =. y
    if. 0=#rest do.
        SeqCount =: >:SeqCount
        if. (#SeqFirst)<SeqLimit do. SeqFirst =: SeqFirst,<path end.
        return.
    end.
    for_p. rest do.
        if. (need p) fits work do. sequenceWalk (rest-.p);(work+p{Alloc);path,p end.
    end.
)
cycleWalk =: 3 : 0
    'start p path seen resource' =. y
    for_e. Edges do.
        'from to label' =. >e
        if. from~:p do. continue. end.
        next =. path
        if. resource do. next =. next,label end.
        next =. next,to
        if. to=start do. Cycles =: Cycles,<next
        elseif. (to>start) *. -.to e.seen do. cycleWalk start;to;next;(seen,to);resource
        end.
    end.
)
printCycles =: 3 : 0
    resource =. y
    Cycles =: 0$a:
    for_p. I.Exists do. cycleWalk p;p;(,p);(,p);resource end.
    Cycles =: /:~Cycles
    if. 0=#Cycles do. emit 'no cycles' return. end.
    for_c. Cycles do.
        elements =. 0$a:
        path =. >c
        for_i. i.#path do.
            if. resource *. 2|i do. elements =. elements,<,((65+i{path){a.)
            else. elements =. elements,<pname i{path end.
        end.
        emit 'cycle: ',' -> ' join elements
    end.
)
fixed =: 4 : 0
    'den digits' =. y
    scale =. 10^digits
    q =. <.(scale*x)%den
    (num <.q%scale),'.',(-digits){.(digits#'0'),num scale|q
)
padLeft =: 4 : '(-x){.(x#'' ''),y'
padRight =: 4 : 'x{.y,x#'' '''
tableVector =: 3 : 0
    fields =. 0$a:
    for_i. i.#y do. fields =. fields,<((i{Widths) padLeft num i{y) end.
    ' 'join fields
)
tableRow =: 3 : 0
    'heading values' =. y
    line =. 9 padRight heading
    for_i. i.4 do.
        text =. ''
        if. i<#values do. text =. i{::values end.
        line =. line,'  ',(i{Columns) padRight text
    end.
    emit ((#line)-+/ *./\ ' '=|.line){.line
)
execute =: 3 : 0
    fields =. ' 'split y
    cmd =. 0{::fields
    args =. }.fields
    id =. 0
    if. #args do. id =. 0".0{::args end.
    hasId =. (<cmd)e.;:'PROCESS CLAIM REQUEST WHATIF RELEASE'
    v =. 0".each hasId}.args
    v =. >v
    if. (<cmd)e.;:'PROCESS CLAIM ADD REMOVE REQUEST WHATIF RELEASE' do.
        if. (#v)~:#Total do. fail 'wrong vector length' end.
    end.
    if. (<cmd)e.;:'CLAIM REQUEST WHATIF RELEASE FINISH ABORT CANCEL MAXGRANT' do.
        if. -.id{Exists do. fail 'unknown process ',pname id end.
    end.
    select. cmd
    case. 'RESOURCES' do.
        Total =: Avail =: v
        Exists =: Born =: 100#0
        Max =: Alloc =: (100,#v)$0
        Queue =: History =: 0$a:
        say 'resources';vec v
    case. 'MODE' do. Mode =: 0{::args [ say 'mode';0{::args
    case. 'POLICY' do. Policy =: 0{::args [ say 'policy';0{::args
    case. 'TRACE' do. Trace =: 'ON'eq 0{::args [ say 'trace';0{::args
    case. 'AUTODETECT' do. Auto =: 'ON'eq 0{::args [ say 'autodetect';0{::args
    case. 'PROCESS' do.
        if. id{Exists do. fail 'duplicate process ',pname id end.
        if. -.v fits Total do. fail 'max exceeds total' end.
        Exists =: 1 id}Exists
        Max =: v id}Max
        Born =: Time id}Born
        say 'process';(pname id);'max';vec v
    case. 'CLAIM' do.
        if. blocked id do. fail 'process ',(pname id),' is blocked' end.
        if. -.(id{Alloc)fits v do. fail 'claim below allocation' end.
        if. -.v fits Total do. fail 'max exceeds total' end.
        old =. id{Max
        Max =: v id}Max
        if. 'AVOID'eq Mode do.
            if. #1{::check 0,Trace do.
                Max =: old id}Max
                fail 'claim makes state unsafe'
            end.
        end.
        say 'claim';(pname id);'max';vec v
        retry''
    case. 'ADD' do.
        if. zero v do. fail 'zero vector' end.
        Total =: Total+v
        Avail =: Avail+v
        say 'added';(vec v);'total';vec Total
        retry''
    case. 'REMOVE' do.
        if. zero v do. fail 'zero vector' end.
        if. -.v fits Avail do. fail 'remove exceeds available' end.
        total =. Total-v
        if. 0 e.total do. fail 'total must stay positive' end.
        for_p. I.Exists do. if. -.(p{Max)fits total do. fail 'max exceeds total' end. end.
        Avail =: Avail-v
        if. 'AVOID'eq Mode do.
            if. #1{::check 0,Trace do.
                Avail =: Avail+v
                fail 'removal makes state unsafe'
            end.
        end.
        Total =: total
        say 'removed';(vec v);'total';vec Total
    case. 'REQUEST';'WHATIF' do.
        'kind reason sequence' =. decide id;v;1;Trace
        if. 'WHATIF'eq cmd do.
            text =. 'whatif ',(pname id),' ',(vec v),': ',kind
            if. 'granted'eq kind do.
                if. 'AVOID'eq Mode do. text =. text,', safe sequence ',pnames sequence end.
            else. text =. text,' (',reason,')' end.
            emit text
        elseif. 'rejected'eq kind do. fail reason
        elseif. 'granted'eq kind do.
            allocate id;v
            say 'granted';(pname id);vec v
            record 'granted';id;v;0
        else.
            Queue =: Queue,<id;v;Time
            emit 'blocked ',(pname id),' ',(vec v),': ',reason
            record 'blocked';id;v;0
            if. Auto do.
                dead =. 1{::check 1,Trace
                if. #dead do. emit 'deadlock detected: ',pnames dead end.
            end.
        end.
    case. 'RELEASE' do.
        if. blocked id do. fail 'process ',(pname id),' is blocked' end.
        if. zero v do. fail 'zero vector' end.
        if. -.v fits id{Alloc do. fail 'release exceeds allocation' end.
        Alloc =: ((id{Alloc)-v)id}Alloc
        Avail =: Avail+v
        say 'released';(pname id);vec v
        record 'released';id;v;0
        retry''
    case. 'FINISH';'ABORT' do.
        if. ('FINISH'eq cmd) *. blocked id do. fail 'process ',(pname id),' is blocked' end.
        kind =. 'aborted'
        if. 'FINISH'eq cmd do. kind =. 'finished' end.
        terminate id;kind;1
    case. 'CANCEL' do.
        if. -.blocked id do. fail 'process ',(pname id),' is not blocked' end.
        v =. request id
        dequeue id
        say 'cancelled';(pname id);vec v
        record 'cancelled';id;v;0
    case. 'MAXGRANT' do.
        if. blocked id do. fail 'process ',(pname id),' is blocked' end.
        result =. (#Total)#0
        for_i. i.#Total do.
            lo =. 0
            hi =. i{need id
            while. lo<hi do.
                mid =. <.(lo+hi+1)%2
                q =. mid i}(#Total)#0
                if. 'granted'eq 0{::decide id;q;1;0 do. lo =. mid else. hi =. <:mid end.
            end.
            result =. lo i}result
        end.
        emit 'maxgrant ',(pname id),': ',vec result
    case. 'SAFE' do.
        if. 0=+/Exists do. emit 'safe: no processes'
        else.
            'seq rest' =. check 0,Trace
            if. #rest do. emit 'unsafe: ',(pnames rest),' cannot finish'
            else. emit 'safe: ',pnames seq end.
        end.
    case. 'SEQUENCES' do.
        if. 0=+/Exists do. emit 'safe sequences: no processes'
        else.
            SeqCount =: 0
            SeqLimit =: id
            SeqFirst =: 0$a:
            sequenceWalk (I.Exists);Avail;i.0
            emit 'safe sequences: ',num SeqCount
            for_s. SeqFirst do. emit pnames >s end.
        end.
    case. 'DEFICIT' do.
        original =. Avail
        result =. 0$a:
        for_i. i.#Total do.
            lo =. 0
            hi =. +/i{"1 ((I.Exists){Max)-(I.Exists){Alloc
            Avail =: (original+hi*(i=i.#Total))
            if. #1{::check 0 0 do. result =. result,<'-'
            else.
                while. lo<hi do.
                    mid =. <.(lo+hi)%2
                    Avail =: original+mid*(i=i.#Total)
                    if. #1{::check 0 0 do. lo =. >:mid else. hi =. mid end.
                end.
                result =. result,<num lo
            end.
        end.
        Avail =: original
        emit 'deficit: (',(','join result),')'
    case. 'STATE' do.
        Widths =: #@num"0 Total
        names =. 0$a:
        for_i. i.#Total do. names =. names,<((i{Widths)padLeft ,(65+i){a.) end.
        nameRow =. ' 'join names
        Columns =: 10 3 4 7>.#nameRow
        tableRow 'Process';<('Allocation';'Max';'Need';'Request')
        tableRow '';<4$<nameRow
        for_p. I.Exists do.
            tableRow (pname p);<(tableVector each (p{Alloc);(p{Max);(need p);request p)
        end.
        tableRow 'Available';<,<tableVector Avail
        tableRow 'Total';<,<tableVector Total
        entries =. 0$a:
        for_q. Queue do.
            'p v since' =. >q
            entries =. entries,<(pname p),' ',(vec v),' since t=',num since
        end.
        if. #entries do. emit 'blocked queue: ',(', 'join entries) else. emit 'blocked queue: empty' end.
    case. 'STATS' do.
        for_i. i.#Total do.
            t =. i{Total
            u =. t-i{Avail
            requested =. 0
            for_q. Queue do. requested =. requested+i{1{::>q end.
            emit (,(65+i){a.),': allocated ',(num u),'/',(num t),' (',((100*u) fixed t,1),'%), requested ',num requested
        end.
        counts =. 0$a:
        waits =. i.0
        for_kind. Kinds do.
            n =. 0
            for_e. History do.
                if. (>kind)eq 1{::>e do.
                    n =. >:n
                    if. 'unblocked'eq >kind do. waits =. waits,4{::>e end.
                end.
            end.
            counts =. counts,<words kind,<n
        end.
        emit 'events: ',(', 'join counts)
        if. #waits do.
            emit 'waits: ',(num #waits),' unblocked, total ',(num +/waits),', average ',((+/waits)fixed (#waits),2)
        else. emit 'waits: none' end.
    case. 'DETECT' do.
        dead =. 1{::check 1,Trace
        if. #dead do. emit 'deadlocked: ',pnames dead else. emit 'no deadlock' end.
    case. 'VICTIMS' do.
        dead =. 1{::check 1 0
        if. 0=#dead do. emit 'no deadlock'
        else.
            sets =. 0$a:
            for_mask. >:i.<:2^#dead do.
                ids =. dead#~(#dead){.|.2#:mask
                sets =. sets,<ids
            end.
            ranks =. 0$a:
            for_ids. sets do.
                ids =. >ids
                ranks =. ranks,<((#ids),+/,ids{Alloc),ids
            end.
            sets =. (/:ranks){sets
            saved =. save''
            for_ids. sets do.
                ids =. >ids
                restore saved
                Avail =: Avail++/ids{Alloc
                Exists =: 0 ids}Exists
                for_p. ids do. dequeue p end.
                if. 0=#1{::check 1 0 do. emit 'victims: ',pnames ids break. end.
            end.
            restore saved
        end.
    case. 'RECOVER' do.
        n =. 0
        if. #args do.
            dead =. 1{::check 1,Trace
            for_p. dead do. terminate p;'aborted';0 end.
            n =. #dead
            if. n do. retry'' end.
        else.
            while. 1 do.
                dead =. 1{::check 1,Trace
                if. 0=#dead do. break. end.
                candidates =. 0 2$0
                for_p. dead do.
                    if. 'ALLOC'eq Policy do. cost =. +/p{Alloc
                    elseif. 'NEED'eq Policy do. cost =. -+/need p
                    else. cost =. -p{Born end.
                    candidates =. candidates,cost,-p
                end.
                candidates =. /:~candidates
                chosen =. -1{0{candidates
                terminate chosen;'aborted';1
                n =. >:n
            end.
        end.
        if. n do. emit 'recovered: ',(num n),' aborted' else. emit 'no deadlock' end.
    case. 'WAITGRAPH';'GRAPH' do.
        resource =. 'GRAPH'eq cmd
        Edges =: 0$a:
        if. resource do.
            if. -. *./1=Total do. fail 'not single-instance' end.
            for_i. i.#Total do.
                for_p. I.Exists do.
                    if. i{p{Alloc do. say 'assign';(,(65+i){a.);'->';pname p end.
                end.
            end.
            for_p. I.Exists do.
                req =. request p
                for_i. I.req>0 do.
                    say 'request';(pname p);'->';,(65+i){a.
                    for_q. I.Exists do.
                        if. i{q{Alloc do. Edges =: Edges,<p;q;i end.
                    end.
                end.
            end.
            for_p. I.Exists do.
                for_i. I.((need p)>0)*.0=request p do. say 'claim';(pname p);'->';,(65+i){a. end.
            end.
        else.
            for_p. I.Exists do.
                if. -.blocked p do. continue. end.
                short =. (request p)>Avail
                for_q. (I.Exists)-.p do.
                    label =. I.short*.0<q{Alloc
                    if. #label do.
                        Edges =: Edges,<p;q;label
                        say (pname p);'->';(pname q);'on';(','join <"0 (65+label){a.)
                    end.
                end.
            end.
            if. 0=#Edges do. emit 'no wait edges' end.
        end.
        printCycles resource
    case. 'HISTORY' do.
        n =. 0
        for_e. History do.
            't kind p v wait' =. >e
            good =. 1
            if. #args do. good =. ((0{::args)eq num p)+.((0{::args)eq kind) end.
            if. good do.
                text =. 't=',(num t),' ',kind,' ',(pname p),' ',vec v
                if. 'unblocked'eq kind do. text =. text,' waited ',num wait end.
                emit text
                n =. >:n
            end.
        end.
        if. n=0 do. emit 'no events' end.
    case. 'SNAPSHOT' do.
        name =. 0{::args
        index =. SnapNames i.<name
        if. index=#SnapNames do.
            SnapNames =: SnapNames,<name
            Snapshots =: Snapshots,<save''
        else. Snapshots =: (<save'')index}Snapshots end.
        say 'saved';name
    case. 'RESTORE' do.
        name =. 0{::args
        index =. SnapNames i.<name
        if. index=#SnapNames do. fail 'unknown snapshot ',name end.
        restore index{::Snapshots
        say 'restored';name
    end.
)
main =: 3 : 0
    lines =. <;._2 (1!:1 <'/dev/stdin'),LF
    count =. 0".0{::lines
    for_i. >:i.count do.
        Time =: i
        try. execute i{::lines catcht. end.
    end.
    1!:2&2 (LF join Output),LF
)
main''
