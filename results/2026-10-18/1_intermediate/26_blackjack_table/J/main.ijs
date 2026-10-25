LF =: 10{a.
Ranks =: 'A23456789TJQK'
Suits =: 'CDHS'
Commands =: ;:'SHOE RULE RULES PLAYER LEAVE REBUY BET SIDE DEAL INSURANCE HIT STAND DOUBLE SPLIT SURRENDER HINT AUTO STATUS COUNT STATS'
Actions =: ;:'HIT STAND DOUBLE SPLIT SURRENDER'
IdleCommands =: ;:'SHOE RULE PLAYER LEAVE REBUY BET SIDE DEAL'
PlayerCommands =: ;:'LEAVE REBUY BET SIDE INSURANCE HIT STAND DOUBLE SPLIT SURRENDER AUTO'
AmountCommands =: ;:'REBUY BET SIDE INSURANCE'
RuleNames =: ;:'DEALER PEN MIN MAX BJ DAS DOUBLE HANDS RSA SURRENDER CHARLIE SIDEMAX'
Rules =: 0 75 10 500 0 1 0 4 0 1 0 25
StatNames =: ;:'rounds hands wins losses pushes blackjacks busts surrenders doubles splits'
Results =: ;:'blackjack win charlie push lose bust surrender'
Names =: 7$<''
Money =: 7 4$0x
Stats =: 7 11$0x
Participants =: i.0
Hands =: 0 6$0x
Cards =: 0$a:
State =: 'idle'
Round =: DealerBlackjacks =: DealerBusts =: 0
Decks =: Drawn =: Running =: HoleRevealed =: InsuranceTurn =: 0
Shoe =: Dealer =: i.0
RandomState =: 1x
Error =: ''

split =: 4 : '<;._1 x,y'
number =: 3 : 0
    text =. ,'0' 8!:2 |y
    if. y<0 do. '-',text else. text end.
)
signed =: 3 : 0
    if. y<0 do. number y else. '+',number y end.
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
    fields =. 0$a:
    for_field. y do.
        field =. >field
        if. 2~:3!:0 field do. field =. number field end.
        fields =. fields,<field
    end.
    ' ' join fields
)
emit =: 3 : '(y,LF) 1!:2 4'
say =: 3 : 'emit words y'
fail =: 3 : 0
    Error =: y
    throw.
)
integer_word =: 4 : 0
    if. ((#y)<1)+.(#y)>10 do. fail 'bad value ',y end.
    if. -. *./y e.'0123456789' do. fail 'bad value ',y end.
    if. ((#y)>1)*.'0'={.y do. fail 'bad value ',y end.
    value =. x:0".y
    if. (value<{.x)+.value>{:x do. fail 'bad value ',y end.
    value
)
player_name =: 3 : 0
    if. ((#y)<1)+.((#y)>8)+.-.*./y e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ' do. fail 'bad name ',y end.
    y
)
lookup_player =: 3 : 0
    index =. Names i.<y
    if. index=7 do. fail 'unknown player ',y end.
    index
)
seated =: 3 : 'I.0<#&>Names'
add_money =: 4 : 'Money =: (y+x{Money) x}Money'
add_stat =: 4 : 'Stats =: (y+x{Stats) x}Stats'
next_random =: 3 : '2147483647|48271x*y'
points =: 3 : '10<.1+13|y'
card_text =: 3 : '((13|y){Ranks),(<.y%13){Suits'
lowercase =: 3 : 'a.{~32+a.i.y'
cut =: 3 : '<.((#Shoe)*(1{Rules))%100'

rule_options =: 3 : 0
    select. y
    case. 0 do. ' ' split 'S17 H17'
    case. 4 do. ' ' split '3:2 6:5'
    case. 5;8;9 do. ;:'OFF ON'
    case. 6 do. ' ' split 'ANY 9-11 10-11'
    case. do. 0$a:
    end.
)
parse_rule =: 4 : 0
    options =. rule_options x
    if. #options do.
        value =. options i.<y
        if. value=#options do. fail 'bad value ',y end.
        value return.
    end.
    select. x
    case. 1 do. value =. 50 90 integer_word y
    case. 2;3 do. value =. 1 10000 integer_word y
    case. 7 do. value =. 1 4 integer_word y
    case. 10 do.
        value =. 0 7 integer_word y
        if. -.value e.0 5 6 7 do. fail 'bad value ',y end.
    case. 11 do. value =. 0 1000 integer_word y
    end.
    value
)
rule_text =: 3 : 0
    options =. rule_options y
    if. #options do. (y{Rules){::options else. number y{Rules end.
)
hand_total =: 3 : 0
    value =. +/points y
    soft =. (0 e.13|y)*.(value+10)<:21
    (value+10*soft),soft
)
natural =: 4 : '(-.x)*.(2=#y)*.21={.hand_total y'
hand_text =: 4 : 0
    'value soft' =. hand_total y
    if. x natural y do. status =. 'blackjack'
    elseif. value>21 do. status =. 'bust ',number value
    elseif. soft do. status =. 'soft ',number value
    else. status =. number value end.
    (' ' join card_text&.><"0 y),' (',status,')'
)
hand_name =: 3 : 0
    owner =. 0{y{Hands
    index =. +/owner=0{"1 (y+1){.Hands
    (owner{::Names),'[',(number index),']'
)
hand_display =: 3 : '(2{y{Hands) hand_text y{::Cards'
current_hand =: 3 : '{.(I.0=4{"1 Hands),_1'

shuffle =: 3 : 0
    Shoe =: 52|i.52*Decks
    for_i. |.}.i.#Shoe do.
        RandomState =: next_random RandomState
        j =. (i+1)|RandomState
        Shoe =: ((j,i){Shoe) (i,j)}Shoe
    end.
    Drawn =: Running =: 0
)
count_card =: 3 : 0
    value =. points y
    Running =: Running+(value e.2 3 4 5 6)-value e.1 10
)
draw =: 3 : 0
    card =. Drawn{Shoe
    Drawn =: Drawn+1
    if. y do. count_card card end.
    card
)
reveal_dealer =: 3 : 0
    if. -.HoleRevealed do.
        count_card 1{Dealer
        HoleRevealed =: 1
    end.
    emit 'dealer: ',0 hand_text Dealer
)
finish_check =: 3 : 0
    hand =. y{Hands
    cards =. y{::Cards
    value =. {.hand_total cards
    if. value>21 do.
        Hands =: 1x (<y,5)}Hands
        Hands =: 1x (<y,4)}Hands
    elseif. (0~:10{Rules)*.(#cards)=10{Rules do.
        Hands =: 3x (<y,5)}Hands
        Hands =: 1x (<y,4)}Hands
    elseif. value=21 do. Hands =: 1x (<y,4)}Hands
    elseif. (3{hand)*.2=#cards do.
        owner =. 0{hand
        again =. (*./0=13|cards)*.(8{Rules)*.(+/owner=0{"1 Hands)<7{Rules
        Hands =: (-.again) (<y,4)}Hands
    end.
)
settle =: 3 : 0
    dealer_total =. {.hand_total Dealer
    for_owner. Participants do.
        for_index. I.owner=0{"1 Hands do.
            hand =. index{Hands
            cards =. index{::Cards
            blackjack =. (2{hand) natural cards
            if. y do. result =. 4-blackjack
            elseif. blackjack do. result =. 0
            elseif. 5{hand do. result =. (5{hand){_1 5 6 2
            else.
                value =. {.hand_total cards
                if. (dealer_total>21)+.value>dealer_total do. result =. 1
                elseif. value=dealer_total do. result =. 3
                else. result =. 4 end.
            end.
            bet =. 1{hand
            select. result
            case. 0 do.
                if. 4{Rules do. profit =. <.(6*bet)%5
                else. profit =. <.(3*bet)%2 end.
            case. 1;2 do. profit =. bet
            case. 3 do. profit =. 0x
            case. 6 do. profit =. (<.bet%2)-bet
            case. do. profit =. -bet
            end.
            (<owner,0) add_money bet+profit
            (<owner,10) add_stat profit
            (<owner,1) add_stat 1
            if. result e.0 1 2 do. (<owner,2) add_stat 1
            elseif. result=3 do. (<owner,4) add_stat 1
            else. (<owner,3) add_stat 1 end.
            if. result=0 do. (<owner,5) add_stat 1 end.
            if. result=5 do. (<owner,6) add_stat 1 end.
            if. result=6 do. (<owner,7) add_stat 1 end.
            say (hand_name index);(result{::Results);signed profit
        end.
        say (owner{::Names);'bankroll';(<owner,0){Money
    end.
    for_owner. seated'' do.
        Money =: 0x (<owner,1)}Money
        Money =: 0x (<owner,2)}Money
    end.
    State =: 'idle'
)
dealer_turn =: 3 : 0
    reveal_dealer''
    required =. 0
    for_index. i.#Hands do.
        hand =. index{Hands
        if. (0=5{hand)*.-.(2{hand) natural index{::Cards do. required =. 1 end.
    end.
    drew =. 0
    if. required do.
        while. 1 do.
            'value soft' =. hand_total Dealer
            if. -.(value<17)+.(value=17)*.soft*.0{Rules do. break. end.
            Dealer =: Dealer,draw 1
            drew =. 1
            emit 'dealer hits: ',0 hand_text Dealer
        end.
    end.
    if. drew*.21<{.hand_total Dealer do. DealerBusts =: DealerBusts+1 end.
    settle 0
)
advance_hands =: 3 : 0
    while. 1 do.
        index =. current_hand''
        if. index=_1 do. dealer_turn'' return. end.
        cards =. index{::Cards
        if. 1~:#cards do. return. end.
        Cards =: (<cards,draw 1) index}Cards
        emit (hand_name index),': ',hand_display index
        finish_check index
        if. 0=(<index,4){Hands do. return. end.
    end.
)
peek =: 3 : 0
    blackjack =. 0 natural Dealer
    if. blackjack do. emit 'dealer peeks: blackjack'
    else. emit 'dealer peeks: no blackjack' end.
    for_owner. Participants do.
        amount =. (<owner,3){Money
        if. amount=0 do. continue. end.
        profit =. amount*_1+3*blackjack
        (<owner,0) add_money amount+profit
        (<owner,10) add_stat profit
        say (owner{::Names);'insurance';signed profit
    end.
    if. blackjack do.
        DealerBlackjacks =: DealerBlackjacks+1
        reveal_dealer''
        settle 1
    else.
        State =: 'play'
        advance_hands''
    end.
)
deal =: 3 : 0
    if. Drawn>:cut'' do.
        shuffle''
        emit 'shuffle'
    end.
    Round =: Round+1
    say 'round';Round
    Participants =: (seated'')#~0~:1{"1 (seated''){Money
    Hands =: 0 6$0x
    Cards =: 0$a:
    for_owner. Participants do.
        bet =. (<owner,1){Money
        (<owner,0) add_money -(+/(1 2){owner{Money)
        Money =: 0x (<owner,3)}Money
        (<owner,0) add_stat 1
        Hands =: Hands,owner,bet,0 0 0 0
        Cards =: Cards,<,draw 1
    end.
    Dealer =: ,draw 1
    for_index. i.#Hands do.
        cards =. (index{::Cards),draw 1
        Cards =: (<cards) index}Cards
        Hands =: (0 natural cards) (<index,4)}Hands
    end.
    Dealer =: Dealer,draw 0
    HoleRevealed =: 0
    for_index. i.#Hands do. emit (hand_name index),': ',hand_display index end.
    emit 'dealer: ',(card_text {.Dealer),' ??'
    for_owner. Participants do.
        amount =. (<owner,2){Money
        if. amount=0 do. continue. end.
        index =. {.I.owner=0{"1 Hands
        'a b' =. index{::Cards
        result =. 'lose'
        multiplier =. _1
        if. (13|a)=13|b do.
            if. a=b do. result =. 'perfect'
                multiplier =. 25
            elseif. ((<.a%13)e.0 3)=(<.b%13)e.0 3 do.
                result =. 'colored'
                multiplier =. 12
            else. result =. 'mixed'
                multiplier =. 6
            end.
        end.
        profit =. amount*multiplier
        (<owner,0) add_money amount+profit
        (<owner,10) add_stat profit
        say (owner{::Names);'side';result;signed profit
    end.
    upcard =. points {.Dealer
    if. upcard=1 do.
        State =: 'insurance'
        InsuranceTurn =: 0
        emit 'insurance offered'
    elseif. upcard=10 do. peek''
    else. State =: 'play'
        advance_hands''
    end.
)
action_error =: 4 : 0
    hand =. y{Hands
    cards =. y{::Cards
    owner =. 0{hand
    select. x
    case. 'HIT' do.
        if. 3{hand do. 'split aces' return. end.
    case. 'DOUBLE' do.
        if. 3{hand do. 'split aces' return. end.
        if. 2~:#cards do. 'two cards only' return. end.
        'value soft' =. hand_total cards
        rule =. 6{Rules
        limited =. (rule~:0)*.soft+.(value<8+rule)+.value>11
        if. limited+.(-.5{Rules)*.2{hand do. 'double not allowed' return. end.
        if. ((<owner,0){Money)<1{hand do. 'insufficient funds' return. end.
    case. 'SPLIT' do.
        if. 2~:#cards do. 'two cards only' return. end.
        if. ~:/points cards do. 'not a pair' return. end.
        if. (+/owner=0{"1 Hands)>:7{Rules do. 'hand limit' return. end.
        if. ((<owner,0){Money)<1{hand do. 'insufficient funds' return. end.
    case. 'SURRENDER' do.
        if. (-.9{Rules)+.2{hand do. 'surrender not allowed' return. end.
        if. 2~:#cards do. 'two cards only' return. end.
    end.
    ''
)
action =: 3 : 0
    index =. current_hand''
    hand =. index{Hands
    cards =. index{::Cards
    owner =. 0{hand
    bet =. 1{hand
    name =. hand_name index
    select. y
    case. 'SPLIT' do.
        'first second' =. cards
        (<owner,0) add_money -bet
        (<owner,9) add_stat 1
        say name;'splits';(card_text first);card_text second
        aces =. (3{hand)+.1=points first
        row =. owner,bet,1,aces,0 0
        Hands =: (index{.Hands),(row,:row),((index+1)}.Hands)
        Cards =: (index{.Cards),(<,first),(<,second),((index+1)}.Cards)
        Cards =: (<(index{::Cards),draw 1) index}Cards
        emit name,': ',hand_display index
        finish_check index
    case. 'STAND';'SURRENDER' do.
        Hands =: 1x (<index,4)}Hands
        if. y-:'SURRENDER' do.
            Hands =: 2x (<index,5)}Hands
            verb =. 'surrenders'
        else. verb =. 'stands' end.
        emit name,' ',verb,': ',hand_display index
    case. do.
        if. y-:'DOUBLE' do.
            (<owner,0) add_money -bet
            Hands =: (2*bet) (<index,1)}Hands
            (<owner,8) add_stat 1
            verb =. 'doubles'
        else. verb =. 'hits' end.
        Cards =: (<cards,draw 1) index}Cards
        emit name,' ',verb,': ',hand_display index
        finish_check index
        if. y-:'DOUBLE' do. Hands =: 1x (<index,4)}Hands end.
    end.
    advance_hands''
)
recommend =: 3 : 0
    index =. current_hand''
    hand =. index{Hands
    cards =. index{::Cards
    can_split =. 0=#'SPLIT' action_error index
    if. 3{hand do.
        if. can_split do. 'SPLIT' else. 'STAND' end. return.
    end.
    up =. points {.Dealer
    if. up=1 do. up =. 11 end.
    if. (2=#cards)*.can_split do.
        values =. points cards
        if. =/values do.
            value =. {.values
            wanted =. (value e.1 8)+.((value=9)*.-.up e.7 10 11)
            wanted =. wanted+.((value e.2 3 7)*.up<:7)+.((value=6)*.up<:6)+.((value=4)*.up e.5 6)
            if. wanted do. 'SPLIT' return. end.
        end.
    end.
    'value soft' =. hand_total cards
    symbol =. 'H'
    if. soft do.
        if. value>:19 do. symbol =. 'S'
        elseif. value=18 do.
            if. up e.3 4 5 6 do. symbol =. 'Ds'
            elseif. up e.2 7 8 do. symbol =. 'S' end.
        elseif. ((value=17)*.up e.3 4 5 6)+.((value e.15 16)*.up e.4 5 6)+.((value e.13 14)*.up e.5 6) do. symbol =. 'D'
        end.
    else.
        if. value>:17 do. symbol =. 'S'
        elseif. value>:13 do.
            if. up<:6 do. symbol =. 'S'
            elseif. ((value=16)*.up>:9)+.(value=15)*.up=10 do. symbol =. 'R' end.
        elseif. value=12 do.
            if. up e.4 5 6 do. symbol =. 'S' end.
        elseif. ((value=11)*.up<:10)+.((value=10)*.up<:9)+.((value=9)*.up e.3 4 5 6) do. symbol =. 'D'
        end.
    end.
    if. symbol-:'S' do. 'STAND' return. end.
    if. (<symbol)e.'D';'Ds' do.
        if. 0=#'DOUBLE' action_error index do. 'DOUBLE'
        elseif. symbol-:'Ds' do. 'STAND'
        else. 'HIT' end. return.
    end.
    if. symbol-:'R' do.
        if. 0=#'SURRENDER' action_error index do. 'SURRENDER' else. 'HIT' end. return.
    end.
    'HIT'
)
status_output =: 3 : 0
    text =. words 'table';State;'round';Round
    if. State-:'insurance' do. text =. text,' next ',(InsuranceTurn{Participants){::Names
    elseif. State-:'play' do. text =. text,' turn ',hand_name current_hand'' end.
    emit text
    if. -.State-:'idle' do. emit 'dealer: ',(card_text {.Dealer),' ??' end.
    for_owner. seated'' do.
        say 'seat';(owner+1);(owner{::Names);'bankroll';((<owner,0){Money);'bet';((<owner,1){Money);'side';(<owner,2){Money
        if. (-.State-:'idle')*.owner e.Participants do.
            for_index. I.owner=0{"1 Hands do.
                emit (hand_name index),': ',(hand_display index),' bet ',number (<index,1){Hands
            end.
        end.
    end.
)
stats_output =: 3 : 0
    owners =. seated''
    if. 0=#owners do. fail 'no players' end.
    for_owner. owners do.
        fields =. 'stats';owner{::Names
        for_stat. i.10 do. fields =. fields,(stat{StatNames),<number (<owner,stat){Stats end.
        fields =. fields,'net';signed (<owner,10){Stats
        say fields
    end.
    say 'stats';'dealer';'rounds';Round;'blackjacks';DealerBlackjacks;'busts';DealerBusts
)
command =: 3 : 0
    tokens =. ' ' split y
    cmd =. 0{::tokens
    if. -.(<cmd)e.Commands do. fail 'unknown command ',cmd end.
    value =. 0x
    owner =. _1
    if. cmd-:'SHOE' do.
        value =. 1 8 integer_word 1{::tokens
        seed =. 1 2147483646 integer_word 2{::tokens
    elseif. cmd-:'RULE' do.
        rule =. RuleNames i.1{tokens
        if. rule=#RuleNames do. fail 'unknown rule ',1{::tokens end.
        value =. rule parse_rule 2{::tokens
    elseif. cmd-:'PLAYER' do.
        name =. player_name 1{::tokens
        value =. 1 1000000 integer_word 2{::tokens
    elseif. (<cmd)e.PlayerCommands do.
        owner =. lookup_player 1{::tokens
        if. (<cmd)e.AmountCommands do.
            value =. ((cmd-:'REBUY'),1000000) integer_word 2{::tokens
        end.
    end.
    if. (<cmd)e.IdleCommands do.
        if. -.State-:'idle' do. fail 'round in progress' end.
    elseif. cmd-:'INSURANCE' do.
        if. -.State-:'insurance' do. fail 'no insurance' end.
    elseif. ((<cmd)e.Actions)+.(<cmd)e.;:'AUTO HINT' do.
        if. State-:'idle' do. fail 'no round' end.
        if. State-:'insurance' do. fail 'insurance pending' end.
    end.
    if. ((<cmd)e.Actions)+.cmd-:'AUTO' do.
        index =. current_hand''
        if. owner~:0{index{Hands do. fail 'waiting for ',hand_name index end.
        if. cmd-:'AUTO' do.
            while. State-:'play' do.
                if. owner~:0{(current_hand''){Hands do. break. end.
                action recommend''
            end.
        else.
            problem =. cmd action_error index
            if. #problem do. fail problem end.
            action cmd
        end.
        return.
    end.
    select. cmd
    case. 'SHOE' do.
        Decks =: value
        RandomState =: seed
        shuffle''
        say 'shoe';Decks;'decks';(#Shoe);'cards';'cut';cut''
    case. 'RULE' do.
        minimum =. 2{Rules
        maximum =. 3{Rules
        if. rule=2 do. minimum =. value end.
        if. rule=3 do. maximum =. value end.
        if. minimum>maximum do. fail 'min above max' end.
        Rules =: value rule}Rules
        say 'rule';(rule{::RuleNames);rule_text rule
    case. 'RULES' do.
        fields =. <'rules'
        for_rule. i.#Rules do. fields =. fields,(rule{RuleNames),<rule_text rule end.
        say fields
    case. 'PLAYER' do.
        if. (<name)e.Names do. fail 'player exists' end.
        empty =. I.0=#&>Names
        if. 0=#empty do. fail 'table full' end.
        owner =. {.empty
        Names =: (<name) owner}Names
        Money =: (value,0 0 0) owner}Money
        Stats =: (11$0x) owner}Stats
        say name;'sits';'at';'seat';(owner+1);'with';value
    case. 'LEAVE' do.
        say (owner{::Names);'leaves';'with';((<owner,0){Money);'net';signed (<owner,10){Stats
        Names =: (< '') owner}Names
        Money =: (4$0x) owner}Money
        Stats =: (11$0x) owner}Stats
    case. 'REBUY' do.
        (<owner,0) add_money value
        say (owner{::Names);'rebuys';value;'bankroll';(<owner,0){Money
    case. 'BET' do.
        if. value do.
            if. (value<2{Rules)+.value>3{Rules do. fail 'bet out of limits' end.
            if. (value+(<owner,2){Money)>(<owner,0){Money do. fail 'insufficient funds' end.
        end.
        Money =: value (<owner,1)}Money
        if. value do. say (owner{::Names);'bets';value
        else.
            Money =: 0x (<owner,2)}Money
            say (owner{::Names);'bet';'cleared'
        end.
    case. 'SIDE' do.
        if. value do.
            if. 0=(<owner,1){Money do. fail 'no bet' end.
            if. value>11{Rules do. fail 'side out of limits' end.
            if. (value+(<owner,1){Money)>(<owner,0){Money do. fail 'insufficient funds' end.
        end.
        Money =: value (<owner,2)}Money
        if. value do. say (owner{::Names);'side';value
        else. say (owner{::Names);'side';'cleared' end.
    case. 'DEAL' do.
        if. Decks=0 do. fail 'no shoe' end.
        if. -. +./0~:1{"1 (seated''){Money do. fail 'no bets' end.
        deal''
    case. 'INSURANCE' do.
        waiting =. InsuranceTurn{Participants
        if. owner~:waiting do. fail 'waiting for ',waiting{::Names end.
        if. value><.((<owner,1){Money)%2 do. fail 'insurance out of limits' end.
        if. value>(<owner,0){Money do. fail 'insufficient funds' end.
        (<owner,0) add_money -value
        Money =: value (<owner,3)}Money
        if. value do. say (owner{::Names);'insures';value
        else. say (owner{::Names);'declines';'insurance' end.
        InsuranceTurn =: InsuranceTurn+1
        if. InsuranceTurn=#Participants do. peek'' end.
    case. 'HINT' do.
        emit 'hint ',(hand_name current_hand''),': ',lowercase recommend''
    case. 'STATUS' do. status_output''
    case. 'COUNT' do.
        if. Decks=0 do. fail 'no shoe' end.
        remaining =. (#Shoe)-Drawn
        value =. <.(5200x*|Running)%remaining
        decimals =. number 100|value
        text =. (number <.value%100),'.',((2-#decimals)$'0'),decimals
        if. Running<0 do. text =. '-',text end.
        say 'count';'running';Running;'true';text;'remaining';remaining
    case. 'STATS' do. stats_output''
    end.
)
main =: 3 : 0
    lines =. <;._2 (1!:1 3),LF
    count =. 0".0{::lines
    for_line. count{.}.lines do.
        try. command >line
        catcht. emit 'error: ',Error end.
    end.
)
main''
