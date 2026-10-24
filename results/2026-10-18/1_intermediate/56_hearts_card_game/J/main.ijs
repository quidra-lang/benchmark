LF =: 10{a.
num =: 3 : ',''0'' 8!:2 y'
eq =: 4 : '(,x)-:,y'
split =: 4 : '<;._1 x,y'
join =: 4 : 0
    r =. ''
    for_i. i.#y do.
        if. i do. r =. r,x end.
        r =. r,i{::y
    end.
    r
)
words =: 3 : 0
    r =. 0$a:
    for_v. y do.
        v =. >v
        if. 2~:3!:0 v do. v =. num v end.
        r =. r,<,v
    end.
    ' 'join r
)
emit =: 3 : 'Output =: Output,<y'
say =: 3 : 'emit words y'
fail =: 3 : 0
    emit 'error: ',y
    throw.
)
parse =: 3 : '0". ''_'' (I.y=''-'')}y'
Seats =: 'NESW'
Suits =: 'CDSH'
Ranks =: '23456789TJQKA'
Strategies =: ;:'BASIC LOW HIGH SMART MOON'
RuleNames =: ;:'TARGET LIMIT MOON JACK QSBREAK BLOOD PASS'
Rules =: 100;100;'ADD';'OFF';'OFF';'OFF';'LRAH'
Bots =: 4#<'BASIC'
Output =: 0$a:
PrintLevel =: 2
State =: 0
Number =: 0
X =: 1
Scores =: 4#0
Stats =: 4 4$0
Stacked =: 4#<i.0
History =: 0$a:
Hands =: 4#<i.0
Taken =: 4#<i.0
Passed =: 4#0
Passes =: 4#<i.0
Tricks =: 0$a:
Counts =: 4#0
Current =: 0 2$0
Leader =: 0
Broken =: 0
Undo =: 0$a:
Record =: 0$a:
PassCode =: 'L'
seatText =: 3 : ',y{Seats'
cardText =: 3 : '((13|y){Ranks),(<.y%13){Suits'
suit =: 3 : '<.y%13'
penalty =: 3 : '(y=36)+.3=suit y'
point =: 3 : 0
    if. y=36 do. 13
    elseif. 3=suit y do. 1
    elseif. (y=22)*.'ON'eq 3{::Rules do. _10
    else. 0 end.
)
points =: 3 : '+/point"0 y'
display =: 3 : 0
    if. 0=#y do. '-' return. end.
    ' 'join cardText&.> <"0 /:~y
)
seatValue =: 3 : 0
    if. (1~:#y)+.-.*./y e.Seats do. fail 'bad seat ',y end.
    Seats i.{.y
)
cardValue =: 3 : 0
    if. 2~:#y do. fail 'bad card ',y end.
    if. (-.({.y)e.Ranks)+.-.({:y)e.Suits do. fail 'bad card ',y end.
    (Ranks i.{.y)+13*Suits i.{:y
)
bounded =: 4 : 0
    v =. parse y
    if. (v<{.x)+.v>{:x do. fail 'bad value ',y end.
    v
)
pairs =: 4 : 0
    r =. x
    for_i. i.4 do. r =. r,' ',(seatText i),' ',words <i{::y end.
    r
)
direction =: 3 : '( ''LRAH'' i.{.y){::;:''LEFT RIGHT ACROSS HOLD'''
draw =: 3 : 'X =: 2147483647|48271x*X'
lowOrder =: 3 : '(/:((13|y),.suit y)){y'
highOrder =: 3 : '(/:((-(13|y)),.suit y)){y'
lowest =: 3 : '{.lowOrder y'
highest =: 3 : '{.highOrder y'
recordLine =: 3 : 0
    'level text' =. y
    if. level>0 do. Record =: Record,<text end.
    if. level<:PrintLevel do. emit text end.
)
position =: 3 : 'Hands;Taken;Tricks;Counts;Current;Leader;Broken;<Record'
restorePosition =: 3 : 0
    'Hands Taken Tricks Counts Current Leader Broken Record' =: y
)
saveGame =: 3 : 'State;Number;X;Scores;Stats;Stacked;History;Hands;Taken;Passed;Passes;Tricks;Counts;Current;Leader;Broken;Undo;Record;PassCode'
restoreGame =: 3 : 0
    'State Number X Scores Stats Stacked History Hands Taken Passed Passes Tricks Counts Current Leader Broken Undo Record PassCode' =: y
)
newGame =: 3 : 0
    State =: 1
    Number =: 0
    Scores =: 4#0
    Stats =: 4 4$0
    Stacked =: 4#<i.0
    History =: 0$a:
)
beginPlay =: 3 : 0
    State =: 3
    for_s. i.4 do.
        if. 0 e.s{::Hands do. Leader =: s break. end.
    end.
    recordLine 2;('lead ',seatText Leader)
)
deal =: 3 : 0
    Number =: >:Number
    cycle =. 6{::Rules
    PassCode =: ,((#cycle)|Number-1){cycle
    Hands =: Stacked
    used =. ;Hands
    deck =. (i.52)-.used
    if. 1<#deck do.
        for_i. |.>:i.<:#deck do.
            j =. (i+1)|draw''
            deck =. ((j,i){deck)(i,j)}deck
        end.
    end.
    free =. I.0=#&>Stacked
    for_i. i.#deck do.
        seat =. ((#free)|i){free
        Hands =: (<(seat{::Hands),i{deck)seat}Hands
    end.
    Stacked =: 4#<i.0
    Passed =: 4#0
    Passes =: 4#<i.0
    Taken =: 4#<i.0
    Tricks =: 0$a:
    Counts =: 4#0
    Current =: 0 2$0
    Broken =: 0
    Undo =: 0$a:
    Record =: 0$a:
    recordLine 1;words 'hand';Number;'pass';direction PassCode
    for_s. i.4 do. recordLine 2;((seatText s),': ',display s{::Hands) end.
    if. 'H'eq PassCode do. beginPlay'' else. State =: 2 end.
)
passCards =: 4 : 0
    Hands =: (<(x{::Hands)-.y)x}Hands
    Passes =: (<y)x}Passes
    Passed =: 1 x}Passed
    recordLine 2;((seatText x),' passes ',display y)
    if. *./Passed do.
        offset =. ('LRA'i.{.PassCode){1 3 2
        for_s. i.4 do.
            target =. 4|s+offset
            Hands =: (<(target{::Hands),s{::Passes)target}Hands
        end.
        beginPlay''
    end.
)
actor =: 3 : '4|Leader+#Current'
legal =: 3 : 0
    hand =. (actor''){::Hands
    if. 0=#Current do.
        if. 0=#Tricks do. ,0 return. end.
        safe =. hand#~3~:suit hand
        if. (-.Broken)*.0<#safe do. safe else. hand end.
        return.
    end.
    led =. suit 1{0{Current
    follow =. hand#~led=suit hand
    if. #follow do. follow return. end.
    if. (0=#Tricks)*.'OFF'eq 5{::Rules do.
        safe =. hand#~-.penalty hand
        if. #safe do. safe return. end.
    end.
    hand
)
choosePass =: 3 : 0
    hand =. y{::Hands
    strategy =. y{::Bots
    low =. lowOrder hand
    high =. highOrder hand
    hearts =. high#~3=suit high
    special =. 36 37 38#~36 37 38 e.hand
    select. strategy
    case. 'LOW' do. order =. high
    case. 'HIGH' do. order =. low
    case. 'MOON' do. order =. (low#~3~:suit low),low#~3=suit low
    case. 'SMART' do.
        protected =. (36 e.hand)*.5<:+/2=suit hand
        order =. special
        if. protected do. order =. i.0 end.
        counts =. +/"1 0 1=/suit hand
        choices =. I.counts>0
        if. #choices do.
            su =. {.choices /: choices{counts
            order =. order,high#~su=suit high
        end.
        order =. order,hearts,high
    case. do. order =. special,hearts,high
    end.
    3{.~.order
)
queenPlayed =: 3 : '(36 e.;Taken)+.36 e.1{"1 Current'
choosePlay =: 3 : 0
    seat =. actor''
    hand =. seat{::Hands
    cs =. legal''
    strategy =. seat{::Bots
    if. 'LOW'eq strategy do. lowest cs return. end.
    if. 'HIGH'eq strategy do. highest cs return. end.
    if. 'MOON'eq strategy do.
        for_o. (i.4)-.seat do.
            if. +./penalty o{::Taken do. strategy =. 'BASIC' end.
        end.
    end.
    if. 0=#Current do.
        if. ('SMART'eq strategy)*.(-.queenPlayed'')*.-.36 e.hand do.
            small =. cs#~(2=suit cs)*.(13|cs)<10
            if. #small do. lowest small return. end.
        end.
        counts =. +/"1 (i.4)=/suit cs
        choices =. I.counts>0
        key =. choices{counts
        if. 'MOON'eq strategy do. key =. -key end.
        su =. {.choices /:key
        chosen =. cs#~su=suit cs
        if. 'MOON'eq strategy do. highest chosen else. lowest chosen end.
        return.
    end.
    led =. suit 1{0{Current
    if. led e.suit hand do.
        played =. 1{"1 Current
        winning =. >./13|played#~led=suit played
        lower =. cs#~winning>13|cs
        if. 'MOON'eq strategy do.
            c =. highest cs
            if. (13|c)>winning do. c else. lowest cs end.
            return.
        end.
        if. #lower do. highest lower return. end.
        if. ('SMART'eq strategy)*.3=#Current do.
            safe =. cs-.36
            if. #safe do. highest safe else. 36 end.
            return.
        end.
        lowest cs return.
    end.
    if. 'MOON'eq strategy do.
        safe =. cs#~-.penalty cs
        if. #safe do. lowest safe else. lowest cs end.
        return.
    end.
    if. 36 e.cs do. 36 return. end.
    if. ('SMART'eq strategy)*.-.queenPlayed'' do.
        if. 38 e.cs do. 38 return. end.
        if. 37 e.cs do. 37 return. end.
    end.
    hearts =. cs#~3=suit cs
    if. #hearts do. highest hearts else. highest cs end.
)
winner =: 3 : 0
    cards =. 1{"1 y
    follow =. I.(suit {.cards)=suit cards
    i =. {.follow \:13|follow{cards
    0{i{y
)
playText =: 3 : 0
    texts =. 0$a:
    for_p. y do.
        's c' =. p
        texts =. texts,<(seatText s),' ',cardText c
    end.
    ' 'join texts
)
trickLine =: 4 : 0
    'trick ',(num x),': ',(playText y),' -> ',(seatText winner y),' ',num points 1{"1 y
)
ranking =: 3 : '/:Scores'
statsLines =: 3 : 0
    lines =. 0$a:
    for_s. i.4 do.
        't h q m' =. s{Stats
        lines =. lines,<words 'stats';(seatText s);'tricks';t;'hearts';h;'queens';q;'moons';m
    end.
    lines
)
finish =: 3 : 0
    ps =. points&>Taken
    shooter =. _1
    for_s. i.4 do. if. 14=+/penalty s{::Taken do. shooter =. s end. end.
    if. shooter>:0 do.
        ps =. ((shooter{ps)-26)shooter}ps
        method =. 2{::Rules
        if. 'AUTO'eq method do.
            add =. Scores+ps+26*(i.4)~:shooter
            ended =. (Number>:1{::Rules)+.+./add>:0{::Rules
            win =. {./:add
            method =. 'ADD'
            if. ended*.win~:shooter do. method =. 'SUB' end.
        end.
        if. 'SUB'eq method do. ps =. ((shooter{ps)-26)shooter}ps
        else. ps =. ps+26*(i.4)~:shooter end.
        recordLine 1;words 'moon';(seatText shooter);method
    end.
    Scores =: Scores+ps
    for_s. i.4 do.
        cs =. s{::Taken
        row =. (s{Stats)+(s{Counts),(+/3=suit cs),(36 e.cs),s=shooter
        Stats =: row s}Stats
    end.
    recordLine 1; 'points'pairs <"0 ps
    recordLine 1; 'scores'pairs <"0 Scores
    History =: History,<Number;(direction PassCode);ps;shooter;<Record
    ended =. (Number>:1{::Rules)+.+./Scores>:0{::Rules
    State =: 1
    if. ended do.
        State =: 0
        recordLine 0;words 'game over hands';Number
        order =. ranking''
        for_i. i.4 do.
            s =. i{order
            recordLine 0;words 'rank';(>:i);(seatText s);s{Scores
        end.
        for_line. statsLines'' do. recordLine 0;>line end.
    end.
)
play =: 3 : 0
    seat =. actor''
    Undo =: Undo,< (position'');seat;y
    Hands =: (<(seat{::Hands)-.y)seat}Hands
    Current =: Current,seat,y
    if. (3=suit y)+.(y=36)*.'ON'eq 4{::Rules do. Broken =: 1 end.
    if. 4=#Current do.
        win =. winner Current
        Taken =: (<(win{::Taken),1{"1 Current)win}Taken
        Counts =: (>:win{Counts)win}Counts
        Tricks =: Tricks,<Current
        recordLine 2;(#Tricks)trickLine Current
        Current =: 0 2$0
        Leader =: win
        if. 13=#Tricks do. finish'' end.
    end.
)
autoPass =: 3 : 0
    for_s. i.4 do. if. -.s{Passed do. s passCards choosePass s end. end.
)
autoHand =: 3 : 0
    if. State=2 do. autoPass'' end.
    while. State=3 do. play choosePlay'' end.
)
autoGame =: 3 : 0
    if. State e.2 3 do. autoHand'' end.
    while. State~:0 do.
        deal''
        autoHand''
    end.
)
duplicates =: 3 : 0
    seen =. i.0
    for_c. y do.
        if. c e.seen do. fail 'duplicate card ',cardText c end.
        seen =. seen,c
    end.
)
require =: 3 : 0
    select. y
    case. 'game' do. if. State=0 do. fail 'no game' end.
    case. 'between' do.
        if. State=0 do. fail 'no game' end.
        if. State~:1 do. fail 'hand in progress' end.
    case. 'hand' do. if. -.State e.2 3 do. fail 'no hand' end.
    case. 'passing' do. if. State~:2 do. fail 'not passing' end.
    case. 'playing' do. if. State~:3 do. fail 'not playing' end.
    end.
)
simulate =: 3 : 0
    'cmd seed count' =. y
    saved =. saveGame''
    originalBots =. Bots
    X =: seed
    if. 'GAME'eq cmd do.
        say 'game seed';seed
        PrintLevel =: count
        newGame''
        autoGame''
    else.
        PrintLevel =: _1
        rounds =. 1+3*'ROTATE'eq cmd
        places =. 4 4$0
        totals =. 4#0
        sums =. 4 4$0
        hands =. 0
        for_rotation. i.rounds do.
            for_s. i.4 do. Bots =: (s{originalBots)(4|s+rotation)}Bots end.
            for_g. i.count do.
                newGame''
                autoGame''
                hands =. hands+Number
                order =. ranking''
                for_s. i.4 do.
                    actual =. 4|s+rotation
                    rank =. order i.actual
                    places =. (>: (<s,rank){places)(<s,rank)}places
                    totals =. ((s{totals)+actual{Scores)s}totals
                    sums =. ((s{sums)+actual{Stats)s}sums
                end.
            end.
        end.
        games =. rounds*count
        label =. 'match'
        if. 'ROTATE'eq cmd do. label =. 'rotate' end.
        say label;'seed';seed;'games';games;'hands';hands
        for_s. i.4 do.
            cents =. <.(100*s{totals)%games
            abs =. |cents
            average =. (num <.abs%100),'.',_2{.'00',num 100|abs
            if. cents<0 do. average =. '-',average end.
            name =. seatText s
            if. 'ROTATE'eq cmd do. name =. name,' ',s{::originalBots end.
            't h q m' =. s{sums
            emit name,' places ',(words <"0 s{places),' ',words 'total';(s{totals);'average';average;'tricks';t;'hearts';h;'queens';q;'moons';m
        end.
    end.
    restoreGame saved
    Bots =: originalBots
    PrintLevel =: 2
)
execute =: 3 : 0
    ts =. ' 'split y
    cmd =. 0{::ts
    args =. }.ts
    known =. ;:'RULE BOT SETTINGS GAME MATCH ROTATE NEW ABANDON STACK DEAL SHOW PASS PLAY AUTO UNDO CLAIM LEGAL PREVIEW SCORE TAKEN TRICKS VOIDS UNSEEN STATS HISTORY REPLAY'
    if. -.(<cmd)e.known do. fail 'unknown command ',cmd end.
    if. 'RULE'eq cmd do.
        'name word' =. args
        i =. RuleNames i.<name
        if. i=#RuleNames do. fail 'unknown rule ',name end.
        value =. word
        if. i e.0 1 do.
            lim =. (i=0){100 1000
            good =. *./word e.'-0123456789'
            if. good do.
                value =. parse word
                good =. (value>:1)*.value<:lim
            end.
        elseif. i=2 do. good =. (<word)e.;:'ADD SUB AUTO'
        elseif. i=6 do. good =. (0<#word)*.(8>:#word)*.*./word e.'LRAH'
        else. good =. (<word)e.;:'ON OFF' end.
        if. -.good do. fail 'bad value ',word end.
        if. State~:0 do. fail 'game in progress' end.
        Rules =: (<value)i}Rules
        say 'rule';name;word
        return.
    end.
    if. 'BOT'eq cmd do.
        s =. seatValue 0{::args
        strategy =. 1{::args
        if. -.(<strategy)e.Strategies do. fail 'bad value ',strategy end.
        Bots =: (<strategy)s}Bots
        say 'bot';(seatText s);strategy
        return.
    end.
    if. 'SETTINGS'eq cmd do.
        text =. 'rules'
        for_i. i.7 do. text =. text,' ',(i{::RuleNames),' ',words <i{::Rules end.
        emit text
        emit 'bots'pairs Bots
        return.
    end.
    if. (<cmd)e.;:'GAME MATCH ROTATE' do.
        seed =. 1 2147483646 bounded 0{::args
        low =. 1 [ high =. 50
        if. 'GAME'eq cmd do. low =. 0 [ high =. 2 end.
        if. 'ROTATE'eq cmd do. high =. 10 end.
        count =. (low,high)bounded 1{::args
        simulate cmd;seed;count
        return.
    end.
    if. 'NEW'eq cmd do.
        seed =. 1 2147483646 bounded 0{::args
        if. State~:0 do. fail 'game in progress' end.
        X =: seed
        newGame''
        say 'new game seed';seed
        return.
    end.
    if. 'ABANDON'eq cmd do.
        require 'game'
        State =: 0
        emit 'game abandoned'
        return.
    end.
    s =. _1
    cs =. i.0
    if. (<cmd)e.;:'STACK PASS PLAY CLAIM' do. s =. seatValue 0{::args end.
    if. (<cmd)e.;:'STACK PASS PLAY' do.
        for_word. }.args do. cs =. cs,cardValue >word end.
    end.
    if. ('STACK'eq cmd)*.13~:#cs do. fail 'need 13 cards' end.
    if. 'AUTO'eq cmd do.
        mode =. 0{::args
        if. -.(<mode)e.;:'PASS CARD TRICK HAND GAME' do. fail 'bad value ',mode end.
    end.
    if. (<cmd)e.;:'STACK DEAL' do. require 'between'
    elseif. 'SHOW'eq cmd do. require 'hand'
    elseif. 'PASS'eq cmd do. require 'passing'
    elseif. (<cmd)e.;:'PLAY UNDO CLAIM LEGAL PREVIEW TAKEN TRICKS VOIDS UNSEEN' do. require 'playing'
    elseif. (<cmd)e.;:'SCORE STATS HISTORY REPLAY' do. require 'game'
    elseif. 'AUTO'eq cmd do.
        if. 'PASS'eq mode do. require 'passing'
        elseif. (<mode)e.;:'CARD TRICK' do. require 'playing'
        elseif. 'HAND'eq mode do. require 'hand'
        else. require 'game' end.
    end.
    select. cmd
    case. 'STACK' do.
        duplicates cs
        for_c. cs do. for_o. (i.4)-.s do.
            if. c e.o{::Stacked do. fail (cardText c),' stacked for ',seatText o end.
        end. end.
        Stacked =: (<cs)s}Stacked
        emit 'stacked ',seatText s
    case. 'DEAL' do. deal''
    case. 'SHOW' do. for_i. i.4 do. emit (seatText i),': ',display i{::Hands end.
    case. 'PASS' do.
        if. s{Passed do. fail (seatText s),' already passed' end.
        duplicates cs
        for_c. cs do. if. -.c e.s{::Hands do. fail (seatText s),' does not hold ',cardText c end. end.
        s passCards cs
    case. 'PLAY' do.
        c =. {.cs
        if. s~:actor'' do. fail 'waiting for ',seatText actor'' end.
        if. -.c e.s{::Hands do. fail (seatText s),' does not hold ',cardText c end.
        if. -.c e.legal'' do.
            if. 0=#Current do.
                if. 0=#Tricks do. fail 'must lead 2C' else. fail 'hearts not broken' end.
            end.
            led =. suit 1{0{Current
            if. led e.suit s{::Hands do. fail 'must follow ',led{Suits end.
            fail 'no points on first trick'
        end.
        say (seatText s);'plays';cardText c
        play c
    case. 'AUTO' do.
        select. mode
        case. 'PASS' do. autoPass''
        case. 'CARD' do.
            c =. choosePlay''
            say (seatText actor'');'plays';cardText c
            play c
        case. 'TRICK' do.
            before =. #Tricks
            while. (State=3)*.before=#Tricks do. play choosePlay'' end.
        case. 'HAND' do. autoHand''
        case. 'GAME' do. autoGame''
        end.
    case. 'UNDO' do.
        if. 0=#Undo do. fail 'nothing to undo' end.
        'pos seat card' =. _1{::Undo
        Undo =: }:Undo
        restorePosition pos
        say 'undo';(seatText seat);cardText card
    case. 'CLAIM' do.
        if. s~:actor'' do. fail 'waiting for ',seatText actor'' end.
        if. #Current do. fail 'trick in progress' end.
        for_c. s{::Hands do.
            for_o. (i.4)-.s do.
                other =. o{::Hands
                if. +./((suit c)=suit other)*.(13|other)>13|c do. fail 'claim rejected' end.
            end.
        end.
        remaining =. ;Hands
        count =. 13-#Tricks
        Taken =: (<(s{::Taken),remaining)s}Taken
        Counts =: ((s{Counts)+count)s}Counts
        Hands =: 4#<i.0
        recordLine 2;words 'claim';(seatText s);'tricks';count;'points';points remaining
        finish''
    case. 'LEGAL' do.
        emit 'legal ',(seatText actor''),': ',(display legal''),' bot ',cardText choosePlay''
    case. 'PREVIEW' do.
        saved =. saveGame''
        PrintLevel =: _1
        for_c. /:~legal'' do.
            before =. #Tricks
            play c
            while. (State=3)*.before=#Tricks do. play choosePlay'' end.
            trick =. _1{::Tricks
            say 'preview';(cardText c);'->';(seatText winner trick);points 1{"1 trick
            restoreGame saved
        end.
        PrintLevel =: 2
    case. 'SCORE' do.
        emit 'scores'pairs <"0 Scores
        if. State=3 do. emit 'taken'pairs <"0 points&>Taken end.
    case. 'TAKEN' do.
        for_i. i.4 do.
            cs =. i{::Taken
            emit (seatText i),': ',display cs#~0~:point"0 cs
        end.
    case. 'TRICKS' do.
        for_i. i.#Tricks do. emit (>:i)trickLine i{::Tricks end.
        if. #Current do. emit 'current: ',playText Current
        elseif. 0=#Tricks do. emit 'no tricks' end.
    case. 'VOIDS' do.
        voids =. 4 4$0
        all =. Tricks
        if. #Current do. all =. all,<Current end.
        for_t. all do.
            trick =. >t
            led =. suit 1{0{trick
            for_p. trick do.
                'seat card' =. p
                if. led~:suit card do. voids =. 1 (<seat,led)}voids end.
            end.
        end.
        text =. 0$a:
        for_i. i.4 do.
            s =. (I.i{voids){Suits
            if. 0=#s do. s =. '-' end.
            text =. text,<s
        end.
        emit 'voids'pairs text
    case. 'UNSEEN' do.
        seat =. actor''
        used =. (;Taken),(1{"1 Current),seat{::Hands
        emit 'unseen ',(seatText seat),': ',display (i.52)-.used
    case. 'STATS' do. for_line. statsLines'' do. emit >line end.
    case. 'HISTORY' do.
        if. 0=#History do. emit 'no hands' end.
        for_h. History do.
            'number dir ps shooter record' =. >h
            text =. (words 'hand';number;'pass';dir),' ','points'pairs <"0 ps
            if. shooter>:0 do. text =. text,' moon ',seatText shooter end.
            emit text
        end.
    case. 'REPLAY' do.
        word =. 0{::args
        h =. parse word
        if. (h<1)+.h>#History do. fail 'bad value ',word end.
        for_line. 4{::(h-1){::History do. emit >line end.
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
