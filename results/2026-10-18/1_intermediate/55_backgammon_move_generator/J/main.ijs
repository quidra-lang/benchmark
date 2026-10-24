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
    fields =. 0$a:
    for_v. y do.
        v =. >v
        if. 2~:3!:0 v do. v =. num v end.
        fields =. fields,<,v
    end.
    ' 'join fields
)
emit =: 3 : 'Output =: Output,<y'
say =: 3 : 'emit words y'
parse =: 3 : '0". ''_'' (I.y=''-'')}y'
color =: 3 : ',y{''WB'''
owner =: 3 : 0
    if. y=_1 do. 'center' else. color y end.
)
fail =: 3 : 0
    emit 'ERROR ',y
    throw.
)
initial =: 3 : 0
    p =. 5 3 5 2 (6 8 13 24)}26#0
    (p,:p);0;1;_1;0;0;0 0
)
notation =: 3 : 0
    'pairs hits' =. y
    key =. (\:pairs){pairs
    while. 1 do.
        a =. _1
        b =. _1
        for_i. i.#key do.
            's t' =. i{key
            starts =. I.t=0{"1 key
            if. (t>0)*.(-.t e.hits)*.0<#starts do.
                a =. i
                b =. {.starts
                break.
            end.
        end.
        if. a=_1 do. break. end.
        pair =. (0{a{key),1{b{key
        key =. ((i.#key)-.a,b){key
        key =. key,pair
        key =. (\:key){key
    end.
    elements =. 0$a:
    marked =. i.0
    i =. 0
    while. i<#key do.
        's t' =. i{key
        j =. >:i
        while. j<#key do.
            if. -. (i{key)-:j{key do. break. end.
            j =. >:j
        end.
        source =. num s
        target =. num t
        if. s=25 do. source =. 'bar' end.
        if. t=0 do. target =. 'off' end.
        text =. source,'/',target
        if. (t e.hits)*.-.t e.marked do. text =. text,'*'
            marked =. marked,t
        end.
        if. (j-i)>1 do. text =. text,'(',(num j-i),')' end.
        elements =. elements,<text
        i =. j
    end.
    text =. 'none'
    if. #elements do. text =. ' 'join elements end.
    key;text
)
visit =: 3 : 0
    'position dice pairs hits used' =. y
    'key text' =. notation pairs;hits
    GenPossible =: GenPossible,<position;pairs;hits;used;key;text
    own =. GenSide{position
    other =. (1-GenSide){position
    for_i. i.#dice do.
        if. i do. if. (i{dice)=(i-1){dice do. continue. end. end.
        d =. i{dice
        starts =. |.>:i.24
        if. 25{own do. starts =. ,25 end.
        for_s. starts do.
            if. 0=s{own do. continue. end.
            t =. s-d
            if. t>0 do.
                if. 2<:(25-t){other do. continue. end.
            else.
                if. +./0<7}.own do. continue. end.
                if. t<0 do.
                    if. +./0<(s+1)}.7{.own do. continue. end.
                end.
                t =. 0
            end.
            nextOwn =. (<:s{own)s}own
            nextOwn =. (>:t{nextOwn)t}nextOwn
            nextOther =. other
            hit =. 0
            if. t>0 do. hit =. 1=(25-t){other end.
            if. hit do.
                nextOther =. 0 (25-t)}nextOther
                nextOther =. (>:25{nextOther)25}nextOther
            end.
            next =. nextOwn GenSide}position
            next =. nextOther (1-GenSide)}next
            newHits =. hits
            if. hit do. newHits =. ~.hits,t end.
            visit next;(((i.#dice)-.i){dice);(pairs,s,t);newHits;used,d
        end.
    end.
)
generate =: 3 : 0
    'position side d1 d2' =. y
    GenSide =: side
    GenPossible =: 0$a:
    dice =. /:~d1,d2
    if. d1=d2 do. dice =. 4#d1 end.
    visit position;dice;(0 2$0);(i.0);i.0
    maximum =. 0
    for_p. GenPossible do. maximum =. maximum>.#1{::>p end.
    candidates =. 0$a:
    for_p. GenPossible do.
        if. maximum=#1{::>p do. candidates =. candidates,p end.
    end.
    if. (maximum=1)*.d1~:d2 do.
        bigger =. 0$a:
        for_p. candidates do.
            if. (d1>.d2)={.3{::>p do. bigger =. bigger,p end.
        end.
        if. #bigger do. candidates =. bigger end.
    end.
    positions =. 0$a:
    legal =. 0$a:
    keys =. 0$a:
    for_p. candidates do.
        position =. 0{::>p
        if. (<position)e.positions do. continue. end.
        positions =. positions,<position
        legal =. legal,p
        key =. ,4{::>p
        NB. Keys have equal row count or use a sentinel to put longer prefixes first.
        keys =. keys,<(key,_1)
    end.
    legal =. (\:keys){legal
    GenPossible;legal;maximum
)
pips =: 4 : '+/(i.26)*y{x'
evaluate =: 4 : 0
    position =. x
    side =. y
    own =. side{position
    other =. (1-side){position
    P =. (position pips 1-side)-position pips side
    S =. H =. R =. A =. run =. 0
    for_p. >:i.24 do.
        if. 2<:p{own do.
            run =. >:run
            R =. R>.run
            H =. H+p<:6
            A =. A+p>:19
        else. run =. 0 end.
        if. 1~:p{own do. continue. end.
        distances =. i.0
        for_q. i.p do.
            index =. 25-q
            if. 0<index{other do. distances =. distances,p-q end.
        end.
        for_a. >:i.6 do. for_b. >:i.6 do.
            hit =. (a e.distances)+.(b e.distances)+.(a+b)e.distances
            if. a=b do. hit =. hit+.((3*a)e.distances)+.(4*a)e.distances end.
            S =. S+hit
        end. end.
    end.
    G =. (25{other)-25{own
    E =. (2*P)-S
    E =. E+(4*H)+(3*R)+(3*A)+6*G
    E,P,S,H,R,A,G
)
ranked =: 4 : 0
    side =. x
    plays =. y
    scores =. i.0
    for_p. plays do. scores =. scores,{.(0{::>p)evaluate side end.
    order =. \:scores
    (order{plays);order{scores
)
contact =: 3 : 0
    w =. 0{y
    b =. 1{y
    maxW =. 0
    minB =. 25
    if. 25{w do. maxW =. 25 end.
    if. 25{b do. minB =. 0 end.
    for_p. >:i.24 do.
        if. p{w do. maxW =. maxW>.p end.
        if. p{b do. minB =. minB<.25-p end.
    end.
    maxW>minB
)
keith =: 4 : 0
    own =. y{x
    (x pips y)+(2*0>.(1{own)-1)+(0>.(2{own)-1)+(0>.(3{own)-3)++/0=4 5 6{own
)
cube =: 4 : 0
    prohibited =. x
    'position side value owner pending over score' =. y
    if. (owner=1-side)+.(value=64)+.prohibited do. 'unavailable' return. end.
    if. contact position do.
        e =. {.position evaluate side
        if. e<60 do. 'no double' elseif. e<:100 do. 'double take' else. 'double drop' end.
    else.
        v =. (8*position keith side)-7*position keith 1-side
        limit =. 21+7*owner=_1
        if. v>limit do. 'no double' elseif. v>:14 do. 'double take' else. 'double drop' end.
    end.
)
finish =: 3 : 0
    's winner kind' =. y
    'position side value own pending over score' =. s
    multiplier =. 1+('gammon'eq kind)+2*'backgammon'eq kind
    points =. value*multiplier
    score =. (points+winner{score)winner}score
    s =. position;side;value;own;0;1;score
    s;<(winner;kind;points)
)
move =: 4 : 0
    s =. x
    play =. y
    'old side value own pending over score' =. s
    position =. 0{::play
    if. 15=0{side{position do.
        opponent =. (1-side){position
        if. 0<0{opponent do. kind =. 'single'
        elseif. (0<25{opponent)+.+./0<19}.25{.opponent do. kind =. 'backgammon'
        else. kind =. 'gammon' end.
        finish (position;side;value;own;pending;over;score);side;kind
    else.
        (position;(1-side);value;own;pending;over;score);i.0
    end.
)
resultLine =: 3 : 0
    'winner kind points' =. y
    words 'result';(color winner);kind;points
)
apply =: 3 : 0
    'play d1 d2' =. y
    before =. State
    side =. 1{::State
    record =. words (color side);((num d1),'-',num d2);5{::play
    'State result' =: State move play
    History =: History,<record;before;<State
    Redo =: 0$a:
    if. #result do. emit resultLine result end.
)
range =: 4 : '(x>:{.y)*.x<:{:y'
parsePlay =: 3 : 0
    elements =. y
    if. (1=#elements)*.'none'eq 0{::elements do. 0 2$0 return. end.
    pairs =. 0 2$0
    for_el. elements do.
        text =. >el
        repeat =. 1
        if. ')'={:text do.
            open =. text i.'('
            if. open=(#text)-3 do.
                digit =. (open+1){text
                if. -.digit e.'234' do. _1 return. end.
                repeat =. parse ,digit
                text =. open{.text
            else. _1 return. end.
        end.
        tokens =. '/'split text
        if. (#tokens)<2 do. _1 return. end.
        points =. i.0
        for_i. i.#tokens do.
            token =. i{::tokens
            if. (i=0)*.'bar'eq token do. p =. 25
            elseif. (i>0)*.'off'eq token do. p =. 0
            else.
                if. i>0 do.
                    if. '*'={:token do. token =. }:token end.
                end.
                if. (0=#token)+.-.*./token e.'0123456789' do. _1 return. end.
                p =. parse token
                if. (-.(p range 1 24))+. -.token eq num p do. _1 return. end.
            end.
            if. #points do. if. p>:{:points do. _1 return. end. end.
            points =. points,p
        end.
        for_i. >:i.<:#points do.
            pair =. ((i-1){points),i{points
            pairs =. pairs,repeat#,:pair
        end.
    end.
    pairs
)
proposed =: 3 : 0
    position =. 0{::State
    side =. 1{::State
    own =. side{position
    other =. (1-side){position
    for_pair. <"1 y do.
        's t' =. ,>pair
        own =. (<:s{own)s}own
        own =. (>:t{own)t}own
    end.
    for_t. ~.1{"1 y do.
        if. t>0 do.
            if. 1=(25-t){other do.
                other =. 0 (25-t)}other
                other =. (>:25{other)25}other
            end.
        end.
    end.
    position =. own side}position
    other (1-side)}position
)
nextRandom =: 3 : 0
    Seed =: 2147483647|48271*Seed
    Seed
)
selfPlay =: 3 : 0
    's strategies opening report matchTarget matchScore crawford' =. y
    openingDice =. i.0
    if. opening do.
        w =. b =. 0
        while. w=b do.
            w =. 1+6|nextRandom''
            b =. 1+6|nextRandom''
        end.
        side =. w<b
        s =. (<side)1}s
        openingDice =. w,b
    end.
    first =. 1{::s
    turn =. 1
    turns =. 0
    while. 1 do.
        'position side value own pending over score' =. s
        if. #openingDice do.
            dice =. openingDice
            openingDice =. i.0
        else.
            prohibited =. 0
            if. matchTarget do. prohibited =. crawford+.matchTarget<:value+side{matchScore end.
            decision =. prohibited cube s
            if. (<decision)e.'double take';'double drop' do.
                if. report do.
                    say turn;(color side);'doubles';2*value
                    reply =. 'takes'
                    if. 'double drop'eq decision do. reply =. 'drops' end.
                    say turn;(color 1-side);reply
                end.
                if. 'double drop'eq decision do.
                    's result' =. finish s;side;'drop'
                    if. report do. emit resultLine result end.
                    result;turns;first return.
                end.
                value =. 2*value
                own =. 1-side
                s =. position;side;value;own;pending;over;score
            end.
            d1 =. 1+6|nextRandom''
            d2 =. 1+6|nextRandom''
            dice =. d1,d2
        end.
        'possible legal maximum' =. generate position;side;({.dice);{:dice
        strategy =. side{::strategies
        if. 'FIRST'eq strategy do. play =. 0{::legal
        elseif. 'RANDOM'eq strategy do. play =. ((#legal)|nextRandom''){::legal
        else. play =. 0{::0{::side ranked legal end.
        if. report do. say turn;(color side);((num {.dice),'-',num {:dice);5{::play end.
        's result' =. s move play
        turns =. >:turns
        if. #result do.
            if. report do. emit resultLine result end.
            result;turns;first return.
        end.
        turn =. >:turn
    end.
)
State =: initial''
History =: Redo =: Output =: 0$a:
NoArgs =: ;:'NEW SHOW BOARD PIPS RACE EVAL SHOTS CUBE DOUBLE TAKE DROP SCORE HISTORY'
Known =: NoArgs,;:'POS MOVES PLAY AUTO HINT RESIGN UNDO REDO GAME MATCH STATS'
NoOver =: ;:'RACE MOVES PLAY AUTO HINT EVAL SHOTS CUBE DOUBLE TAKE DROP RESIGN GAME'
NoPending =: ;:'PLAY AUTO CUBE DOUBLE RESIGN GAME'
boardRow =: 3 : 0
    fields =. 0$a:
    for_v. y do. fields =. fields,<_3{.'   ',>v end.
    emit (;6{.fields),' |',;6}.fields
)
boardFields =: 3 : 0
    'position points row' =. y
    fields =. 0$a:
    for_p. points do.
        w =. p{0{position
        b =. (25-p){1{position
        count =. w+b
        text =. '.'
        if. count>:row do.
            text =. 'B'
            if. w do. text =. 'W' end.
        end.
        if. (row=5)*.count>5 do. text =. num count end.
        fields =. fields,<text
    end.
    fields
)
execute =: 3 : 0
    tokens =. ' 'split y
    cmd =. 0{::tokens
    args =. }.tokens
    a =. >parse each args
    if. -.(<cmd)e.Known do. fail 'unknown command' end.
    'position side value own pending over score' =. State
    if. 'POS'eq cmd do.
        valid =. 4=#args
        if. valid do.
            points =. >parse each ','split 0{::args
            wb =. parse 1{::args
            bb =. parse 2{::args
            nextSide =. 'WB'i.{.3{::args
            valid =. (24=#points)*.(wb range 0 15)*.(bb range 0 15)*.(<3{::args)e.;:'W B'
            white =. wb++/0>.points
            black =. bb++/0>.-points
            valid =. valid*.(white range 1 15)*.black range 1 15
        end.
        if. -.valid do. fail 'bad position' end.
        p =. 2 26$0
        w =. (15-white),(0>.points),wb
        b =. (15-black),(|.0>.-points),bb
        p =. w,:b
        State =: p;nextSide;1;_1;0;0;score
        History =: Redo =: 0$a:
        emit 'OK'
        return.
    end.
    valid =. 1
    select. cmd
    case. 'MOVES';'AUTO';'PLAY';'HINT' do.
        required =. 2
        if. 'PLAY'eq cmd do. valid =. 3<:#args
        elseif. 'HINT'eq cmd do. valid =. 3=#args
        else. valid =. 2=#args end.
        if. valid do.
            valid =. ((0{a)range 1 6)*.(1{a)range 1 6
            if. 'HINT'eq cmd do. valid =. valid*.(2{a)range 1 1000 end.
        end.
    case. 'RESIGN' do.
        valid =. 1=#args
        if. valid do. valid =. (<0{::args)e.;:'single gammon backgammon' end.
    case. 'UNDO';'REDO' do.
        valid =. 1=#args
        if. valid do. valid =. (0{a)range 1 1000 end.
    case. 'GAME' do.
        valid =. 3=#args
        if. valid do. valid =. ((0{a)range 1 2147483646)*.*./(}.args)e.;:'BEST FIRST RANDOM' end.
    case. 'MATCH';'STATS' do.
        valid =. 2=#args
        if. valid do.
            limit =. 15
            if. 'STATS'eq cmd do. limit =. 50 end.
            valid =. ((0{a)range 1,limit)*.(1{a)range 1 2147483646
        end.
    case. do. valid =. 0=#args
    end.
    if. -.valid do. fail 'bad arguments' end.
    if. over*.(<cmd)e.NoOver do. fail 'game over' end.
    if. pending*.(<cmd)e.NoPending do. fail 'double pending' end.
    select. cmd
    case. 'NEW' do.
        State =: (<score)6}initial''
        History =: Redo =: 0$a:
        emit 'OK'
    case. 'SHOW' do.
        points =. (1}.25{.0{position)-|.1}.25{.1{position
        say 'POS';(','join num each <"0 points);(25{0{position);(25{1{position);color side
    case. 'BOARD' do.
        top =. 13+i.12
        bottom =. |.>:i.12
        boardRow num each <"0 top
        for_row. >:i.5 do. boardRow boardFields position;top;row end.
        status =. (color side),' to move'
        if. pending do. status =. (color side),' doubles' end.
        if. over do. status =. 'game over' end.
        emit 'bar W',(num 25{0{position),' B',(num 25{1{position),' | off W',(num 0{0{position),' B',(num 0{1{position),' | cube ',(num value),' ',(owner own),' | ',status
        for_row. |.>:i.5 do. boardRow boardFields position;bottom;row end.
        boardRow num each <"0 bottom
    case. 'PIPS' do. say 'pips';'W';(position pips 0);'B';position pips 1
    case. 'RACE' do.
        if. contact position do. emit 'contact' else. say 'race';'W';(position keith 0);'B';position keith 1 end.
    case. 'MOVES';'PLAY';'AUTO';'HINT' do.
        if. 'PLAY'eq cmd do.
            pairs =. parsePlay 2}.args
            if. _1-:pairs do. emit 'ILLEGAL syntax' return. end.
            final =. proposed pairs
            mine =. side{final
            other =. (1-side){position
            if. +./mine<0 do. emit 'ILLEGAL no checker' return. end.
            if. (0<25{mine)*.+./25~:0{"1 pairs do. emit 'ILLEGAL bar' return. end.
            blocked =. 0
            for_t. 1{"1 pairs do.
                if. t>0 do. blocked =. blocked+.2<:(25-t){other end.
            end.
            if. blocked do. emit 'ILLEGAL blocked' return. end.
            if. (0 e.1{"1 pairs)*.+./0<7}.mine do. emit 'ILLEGAL bear-off' return. end.
        end.
        'possible legal maximum' =. generate position;side;(0{a);1{a
        if. 'MOVES'eq cmd do.
            for_play. legal do. emit 5{::>play end.
            say 'total';#legal
        elseif. 'PLAY'eq cmd do.
            chosen =. i.0
            for_play. legal do.
                if. final-:0{::>play do. chosen =. >play break. end.
            end.
            if. #chosen do.
                emit 'OK ',5{::chosen
                apply chosen;(0{a);1{a
            else.
                same =. 0
                fewer =. 0
                for_play. possible do.
                    if. final-:0{::>play do.
                        same =. 1
                        fewer =. fewer+.maximum>#1{::>play
                    end.
                end.
                reason =. 'impossible'
                if. same do.
                    reason =. 'larger die required'
                    if. fewer do. reason =. 'too few dice' end.
                end.
                emit 'ILLEGAL ',reason
            end.
        else.
            'choices scores' =. side ranked legal
            if. 'HINT'eq cmd do.
                for_i. i.(#choices)<.2{a do. say (i{scores);5{::i{::choices end.
            else.
                play =. 0{::choices
                say 'OK';(5{::play);'eval';0{scores
                apply play;(0{a);1{a
            end.
        end.
    case. 'EVAL' do.
        'E P S H R A G' =. position evaluate side
        say 'eval';E;'pips';P;'blots';S;'home';H;'prime';R;'anchors';A;'bar';G
    case. 'SHOTS' do.
        blots =. |.I.1=side{position
        blots =. blots#~(blots>:1)*.blots<:24
        weights =. (#blots)#0
        rolls =. 0$a:
        total =. 0
        for_a. |.>:i.6 do. for_b. |.>:i.a do.
            legal =. 1{::generate position;(1-side);a;b
            hits =. i.0
            for_play. legal do. hits =. hits,2{::>play end.
            marked =. (25-blots)e.hits
            weight =. 2-a=b
            weights =. weights+weight*marked
            if. +./marked do.
                total =. total+weight
                rolls =. rolls,<(num a),'-',num b
            end.
        end. end.
        text =. 'shots ',(num total),'/36'
        if. #rolls do. text =. text,' ',' 'join rolls end.
        emit text
        for_i. i.#blots do. emit 'blot ',(num i{blots),' ',(num i{weights),'/36' end.
    case. 'CUBE' do. emit 'cube ',0 cube State
    case. 'DOUBLE' do.
        if. (own=1-side)+.value=64 do. fail 'cube unavailable' end.
        State =: (<1)4}State
        Redo =: 0$a:
        say 'OK';'double';2*value
    case. 'TAKE' do.
        if. -.pending do. fail 'no double' end.
        State =: position;side;(2*value);(1-side);0;over;score
        Redo =: 0$a:
        say 'OK';'take';(2*value);color 1-side
    case. 'DROP';'RESIGN' do.
        if. 'DROP'eq cmd do.
            if. -.pending do. fail 'no double' end.
            winner =. side
            kind =. 'drop'
            text =. 'OK drop'
        else.
            winner =. 1-side
            kind =. 0{::args
            text =. 'OK resign'
        end.
        'State result' =: finish State;winner;kind
        Redo =: 0$a:
        emit text
        emit resultLine result
    case. 'SCORE' do. say 'score';'W';(0{score);'B';1{score
    case. 'HISTORY' do.
        say 'history';#History
        for_i. i.#History do. say (i+1);0{::i{::History end.
    case. 'UNDO' do.
        n =. 0{a
        if. n>#History do. fail 'cannot undo' end.
        entries =. (-n){.History
        History =: (-n)}.History
        State =: 1{::0{::entries
        Redo =: entries,Redo
        emit 'OK'
    case. 'REDO' do.
        n =. 0{a
        if. n>#Redo do. fail 'cannot redo' end.
        entries =. n{.Redo
        Redo =: n}.Redo
        History =: History,entries
        State =: 2{::>{:entries
        emit 'OK'
    case. 'GAME';'MATCH';'STATS' do.
        if. 'GAME'eq cmd do.
            Seed =: 0{a
            selfPlay State;(}.args);0;1;0;0 0;0
        else.
            Seed =: 1{a
            target =. 0{a
            scores =. 0 0
            counts =. 4 2$0
            kinds =. ;:'single gammon backgammon drop'
            game =. turns =. used =. 0
            while. 1 do.
                if. 'MATCH'eq cmd do.
                    if. +./scores>:target do. break. end.
                elseif. game>:target do. break. end.
                game =. >:game
                crawford =. ('MATCH'eq cmd)*.(-.used)*.(>./scores)=target-1
                used =. used+.crawford
                matchTarget =. 0
                if. 'MATCH'eq cmd do. matchTarget =. target end.
                'result played first' =. selfPlay (initial'');('BEST';'BEST');1;0;matchTarget;scores;crawford
                'winner kind points' =. result
                scores =. (points+winner{scores)winner}scores
                row =. kinds i.<kind
                counts =. (>:winner{row{counts)(<row,winner)}counts
                turns =. turns+played
                if. 'MATCH'eq cmd do.
                    text =. words 'game';game
                    if. crawford do. text =. text,' crawford' end.
                    text =. text,' ',words 'start';(color first);'turns';played
                    text =. text,' ',(resultLine result),' score ',(num 0{scores),'-',num 1{scores
                    emit text
                end.
            end.
            if. 'MATCH'eq cmd do.
                winner =. 0
                if. (1{scores)>:target do. winner =. 1 end.
                say 'match';(color winner);(num 0{scores),'-',num 1{scores
            else.
                for_i. i.4 do. say (i{::kinds);'W';(0{i{counts);'B';1{i{counts end.
                say 'points';'W';(0{scores);'B';1{scores
                say 'turns';turns
            end.
        end.
    end.
)
main =: 3 : 0
    lines =. <;._2 (1!:1 <'/dev/stdin'),LF
    n =. parse 0{::lines
    for_i. >:i.n do.
        try. execute i{::lines catcht. end.
        1!:2&2 (LF join Output),LF
        Output =: 0$a:
    end.
)
main''
