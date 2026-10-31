LF =: 10{a.
Categories =: ;:'ONES TWOS THREES FOURS FIVES SIXES THREEKIND FOURKIND FULLHOUSE SMALL LARGE YAHTZEE CHANCE'
Strategies =: ;:'KIND STRAIGHT HIGH UPPER'
Commands =: ;:'RULE GAME BOT LOAD ROLL HOLD KEEP SCORE WHATIF UNDO REDO SUGGEST ODDS ADVISE AUTO STATUS CARD BONUS STATS LOG FACES STANDINGS END RECORDS SIM'
RollLimit =: 3
JokerRule =: 'FORCED'
HaveGame =: Silent =: 0
Names =: Entries =: Redo =: 0$a:
Bots =: YBonuses =: Dice =: Queue =: i.0
Cards =: 0 13$_1
Current =: RollCount =: 0
Holds =: 5$0
RandomState =: 1x
FaceCounts =: 6$0x
RecordNames =: 0$a:
Records =: 0 4$0x
Patterns =: (5#2)#:i.32
TablesReady =: 0
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
words =: 3 : 0
    parts =. 0$a:
    for_part. y do.
        part =. >part
        if. 2~:3!:0 part do. part =. number part end.
        parts =. parts,<part
    end.
    ' ' join parts
)
emit =: 3 : 0
    if. -.Silent do. (y,LF) 1!:2 4 end.
    i.0
)
say =: 3 : 'emit words y'
fail =: 3 : 0
    Error =: y
    throw.
)
fraction =: 3 : 0
    'numerator denominator' =. x:y
    divisor =. numerator+.denominator
    numerator =. <.numerator%divisor
    denominator =. <.denominator%divisor
    if. denominator=1 do. number numerator else. (number numerator),'/',number denominator end.
)
average =: 4 : 0
    value =. 0x
    if. y do. value =. <.(100x*x)%y end.
    decimals =. number 100x|value
    (number <.value%100x),'.',((2-#decimals)#'0'),decimals
)
face_text =: 3 : 0
    if. #y do. words <"0 y else. '-' end.
)
pattern_text =: 3 : 'y{''01'''
integer_word =: 4 : 0
    text =. y
    negative =. '-'={.text
    if. negative do. text =. }.text end.
    if. 0=#text do. fail 'bad value ',y end.
    if. -. *./text e.'0123456789' do. fail 'bad value ',y end.
    if. ((#text)>1)*.'0'={.text do. fail 'bad value ',y end.
    if. negative*.'0'-:text do. fail 'bad value ',y end.
    value =. x:0".text
    if. negative do. value =. -value end.
    if. (value<{.x)+.value>{:x do. fail 'bad value ',y end.
    value
)
player_name =: 3 : 0
    if. ((#y)>8)+.-.*./y e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ' do. fail 'bad name ',y end.
    y
)
hold_pattern =: 3 : 0
    if. (5~:#y)+.-.*./y e.'01' do. fail 'bad pattern ',y end.
    y='1'
)
category =: 3 : 0
    index =. Categories i.<y
    if. index=#Categories do. fail 'bad category ',y end.
    index
)
strategy =: 3 : 0
    index =. Strategies i.<y
    if. index=#Strategies do. fail 'bad strategy ',y end.
    index
)
face_values =: 3 : 0
    result =. i.0
    for_token. y do. result =. result,1 6 integer_word >token end.
    result
)
game_check =: 3 : 0
    if. -.HaveGame do. fail 'no game' end.
)
turn_check =: 3 : 0
    game_check''
    if. Current=_1 do. fail 'game over' end.
)
rolled_check =: 3 : 0
    turn_check''
    if. RollCount=0 do. fail 'not rolled' end.
)
rolls_left =: 3 : 0
    rolled_check''
    if. RollCount=RollLimit do. fail 'no rolls left' end.
)
counts_of =: 3 : '+/"1 (1+i.6)=/y'
normal_scores =: 3 : 0
    upper =. (1+i.6)*y
    total =. +/upper
    frequent =. >./y
    present =. y>0
    full =. 25*((2 e.y)*.3 e.y)
    small =. 30*+./4 *./\ present
    large =. 40*+./5 *./\ present
    upper,(total*(frequent>:3)),(total*(frequent>:4)),full,small,large,(50*frequent=5),total
)
score_options =: 4 : 0
    allowed =. x=_1
    joker =. (-.JokerRule-:'OFF')*.(5 e.y)*.(_1~:11{x)
    points =. normal_scores y
    if. joker do.
        points =. 25 30 40 (8 9 10)}points
        if. JokerRule-:'FORCED' do.
            face =. y i.5
            if. face{allowed do.
                allowed =. 1 (face}) 13$0
            elseif. +./6}.allowed do.
                allowed =. (6$0),6}.allowed
            end.
        end.
    end.
    joker;allowed;points
)
candidates =: 4 : 0
    'joker allowed points' =. x score_options y
    allowed*points
)
best =: 4 : 0
    open =. I.x=_1
    values =. open{x candidates y
    chosen =. values i.>./values
    (chosen{open),chosen{values
)
upper_subtotals =: 3 : '+/"1 0>.6{."1 Cards'
player_totals =: 3 : '(+/"1 0>.Cards)+(35*(upper_subtotals'''')>:63)+YBonuses'
turn_line =: 3 : 0
    if. Current=_1 do. emit 'game over'
    else. say 'turn';(1++/(_1~:Current{Cards));Current{::Names end.
)
new_game =: 3 : 0
    'seed players bots' =. y
    HaveGame =: 1
    Names =: players
    Bots =: bots
    Cards =: ((#Names),13)$_1
    YBonuses =: (#Names)$0
    Current =: RollCount =: 0
    Dice =: Queue =: i.0
    Holds =: 5$0
    RandomState =: x:seed
    FaceCounts =: 6$0x
    Entries =: Redo =: 0$a:
)
roll_dice =: 3 : 0
    if. RollCount=0 do. Dice =: 5$0 end.
    for_i. I.-.Holds do.
        if. #Queue do.
            face =. {.Queue
            Queue =: }.Queue
        else.
            RandomState =: 2147483647|48271x*RandomState
            face =. 1+6|RandomState
        end.
        Dice =: face i}Dice
        index =. face-1
        FaceCounts =: (1+index{FaceCounts) index}FaceCounts
    end.
    RollCount =: RollCount+1
    Redo =: 0$a:
    emit words (Current{::Names);'roll';((number RollCount),':');face_text Dice
)
set_holds =: 3 : 0
    Holds =: y
    Redo =: 0$a:
    emit words (Current{::Names);'holds';((pattern_text Holds),':');face_text Holds#Dice
)
score_plan =: 3 : 0
    counts =. counts_of Dice
    'joker allowed points' =. (Current{Cards) score_options counts
    points =. y{points
    bonus =. 100*((5 e.counts)*.50=(<Current,11){Cards)
    upper =. Current{upper_subtotals''
    after =. upper+(y<6)*points
    gained =. 35*((upper<63)*.after>:63)
    total =. (Current{player_totals'')+points+bonus+gained
    points,bonus,joker,gained,total
)
score_line =: 4 : 0
    'points bonus joker gained total' =. score_plan y
    text =. words (Current{::Names);x;points;'in';y{::Categories
    if. joker do. text =. text,' joker' end.
    if. bonus do. text =. text,' ybonus 100' end.
    if. gained do. text =. text,' ubonus 35' end.
    text,' total ',number total
)
score_check =: 3 : 0
    rolled_check''
    if. _1~:(<Current,y){Cards do. fail (y{::Categories),' already used' end.
    counts =. counts_of Dice
    'joker allowed points' =. (Current{Cards) score_options counts
    if. -.y{allowed do.
        face =. counts i.5
        if. _1=(<Current,face){Cards do. fail 'joker requires ',face{::Categories
        else. fail 'joker requires lower box' end.
    end.
)
enter_score =: 3 : 0
    'points bonus joker gained total' =. score_plan y
    emit 'scores' score_line y
    entry =. Current;y;points;bonus;joker;Dice;Holds;RollCount
    Entries =: Entries,<entry
    Cards =: points (<Current,y)}Cards
    YBonuses =: (bonus+Current{YBonuses) Current}YBonuses
    Redo =: 0$a:
    if. *./,_1~:Cards do. Current =: _1
    else. Current =: (#Names)|Current+1 end.
    RollCount =: 0
    Dice =: i.0
    Holds =: 5$0
    turn_line''
)
turn_snapshot =: 3 : 'Current;RollCount;Dice;Holds'
restore_turn =: 3 : '''Current RollCount Dice Holds'' =: y'
snapshot =: 3 : 'HaveGame;Names;Bots;Cards;YBonuses;Current;RollCount;Dice;Holds;RandomState;Queue;Entries;Redo;FaceCounts'
restore =: 3 : '''HaveGame Names Bots Cards YBonuses Current RollCount Dice Holds RandomState Queue Entries Redo FaceCounts'' =: y'
bot_holds =: 3 : 0
    if. y=2 do. Dice>:5 return. end.
    counts =. counts_of Dice
    if. y=1 do.
        start =. length =. 0
        for_a. 1+i.6 do.
            run =. 0
            while. (a+run)e.Dice do. run =. run+1 end.
            if. (run>0)*.run>:length do. start =. a [ length =. run end.
        end.
        if. length>:3 do.
            held =. 5$0
            for_face. start+i.length do. held =. 1 (Dice i.face)}held end.
            held return.
        end.
    end.
    face =. 1+{:I.counts=>./counts
    Dice=face
)
bot_turn =: 3 : 0
    if. RollCount=0 do. roll_dice'' end.
    mode =. Current{Bots
    while. RollCount<RollLimit do.
        held =. bot_holds mode
        if. *./held do. break. end.
        set_holds held
        roll_dice''
    end.
    counts =. counts_of Dice
    card =. Current{Cards
    chosen =. {.card best counts
    if. mode=3 do.
        face =. {:I.counts=>./counts
        'joker allowed points' =. card score_options counts
        if. ((face{counts)>:3)*.face{allowed do. chosen =. face end.
    end.
    enter_score chosen
)

compositions =: 4 : 0
    if. y=1 do. 1 1$x return. end.
    result =. (0,y)$0
    for_count. i.x+1 do.
        suffix =. (x-count) compositions y-1
        result =. result,((#suffix)#count),.suffix
    end.
    result
)
prepare_tables =: 3 : 0
    if. TablesReady do. return. end.
    Outcomes =: Weights =: 0$a:
    HeldCounts =: 0 6$0
    for_count. i.6 do.
        rows =. count compositions 6
        weight =. <.(!x:count)%*/"1 !x:rows
        Outcomes =: Outcomes,<rows
        Weights =: Weights,<weight
        HeldCounts =: HeldCounts,rows
    end.
    FullCounts =: 5{::Outcomes
    FullLookup =: (i.#FullCounts) (6#."1 FullCounts)}(6^6)$_1
    HeldLookup =: (i.#HeldCounts) (6#."1 HeldCounts)}(6^6)$_1
    NextStates =: TransitionWeights =: Subsets =: 0$a:
    for_held. HeldCounts do.
        kept =. +/held
        rest =. (5-kept){::Outcomes
        indices =. (6#."1 held+"1 rest){FullLookup
        NextStates =: NextStates,<indices
        TransitionWeights =: TransitionWeights,<(6^kept)*(5-kept){::Weights
    end.
    for_dice. FullCounts do. Subsets =: Subsets,<I.*./"1 dice>:"1 HeldCounts end.
    TablesReady =: 1
)
odds =: 3 : 0
    prepare_tables''
    held =. counts_of y#Dice
    held_index =. (6#.held){HeldLookup
    indices =. held_index{::NextStates
    rerolled =. 5-+/y
    weights =. rerolled{::Weights
    denominator =. 6^rerolled
    card =. Current{Cards
    totals =. chances =. 13$0x
    best_total =. 0x
    for_i. i.#indices do.
        values =. card candidates (i{indices){FullCounts
        weight =. i{weights
        totals =. totals+weight*values
        chances =. chances+weight*values>0
        best_total =. best_total+weight*>./values
    end.
    say 'odds';(pattern_text y);'outcomes';denominator
    for_cat. I.card=_1 do.
        say (cat{::Categories);'expect';(fraction (cat{totals),denominator);'chance';fraction (cat{chances),denominator
    end.
    say 'best';'expect';fraction best_total,denominator
)
advise =: 3 : 0
    prepare_tables''
    card =. Current{Cards
    values =. 0$0x
    for_dice. FullCounts do. values =. values,{:card best dice end.
    remaining =. RollLimit-RollCount
    for_step. i.remaining do.
        expected =. 0$0x
        for_i. i.#HeldCounts do.
            expected =. expected,+/(i{::TransitionWeights)*(i{::NextStates){values
        end.
        values =. 0$0x
        for_subset. Subsets do. values =. values,>./(>subset){expected end.
    end.
    choices =. 0$0x
    for_held. Patterns do.
        index =. (6#.counts_of held#Dice){HeldLookup
        choices =. choices,index{expected
    end.
    chosen =. choices i.>./choices
    held =. chosen{Patterns
    emit words 'advise';((pattern_text held),':');(face_text held#Dice);'expect';fraction (chosen{choices),7776x^remaining
)
card_row =: 4 : 0
    text =. x,(9-#x)#' '
    for_p. i.#Names do.
        cell =. p{::y
        width =. 4>.#p{::Names
        text =. text,' ',((0>.width-#cell)#' '),cell
    end.
    emit text
)
record_game =: 3 : 0
    totals =. player_totals''
    winner =. {.\:totals
    for_p. i.#Names do.
        name =. p{Names
        index =. RecordNames i.name
        if. index=#RecordNames do.
            RecordNames =: RecordNames,name
            Records =: Records,1 4$0x
        end.
        row =. index{Records
        row =. (1+0{row) 0}row
        row =. ((1{row)+p=winner) 1}row
        row =. ((2{row)>.p{totals) 2}row
        row =. ((3{row)+p{totals) 3}row
        Records =: row index}Records
    end.
)
simulation =: 3 : 0
    'seed count modes' =. y
    saved =. snapshot''
    Silent =: 1
    stats =. ((#modes),5)$0x
    random =. seed
    players =. (#modes){.;:'A B C D E F'
    for_game. i.count do.
        new_game random;players;modes
        while. Current~:_1 do. bot_turn'' end.
        random =. RandomState
        totals =. player_totals''
        uppers =. upper_subtotals''
        winner =. {.\:totals
        for_p. i.#modes do.
            row =. p{stats
            row =. ((0{row)+p=winner) 0}row
            row =. ((1{row)+p{totals) 1}row
            row =. ((2{row)>.p{totals) 2}row
            row =. ((3{row)+(p{uppers)>:63) 3}row
            row =. ((4{row)+50=(<p,11){Cards) 4}row
            stats =. row p}stats
        end.
    end.
    restore saved
    Silent =: 0
    say 'sim';'seed';seed;'games';count;'players';#modes
    for_p. i.#modes do.
        'wins total best bonus yahtzee' =. p{stats
        say 'seat';(p+1);((p{modes){::Strategies);'wins';wins;'average';(total average count);'best';best;'bonus';bonus;'yahtzee';yahtzee
    end.
)

command =: 3 : 0
    tokens =. ' ' split y
    op =. 0{::tokens
    if. -. (<op)e.Commands do. fail 'unknown command ',op end.
    select. op
    case. 'RULE' do.
        rule =. 1{::tokens
        value =. 2{::tokens
        if. rule-:'ROLLS' do. limit =. 1 4 integer_word value
        elseif. rule-:'JOKER' do.
            if. -.(<value)e.;:'FORCED FREE OFF' do. fail 'bad value ',value end.
        else. fail 'unknown rule ',rule end.
        if. HaveGame do. fail 'game in progress' end.
        if. rule-:'ROLLS' do. RollLimit =: limit else. JokerRule =: value end.
        say 'rule';rule;value
    case. 'GAME' do.
        seed =. 1 2147483646 integer_word 1{::tokens
        players =. 2}.tokens
        for_name. players do. player_name >name end.
        if. (#players)>6 do. fail 'too many players' end.
        if. HaveGame do. fail 'game in progress' end.
        seen =. 0$a:
        for_name. players do.
            if. name e.seen do. fail 'duplicate name ',>name end.
            seen =. seen,name
        end.
        new_game seed;players;(#players)$0
        emit 'game seed ',(number seed),' players ',' ' join Names
        turn_line''
    case. 'BOT' do.
        name =. player_name 1{::tokens
        mode =. strategy 2{::tokens
        game_check''
        p =. Names i.<name
        if. p=#Names do. fail 'no player ',name end.
        Bots =: mode p}Bots
        say 'bot';name;mode{::Strategies
    case. 'LOAD' do.
        faces =. face_values }.tokens
        game_check''
        Queue =: Queue,faces
        say 'loaded';#Queue
    case. 'ROLL' do.
        turn_check''
        if. RollCount=RollLimit do. fail 'no rolls left' end.
        if. *./Holds do. fail 'all dice held' end.
        roll_dice''
    case. 'HOLD' do.
        held =. hold_pattern 1{::tokens
        rolls_left''
        set_holds held
    case. 'KEEP' do.
        faces =. face_values }.tokens
        rolls_left''
        held =. 5$0
        for_face. faces do.
            available =. I.(Dice=face)*.-.held
            if. 0=#available do. fail 'not showing ',number face end.
            held =. 1 ({.available)}held
        end.
        set_holds held
    case. 'SCORE';'WHATIF' do.
        cat =. category 1{::tokens
        score_check cat
        if. op-:'WHATIF' do. emit 'would score' score_line cat else. enter_score cat end.
    case. 'UNDO' do.
        game_check''
        if. 0=#Entries do. fail 'nothing to undo' end.
        entry =. >{:Entries
        Redo =: Redo,<((<turn_snapshot''),<entry)
        Entries =: }:Entries
        'p cat points bonus joker dice held rolls' =. entry
        Cards =: _1 (<p,cat)}Cards
        YBonuses =: ((p{YBonuses)-bonus) p}YBonuses
        restore_turn p;rolls;dice;held
        say 'undo';(p{::Names);(cat{::Categories);points
    case. 'REDO' do.
        game_check''
        if. 0=#Redo do. fail 'nothing to redo' end.
        pair =. >{:Redo
        Redo =: }:Redo
        'saved entry' =. pair
        'p cat points bonus joker dice held rolls' =. entry
        Cards =: points (<p,cat)}Cards
        YBonuses =: ((p{YBonuses)+bonus) p}YBonuses
        Entries =: Entries,<entry
        restore_turn saved
        say 'redo';(p{::Names);(cat{::Categories);points
    case. 'SUGGEST' do.
        rolled_check''
        card =. Current{Cards
        counts =. counts_of Dice
        values =. card candidates counts
        text =. 'suggest'
        for_cat. I.card=_1 do. text =. text,' ',(cat{::Categories),' ',number cat{values end.
        'cat score' =. card best counts
        emit text,' best ',(cat{::Categories),' ',number score
    case. 'ODDS' do.
        held =. hold_pattern 1{::tokens
        rolls_left''
        odds held
    case. 'ADVISE' do.
        rolls_left''
        advise''
    case. 'AUTO' do.
        count =. 1 100 integer_word 1{::tokens
        turn_check''
        Redo =: 0$a:
        for_turn. i.count do.
            if. Current=_1 do. break. end.
            bot_turn''
        end.
    case. 'STATUS' do.
        game_check''
        if. Current=_1 do. emit 'status game over'
        else. say 'status';'round';(1++/(_1~:Current{Cards));'player';(Current{::Names);'rolls';RollCount;'dice';(face_text Dice);'holds';pattern_text Holds end.
    case. 'CARD' do.
        game_check''
        'CATEGORY' card_row Names
        for_cat. i.13 do.
            cells =. 0$a:
            for_p. i.#Names do.
                value =. (<p,cat){Cards
                if. value=_1 do. cell =. '-' else. cell =. number value end.
                cells =. cells,<cell
            end.
            (cat{::Categories) card_row cells
        end.
        upper =. upper_subtotals''
        'UPPER' card_row number each <"0 upper
        'BONUS' card_row number each <"0 35*upper>:63
        'YBONUS' card_row number each <"0 YBonuses
        'TOTAL' card_row number each <"0 player_totals''
    case. 'BONUS' do.
        game_check''
        upper =. upper_subtotals''
        for_p. i.#Names do.
            subtotal =. p{upper
            maximum =. subtotal+5*+/(1+i.6)*_1=6{.p{Cards
            if. subtotal>:63 do. status =. 'made'
            elseif. maximum<63 do. status =. 'lost'
            else. status =. 'open' end.
            say 'bonus';(p{::Names);'upper';subtotal;'need';(0>.63-subtotal);'max';maximum;status
        end.
    case. 'STATS' do.
        game_check''
        for_p. i.#Names do.
            turns =. rolls =. zeros =. yahtzees =. total =. 0
            for_entry. Entries do.
                entry =. >entry
                if. p=0{::entry do.
                    turns =. turns+1
                    rolls =. rolls+7{::entry
                    points =. 2{::entry
                    zeros =. zeros+points=0
                    yahtzees =. yahtzees+1=#~.5{::entry
                    total =. total+points
                end.
            end.
            say 'stats';(p{::Names);'turns';turns;'rolls';rolls;'zeros';zeros;'yahtzees';yahtzees;'average';total average turns
        end.
    case. 'LOG' do.
        game_check''
        if. 0=#Entries do. emit 'no scores' end.
        for_i. i.#Entries do.
            'p cat points bonus joker dice held rolls' =. i{::Entries
            text =. words 'log';(i+1);(p{::Names);(face_text dice);(cat{::Categories);points
            if. joker do. text =. text,' joker' end.
            if. bonus do. text =. text,' ybonus 100' end.
            emit text
        end.
    case. 'FACES' do.
        game_check''
        total =. +/FaceCounts
        chi =. '0'
        if. total do. chi =. fraction ((6*+/FaceCounts^2)-total^2),total end.
        emit 'faces ',(words <"0 FaceCounts),' total ',(number total),' chi2 ',chi
    case. 'STANDINGS' do.
        game_check''
        totals =. player_totals''
        order =. \:totals
        for_rank. i.#order do.
            p =. rank{order
            say 'standing';(rank+1);(p{::Names);(p{totals);'behind';(>./totals)-p{totals
        end.
    case. 'END' do.
        game_check''
        if. Current=_1 do. emit 'end final' else. emit 'end abandoned' end.
        totals =. player_totals''
        order =. \:totals
        for_rank. i.#order do.
            p =. rank{order
            say 'rank';(rank+1);(p{::Names);p{totals
        end.
        if. Current=_1 do. record_game'' end.
        HaveGame =: 0
        Queue =: i.0
    case. 'RECORDS' do.
        if. 0=#RecordNames do. emit 'no records' end.
        order =. /:RecordNames
        order =. order{~\:2{"1 order{Records
        order =. order{~\:1{"1 order{Records
        for_i. order do.
            'games wins best total' =. i{Records
            say 'record';(i{::RecordNames);'games';games;'wins';wins;'best';best;'average';total average games
        end.
    case. 'SIM' do.
        seed =. 1 2147483646 integer_word 1{::tokens
        count =. 1 50 integer_word 2{::tokens
        modes =. i.0
        for_token. 3}.tokens do. modes =. modes,strategy >token end.
        if. (#modes)>6 do. fail 'too many players' end.
        simulation seed;count;modes
    end.
)
main =: 3 : 0
    lines =. <;._2 (1!:1 3),LF
    count =. 0".0{::lines
    for_i. 1+i.count do.
        try. command i{::lines
        catcht. emit 'error: ',Error end.
    end.
)
main''
