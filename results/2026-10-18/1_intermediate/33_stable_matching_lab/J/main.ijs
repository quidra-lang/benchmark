LF =: 10{a.
MarketNames =: Markets =: 0$a:
Error =: ''
split =: 4 : '<;._1 x,y'
number =: 3 : ',''0'' 8!:2 y'
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
emit =: 3 : 'Output =: Output,<y'
fail =: 3 : 0
    Error =: y
    throw.
)
rank_in =: 4 : '1+x i.y'
pack =: 3 : 'Kind;Names;P;Houses;Prefs;Caps;Current;<Source'
require_kind =: 3 : 0
    if. Kind~:y do. fail 'WRONG TYPE ',MarketName end.
)
agent =: 3 : 0
    index =. Names i.<y
    if. index=#Names do. fail 'UNKNOWN AGENT ',y end.
    index
)
side_agent =: 4 : 0
    index =. agent y
    if. (x=0)*.index>:P do. fail 'NOT PROPOSER ',y end.
    if. (x=1)*.index<P do. fail 'NOT RECEIVER ',y end.
    index
)
partner_name =: 3 : 0
    if. y<0 do. '*' else. y{::Names end.
)
list_text =: 3 : 0
    if. 0=#y do. '-' return. end.
    if. Kind=2 do. ' ' join y{Houses else. ' ' join y{Names end.
)
pair_text =: 3 : 0
    parts =. 0$a:
    for_p. i.P do. parts =. parts,<(p{::Names),'-',partner_name p{y end.
    ' ' join parts
)
rotation_text =: 4 : 0
    parts =. 0$a:
    for_p. y do. parts =. parts,<(p{::Names),'-',partner_name p{x end.
    ' ' join parts
)
allocation_text =: 3 : 0
    parts =. 0$a:
    for_a. i.#Names do.
        house =. '*'
        if. (a{y)>:0 do. house =. (a{y){::Houses end.
        parts =. parts,<(a{::Names),'-',house
    end.
    ' ' join parts
)

NB. Preference lists are explicit values so manipulation trials share no state.
deferred =: 4 : 0
    preferences =. x
    reverse =. y
    count =. #Names
    side =. i.P
    if. reverse do. side =. P+i.count-P end.
    next =. held =. count#0
    holding =. (count,count)$0
    lengths =. #&>preferences
    queue =. side#~0<side{lengths
    history =. 0$a:
    proposals =. 0
    while. #queue do.
        proposer =. {.queue
        queue =. }.queue
        receiver =. (proposer{next){proposer{::preferences
        next =. (>:proposer{next) proposer}next
        proposals =. proposals+1
        accepted =. 0
        rejected =. _1
        preference =. receiver{::preferences
        if. proposer e.preference do.
            if. (receiver{held)<receiver{Caps do.
                accepted =. 1
            else.
                partners =. I.receiver{holding
                ranks =. preference rank_in"1 0 partners
                worst =. (ranks i.>./ranks){partners
                if. (preference rank_in proposer)<preference rank_in worst do.
                    accepted =. 1
                    rejected =. worst
                    holding =. 0 (<receiver,worst)}holding
                    held =. held-(i.count)e.receiver,worst
                    if. ((worst{held)<worst{Caps)*.(worst{next)<worst{lengths do.
                        if. -.worst e.queue do. queue =. queue,worst end.
                    end.
                end.
            end.
        end.
        line =. 'PROPOSE ',(proposer{::Names),' ',(receiver{::Names)
        if. accepted do.
            holding =. 1 (<receiver,proposer)}holding
            held =. held+(i.count)e.receiver,proposer
            line =. line,' HOLD'
            if. rejected>:0 do. line =. line,' REJECT ',rejected{::Names end.
        else.
            line =. line,' REJECT'
        end.
        history =. history,<line
        if. ((proposer{held)<proposer{Caps)*.(proposer{next)<proposer{lengths do.
            queue =. queue,proposer
        end.
    end.
    matching =. P#_1
    for_p. i.P do.
        for_r. P+i.count-P do.
            location =. r,p
            if. reverse do. location =. p,r end.
            if. (<location){holding do. matching =. r p}matching end.
        end.
    end.
    matching;proposals;<history
)
boston =: 3 : 0
    preferences =. y
    matching =. P#_1
    remaining =. Caps
    applications =. 0
    rounds =. >./0,#&>P{.preferences
    for_round. i.rounds do.
        applied =. P#_1
        for_p. i.P do.
            if. ((p{matching)<0)*.round<#p{::preferences do.
                receiver =. round{p{::preferences
                applied =. receiver p}applied
                applications =. applications+1
            end.
        end.
        for_r. P+i.(#Names)-P do.
            for_p. r{::preferences do.
                if. 0=r{remaining do. break. end.
                if. r=p{applied do.
                    matching =. r p}matching
                    remaining =. (<:r{remaining) r}remaining
                end.
            end.
        end.
    end.
    matching;applications
)
rotations =: 3 : 0
    matching =. y
    owner =. (#Names)#_1
    successor =. P#_1
    for_p. I.matching>:0 do. owner =. p (p{matching)}owner end.
    for_p. I.matching>:0 do.
        preference =. p{::Prefs
        for_r. (preference rank_in p{matching)}.preference do.
            if. p e.r{::Prefs do.
                other =. r{owner
                if. (other<0)+.((r{::Prefs) rank_in p)<(r{::Prefs) rank_in other do.
                    successor =. other p}successor
                    break.
                end.
            end.
        end.
    end.
    result =. 0$a:
    covered =. P#0
    for_start. i.P do.
        if. start{covered do. continue. end.
        path =. i.0
        point =. start
        while. (point>:0)*.-.point e.path do.
            path =. path,point
            point =. point{successor
        end.
        if. point=start do.
            result =. result,<path
            covered =. covered+.(i.P)e.path
        end.
    end.
    result
)
enumerate =: 3 : 0
    initial =. 0{::Prefs deferred 0
    matchings =. <initial
    origins =. vias =. ,0
    numbered =. 0$a:
    index =. 0
    while. index<#matchings do.
        matching =. index{::matchings
        for_rotation. rotations matching do.
            rotation =. >rotation
            notation =. matching rotation_text rotation
            identifier =. numbered i.<notation
            if. identifier=#numbered do. numbered =. numbered,<notation end.
            following =. matching
            destinations =. (1|.rotation){matching
            following =. destinations rotation}following
            if. -.(<following)e.matchings do.
                if. 50=#matchings do. fail 'TOO MANY MATCHINGS' end.
                matchings =. matchings,<following
                origins =. origins,index+1
                vias =. vias,identifier+1
            end.
        end.
        index =. index+1
    end.
    matchings;origins;vias;<numbered
)
metrics =: 3 : 0
    ranks =. i.0
    for_p. I.y>:0 do.
        receiver =. p{y
        ranks =. ranks,((p{::Prefs) rank_in receiver),(receiver{::Prefs) rank_in p
    end.
    (+/ranks),>./0,ranks
)
check_matching =: 3 : 0
    matching =. y
    unacceptable =. blocking =. 0$a:
    if. Kind=0 do.
        for_p. i.P do.
            receiver =. p{matching
            if. receiver>:0 do.
                if. -. (receiver e.p{::Prefs)*.p e.receiver{::Prefs do.
                    unacceptable =. unacceptable,<'UNACCEPTABLE ',(p{::Names),' ',receiver{::Names
                end.
            end.
            for_r. P+i.(#Names)-P do.
                if. (receiver=r)+.-.(r e.p{::Prefs)*.p e.r{::Prefs do. continue. end.
                if. ((p{::Prefs) rank_in r)>:(p{::Prefs) rank_in receiver do. continue. end.
                partners =. I.r=P{.matching
                worst =. >./0,(r{::Prefs) rank_in"1 0 partners
                if. ((#partners)<r{Caps)+.((r{::Prefs) rank_in p)<worst do.
                    blocking =. blocking,<'BLOCKING ',(p{::Names),' ',r{::Names
                end.
            end.
        end.
    else.
        for_a. i.#Names do.
            for_b. (a+1)+i.(#Names)-(a+1) do.
                mutual =. (b e.a{::Prefs)*.a e.b{::Prefs
                if. b=a{matching do.
                    if. -.mutual do. unacceptable =. unacceptable,<'UNACCEPTABLE ',(a{::Names),' ',b{::Names end.
                elseif. mutual do.
                    if. (((a{::Prefs) rank_in b)<(a{::Prefs) rank_in a{matching)*.((b{::Prefs) rank_in a)<(b{::Prefs) rank_in b{matching do.
                        blocking =. blocking,<'BLOCKING ',(a{::Names),' ',b{::Names
                    end.
                end.
            end.
        end.
    end.
    if. 0=(#unacceptable)+#blocking do.
        emit 'CHECK ',MarketName,' STABLE'
    else.
        emit 'CHECK ',MarketName,' UNSTABLE unacceptable=',(number #unacceptable),' blocking=',number #blocking
        Output =: Output,unacceptable,blocking
    end.
)
check_pairs =: 3 : 0
    matching =. (#Names)#_1
    counts =. (#Names)#0
    for_word. y do.
        'left right' =. '-' split >word
        if. Kind=0 do.
            first =. 0 side_agent left
            second =. 1 side_agent right
        else.
            first =. agent left
            second =. agent right
        end.
        if. (first{matching)>:0 do. fail 'DUPLICATE AGENT ',left end.
        if. Kind=0 do.
            counts =. (>:second{counts) second}counts
            if. (second{counts)>second{Caps do. fail 'OVER CAPACITY ',right end.
        else.
            if. (first=second)+.(second{matching)>:0 do. fail 'DUPLICATE AGENT ',right end.
            matching =. first second}matching
        end.
        matching =. second first}matching
    end.
    check_matching matching
)

remove_pair =: 4 : 0
    'first second' =. x
    result =. (<(first{::y)-.second) first}y
    (<(second{::result)-.first) second}result
)
table_lines =: 3 : 0
    result =. 0$a:
    for_a. i.#Names do. result =. result,<'TABLE ',(a{::Names),' ',list_text a{::y end.
    result
)
roommates =: 3 : 0
    verbose =. y
    work =. Prefs
    held =. (#Names)#_1
    queue =. i.#Names
    proposals =. 0
    failure =. _1
    while. #queue do.
        proposer =. {.queue
        queue =. }.queue
        receiver =. {.proposer{::work
        if. (receiver{held)>:0 do. queue =. queue,receiver{held end.
        held =. proposer receiver}held
        proposals =. proposals+1
        preference =. receiver{::work
        for_other. (>:preference i.proposer)}.preference do.
            work =. (receiver,other) remove_pair work
        end.
        empty =. I.0=#&>work
        if. #empty do. failure =. {.empty break. end.
    end.
    history =. 0$a:
    if. (failure<0)*.verbose do. history =. table_lines work end.
    rotation_count =. 0
    while. failure<0 do.
        multiple =. I.1<#&>work
        if. 0=#multiple do. break. end.
        path =. i.0
        point =. {.multiple
        while. -.point e.path do.
            path =. path,point
            second =. 1{point{::work
            point =. {:second{::work
        end.
        rotation =. (path i.point)}.path
        front =. i.0
        pairs =. 0$a:
        for_a. rotation do.
            partner =. {.a{::work
            front =. front,partner
            pairs =. pairs,<(a{::Names),'-',partner{::Names
        end.
        rotation_count =. rotation_count+1
        history =. history,<'ROTATION ',(number rotation_count),' ',' ' join pairs
        removed =. 0 2$0
        for_i. i.#rotation do.
            receiver =. ((#rotation)|i+1){front
            preference =. receiver{::work
            for_other. (>:preference i.i{rotation)}.preference do.
                removed =. removed,receiver,other
            end.
        end.
        for_pair. removed do. work =. pair remove_pair work end.
        if. verbose do. history =. history,table_lines work end.
        empty =. I.0=#&>work
        if. #empty do. failure =. {.empty end.
    end.
    emit 'ROOMMATES ',MarketName,' proposals=',number proposals
    Output =: Output,history
    if. failure>:0 do.
        emit 'NO STABLE MATCHING ',failure{::Names
    else.
        pairs =. 0$a:
        for_a. i.#Names do.
            partner =. {.a{::work
            if. a<partner do. pairs =. pairs,<(a{::Names),'-',partner{::Names end.
        end.
        emit 'MATCHING ',' ' join pairs
    end.
)
effective =: 3 : 0
    preference =. y{::Prefs
    index =. preference i.y
    if. index<#preference do. (index+1){.preference else. preference,y end.
)
ttc =: 3 : 0
    remaining =. (#Names)#1
    allocation =. (#Names)#_1
    cycles =. 0$a:
    while. +./remaining do.
        pointing =. (#Names)#_1
        for_a. I.remaining do.
            preference =. effective a
            house =. {.preference#~preference{remaining
            pointing =. house a}pointing
        end.
        path =. i.0
        point =. {.I.remaining
        while. -.point e.path do.
            path =. path,point
            point =. point{pointing
        end.
        cycle =. (path i.point)}.path
        parts =. 0$a:
        for_a. cycle do.
            house =. a{pointing
            allocation =. house a}allocation
            remaining =. 0 a}remaining
            parts =. parts,<(a{::Names),':',house{::Houses
        end.
        cycles =. cycles,<'CYCLE ',(number >:#cycles),' ',' ' join parts
    end.
    emit 'TTC ',MarketName,' cycles=',number #cycles
    Output =: Output,cycles
    emit 'ALLOCATION ',allocation_text allocation
)
serial =: 3 : 0
    order =. i.0
    for_word. y do.
        index =. agent >word
        if. index e.order do. fail 'DUPLICATE AGENT ',>word end.
        order =. order,index
    end.
    if. (#order)~:#Names do. fail 'BAD ORDER' end.
    remaining =. (#Names)#1
    allocation =. (#Names)#_1
    for_a. order do.
        preference =. a{::Prefs
        available =. preference#~preference{remaining
        if. #available do.
            house =. {.available
            allocation =. house a}allocation
            remaining =. 0 house}remaining
        end.
    end.
    worse =. i.0
    for_a. i.#Names do.
        if. -.(a{allocation)e.effective a do. worse =. worse,a end.
    end.
    emit 'SERIAL ',MarketName,' assigned=',number +/allocation>:0
    emit 'ALLOCATION ',allocation_text allocation
    text =. '-'
    if. #worse do. text =. ' ' join worse{Names end.
    emit 'WORSE ',text
)
hr =: 3 : 0
    resident =. 0{::Prefs deferred 0
    hospital =. 0{::Prefs deferred 1
    emit 'HR ',MarketName,' residents=',(number P),' hospitals=',number (#Names)-P
    emit 'RESIDENT-OPTIMAL ',pair_text resident
    emit 'HOSPITAL-OPTIMAL ',pair_text hospital
    unmatched =. I.resident<0
    text =. '-'
    if. #unmatched do. text =. ' ' join unmatched{Names end.
    emit 'UNMATCHED ',text
    rural =. (resident>:0)-:hospital>:0
    for_r. P+i.(#Names)-P do.
        first =. r=resident
        second =. r=hospital
        same =. first-:second
        count =. +/first
        other =. +/second
        label =. 'NO'
        if. same do. label =. 'YES' end.
        emit 'HOSPITAL ',(r{::Names),' cap=',(number r{Caps),' resident=',(number count),' hospital=',(number other),' same=',label
        rural =. rural*.(count=other)*.same+.count>:r{Caps
    end.
    if. rural do. emit 'RURAL HOLDS' else. emit 'RURAL FAILS' end.
)
manipulate =: 3 : 0
    proposer =. y
    truth =. proposer{::Prefs
    baseline_b =. proposer{0{::boston Prefs
    baseline_g =. proposer{0{::Prefs deferred 0
    emit 'MANIPULATE ',MarketName,' ',(proposer{::Names),' boston=',(partner_name baseline_b),' gs=',(partner_name baseline_g),' swaps=',number 0>.(#truth)-1
    improved =. 0
    for_i. i.0>.(#truth)-1 do.
        next =. i+1
        swapped =. ((next{truth),(i{truth)) (i,next)}truth
        trial =. (<swapped) proposer}Prefs
        outcomes =. (proposer{0{::boston trial),proposer{0{::trial deferred 0
        baselines =. baseline_b,baseline_g
        labels =. ;:'BOSTON GS'
        for_k. i.2 do.
            result =. k{outcomes
            if. (truth rank_in result)<truth rank_in k{baselines do.
                emit 'IMPROVE ',(k{::labels),' ',(number i+1),' ',((i{truth){::Names),' ',((next{truth){::Names),' result=',partner_name result
                improved =. 1
            end.
        end.
    end.
    if. -.improved do. emit 'NO IMPROVEMENT' end.
)
stats =: 3 : 0
    matched =. I.Current>:0
    pairs =. #matched
    proposer_ranks =. receiver_ranks =. i.0
    for_p. matched do.
        receiver =. p{Current
        proposer_ranks =. proposer_ranks,(p{::Prefs) rank_in receiver
        receiver_ranks =. receiver_ranks,(receiver{::Prefs) rank_in p
    end.
    emit 'STATS ',MarketName,' source=',Source,' pairs=',number pairs
    labels =. ;:'PROPOSERS RECEIVERS'
    ranks =. proposer_ranks;receiver_ranks
    unmatched =. (P-pairs),((#Names)-P)-#~.matched{Current
    for_side. i.2 do.
        values =. side{::ranks
        total =. +/values
        average =. truncated =. '-'
        if. pairs do.
            divisor =. total+.pairs
            average =. (number total%divisor),'/',number pairs%divisor
            cents =. <.(100*total)%pairs
            truncated =. (number <.cents%100),'.',_2{.'00',number 100|cents
        end.
        emit (side{::labels),' sum=',(number total),' average=',average,' truncated=',truncated,' first=',(number +/values=1),' unmatched=',number side{unmatched
    end.
)

create_market =: 3 : 0
    words =. y
    command =. 0{::words
    if. (<MarketName)e.MarketNames do. fail 'DUPLICATE MARKET ',MarketName end.
    Kind =: 0
    if. command-:'ROOMS' do. Kind =: 1 end.
    if. command-:'HOUSES' do. Kind =: 2 end.
    Names =: Houses =: 0$a:
    P =: 0
    if. command-:'RANDOM' do.
        P =: 0".2{::words
        for_i. 1+i.P do. Names =: Names,<'P',number i end.
        for_i. 1+i.P do. Names =: Names,<'R',number i end.
    else.
        for_word. 2}.words do.
            word =. >word
            if. word-:'|' do. P =: #Names continue. end.
            name =. word
            house =. ''
            if. Kind=2 do. 'name house' =. ':' split word end.
            if. (<name)e.Names do. fail 'DUPLICATE AGENT ',name end.
            if. Kind=2 do.
                if. (<house)e.Houses do. fail 'DUPLICATE HOUSE ',house end.
                Houses =: Houses,<house
            end.
            Names =: Names,<name
        end.
    end.
    Prefs =: (#Names)#<i.0
    Caps =: (#Names)#1
    Current =: i.0
    Source =: ''
    if. command-:'RANDOM' do.
        state =. x:0".3{::words
        for_a. i.#Names do.
            preference =. i.P
            if. a<P do. preference =. P+preference end.
            for_length. |.2+i.P-1 do.
                state =. 2147483647x|48271x*state
                index =. length|state
                last =. length-1
                preference =. ((index{preference),(last{preference)) (last,index)}preference
            end.
            Prefs =: (<preference) a}Prefs
        end.
        emit 'RANDOM ',MarketName,' n=',(number P),' seed=',3{::words
    elseif. Kind=0 do.
        emit 'MARKET ',MarketName,' proposers=',(number P),' receivers=',number (#Names)-P
    else.
        emit command,' ',MarketName,' agents=',number #Names
    end.
    MarketNames =: MarketNames,<MarketName
    Markets =: Markets,<pack ''
)
show =: 3 : 0
    if. Kind=0 do.
        emit 'SHOW ',MarketName,' MARKET proposers=',(number P),' receivers=',number (#Names)-P
    else.
        label =. (Kind-1){::;:'ROOMS HOUSES'
        emit 'SHOW ',MarketName,' ',label,' agents=',number #Names
    end.
    for_a. i.#Names do.
        if. Kind=0 do.
            if. a<P do.
                prefix =. 'PROPOSER ',a{::Names
            else.
                prefix =. 'RECEIVER ',(a{::Names),' cap=',number a{Caps
            end.
        else.
            prefix =. 'AGENT ',a{::Names
            if. Kind=2 do. prefix =. prefix,' house=',a{::Houses end.
        end.
        emit prefix,' ',list_text a{::Prefs
    end.
    if. Kind=0 do.
        label =. '-'
        if. #Source do. label =. Source end.
        emit 'CURRENT ',label
    end.
)
execute =: 3 : 0
    words =. ' ' split y
    command =. 0{::words
    MarketName =: 1{::words
    if. (<command)e.;:'MARKET ROOMS HOUSES RANDOM' do. create_market words return. end.
    market_index =. MarketNames i.<MarketName
    if. market_index=#MarketNames do. fail 'UNKNOWN MARKET ',MarketName end.
    'Kind Names P Houses Prefs Caps Current Source' =: market_index{::Markets
    select. command
    case. 'SHOW' do. show ''
    case. 'PREF' do.
        who =. agent 2{::words
        names =. Names
        choices =. i.#Names
        if. Kind=2 do.
            names =. Houses
        elseif. Kind=1 do.
            choices =. choices-.who
        elseif. who<P do.
            choices =. P+i.(#Names)-P
        else.
            choices =. i.P
        end.
        preference =. i.0
        for_word. 3}.words do.
            choice =. names i.word
            if. -.choice e.choices do. fail 'BAD CHOICE ',>word end.
            if. choice e.preference do. fail 'DUPLICATE CHOICE ',>word end.
            preference =. preference,choice
        end.
        Prefs =: (<preference) who}Prefs
        if. Kind=0 do.
            Source =: ''
            Current =: i.0
        end.
        emit 'PREF ',MarketName,' ',(who{::Names),' length=',number #preference
    case. 'CAPACITY' do.
        require_kind 0
        receiver =. 1 side_agent 2{::words
        capacity =. 0".3{::words
        Caps =: capacity receiver}Caps
        Source =: ''
        Current =: i.0
        emit 'CAPACITY ',MarketName,' ',(receiver{::Names),' ',number capacity
    case. 'GS';'GSR' do.
        require_kind 0
        'matching proposals history' =. Prefs deferred command-:'GSR'
        Current =: matching
        Source =: command
        emit command,' ',MarketName,' proposals=',number proposals
        if. 3=#words do. Output =: Output,history end.
        emit 'MATCHING ',pair_text matching
    case. 'CHECK' do.
        if. Kind=2 do. fail 'WRONG TYPE ',MarketName end.
        check_pairs 2}.words
    case. 'LATTICE';'EGALITARIAN';'MINREGRET' do.
        require_kind 0
        if. +./1~:P}.Caps do. fail 'NOT ONE TO ONE' end.
        'matchings origins vias numbered' =. enumerate ''
        if. command-:'LATTICE' do.
            emit 'LATTICE ',MarketName,' matchings=',(number #matchings),' rotations=',number #numbered
            for_i. i.#matchings do.
                matching =. i{::matchings
                'cost regret' =. metrics matching
                origin =. via =. '-'
                if. i do.
                    origin =. number i{origins
                    via =. number i{vias
                end.
                emit 'MATCHING ',(number i+1),' from=',origin,' via=',via,' cost=',(number cost),' regret=',(number regret),' ',pair_text matching
            end.
            for_i. i.#numbered do. emit 'ROTATION ',(number i+1),' ',i{::numbered end.
        else.
            criterion =. command-:'MINREGRET'
            scores =. i.0
            for_matching. matchings do. scores =. scores,criterion{metrics >matching end.
            best =. scores i.<./scores
            Current =: best{::matchings
            Source =: command
            label =. criterion{::;:'cost regret'
            emit command,' ',MarketName,' matching=',(number best+1),' ',label,'=',number best{scores
            emit 'MATCHING ',pair_text Current
        end.
    case. 'HR' do.
        require_kind 0
        hr ''
    case. 'ROOMMATES' do.
        require_kind 1
        for_a. i.#Names do.
            if. (#a{::Prefs)<(#Names)-1 do. fail 'INCOMPLETE ',a{::Names end.
        end.
        roommates 3=#words
    case. 'TTC' do.
        require_kind 2
        ttc ''
    case. 'SERIAL' do.
        require_kind 2
        serial 2}.words
    case. 'BOSTON' do.
        require_kind 0
        'matching applications' =. boston Prefs
        Current =: matching
        Source =: 'BOSTON'
        emit 'BOSTON ',MarketName,' applications=',number applications
        emit 'MATCHING ',pair_text matching
    case. 'MANIPULATE' do.
        require_kind 0
        manipulate 0 side_agent 2{::words
    case. 'STATS' do.
        require_kind 0
        if. 0=#Source do. fail 'NO MATCHING' end.
        stats ''
    end.
    Markets =: (<pack '') market_index}Markets
)
main =: 3 : 0
    count =. 0".1!:1 3
    for_i. i.count do.
        line =. 1!:1 3
        Output =: 0$a:
        try. execute line
        catcht. Output =: <'ERROR ',Error
        end.
        for_row. Output do. ((>row),LF) 1!:2 4 end.
    end.
)
main ''
exit 0
