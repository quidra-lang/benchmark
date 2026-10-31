LF =: 10{a.
ChainNames =: 0$a:
Chains =: 0$a:
Error =: ''
split =: 4 : '<;._1 x,y'
number =: 3 : ',''0'' 8!:2 y'
padded =: 4 : 0
    text =. number y
    ((0>.x-#text)#'0'),text
)
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
words =: 3 : 0
    parts =. 0$a:
    for_part. y do.
        part =. >part
        if. 2~:3!:0 part do. part =. number part end.
        parts =. parts,<part
    end.
    ' ' join parts
)
emit =: 3 : '(y,LF) 1!:2 4'
say =: 3 : 'emit words y'
fail =: 3 : 0
    Error =: y
    throw.
)
yes =: 3 : 'y{::''no'';''yes'''
fraction =: 3 : 0
    'p q' =. 2 x:y
    (number p),'/',number q
)
value =: 3 : 0
    'p q' =. 2 x:y
    decimal =. (number <.y),'.',6 padded <.(1000000x*(q|p))%q
    (fraction y),'(',decimal,')'
)
probability =: 3 : 0
    fields =. '/' split y
    p =. x:0".0{::fields
    q =. 1x
    if. 2=#fields do. q =. x:0".1{::fields end.
    if. (q=0)+.p>q do. fail 'BAD PROBABILITY' end.
    p%q
)
probabilities =: 3 : 0
    result =. 0$0x
    for_token. y do. result =. result,probability >token end.
    result
)
fsum =: 3 : 0
    result =. 0x
    for_term. y do. result =. result+term end.
    result
)
identity =: 3 : 'x:=/~i.y'
matmul =: 4 : 0
    result =. ((#x),{:$y)$0x
    for_i. i.#x do.
        for_j. i.{:$y do.
            total =. fsum (i{x)*j{"1 y
            result =. total (<i,j)}result
        end.
    end.
    result
)
eliminate =: 3 : 0
    rows =. y
    n =. #rows
    for_j. i.n do.
        r =. j+(0~:j{"1 j}.rows)i.1
        rows =. ((r,j){rows) (j,r)}rows
        pivot =. (<j,j){rows
        normalized =. (j{rows)%pivot
        rows =. normalized j}rows
        for_r. i.n do.
            if. r=j do. continue. end.
            factor =. (<r,j){rows
            if. factor~:0 do. rows =. ((r{rows)-factor*normalized) r}rows end.
        end.
    end.
    n}."1 rows
)
save_chain =: 4 : 0
    index =. ChainNames i.<x
    if. index=#ChainNames do.
        ChainNames =: ChainNames,<x
        Chains =: Chains,<y
    else. Chains =: (<y) index}Chains end.
)
state =: 4 : 0
    index =. x i.<y
    if. index=#x do. fail 'UNKNOWN STATE ',y end.
    index
)
unique_states =: 4 : 0
    result =. i.0
    for_name. y do.
        name =. >name
        index =. x state name
        if. index e.result do. fail 'DUPLICATE STATE ',name end.
        result =. result,index
    end.
    /:~result
)
display =: 3 : 0
    'names matrix prefix' =. y
    emit 'STATES ',' ' join names
    for_i. i.#names do.
        entries =. fraction each <"0 i{matrix
        emit prefix,' ',(i{::names),' ',' ' join entries
    end.
)
absorbing_states =: 3 : 'I.1=(,identity #y)#,y'
decompose =: 3 : 0
    n =. #y
    edges =. y>0
    reach =. edges+.identity n
    for_k. i.n do.
        for_i. i.n do.
            if. (<i,k){reach do. reach =. ((i{reach)+.k{reach) i}reach end.
        end.
    end.
    classes =. 0$a:
    closed =. i.0
    levels =. (0,n)$0
    periods =. i.0
    membership =. n#_1
    for_root. i.n do.
        if. _1~:root{membership do. continue. end.
        members =. I.(root{reach)*.root{"1 reach
        membership =. (#classes) members}membership
        inside =. (i.n)e.members
        closed =. closed,-.+./,(I.-.inside){"1 members{edges
        distances =. 0 root}n#_1
        queue =. ,root
        head =. 0
        while. head<#queue do.
            u =. head{queue
            head =. head+1
            neighbors =. members#~(members{u{edges)*._1=members{distances
            distances =. (1+u{distances) neighbors}distances
            queue =. queue,neighbors
        end.
        period =. 0
        for_u. members do.
            for_v. members do.
                if. (<u,v){edges do. period =. period+. |(1+u{distances)-v{distances end.
            end.
        end.
        classes =. classes,<members
        levels =. levels,distances
        periods =. periods,period
    end.
    (<reach),(<classes),(<closed),(<levels),(<periods),<membership
)
stationary =: 4 : 0
    n =. #y
    coefficients =. (|:y{"1 y{x)-identity n
    rows =. coefficients,.n#0x
    rows =. ((n+1)#1x) (n-1)}rows
    {."1 eliminate rows
)
hitting =: 4 : 0
    'targets reach only_probabilities' =. y
    n =. #x
    chances =. 1x targets}n#0x
    times =. 0x targets}n#_1x
    unknown =. I.(-.(i.n)e.targets)*.+./"1 targets{"1 reach
    if. #unknown do.
        coefficients =. (identity #unknown)-unknown{"1 unknown{x
        rhs =. fsum"1 targets{"1 unknown{x
        solution =. {."1 eliminate coefficients,.rhs
        chances =. solution unknown}chances
    end.
    if. only_probabilities do. chances;times return. end.
    certain =. unknown#~1=unknown{chances
    if. #certain do.
        coefficients =. (identity #certain)-certain{"1 certain{x
        solution =. {."1 eliminate coefficients,.(#certain)#1x
        times =. solution certain}times
    end.
    chances;times
)
absorption =: 3 : 0
    n =. #y
    absorbing =. absorbing_states y
    transient =. (i.n)-.absorbing
    t =. #transient
    fundamental =. 0 0$0x
    means =. variances =. 0$0x
    chances =. (0,#absorbing)$0x
    if. t do.
        unit =. identity t
        fundamental =. eliminate (unit-transient{"1 transient{y),.unit
        means =. fsum"1 fundamental
        variances =. t#0x
        for_i. i.t do.
            moment =. fsum ((2x*i{fundamental)-(i=i.t))*means
            variances =. (moment-(i{means)^2) i}variances
        end.
        chances =. fundamental matmul absorbing{"1 transient{y
    end.
    (<transient),(<absorbing),(<fundamental),(<means),(<variances),<chances
)
regular_exponent =: 3 : 0
    edges =. y>0
    power =. edges
    bound =. 1+(*:(#y)-1)
    for_t. 1+i.bound do.
        if. *./,power do. t return. end.
        if. t<bound do. power =. power +./ . *. edges end.
    end.
    0
)
create =: 3 : 0
    'verb name' =. 2{.y
    if. verb-:'CHAIN' do.
        names =. 2}.y
        if. 10<#names do. fail 'TOO MANY STATES' end.
        for_i. i.#names do.
            if. (i{names)e.i{.names do. fail 'DUPLICATE STATE ',i{::names end.
        end.
        name save_chain (<names),<((#names),#names)$0x
        say 'CHAIN';name;'states=',number #names
    elseif. verb-:'BUILD' do.
        order =. 0".2{::y
        tokens =. 3}.y
        if. -.order e.1 2 do. fail 'BAD ORDER' end.
        if. (#tokens)<:order do. fail 'TOO FEW TOKENS' end.
        observations =. tokens
        if. order=2 do.
            observations =. 0$a:
            for_i. i.(#tokens)-1 do.
                observations =. observations,<(i{::tokens),'.',(i+1){::tokens
            end.
        end.
        names =. ~.observations
        n =. #names
        if. n>10 do. fail 'TOO MANY STATES' end.
        indices =. names i.observations
        counts =. (n,n)$0
        for_i. i.(#indices)-1 do.
            position =. <(i{indices),(i+1){indices
            counts =. (1+position{counts) position}counts
        end.
        totals =. +/"1 counts
        p =. (n,n)$0x
        for_i. i.n do.
            if. i{totals do. p =. ((x:i{counts)%x:i{totals) i}p
            else. p =. 1x (<i,i)}p end.
        end.
        name save_chain (<names),<p
        say 'BUILD';name;('order=',number order);('states=',number n);'transitions=',number <:#observations
        for_i. i.n do.
            line =. words 'FROM';(i{::names);'total=',number i{totals
            if. 0=i{totals do. line =. line,' absorbing'
            else.
                for_j. I.0<i{counts do.
                    line =. line,' ',(j{::names),':',number (<i,j){counts
                end.
            end.
            emit line
        end.
    else.
        goal =. 0".2{::y
        start =. 0".3{::y
        if. (goal=0)+.goal>9 do. fail 'BAD SIZE' end.
        if. start>goal do. fail 'BAD START' end.
        chance =. probability 4{::y
        if. chance e.0 1 do. fail 'BAD PROBABILITY' end.
        names =. 0$a:
        for_i. i.goal+1 do. names =. names,<'s',number i end.
        p =. ((goal+1),goal+1)$0x
        p =. 1x (<0 0)}p
        p =. 1x (<goal,goal)}p
        for_i. 1+i.goal-1 do.
            p =. chance (<i,i+1)}p
            p =. (1x-chance) (<i,i-1)}p
        end.
        'transient absorbing fundamental means variances chances' =. absorption p
        ruin =. 1x (0}) (goal+1)#0x
        duration =. (goal+1)#0x
        if. #transient do.
            ruin =. (0{"1 chances) transient}ruin
            duration =. means transient}duration
        end.
        name save_chain (<names),<p
        say 'GAMBLER';name;('g=',number goal);('p=',fraction chance);('start=',start{::names);('ruin=',value start{ruin);'duration=',value start{duration
        for_i. i.goal+1 do.
            say 'CAPITAL';(i{::names);('ruin=',value i{ruin);('win=',value 1x-i{ruin);'duration=',value i{duration
        end.
    end.
)
command =: 3 : 0
    tokens =. ' ' split y
    'verb name' =. 2{.tokens
    if. (<verb)e.;:'CHAIN BUILD GAMBLER' do. create tokens return. end.
    chain_index =. ChainNames i.<name
    if. chain_index=#ChainNames do. fail 'UNKNOWN CHAIN ',name end.
    'names p' =. chain_index{::Chains
    n =. #names
    select. verb
    case. 'P' do.
        i =. names state 2{::tokens
        j =. names state 3{::tokens
        chance =. probability 4{::tokens
        p =. chance (<i,j)}p
        name save_chain (<names),<p
        say 'P';name;(i{::names);(j{::names);(fraction chance);'rowsum=',fraction fsum i{p
        return.
    case. 'ROW' do.
        i =. names state 2{::tokens
        if. n~:(#tokens)-3 do. fail 'BAD LENGTH' end.
        row =. probabilities 3}.tokens
        p =. row i}p
        name save_chain (<names),<p
        say 'ROW';name;(i{::names);'rowsum=',fraction fsum row
        return.
    case. 'SHOW' do.
        say 'MATRIX';name;'states=',number n
        display (<names),(<p),<'ROW'
        return.
    case. 'CHECK' do.
        totals =. fsum"1 p
        bad =. I.totals~:1
        if. 0=#bad do. say 'CHECK';name;'ok'
        else.
            say 'CHECK';name;'bad=',number #bad
            for_i. bad do. say 'BADROW';(i{::names);'sum=',fraction i{totals end.
        end.
        return.
    end.
    for_i. i.n do.
        if. 1~:fsum i{p do. fail 'NOT STOCHASTIC ',i{::names end.
    end.
    'reach classes closed levels periods membership' =. decompose p
    select. verb
    case. 'CLASSES' do.
        say 'CLASSES';name;'count=',number #classes
        for_c. i.#classes do.
            members =. c{::classes
            period =. c{periods
            kind =. (c{closed){::'TRANSIENT';'RECURRENT'
            emit (words 'CLASS';(c+1);kind;('period=',number period);('size=',number #members)),' ',' ' join members{names
            if. period>:2 do.
                for_r. i.period do.
                    cyclic =. members#~r=period|members{c{levels
                    emit 'CYCLIC ',(number r),' ',' ' join cyclic{names
                end.
            end.
        end.
    case. 'CLASSIFY' do.
        absorbing =. absorbing_states p
        absorbs =. (#absorbing)>0
        for_i. i.n do. absorbs =. absorbs*.+./absorbing{i{reach end.
        exponent =. regular_exponent p
        label =. '-'
        if. exponent do. label =. number exponent end.
        say 'CLASSIFY';name;('absorbing_states=',number #absorbing);('absorbing=',yes absorbs);('ergodic=',yes 1=#classes);('regular=',yes exponent>0);'exponent=',label
    case. 'STEP' do.
        initial =. 2{::tokens
        distribution =. n#0x
        if. ({.initial)e.'0123456789' do.
            parts =. ',' split initial
            if. n~:#parts do. fail 'BAD LENGTH' end.
            distribution =. probabilities parts
            if. 1~:fsum distribution do. fail 'BAD DISTRIBUTION' end.
        else. distribution =. 1x (names state initial)}distribution end.
        steps =. 0".3{::tokens
        for_t. i.steps do. distribution =. {. (,:distribution) matmul p end.
        say 'STEP';name;'k=',number steps
        for_i. i.n do. say 'PROB';(i{::names);value i{distribution end.
    case. 'POWER' do.
        steps =. 0".2{::tokens
        power =. identity n
        for_t. i.steps do. power =. power matmul p end.
        say 'POWER';name;'k=',number steps
        display (<names),(<power),<'ROW'
    case. 'STATIONARY' do.
        say 'STATIONARY';name;'count=',number +/closed
        ordinal =. 0
        for_c. I.closed do.
            members =. c{::classes
            pi =. p stationary members
            ordinal =. ordinal+1
            say 'DIST';ordinal;('class=',number c+1);'size=',number #members
            for_i. i.#members do. say 'PI';((i{members){::names);value i{pi end.
        end.
    case. 'RECURRENCE' do.
        i =. names state 2{::tokens
        c =. i{membership
        if. -.c{closed do. fail 'TRANSIENT STATE ',i{::names end.
        members =. c{::classes
        pi =. p stationary members
        rho =. (members i.i){pi
        say 'RECURRENCE';name;(i{::names);('pi=',value rho);('mean=',value %rho);'period=',number c{periods
    case. 'ABSORB' do.
        absorbing =. absorbing_states p
        if. 0=#absorbing do. fail 'NO ABSORBING STATE' end.
        for_i. i.n do.
            if. -.+./absorbing{i{reach do. fail 'NOT ABSORBING ',i{::names end.
        end.
        'transient absorbing fundamental means variances chances' =. absorption p
        t =. #transient
        say 'ABSORB';name;('transient=',number t);'absorbing=',number #absorbing
        if. t=0 do. return. end.
        emit 'TRANSIENT ',' ' join transient{names
        emit 'ABSORBING ',' ' join absorbing{names
        for_i. i.t do.
            emit 'N ',((i{transient){::names),' ',' ' join fraction each <"0 i{fundamental
        end.
        for_i. i.t do.
            say 'STEPS';((i{transient){::names);('mean=',value i{means);'var=',value i{variances
        end.
        for_i. i.t do.
            emit 'B ',((i{transient){::names),' ',' ' join fraction each <"0 i{chances
        end.
    case. 'HITTING' do.
        targets =. names unique_states 2}.tokens
        'chances times' =. p hitting targets;reach;0
        say 'HITTING';name;'targets=',',' join targets{names
        for_i. i.n do.
            duration =. 'inf'
            if. (i{times)>:0 do. duration =. value i{times end.
            say 'HIT';(i{::names);('prob=',value i{chances);'time=',duration
        end.
    case. 'PASSAGE' do.
        if. 1~:#classes do. fail 'NOT IRREDUCIBLE' end.
        pi =. p stationary i.n
        passage =. (n,n)$0x
        for_j. i.n do.
            'chances times' =. p hitting (,j);reach;0
            times =. (%j{pi) j}times
            for_i. i.n do. passage =. (i{times) (<i,j)}passage end.
        end.
        kemeny =. fsum (}.pi)*}.0{passage
        say 'PASSAGE';name;'kemeny=',value kemeny
        display (<names),(<passage),<'M'
    case. 'FIRSTPASSAGE' do.
        from =. names state 2{::tokens
        target =. names state 3{::tokens
        steps =. 0".4{::tokens
        if. steps=0 do. fail 'BAD STEPS' end.
        distribution =. target{"1 p
        first =. cumulative =. 0$0x
        total =. 0x
        others =. (i.n)-.target
        for_t. i.steps do.
            first =. first,from{distribution
            total =. total+from{distribution
            cumulative =. cumulative,total
            if. t=steps-1 do. break. end.
            next =. n#0x
            for_i. i.n do.
                next =. (fsum (others{i{p)*others{distribution) i}next
            end.
            distribution =. next
        end.
        say 'FIRSTPASSAGE';name;(from{::names);(target{::names);('k=',number steps);'total=',value total
        for_t. i.steps do. say 'FP';(t+1);(value t{first);'cum=',value t{cumulative end.
    case. 'PATHPROB' do.
        path =. i.0
        for_token. 2}.tokens do. path =. path,names state >token end.
        chance =. 1x
        zero_at =. 0
        for_t. 1+i.<:#path do.
            chance =. chance*(<((t-1){path),t{path){p
            if. (chance=0)*.zero_at=0 do. zero_at =. t end.
        end.
        line =. words 'PATHPROB';name;('steps=',number <:#path);'prob=',value chance
        if. zero_at do. line =. line,' zero_at=',number zero_at end.
        emit line
    case. 'MOSTLIKELY' do.
        start =. names state 2{::tokens
        steps =. 0".3{::tokens
        if. steps=0 do. fail 'BAD STEPS' end.
        best =. (n#1x) steps}((steps+1),n)$0x
        for_t. |.i.steps do.
            for_i. i.n do.
                best =. (>./(i{p)*(t+1){best) (<t,i)}best
            end.
        end.
        path =. ,start
        for_t. i.steps do.
            current =. {:path
            candidates =. (current{p)*(t+1){best
            path =. path,candidates i.(<t,current){best
        end.
        say 'MOSTLIKELY';name;(start{::names);('k=',number steps);'prob=',value (<0,start){best
        emit 'PATH ',' ' join path{names
    case. 'REVERSIBLE';'REVERSE' do.
        if. 1~:#classes do. fail 'NOT IRREDUCIBLE' end.
        pi =. p stationary i.n
        if. verb-:'REVERSIBLE' do.
            violations =. 0$a:
            for_i. i.n do.
                for_j. (i+1)+i.n-(i+1) do.
                    forward =. (i{pi)*(<i,j){p
                    backward =. (j{pi)*(<j,i){p
                    if. forward~:backward do. violations =. violations,<i;j;forward;backward end.
                end.
            end.
            if. 0=#violations do. say 'REVERSIBLE';name;'yes'
            else.
                say 'REVERSIBLE';name;'no';'violations=',number #violations
                for_record. violations do.
                    'i j forward backward' =. >record
                    say 'VIOLATION';(i{::names);(j{::names);(value forward);value backward
                end.
            end.
        else.
            reversed =. (n,n)$0x
            for_i. i.n do.
                for_j. i.n do. reversed =. (((j{pi)*(<j,i){p)%i{pi) (<i,j)}reversed end.
            end.
            (2{::tokens) save_chain (<names),<reversed
            say 'REVERSE';name;(2{::tokens);'reversible=',yes p-:reversed
            display (<names),(<reversed),<'ROW'
        end.
    case. 'MIXING' do.
        steps =. 0".2{::tokens
        if. steps=0 do. fail 'BAD STEPS' end.
        epsilon =. probability 3{::tokens
        if. 1~:#classes do. fail 'NOT IRREDUCIBLE' end.
        pi =. p stationary i.n
        power =. identity n
        distances =. 0$0x
        worst =. i.0
        mixing_time =. 0
        for_t. 1+i.steps do.
            power =. power matmul p
            row_distances =. (fsum"1 |power -"1 pi)%2x
            greatest =. >./row_distances
            distances =. distances,greatest
            worst =. worst,row_distances i.greatest
            if. (mixing_time=0)*.greatest<:epsilon do. mixing_time =. t end.
        end.
        label =. 'none'
        if. mixing_time do. label =. number mixing_time end.
        say 'MIXING';name;('k=',number steps);('eps=',fraction epsilon);'time=',label
        for_t. i.steps do. say 'TV';(t+1);(value t{distances);'from=',(t{worst){::names end.
    case. 'LUMP' do.
        blocks =. 0$a:
        seen =. i.0
        for_block. '|' split 3{::tokens do.
            members =. i.0
            for_token. ',' split >block do.
                i =. names state >token
                if. i e.seen do. fail 'BAD PARTITION' end.
                seen =. seen,i
                members =. members,i
            end.
            blocks =. blocks,</:~members
        end.
        if. n~:#seen do. fail 'BAD PARTITION' end.
        heads =. >{.&.>blocks
        blocks =. (/:heads){blocks
        representatives =. /:~heads
        count =. #blocks
        lumped =. (count,count)$0x
        for_k. i.count do.
            members =. k{::blocks
            representative =. {.members
            for_l. i.count do.
                target =. l{::blocks
                expected =. fsum target{representative{p
                for_i. members do.
                    actual =. fsum target{i{p
                    if. expected~:actual do.
                        say 'LUMP';name;'not';'lumpable';('block=',representative{::names);('target=',({.target){::names);((representative{::names),'=',value expected);(i{::names),'=',value actual
                        return.
                    end.
                end.
                lumped =. expected (<k,l)}lumped
            end.
        end.
        labels =. representatives{names
        (2{::tokens) save_chain (<labels),<lumped
        say 'LUMP';name;(2{::tokens);'blocks=',number count
        display (<labels),(<lumped),<'ROW'
    case. 'REWARD' do.
        if. n~:(#tokens)-3 do. fail 'BAD LENGTH' end.
        gamma =. probability 2{::tokens
        if. gamma=1 do. fail 'BAD DISCOUNT' end.
        rewards =. x:>0".each 3}.tokens
        discounted =. {."1 eliminate ((identity n)-gamma*p),.rewards
        gains =. n#0x
        for_c. I.closed do.
            members =. c{::classes
            pi =. p stationary members
            average =. fsum pi*members{rewards
            chances =. 0{::p hitting members;reach;1
            gains =. gains+chances*average
        end.
        say 'REWARD';name;'gamma=',fraction gamma
        for_i. i.n do. say 'VALUE';(i{::names);('discounted=',value i{discounted);'gain=',value i{gains end.
    case. 'RESTRICT' do.
        selected =. names unique_states 3}.tokens
        outside =. (i.n)-.selected
        for_i. selected do.
            if. +./0<outside{i{p do. fail 'NOT CLOSED ',i{::names end.
        end.
        labels =. selected{names
        restricted =. selected{"1 selected{p
        (2{::tokens) save_chain (<labels),<restricted
        say 'RESTRICT';name;(2{::tokens);'states=',number #selected
        display (<labels),(<restricted),<'ROW'
    case. 'SIMULATE' do.
        start =. names state 2{::tokens
        steps =. 0".3{::tokens
        if. steps=0 do. fail 'BAD STEPS' end.
        seed =. x:0".4{::tokens
        if. (seed=0)+.seed>:2147483647 do. fail 'BAD SEED' end.
        random =. seed
        current =. start
        path =. ,start
        for_t. i.steps do.
            common =. *./1{"1 2 x:current{p
            random =. 2147483647|48271x*random
            threshold =. common|random
            cumulative =. 0x
            for_j. i.n do.
                cumulative =. cumulative+(<current,j){p
                if. threshold<cumulative*common do. current =. j break. end.
            end.
            path =. path,current
        end.
        say 'SIMULATE';name;(start{::names);('steps=',number steps);('seed=',number seed);'end=',current{::names
        emit 'PATH ',' ' join path{names
        for_i. i.n do. say 'VISIT';(i{::names);+/i=path end.
    end.
)
main =: 3 : 0
    lines =. <;._2 (1!:1 3),LF
    count =. 0".0{::lines
    for_i. 1+i.count do.
        try. command i{::lines
        catcht. emit 'ERROR ',Error end.
    end.
)
main''
