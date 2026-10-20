LF =: 10{a.
Names =: Prefs =: 0$a:
Votes =: Ends =: Active =: Order =: Priority =: i.0
Election =: 0
Error =: ''
Methods =: ;:'PLURALITY RUNOFF IRV COOMBS BUCKLIN BORDA BALDWIN NANSON BLACK VETO CONDORCET COPELAND MINIMAX SCHULZE RANKEDPAIRS KEMENY APPROVAL STV'
Summary =: (10{.Methods),(< 'COPELAND'),(< 'MINIMAX WINNING'),13 14 15{Methods
split =: 4 : '<;._1 x,y'
number =: 3 : ',''0'' 8!:2 y'
join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do. text =. text,x end.
        text =. text,i{::y
    end.
    text
)
fail =: 3 : 0
    Error =: y
    throw.
)
names_text =: 3 : ''', '' join y{Names'
ranks_text =: 3 : ''' > '' join y{Names'
tie_text =: 3 : 'y{::'''';'' (tie)'''
cents =: 3 : 0
    fraction =. number 100|y
    (number <.y%100),'.',(_2{.'00',fraction)
)
value_text =: 4 : 0
    parts =. 0$a:
    for_a. x do. parts =. parts,<(a{::Names),' ',number a{y end.
    ', ' join parts
)
stv_text =: 4 : 0
    parts =. 0$a:
    for_a. x do. parts =. parts,<(a{::Names),' ',cents a{y end.
    ', ' join parts
)
field_id =: 3 : '+/2^y'
members =: 3 : 'I.|.((#Names)#2)#:y'
total_votes =: 3 : '+/Votes'
invalidate =: 3 : 0
    Cache =: (2^#Names)#<i.0
    Pairs =: 0 0$0
)
checked_names =: 3 : 0
    result =. i.0
    for_name. y do.
        a =. Names i.name
        if. a=#Names do. fail 'unknown candidate ',>name end.
        if. a e.result do. fail 'duplicate candidate ',>name end.
        result =. result,a
    end.
    result
)
order_by =: 4 : 0
    'scores descending' =. x
    keys =. ((1-2*descending)*y{scores),.y{Priority
    (/:keys){y
)
scored =: 4 : 0
    order =. x order_by y
    scores =. >{.x
    tie =. 0
    if. 1<#order do. tie =. (0{order{scores)=1{order{scores end.
    order;tie
)
finish =: 3 : 0
    'order tie rows' =. y
    rows =. rows,<'winner: ',(({.order){::Names),tie_text tie
    order;tie;<rows
)

NB. Subset totals depend on the recorded groups, not on withdrawal or tiebreak.
tallies =: 3 : 0
    key =. field_id y
    saved =. key{::Cache
    if. #saved do. saved return. end.
    count =. #Names
    size =. #y
    first =. last =. borda =. count#0
    approval =. (size,count)$0
    nonblank =. 0
    for_i. i.#Votes do.
        votes =. i{Votes
        rank =. i{::Prefs
        rank =. rank#~rank e.y
        positions =. rank i.i.count
        positions =. count (I.positions=#rank)}positions
        if. #rank do. nonblank =. nonblank+votes end.
        first =. first+votes*positions=0
        if. (#rank)=size do.
            last =. last+votes*positions=size-1
        else.
            last =. last+votes*((i.count)e.y)*positions=count
        end.
        borda =. borda+votes*0>.(size-1)-positions
        approval =. approval+votes*(i.size)>:/positions
    end.
    saved =. first;last;borda;approval;nonblank
    Cache =: (<saved) key}Cache
    saved
)
pairwise =: 3 : 0
    if. #Pairs do. Pairs return. end.
    count =. #Names
    result =. (count,count)$0
    for_i. i.#Votes do.
        positions =. (i{::Prefs)i.i.count
        result =. result+(i{Votes)*positions</positions
    end.
    Pairs =: result
)
majority =: 4 : '+./(2*x{y)>+/x{y'
condorcet =: 4 : 0
    matrix =. pairwise ''
    for_a. y do.
        others =. y-.a
        forward =. others{a{matrix
        backward =. a{"1 others{matrix
        if. x do. yes =. *./forward<backward else. yes =. *./forward>backward end.
        if. yes do. a return. end.
    end.
    _1
)
look_back =: 4 : 0
    choices =. x
    tie =. 0
    for_r. |.i.#y do.
        scores =. r{y
        choices =. choices#~(choices{scores)=<./choices{scores
        if. r=(#y)-1 do. tie =. 1<#choices end.
    end.
    eliminated =. {:choices /: choices{Priority
    eliminated;tie
)
elimination =: 4 : 0
    'kind exhausted' =. x
    remaining =. y
    removed =. i.0
    rows =. 0$a:
    history =. (0,#Names)$0
    round =. 0
    while. 1 do.
        'first last borda approval nonblank' =. tallies remaining
        round =. round+1
        prefix =. 'round ',(number round),': '
        if. exhausted do.
            active =. +/remaining{first
            rows =. rows,<prefix,'active ',(number active),', exhausted ',number (total_votes '')-active
        else.
            row =. prefix,remaining value_text first
        end.
        if. (1=#remaining)+.remaining majority first do.
            order =. ((first;1) order_by remaining),|.removed
            if. exhausted do. order;0;<rows return. end.
            finish order;0;<rows,<row return.
        end.
        if. kind-:'COOMBS' do.
            choices =. remaining#~(remaining{last)=>./remaining{last
            tie =. 1<#choices
            eliminated =. {: (first;1) order_by choices
            row =. row,'; last ',remaining value_text last
        else.
            history =. history,first
            'eliminated tie' =. remaining look_back history
        end.
        if. -.exhausted do.
            rows =. rows,<row,'; eliminated ',(eliminated{::Names),tie_text tie
        end.
        removed =. removed,eliminated
        remaining =. remaining-.eliminated
    end.
)
runoff =: 3 : 0
    first =. 0{::tallies y
    order =. (first;1) order_by y
    rows =. <'round 1: ',y value_text first
    tie =. 0
    if. -.y majority first do.
        finalists =. /:~2{.order
        advance =. 0
        if. 2<#order do. advance =. (1{order{first)=2{order{first end.
        second =. 0{::tallies finalists
        tie =. (0{order{second)=1{order{second
        if. (1{order{second)>0{order{second do. order =. (|.2{.order),2}.order end.
        rows =. rows,<'finalists: ',(names_text finalists),tie_text advance
        rows =. rows,<'round 2: ',finalists value_text second
    end.
    finish order;tie;<rows
)
bucklin =: 3 : 0
    'first last borda approval nonblank' =. tallies y
    line =. 1+<.nonblank%2
    rows =. <'majority: ',number line
    final =. 0
    for_depth. i.#y do.
        final =. depth
        scores =. depth{approval
        rows =. rows,<'round ',(number depth+1),': ',y value_text scores
        if. +./(y{scores)>:line do. break. end.
    end.
    keys =. (|:- y{"1 |.(>:final){.approval),.y{Priority
    order =. (/:keys){y
    tie =. (0{order{scores)=1{order{scores
    finish order;tie;<rows
)
borda_elimination =: 4 : 0
    remaining =. y
    tail =. i.0
    history =. (0,#Names)$0
    rows =. 0$a:
    round =. 0
    while. 1<#remaining do.
        scores =. 2{::tallies remaining
        round =. round+1
        row =. 'round ',(number round),': ',remaining value_text scores
        if. x do.
            below =. remaining#~((#remaining)*remaining{scores)<+/remaining{scores
            if. 0=#below do. rows =. rows,<row break. end.
            rows =. rows,<row,'; eliminated ',names_text below
            removed =. (scores;1) order_by below
        else.
            history =. history,scores
            'a tie' =. remaining look_back history
            removed =. ,a
            rows =. rows,<row,'; eliminated ',(a{::Names),tie_text tie
        end.
        tail =. removed,tail
        remaining =. remaining-.removed
    end.
    order =. (remaining /: remaining{Priority),tail
    finish order;(x*.1<#remaining);<rows
)
pair_lines =: 4 : 0
    rows =. 0$a:
    for_i. i.#x do.
        a =. i{x
        for_b. (i+1)}.x do.
            ab =. (<a,b){y
            ba =. (<b,a){y
            result =. 'tie'
            if. ab>ba do. result =. a{::Names end.
            if. ab<ba do. result =. b{::Names end.
            rows =. rows,<(a{::Names),' vs ',(b{::Names),': ',(number ab),'-',(number ba),' (',result,')'
        end.
    end.
    rows
)
closure =: 4 : 0
    result =. y
    for_k. x do.
        result =. result+.(k{"1 result)*./k{result
    end.
    result
)
condorcet_report =: 3 : 0
    matrix =. pairwise ''
    win =. 0 condorcet y
    lose =. 1 condorcet y
    winner =. loser =. 'NONE'
    if. win>:0 do. winner =. win{::Names end.
    if. lose>:0 do. loser =. lose{::Names end.
    weak =. y closure matrix>:|:matrix
    strong =. y closure matrix>|:matrix
    smith =. schwartz =. i.0
    for_a. y do.
        if. *./y{a{weak do. smith =. smith,a end.
        if. *./(-.a{"1 y{strong)+.y{a{strong do. schwartz =. schwartz,a end.
    end.
    rows =. ('winner: ';'loser: ';'smith: ';'schwartz: '),&.>winner;loser;(names_text smith);<names_text schwartz
    (i.0);0;<rows
)
topological =: 4 : 0
    remaining =. x
    order =. i.0
    tie =. 0
    while. #remaining do.
        incoming =. +./remaining{"1 remaining{y
        choices =. remaining#~-.incoming
        if. 0=#order do. tie =. 1<#choices end.
        a =. {.choices /: choices{Priority
        order =. order,a
        remaining =. remaining-.a
    end.
    order;tie
)
schulze =: 3 : 0
    matrix =. pairwise ''
    paths =. matrix*matrix>|:matrix
    for_i. y do.
        for_j. y-.i do.
            for_k. y-.i,j do.
                strength =. ((<j,i){paths)<.(<i,k){paths
                paths =. (strength>.(<j,k){paths) (<j,k)}paths
            end.
        end.
    end.
    'order tie' =. y topological paths>|:paths
    rows =. (y pair_lines paths),<'ranking: ',ranks_text order
    finish order;tie;<rows
)
ranked_pairs =: 3 : 0
    matrix =. pairwise ''
    edges =. keys =. 0 2$0
    keys =. 0 4$0
    for_a. y do.
        for_b. y do.
            win =. (<a,b){matrix
            lose =. (<b,a){matrix
            if. win>lose do.
                edges =. edges,a,b
                keys =. keys,(-win),lose,(a{Priority),b{Priority
            end.
        end.
    end.
    edges =. (/:keys){edges
    locked =. reached =. ((#Names),#Names)$0
    rows =. 0$a:
    for_edge. edges do.
        'a b' =. edge
        accepted =. -. (<b,a){reached
        label =. accepted{::'skip ';'lock '
        rows =. rows,<label,(a{::Names),'>',(b{::Names),' ',(number (<a,b){matrix),'-',number (<b,a){matrix
        if. accepted do.
            locked =. 1 (<a,b)}locked
            reached =. y closure 1 (<a,b)}reached
        end.
    end.
    'order tie' =. y topological locked
    finish order;tie;<rows
)
kemeny =: 3 : 0
    matrix =. pairwise ''
    limit =. 2^#Names
    best =. limit#0
    ways =. 1 (0})limit#0
    heads =. limit#<i.0
    for_subset. }.i.limit do.
        field =. members subset
        if. -. *./field e.y do. continue. end.
        score =. _1
        count =. 0
        options =. i.0
        for_a. field do.
            rest =. subset-2^a
            value =. (rest{best)+ +/(field-.a){a{matrix
            if. value>score do.
                score =. value
                count =. 0
                options =. i.0
            end.
            if. value=score do.
                count =. count+rest{ways
                options =. options,a
            end.
        end.
        best =. score subset}best
        ways =. count subset}ways
        heads =. (<options) subset}heads
    end.
    key =. field_id y
    remaining =. key
    order =. i.0
    while. remaining do.
        choices =. remaining{::heads
        a =. {.choices /: choices{Priority
        order =. order,a
        remaining =. remaining-2^a
    end.
    rows =. (<'score: ',number key{best),(<'optimal: ',number key{ways),<'ranking: ',ranks_text order
    finish order;(1<#key{::heads);<rows
)
stv =: 4 : 0
    seats =. x
    continuing =. y
    values =. (#Votes)#0
    for_i. i.#Votes do.
        if. +./(i{::Prefs)e.y do. values =. 100 i}values end.
    end.
    nonblank =. 4{::tallies y
    quota =. 1+<.(100*nonblank)%seats+1
    rows =. <'quota: ',cents quota
    history =. (0,#Names)$0
    elected =. i.0
    round =. 0
    while. 1 do.
        scores =. (#Names)#0
        owners =. (#Votes)#_1
        exhausted =. 0
        for_i. i.#Votes do.
            if. 0=i{values do. continue. end.
            rank =. i{::Prefs
            rank =. rank#~rank e.continuing
            amount =. (i{Votes)*i{values
            if. #rank do.
                a =. {.rank
                owners =. a i}owners
                scores =. (amount+a{scores) a}scores
            else.
                exhausted =. exhausted+amount
            end.
        end.
        history =. history,scores
        round =. round+1
        row =. 'round ',(number round),': ',(continuing stv_text scores),'; exhausted ',cents exhausted
        order =. (scores;1) order_by continuing
        if. (#continuing)=seats-#elected do.
            elected =. elected,order
            rows =. rows,<row,'; elected ',names_text order
            break.
        end.
        a =. {.order
        if. (a{scores)>:quota do.
            surplus =. (a{scores)-quota
            elected =. elected,a
            continuing =. continuing-.a
            indices =. I.owners=a
            transferred =. <.((indices{values)*surplus)%a{scores
            values =. transferred indices}values
            rows =. rows,<row,'; elected ',(a{::Names),' (surplus ',(cents surplus),')'
            if. seats=#elected do. break. end.
        else.
            'a tie' =. continuing look_back history
            continuing =. continuing-.a
            rows =. rows,<row,'; excluded ',(a{::Names),tie_text tie
        end.
    end.
    rows =. rows,<'elected: ',names_text elected
    (i.0);0;<rows
)
tally =: 4 : 0
    words =. ' ' split x
    method =. 0{::words
    select. method
    case. 'RUNOFF' do. runoff y return.
    case. 'IRV';'COOMBS' do. (method;0) elimination y return.
    case. 'BUCKLIN' do. bucklin y return.
    case. 'BALDWIN';'NANSON' do. (method-:'NANSON') borda_elimination y return.
    case. 'CONDORCET' do. condorcet_report y return.
    case. 'SCHULZE' do. schulze y return.
    case. 'RANKEDPAIRS' do. ranked_pairs y return.
    case. 'KEMENY' do. kemeny y return.
    case. 'STV' do. (0".1{::words) stv y return.
    end.
    'first last borda approval nonblank' =. tallies y
    scores =. (#Names)#0
    descending =. 1
    label =. 'scores'
    rows =. 0$a:
    winner =. _1
    select. method
    case. 'PLURALITY' do. scores =. first [ label =. 'votes'
    case. 'BORDA';'BLACK' do.
        scores =. borda
        if. method-:'BLACK' do.
            winner =. 0 condorcet y
            text =. 'NONE'
            if. winner>:0 do. text =. winner{::Names end.
            rows =. rows,<'condorcet: ',text
        end.
    case. 'VETO' do. scores =. last [ descending =. 0 [ label =. 'vetoes'
    case. 'APPROVAL' do.
        depth =. (#y)<.0".1{::words
        scores =. (depth-1){approval
        label =. 'approvals'
    case. 'COPELAND' do.
        matrix =. pairwise ''
        parts =. 0$a:
        for_a. y do.
            other =. y-.a
            forward =. other{a{matrix
            backward =. a{"1 other{matrix
            wins =. +/forward>backward
            draws =. +/forward=backward
            losses =. +/forward<backward
            score =. (2*wins)+draws
            scores =. score a}scores
            decimal =. (number <.score%2),'.',number 5*2|score
            parts =. parts,<(a{::Names),' ',decimal,' (',(number wins),'-',(number draws),'-',(number losses),')'
        end.
        rows =. rows,<'scores: ',', ' join parts
    case. 'MINIMAX' do.
        matrix =. pairwise ''
        kind =. 1{::words
        descending =. 0
        for_a. y do.
            other =. y-.a
            opposition =. a{"1 other{matrix
            support =. other{a{matrix
            selected =. opposition
            if. -.kind-:'OPPOSITION' do.
                selected =. selected*opposition>support
                if. kind-:'MARGIN' do. selected =. 0>.opposition-support end.
            end.
            scores =. (>./selected) a}scores
        end.
    end.
    'order tie' =. (scores;descending) scored y
    if. winner>:0 do. order =. winner,order-.winner [ tie =. 0 end.
    if. -.method-:'COPELAND' do. rows =. rows,<label,': ',y value_text scores end.
    finish order;tie;<rows
)
ballots_report =: 3 : 0
    notation =. 0$a:
    blank =. 0
    field =. I.Active
    for_i. i.#Votes do.
        rank =. i{::Prefs
        rank =. rank#~rank e.field
        if. #rank do. text =. '>' join rank{Names else. text =. '-' [ blank =. blank+i{Votes end.
        notation =. notation,<text
    end.
    distinct =. ~.notation
    counts =. i.0
    for_text. distinct do. counts =. counts,+/(notation=text)#Votes end.
    order =. /:s:distinct
    order =. (/: - order{counts){order
    rows =. <'total ',(number total_votes ''),', blank ',(number blank),', distinct ',number #distinct
    for_i. order do. rows =. rows,<(number i{counts),' ',i{::distinct end.
    rows
)
status =: 3 : 0
    withdrawn =. 'none'
    if. +./-.Active do. withdrawn =. names_text I.-.Active end.
    (<'election ',number Election),(<'active: ',names_text I.Active),(<'withdrawn: ',withdrawn),(< 'tiebreak: ',names_text Order),<'ballots: ',(number total_votes ''),' in ',(number #Ends),' entries'
)
execute =: 3 : 0
    words =. ' ' split y
    command =. 0{::words
    if. command-:'CANDIDATES' do.
        candidates =. }.words
        if. 1=#candidates do. fail 'too few candidates' end.
        seen =. 0$a:
        for_name. candidates do.
            if. name e.seen do. fail 'duplicate candidate ',>name end.
            seen =. seen,name
        end.
        Names =: candidates
        Active =: (#Names)#1
        Order =: /:s:Names
        Priority =: Order i.i.#Names
        Prefs =: 0$a:
        Votes =: Ends =: i.0
        Election =: Election+1
        invalidate ''
        <'election ',(number Election),': ',(number #Names),' candidates' return.
    end.
    if. 0=Election do. fail 'no election' end.
    select. command
    case. 'BALLOT' do.
        ranking =. i.0
        if. -. '-' -:2{::words do. ranking =. checked_names '>' split 2{::words end.
        Votes =: Votes,0".1{::words
        Prefs =: Prefs,<ranking
        Ends =: Ends,#Votes
        invalidate ''
        0$a: return.
    case. 'RANDOM' do.
        groups =. 0".1{::words
        state =. x:0".2{::words
        for_group. i.groups do.
            ranking =. I.Active
            for_i. |.}.i.#ranking do.
                state =. 2147483647x|48271x*state
                index =. (i+1)|state
                pair =. i,index
                ranking =. (|.pair{ranking) pair}ranking
            end.
            state =. 2147483647x|48271x*state
            ranking =. (1+(#ranking)|state){.ranking
            Votes =: Votes,1
            Prefs =: Prefs,<ranking
        end.
        Ends =: Ends,#Votes
        invalidate ''
        0$a: return.
    case. 'UNDO' do.
        if. 0=#Ends do. fail 'nothing to undo' end.
        Ends =: }:Ends
        count =. {:0,Ends
        Votes =: count{.Votes
        Prefs =: count{.Prefs
        invalidate ''
        0$a: return.
    case. 'WITHDRAW';'RESTORE' do.
        name =. 1{::words
        a =. Names i.<name
        if. a=#Names do. fail 'unknown candidate ',name end.
        if. command-:'WITHDRAW' do.
            if. -.a{Active do. fail 'already withdrawn ',name end.
            if. 2>:+/Active do. fail 'too few candidates' end.
            Active =: 0 a}Active
        else.
            if. a{Active do. fail 'not withdrawn ',name end.
            Active =: 1 a}Active
        end.
        0$a: return.
    case. 'TIEBREAK' do.
        order =. checked_names }.words
        if. (#order)~:#Names do. fail 'incomplete tiebreak' end.
        Order =: order
        Priority =: Order i.i.#Names
        0$a: return.
    end.
    heading =. <'[',y,']'
    if. command-:'STATUS' do. heading,status '' return. end.
    if. 0=#Ends do. fail 'no ballots' end.
    field =. I.Active
    ranking =. command-:'RANKING'
    spoilers =. command-:'SPOILERS'
    if. ranking+.spoilers do.
        method =. ' ' join }.words
        if. (1{words)e.;:'CONDORCET STV' do. fail 'not rankable' end.
        if. spoilers*.3>#field do. fail 'too few candidates' end.
        order =. 0{::method tally field
        if. ranking do. heading,<ranks_text order return. end.
        winner =. {.order
        rows =. <'winner: ',winner{::Names
        for_a. field-.winner do.
            other =. {.0{::method tally field-.a
            suffix =. ''
            if. other~:winner do. suffix =. ' (changed)' end.
            rows =. rows,<'without ',(a{::Names),': ',(other{::Names),suffix
        end.
        heading,rows return.
    end.
    if. command-:'COMPARE' do.
        compared =. i.0
        for_word. }.words do.
            a =. Names i.word
            if. a=#Names do. fail 'unknown candidate ',>word end.
            if. -.a{Active do. fail 'withdrawn candidate ',>word end.
            compared =. compared,a
        end.
        if. =/compared do. fail 'same candidate' end.
    end.
    if. command-:'STV' do.
        if. (0".1{::words)>:#field do. fail 'too many seats' end.
    end.
    rows =. 0$a:
    select. command
    case. 'BALLOTS' do. rows =. ballots_report ''
    case. 'PROFILE' do.
        'first last borda approval nonblank' =. tallies field
        for_a. field do.
            cumulative =. a{"1 approval
            counts =. cumulative-0,}:cumulative
            rows =. rows,<(a{::Names),': ',(' ' join number&.>counts),' unranked ',number (total_votes '')-{:cumulative
        end.
    case. 'PAIRWISE' do. rows =. field pair_lines pairwise ''
    case. 'EXHAUSTED' do. rows =. 2{::('IRV';1) elimination field
    case. 'SUMMARY';'COMPARE' do.
        wins =. (#Names)#0
        ahead =. 2#<0$a:
        for_method. Summary do.
            order =. 0{::(>method) tally field
            if. command-:'SUMMARY' do.
                a =. {.order
                wins =. (1+a{wins) a}wins
                rows =. rows,<(>method),': ',a{::Names
            else.
                side =. (order i.0{compared)>order i.1{compared
                ahead =. (<(side{::ahead),method) side}ahead
            end.
        end.
        if. command-:'SUMMARY' do.
            rows =. rows,<'wins: ',field value_text wins
        else.
            'a b' =. compared
            matrix =. pairwise ''
            ab =. (<a,b){matrix
            ba =. (<b,a){matrix
            rows =. <(a{::Names),' ',(number ab),', ',(b{::Names),' ',(number ba),', neither ',number (total_votes '')-ab+ba
            for_i. i.2 do.
                text =. 'none'
                if. #i{::ahead do. text =. ', ' join i{::ahead end.
                rows =. rows,<((i{compared){::Names),' ahead: ',text
            end.
        end.
    case. do. rows =. 2{::y tally field
    end.
    heading,rows
)
main =: 3 : 0
    count =. 0".1!:1 3
    for_i. i.count do.
        line =. 1!:1 3
        try. rows =. execute line
        catcht. rows =. <'ERROR ',Error
        end.
        for_row. rows do. ((>row),LF) 1!:2 4 end.
    end.
)
main ''
exit 0
