LF =: 10{a.
Ships =: ;:'CARRIER BATTLESHIP CRUISER SUBMARINE DESTROYER'
Lengths =: 5 4 3 3 2
Symbols =: 'CBRSD'
Strategies =: ;:'HUNT PROB RANDOM'
Switches =: ;:'OFF ON'
SetupCommands =: ;:'PLACE REMOVE AUTOPLACE LAYOUT REEF SALVO CHAIN TOUCH'
TurnCommands =: ;:'FIRE AI TORPEDO SONAR'
Wins =: 0 0
Mode =: 0
Error =: ''

split =: 4 : '<;._1 x,y'
number =: 3 : 0
    text =. , '0' 8!:2 |y
    if. y<0 do. '-',text else. text end.
)
join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do. text =. text,x end.
        text =. text,i{::y
    end.
    text
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
cell_text =: 3 : '((<.y%10){''ABCDEFGHIJ''),number 1+10|y'
parse_cell =: 3 : '(10*''ABCDEFGHIJ'' i.{.y)+_1+0".}.y'
ship_range =: 3 : '(cell_text {.y),''-'',cell_text {:y'
next_random =: 3 : '2147483647|48271x*y'
pad =: 4 : '((0>.x-#y)$'' ''),y'

geometry =: 3 : 0
    Around =: Orthogonal =: 0$a:
    Steps =: 0 4$0
    for_cell. i.100 do.
        row =. <.cell%10
        col =. 10|cell
        nearby =. i.0
        for_dr. _1 0 1 do.
            for_dc. _1 0 1 do.
                if. (dr=0)*.dc=0 do. continue. end.
                r =. row+dr
                c =. col+dc
                if. (r>:0)*.(r<10)*.(c>:0)*.c<10 do. nearby =. nearby,c+10*r end.
            end.
        end.
        Around =: Around,<nearby
        steps =. i.0
        for_direction. i.4 do.
            r =. row+direction{0 1 0 _1
            c =. col+direction{1 0 _1 0
            if. (r>:0)*.(r<10)*.(c>:0)*.c<10 do. steps =. steps,c+10*r
            else. steps =. steps,_1 end.
        end.
        Steps =: Steps,steps
        adjacent =. 2 1 0 3{steps
        Orthogonal =: Orthogonal,<adjacent#~adjacent>:0
    end.
)
span =: 3 : 0
    'ship first direction' =. y
    length =. ship{Lengths
    start =. direction{(10|first),<.first%10
    if. (start+length)>10 do. i.0 return. end.
    first+(direction{1 10)*i.length
)
touches =: 4 : '+./y e.;x{Around'
new_game =: 3 : 0
    Phase =: 'SETUP'
    Turn =: 0
    Winner =: _1
    Salvo =: Chain =: Touch =: 0
    Reefs =: 100$0
    Fleets =: 2 5$<i.0
    Attacked =: 2 100$0
    Targets =: 2$<i.0
    Random =: 1x 2
    Controllers =: 2$<'HUMAN'
    Torpedoes =: Sonars =: 0 0
    Stats =: 2 6$0
)
snapshot =: 3 : 'Phase;Turn;Winner;Salvo;Chain;Touch;Reefs;Fleets;Attacked;Targets;Random;Controllers;Torpedoes;Sonars;Stats;Wins;Mode'
restore =: 3 : '''Phase Turn Winner Salvo Chain Touch Reefs Fleets Attacked Targets Random Controllers Torpedoes Sonars Stats Wins Mode'' =: y'
board =: 3 : 0
    result =. 100$_1
    for_ship. i.5 do.
        cells =. (<y,ship){::Fleets
        result =. ship cells}result
    end.
    result
)
sunk =: 3 : 0
    result =. i.0
    for_ship. i.5 do.
        cells =. (<y,ship){::Fleets
        result =. result,(0<#cells)*.*./cells{y{Attacked
    end.
    result
)
afloat =: 3 : '+/((0<#&>y{Fleets)*.-.sunk y)'
allowance =: 3 : 0
    if. Salvo do. afloat y else. 1 end.
)
placement_problem =: 4 : 0
    if. 0=#y do. 'out of bounds' return. end.
    if. +./y{Reefs do. 'on reef' return. end.
    fleet =. x{Fleets
    for_ship. i.5 do.
        if. +./y e.ship{::fleet do. 'overlaps ',ship{::Ships return. end.
    end.
    if. -.Touch do.
        for_ship. i.5 do.
            if. y touches ship{::fleet do. 'touches ',ship{::Ships return. end.
        end.
    end.
    ''
)
placed_output =: 3 : 0
    for_ship. i.5 do. say 'PLACED';(y+1);(ship{::Ships);ship_range (<y,ship){::Fleets end.
)
autoplace =: 4 : 0
    Random =: y x}Random
    Fleets =: (5$<i.0) x}Fleets
    attempts =. 0
    for_ship. i.5 do.
        length =. ship{Lengths
        while. 1 do.
            attempts =. attempts+1
            random =. next_random x{Random
            direction =. 2|random
            random =. next_random random
            Random =: random x}Random
            k =. (10*11-length)|random
            if. direction do. first =. k
            else. first =. (10*<.k%(11-length))+(11-length)|k end.
            cells =. span ship,first,direction
            if. 0=#x placement_problem cells do.
                Fleets =: (<cells) (<x,ship)}Fleets
                break.
            end.
        end.
    end.
    attempts
)
layout_fleet =: 3 : 0
    chars =. y-.'/'
    fleet =. 0$a:
    for_ship. i.5 do.
        cells =. I.chars=ship{Symbols
        if. (#cells)~:ship{Lengths do. fail words (ship{::Ships);'has';(#cells);'cells' end.
        first =. {.cells
        if. -.((cells-:span ship,first,0)+.cells-:span ship,first,1) do. fail (ship{::Ships),' not straight' end.
        if. +./cells{Reefs do. fail (ship{::Ships),' on reef' end.
        fleet =. fleet,<cells
    end.
    if. -.Touch do.
        for_a. i.5 do.
            for_b. (a+1)+i.4-a do.
                if. (a{::fleet) touches b{::fleet do. fail words (a{::Ships);'touches';b{::Ships end.
            end.
        end.
    end.
    fleet
)

view =: 3 : 0
    opponent =. 1-y
    occupied =. board opponent
    lost =. sunk opponent
    attacked =. opponent{Attacked
    chars =. 100$'.'
    for_cell. I.attacked do.
        ship =. cell{occupied
        if. ship<0 do. value =. 'o'
        elseif. ship{lost do. value =. '#'
        else. value =. 'x' end.
        chars =. value cell}chars
    end.
    '~' (I.Reefs)}chars
)
excluded =: 3 : 0
    mask =. 100$0
    if. -.Touch do. mask =. 1 (~.;(I.y='#'){Around)}mask end.
    mask
)
density =: 3 : 0
    chars =. view y
    blocked =. excluded chars
    allowed =. (chars e.'.x')*.-.blocked
    scores =. 100$0
    for_ship. I.-.sunk 1-y do.
        for_position. ship{::Placements do.
            cells =. >position
            if. *./cells{allowed do.
                weight =. 1+10*+/'x'=cells{chars
                scores =. ((cells{scores)+weight) cells}scores
            end.
        end.
    end.
    scores
)
choose =: 4 : 0
    chars =. view x
    candidates =. (chars='.')*.-.excluded chars
    random =. x{Random
    select. y
    case. 'HUNT' do.
        for_hit. I.chars='x' do.
            for_direction. 0 1 do.
                front =. (<hit,direction){Steps
                if. (front>:0)*.'x'=front{chars do.
                    while. (front>:0)*.'x'=front{chars do. front =. (<front,direction){Steps end.
                    back =. (<hit,direction+2){Steps
                    if. (front>:0)*.front{candidates do. front;'LINE';random return. end.
                    if. (back>:0)*.back{candidates do. back;'LINE';random return. end.
                end.
            end.
        end.
        for_cell. |.x{::Targets do.
            if. cell{candidates do. cell;'STACK';random return. end.
        end.
        length =. <./(-.sunk 1-x)#Lengths
        cells =. I.candidates
        parity =. 0=length|(10|cells)+<.cells%10
        ({.parity#cells);'PARITY';random
    case. 'PROB' do.
        scores =. density x
        cells =. I.chars='.'
        best =. >./cells{scores
        cell =. {.cells#~best=cells{scores
        cell;best;random
    case. 'RANDOM' do.
        cells =. I.candidates
        random =. next_random random
        (((#cells)|random){cells);(#cells);random
    end.
)

update_shot =: 4 : 0
    stats =. x{Stats
    stats =. (1+0{stats) (0})stats
    if. y e.1 2 do.
        stats =. (1+1 4{stats) 1 4}stats
        stats =. ((5{stats)>.4{stats) (5})stats
        if. y=2 do. stats =. (1+2{stats) (2})stats end.
    else. stats =. 0 (4})stats end.
    Stats =: stats x}Stats
)
shoot =: 4 : 0
    opponent =. 1-x
    occupied =. board opponent
    ship =. y{occupied
    if. (<opponent,y){Attacked do. result =. 3
    else.
        Attacked =: 1 (<opponent,y)}Attacked
        if. ship<0 do. result =. 0
        elseif. ship{sunk opponent do. result =. 2
        else.
            result =. 1
            Targets =: (<((x{::Targets),y{::Orthogonal)) x}Targets
        end.
    end.
    x update_shot result
    if. (Mode=1)*.result=2 do. say 'SINK';(x+1);(ship{::Ships);(<x,0){Stats end.
    result
)
shot_text =: 4 : 0
    'cell result' =. y
    if. result=2 do. 'SUNK ',(cell{board 1-x){::Ships
    else. result{::;:'MISS HIT SUNK ALREADY' end.
)
end_turn =: 4 : 0
    Stats =: (1+(<x,3){Stats) (<x,3)}Stats
    if. *./sunk 1-x do.
        Phase =: 'OVER'
        Winner =: x
        Wins =: (1+x{Wins) x}Wins
        if. Mode=0 do. say 'WINNER';x+1 end.
    elseif. -.Chain*.y do. Turn =: 1-x
    else. Turn =: x end.
)
shoot_turn =: 3 : 0
    'player strategy cells' =. y
    allowance_now =. allowance player
    hit =. 0
    for_index. i.allowance_now do.
        if. #strategy do.
            'cell info random' =. player choose strategy
            Random =: random player}Random
        else. cell =. index{cells end.
        result =. player shoot cell
        hit =. hit+.result e.1 2
        if. Mode=0 do. say 'SHOT';(player+1);(cell_text cell);player shot_text cell,result end.
        if. *./sunk 1-player do. break. end.
    end.
    player end_turn hit
)
automatic =: 3 : 0
    while. Phase-:'BATTLE' do.
        controller =. Turn{::Controllers
        if. controller-:'HUMAN' do. break. end.
        shoot_turn Turn;controller;i.0
    end.
)
torpedo =: 3 : 0
    'player row side' =. y
    Torpedoes =: 1 player}Torpedoes
    opponent =. 1-player
    occupied =. board opponent
    cells =. (10*row)+i.10
    if. side-:'E' do. cells =. |.cells end.
    text =. 'MISS'
    hit =. stopped_ship =. 0
    for_cell. cells do.
        if. cell{Reefs do. text =. 'REEF ',cell_text cell break. end.
        if. (cell{occupied)>:0 do.
            result =. player shoot cell
            hit =. result e.1 2
            stopped_ship =. 1
            text =. (player shot_text cell,result),' ',cell_text cell
            break.
        end.
        Attacked =: 1 (<opponent,cell)}Attacked
    end.
    if. -.stopped_ship do. player update_shot 0 end.
    say 'TORPEDO';(player+1);(,row{'ABCDEFGHIJ');side;text
    player end_turn hit
)
sonar =: 4 : 0
    Sonars =: 1 x}Sonars
    cells =. y,y{::Around
    occupied =. board 1-x
    count =. +/((cells{occupied)>:0)*.-.cells{(1-x){Attacked
    say 'SONAR';(x+1);(cell_text y);count
    x end_turn 0
)

grid =: 4 : 0
    'player chars' =. y
    say x;player+1
    emit '  1 2 3 4 5 6 7 8 9 10'
    for_row. i.10 do. emit ' ' join (<,row{'ABCDEFGHIJ'),<"0 ((row*10)+i.10){chars end.
)
own_view =: 3 : 0
    chars =. 100$'.'
    occupied =. board y
    for_cell. i.100 do.
        ship =. cell{occupied
        attacked =. (<y,cell){Attacked
        if. ship>:0 do.
            if. attacked do. value =. ship{'cbrsd' else. value =. ship{Symbols end.
        elseif. attacked do. value =. 'o'
        else. value =. '.' end.
        chars =. value cell}chars
    end.
    '~' (I.Reefs)}chars
)
export_fleet =: 3 : 0
    chars =. 100$'.'
    for_ship. i.5 do. chars =. (ship{Symbols) ((<y,ship){::Fleets)}chars end.
    '/' join <"1 (10 10)$chars
)
fleet_output =: 3 : 0
    say 'FLEET';(y+1);'afloat';afloat y
    lost =. sunk y
    for_ship. i.5 do.
        cells =. (<y,ship){::Fleets
        if. 0=#cells do. say (ship{::Ships);'unplaced'
        else.
            hits =. +/cells{y{Attacked
            status =. (ship{lost){::;:'AFLOAT SUNK'
            say (ship{::Ships);(ship_range cells);((number hits),'/',number ship{Lengths);status
        end.
    end.
)
density_output =: 3 : 0
    chars =. view y
    scores =. density y
    cells =. I.chars='.'
    best =. >./cells{scores
    cell =. {.cells#~best=cells{scores
    say 'DENSITY';y+1
    header =. ' '
    for_column. 1+i.10 do. header =. header,5 pad number column end.
    emit header
    for_row. i.10 do.
        line =. ,row{'ABCDEFGHIJ'
        for_column. i.10 do.
            index =. column+10*row
            mark =. index{chars
            if. mark='.' do. value =. number index{scores
            elseif. mark='~' do. value =. '~'
            else. value =. '-' end.
            line =. line,5 pad value
        end.
        emit line
    end.
    say 'BEST';(cell_text cell);best
)
status_output =: 3 : 0
    prefix =. words 'STATUS';Phase;'salvo';(Salvo{::Switches);'chain';(Chain{::Switches);'touch';(Touch{::Switches);'reefs';+/Reefs
    if. Phase-:'SETUP' do. suffix =. words 'placed';(+/0<#&>0{Fleets);+/0<#&>1{Fleets
    elseif. Phase-:'BATTLE' do. suffix =. words 'turn';(Turn+1);'shots';(allowance Turn);'afloat';(afloat 0);afloat 1
    else. suffix =. words 'winner';(Winner+1);'afloat';(afloat 0);afloat 1 end.
    emit prefix,' ',suffix
)
stats_output =: 3 : 0
    for_player. i.2 do.
        'shots hits sinks turns streak best' =. player{Stats
        if. shots do. accuracy =. (number <.(100x*hits)%shots),'%' else. accuracy =. '-' end.
        say 'STATS';(player+1);'shots';shots;'hits';hits;'sunk';sinks;'turns';turns;'streak';best;'accuracy';accuracy;'wins';player{Wins
    end.
)

match =: 3 : 0
    'seed1 seed2 strategy1 strategy2 mode' =. y
    saved =. snapshot''
    rules =. Salvo,Chain,Touch
    reefs =. Reefs
    new_game''
    'Salvo Chain Touch' =: rules
    Reefs =: reefs
    Wins =: 0 0
    Mode =: mode
    0 autoplace seed1
    1 autoplace seed2
    Phase =: 'BATTLE'
    strategies =. strategy1;strategy2
    while. Phase-:'BATTLE' do. shoot_turn Turn;(Turn{::strategies);i.0 end.
    result =. Winner;(0{"1 Stats);1{"1 Stats
    restore saved
    result
)
series =: 3 : 0
    'count random strategy1 strategy2' =. y
    wins =. totals =. 0 0
    fastest =. _1 _1
    for_index. i.count do.
        seed1 =. next_random random
        random =. next_random seed1
        'winner shots hits' =. match seed1;random;strategy1;strategy2;2
        totals =. totals+shots
        wins =. (1+winner{wins) winner}wins
        previous =. winner{fastest
        if. (previous<0)+.(winner{shots)<previous do. fastest =. (winner{shots) winner}fastest end.
    end.
    display =. 0$a:
    for_value. fastest do.
        if. value<0 do. display =. display,<'-' else. display =. display,<number value end.
    end.
    say 'SERIES';count;'wins';(0{wins);(1{wins);'shots';(0{totals);(1{totals);'fastest';(0{::display);1{::display
)
tourney =: 3 : 0
    'count random' =. y
    wins =. totals =. 3$0
    for_pair. (6 2)$0 1 0 2 1 0 1 2 2 0 2 1 do.
        for_index. i.count do.
            seed1 =. next_random random
            random =. next_random seed1
            'winner shots hits' =. match seed1;random;((0{pair){::Strategies);((1{pair){::Strategies);2
            totals =. ((pair{totals)+shots) pair}totals
            strategy =. winner{pair
            wins =. (1+strategy{wins) strategy}wins
        end.
    end.
    order =. /:(-wins),.totals,.i.3
    say 'TOURNEY';count
    for_rank. i.3 do.
        strategy =. rank{order
        say (rank+1);(strategy{::Strategies);'wins';(strategy{wins);'shots';strategy{totals
    end.
)

command =: 3 : 0
    tokens =. ' ' split y
    op =. 0{::tokens
    if. ((<op)e.SetupCommands)*.-.Phase-:'SETUP' do. fail 'setup closed' end.
    if. (<op)e.TurnCommands do.
        player =. _1+0".1{::tokens
        if. Phase-:'OVER' do. fail 'game over' end.
        if. (Phase-:'SETUP')*.+./0=#&>,Fleets do. fail 'fleets not ready' end.
        if. player~:Turn do. fail 'not your turn' end.
        select. op
        case. 'FIRE' do.
            cells =. parse_cell&>2}.tokens
            shots =. allowance player
            if. (#cells)~:shots do. fail words 'expected';shots;'shots' end.
            for_cell. cells do. if. cell{Reefs do. fail 'reef at ',cell_text cell end. end.
        case. 'TORPEDO' do. if. player{Torpedoes do. fail 'torpedo used' end.
        case. 'SONAR' do. if. player{Sonars do. fail 'sonar used' end.
        end.
        Phase =: 'BATTLE'
        select. op
        case. 'FIRE' do. shoot_turn player;'';cells
        case. 'AI' do. shoot_turn player;(2{::tokens);i.0
        case. 'TORPEDO' do. torpedo player;('ABCDEFGHIJ' i.{.2{::tokens);3{::tokens
        case. 'SONAR' do. player sonar parse_cell 2{::tokens
        end.
        automatic''
        return.
    end.
    select. op
    case. 'NEW' do.
        new_game''
        emit 'NEW'
    case. 'SALVO' do.
        Salvo =: 'ON'-:1{::tokens
        emit y
    case. 'CHAIN' do.
        Chain =: 'ON'-:1{::tokens
        emit y
    case. 'TOUCH' do.
        Touch =: 'ON'-:1{::tokens
        emit y
    case. 'REEF' do.
        cell =. parse_cell 1{::tokens
        if. cell{Reefs do. fail 'reef exists at ',cell_text cell end.
        for_player. i.2 do.
            ship =. cell{board player
            if. ship>:0 do. fail words (cell_text cell);'occupied by';(player+1);ship{::Ships end.
        end.
        Reefs =: 1 cell}Reefs
        emit y
    case. 'PLACE';'REMOVE' do.
        player =. _1+0".1{::tokens
        ship =. Ships i.2{tokens
        if. op-:'PLACE' do.
            if. 0<#(<player,ship){::Fleets do. fail (ship{::Ships),' already placed' end.
            cells =. span ship,(parse_cell 3{::tokens),('V'-:4{::tokens)
            problem =. player placement_problem cells
            if. #problem do. fail problem end.
            Fleets =: (<cells) (<player,ship)}Fleets
            say 'PLACED';(player+1);(ship{::Ships);ship_range cells
        else.
            if. 0=#(<player,ship){::Fleets do. fail (ship{::Ships),' not placed' end.
            Fleets =: (<i.0) (<player,ship)}Fleets
            say 'REMOVED';(player+1);ship{::Ships
        end.
    case. 'AUTOPLACE' do.
        player =. _1+0".1{::tokens
        attempts =. player autoplace x:0".2{::tokens
        say 'AUTOPLACE';(player+1);'attempts';attempts
        placed_output player
    case. 'LAYOUT' do.
        player =. _1+0".1{::tokens
        fleet =. layout_fleet 2{::tokens
        Fleets =: fleet player}Fleets
        say 'LAYOUT';player+1
        placed_output player
    case. 'CONTROL' do.
        player =. _1+0".1{::tokens
        Controllers =: (2{tokens) player}Controllers
        say 'CONTROL';(player+1);2{::tokens
    case. 'SEED' do.
        player =. _1+0".1{::tokens
        seed =. x:0".2{::tokens
        Random =: seed player}Random
        say 'SEED';(player+1);seed
    case. 'RESIGN' do.
        if. -.Phase-:'BATTLE' do. fail 'not in battle' end.
        player =. _1+0".1{::tokens
        Phase =: 'OVER'
        Winner =: 1-player
        Wins =: (1+Winner{Wins) Winner}Wins
        say 'RESIGN';player+1
        say 'WINNER';Winner+1
    case. 'HINT' do.
        if. Phase-:'OVER' do. fail 'game over' end.
        player =. _1+0".1{::tokens
        strategy =. 2{::tokens
        'cell info random' =. player choose strategy
        say 'HINT';(player+1);strategy;(cell_text cell);info
    case. 'DENSITY' do.
        if. Phase-:'OVER' do. fail 'game over' end.
        density_output _1+0".1{::tokens
    case. 'SHOW' do.
        player =. _1+0".1{::tokens
        'BOARD' grid player;own_view player
    case. 'RADAR' do.
        player =. _1+0".1{::tokens
        'RADAR' grid player;view player
    case. 'EXPORT' do.
        player =. _1+0".1{::tokens
        say 'EXPORT';(player+1);export_fleet player
    case. 'FLEET' do. fleet_output _1+0".1{::tokens
    case. 'STATUS' do. status_output''
    case. 'STATS' do. stats_output''
    case. 'MATCH' do.
        strategy1 =. 3{::tokens
        strategy2 =. 4{::tokens
        say 'MATCH';1;strategy1;2;strategy2
        'winner shots hits' =. match (x:0".1{::tokens);(x:0".2{::tokens);strategy1;strategy2;1
        say 'RESULT';'winner';(winner+1);'shots';(0{shots);(1{shots);'hits';(0{hits);1{hits
    case. 'SERIES' do. series (0".1{::tokens);(x:0".2{::tokens);(3{::tokens);4{::tokens
    case. 'TOURNEY' do. tourney (0".1{::tokens),x:0".2{::tokens
    end.
)
main =: 3 : 0
    geometry''
    Placements =: 0$a:
    for_ship. i.5 do.
        positions =. 0$a:
        for_cell. i.100 do.
            for_direction. 0 1 do.
                cells =. span ship,cell,direction
                if. #cells do. positions =. positions,<cells end.
            end.
        end.
        Placements =: Placements,<positions
    end.
    new_game''
    lines =. <;._2 (1!:1 3),LF
    count =. 0".0{::lines
    for_line. count{.}.lines do.
        try. command >line
        catcht. emit 'ERROR ',Error end.
    end.
)
main''
