LF =: 10{a.
Commands =: ;:'NEW PRESET LAYOUT SAFETY RESTART REVEAL FLAG UNFLAG QUESTION CHORD UNDO SHOW STATUS CELL HISTORY REPLAY HINT AUTO ANALYZE PROB FRONTIER SOLVE BOARDINFO STATS'
Arity =: 4 2 2 1 0 2 2 2 2 2 0 0 0 2 1 1 0 0 0 2 0 0 0 0
CellCommands =: ;:'REVEAL FLAG UNFLAG QUESTION CHORD CELL PROB'
LiveCommands =: ;:'REVEAL FLAG UNFLAG QUESTION CHORD UNDO HINT AUTO ANALYZE PROB FRONTIER SOLVE'
UndoCommands =: ;:'REVEAL FLAG UNFLAG QUESTION CHORD AUTO SOLVE'
HaveGame =: Placed =: 0
Safety =: 'block'
W =: H =: M =: Seed =: 0
Mines =: Numbers =: Revealed =: Marks =: MoveCells =: i.0
Neighbors =: MoveKinds =: Undos =: 0$a:
GameState =: 'ready'
Explosion =: _1
Played =: Won =: Lost =: Streak =: BestStreak =: 0
Fastest =: _1
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
number_word =: 3 : 0
    if. (#y)>10 do. fail 'bad arguments' end.
    if. -.*./y e.'0123456789' do. fail 'bad arguments' end.
    if. ((#y)>1)*.'0'={.y do. fail 'bad arguments' end.
    x:0".y
)
cell_text =: 3 : '(number W|y),'','',number <.y%W'
size_text =: 3 : '(number W),''x'',number H'
remaining =: 3 : 'M-+/Marks=1'
unknown =: 3 : '(-.Revealed)*.Marks~:1'
finished =: 3 : '(<GameState)e.;:''won lost'''
fraction =: 3 : 0
    'numerator denominator' =. y
    divisor =. numerator+.denominator
    (number <.numerator%divisor),'/',number <.denominator%divisor
)

new_game =: 3 : 0
    'W H M Seed' =: y
    HaveGame =: 1
    Placed =: 0
    Mines =: Numbers =: Revealed =: Marks =: (W*H)$0
    GameState =: 'ready'
    Explosion =: _1
    MoveKinds =: Undos =: 0$a:
    MoveCells =: i.0
    Neighbors =: 0$a:
    for_cell. i.W*H do.
        x =. W|cell
        y =. <.cell%W
        adjacent =. i.0
        for_dy. _1 0 1 do.
            for_dx. _1 0 1 do.
                if. (dx=0)*.dy=0 do. continue. end.
                xx =. x+dx
                yy =. y+dy
                if. (xx>:0)*.(xx<W)*.(yy>:0)*.yy<H do. adjacent =. adjacent,xx+W*yy end.
            end.
        end.
        Neighbors =: Neighbors,<adjacent
    end.
)
compute_numbers =: 3 : 0
    Numbers =: i.0
    for_adjacent. Neighbors do. Numbers =: Numbers,+/(>adjacent){Mines end.
)
place_mines =: 3 : 0
    cells =. i.W*H
    select. Safety
    case. 'block' do.
        x =. W|y
        row =. <.y%W
        allowed =. ((|x-W|cells)>:2)+.(|row-<.cells%W)>:2
        cells =. allowed#cells
    case. 'cell' do. cells =. cells-.y
    end.
    random =. x:Seed
    for_i. i.M do.
        random =. 2147483647|48271x*random
        index =. (#cells)|random
        Mines =: 1 (index{cells)}Mines
        cells =. (index~:i.#cells)#cells
    end.
    compute_numbers''
    Placed =: 1
    GameState =: 'playing'
)
reset_board =: 3 : 0
    Revealed =: Marks =: (W*H)$0
    MoveKinds =: Undos =: 0$a:
    MoveCells =: i.0
    Explosion =: _1
    if. Placed do. GameState =: 'playing' else. GameState =: 'ready' end.
)
snapshot =: 3 : 'Placed;Mines;Numbers;Revealed;Marks;GameState;Explosion;MoveKinds;Undos;MoveCells'
restore =: 3 : '''Placed Mines Numbers Revealed Marks GameState Explosion MoveKinds Undos MoveCells'' =: y'
undo_snapshot =: 3 : 'Revealed;Marks;MoveKinds;MoveCells'
restore_undo =: 3 : '''Revealed Marks MoveKinds MoveCells'' =: y'
record_move =: 4 : 0
    MoveKinds =: MoveKinds,<x
    MoveCells =: MoveCells,y
)

reveal_cell =: 3 : 0
    if. -.Placed do. place_mines y end.
    if. y{Mines do.
        GameState =: 'lost'
        Explosion =: y
        0 return.
    end.
    Revealed =: 1 (y})Revealed
    Marks =: 0 (y})Marks
    queue =. ,y
    head =. 0
    while. head<#queue do.
        cell =. head{queue
        head =. head+1
        if. 0=cell{Numbers do.
            for_adjacent. cell{::Neighbors do.
                if. adjacent{unknown'' do.
                    Revealed =: 1 (adjacent})Revealed
                    Marks =: 0 (adjacent})Marks
                    queue =. queue,adjacent
                end.
            end.
        end.
    end.
    #queue
)
chord_cells =: 3 : 0
    opened =. 0
    for_cell. y{::Neighbors do.
        if. cell{unknown'' do.
            opened =. opened+reveal_cell cell
            if. GameState-:'lost' do. break. end.
        end.
    end.
    opened
)
win_check =: 3 : 0
    if. (GameState-:'playing')*.(+/Revealed)=(W*H)-M do.
        GameState =: 'won'
        Marks =: 1 (I.Mines)}Marks
    end.
)
show_board =: 3 : 0
    chars =. Marks{'#F?'
    for_cell. I.Revealed do.
        value =. cell{Numbers
        if. value=0 do. mark =. '.' else. mark =. {.number value end.
        chars =. mark cell}chars
    end.
    if. GameState-:'lost' do.
        for_cell. i.W*H do.
            if. cell{Mines do.
                if. cell=Explosion do. mark =. '!'
                elseif. 1=cell{Marks do. mark =. 'F'
                else. mark =. '*' end.
                chars =. mark cell}chars
            elseif. 1=cell{Marks do. chars =. 'X' cell}chars end.
        end.
    end.
    for_row. i.H do. emit W{.(row*W)}.chars end.
)
finish_output =: 3 : 0
    if. GameState-:'lost' do.
        say 'boom';cell_text Explosion
        show_board''
    elseif. GameState-:'won' do. say 'win';'moves';#MoveCells end.
)
update_stats =: 3 : 0
    Played =: Played+1
    if. GameState-:'won' do.
        Won =: Won+1
        Streak =: Streak+1
        BestStreak =: BestStreak>.Streak
        if. Fastest=_1 do. Fastest =: #MoveCells else. Fastest =: Fastest<.#MoveCells end.
    else.
        Lost =: Lost+1
        Streak =: 0
    end.
)

constraints =: 3 : 0
    cells =. i.0
    sets =. 0$a:
    needs =. i.0
    hidden =. unknown''
    for_cell. I.Revealed*.Numbers>0 do.
        adjacent =. cell{::Neighbors
        unseen =. (adjacent{hidden)#adjacent
        if. #unseen do.
            cells =. cells,cell
            sets =. sets,<unseen
            needs =. needs,(cell{Numbers)-+/1=adjacent{Marks
        end.
    end.
    cells;sets;needs
)
deduction =: 3 : 0
    'cells sets needs' =. constraints''
    safe =. mine =. (W*H)$0
    safe_why =. mine_why =. (W*H)#<''
    for_rule. 0 1 do.
        for_i. i.#cells do.
            unseen =. i{::sets
            wanted =. rule*#unseen
            if. (i{needs)~:wanted do. continue. end.
            reason =. 'single ',cell_text i{cells
            for_cell. unseen do.
                if. rule=0 do.
                    if. -.cell{safe do. safe_why =. (<reason) cell}safe_why end.
                    safe =. 1 (cell})safe
                else.
                    if. -.cell{mine do. mine_why =. (<reason) cell}mine_why end.
                    mine =. 1 (cell})mine
                end.
            end.
        end.
        if. +./safe+.mine do. ((<safe),(<mine),(<safe_why),<mine_why) return. end.
    end.
    for_a. i.#cells do.
        left =. a{::sets
        for_b. i.#cells do.
            right =. b{::sets
            if. (#left)>:#right do. continue. end.
            if. -.*./left e.right do. continue. end.
            difference =. right-.left
            needed =. (b{needs)-a{needs
            if. (needed~:0)*.needed~:#difference do. continue. end.
            reason =. words 'subset';(cell_text a{cells);cell_text b{cells
            for_cell. difference do.
                if. needed=0 do.
                    if. -.cell{safe do. safe_why =. (<reason) cell}safe_why end.
                    safe =. 1 (cell})safe
                else.
                    if. -.cell{mine do. mine_why =. (<reason) cell}mine_why end.
                    mine =. 1 (cell})mine
                end.
            end.
        end.
    end.
    if. (-.+./safe+.mine)*.(GameState-:'playing')*.0=remaining'' do.
        safe =. unknown''
        safe_why =. (W*H)#<'count'
    end.
    (<safe),(<mine),(<safe_why),<mine_why
)
auto_play =: 3 : 0
    rounds =. flagged =. opened =. 0
    while. GameState-:'playing' do.
        'safe mine safe_why mine_why' =. deduction''
        if. -.+./safe+.mine do. break. end.
        rounds =. rounds+1
        for_cell. I.safe do.
            if. -.cell{Revealed do.
                'auto-reveal' record_move cell
                opened =. opened+reveal_cell cell
                win_check''
                if. finished'' do. break. end.
            end.
        end.
        if. finished'' do. break. end.
        for_cell. I.mine do.
            if. cell{unknown'' do.
                Marks =: 1 (cell})Marks
                flagged =. flagged+1
                'auto-flag' record_move cell
            end.
        end.
    end.
    rounds,flagged,opened
)

search_configs =: 3 : 0
    if. y=#SearchOrder do.
        SearchCount =: SearchCount+1
        SearchMines =: SearchMines+SearchValues
        total =. +/SearchValues
        if. SearchCount=1 do. SearchMin =: SearchMax =: total
        else. SearchMin =: SearchMin<.total [ SearchMax =: SearchMax>.total end.
        return.
    end.
    cell =. y{SearchOrder
    affected =. cell{::SearchTouches
    SearchLeft =: ((affected{SearchLeft)-1) affected}SearchLeft
    for_value. 0 1 do.
        SearchSums =: ((affected{SearchSums)+value) affected}SearchSums
        needed =. affected{SearchNeeds-SearchSums
        if. (*./needed>:0)*.*./needed<:affected{SearchLeft do.
            SearchValues =: value cell}SearchValues
            search_configs y+1
        end.
        SearchSums =: ((affected{SearchSums)-value) affected}SearchSums
    end.
    SearchLeft =: ((affected{SearchLeft)+1) affected}SearchLeft
)
count_component =: 3 : 0
    'cells sets needs' =. y
    SearchNeeds =: needs
    SearchLeft =: #&>sets
    SearchSums =: (#sets)$0
    SearchTouches =: (#cells)#<i.0
    for_i. i.#sets do.
        for_cell. cells i.i{::sets do.
            SearchTouches =: (<(cell{::SearchTouches),i) cell}SearchTouches
        end.
    end.
    SearchOrder =: \:#&>SearchTouches
    SearchValues =: SearchMines =: (#cells)$0
    SearchCount =: 0
    SearchMin =: SearchMax =: 0
    if. (*./needs>:0)*.*./needs<:SearchLeft do. search_configs 0 end.
    cells;SearchMines;SearchCount;SearchMin;SearchMax
)
frontier =: 3 : 0
    'constraint_cells sets needs' =. constraints''
    members =. (W*H)#<i.0
    frontier_mask =. (W*H)$0
    for_i. i.#sets do.
        for_cell. i{::sets do.
            members =. (<(cell{::members),i) cell}members
            frontier_mask =. 1 (cell})frontier_mask
        end.
    end.
    seen =. (W*H)$0
    components =. 0$a:
    for_start. I.frontier_mask do.
        if. start{seen do. continue. end.
        queue =. ,start
        seen =. 1 (start})seen
        head =. 0
        used =. (#sets)$0
        while. head<#queue do.
            cell =. head{queue
            head =. head+1
            for_i. cell{::members do.
                if. i{used do. continue. end.
                used =. 1 (i})used
                for_adjacent. i{::sets do.
                    if. -.adjacent{seen do.
                        seen =. 1 (adjacent})seen
                        queue =. queue,adjacent
                    end.
                end.
            end.
        end.
        cells =. /:~queue
        if. (y=_1)+.y e.cells do.
            component =. count_component cells;(used#sets);used#needs
            components =. components,<component
        end.
    end.
    (<frontier_mask),<components
)
guess_cell =: 3 : 0
    'frontier_mask components' =. frontier _1
    hidden =. unknown''
    numerators =. (W*H)$_1
    denominators =. (W*H)$1
    for_component. components do.
        'cells counts total minimum maximum' =. >component
        if. total do.
            numerators =. counts cells}numerators
            denominators =. total cells}denominators
        end.
    end.
    outside =. I.hidden*.-.frontier_mask
    numerators =. (0>.remaining'') outside}numerators
    denominators =. (+/hidden) outside}denominators
    best =. _1
    best_num =. 0
    best_den =. 1
    for_cell. I.hidden*.numerators>:0 do.
        numerator =. cell{numerators
        denominator =. cell{denominators
        if. (best=_1)+.(numerator*best_den)<best_num*denominator do.
            best =. cell
            best_num =. numerator
            best_den =. denominator
        end.
    end.
    best
)
solve =: 3 : 0
    totals =. 3$0
    guesses =. 0
    while. 1 do.
        totals =. totals+auto_play''
        if. finished'' do. break. end.
        cell =. guess_cell''
        if. cell=_1 do. break. end.
        guesses =. guesses+1
        'guess' record_move cell
        opened =. reveal_cell cell
        totals =. ((2{totals)+opened) 2}totals
        win_check''
        if. finished'' do. break. end.
    end.
    guesses,totals
)
board_info =: 3 : 0
    blank =. (-.Mines)*.Numbers=0
    seen =. covered =. (W*H)$0
    openings =. largest =. 0
    for_start. I.blank do.
        if. start{seen do. continue. end.
        openings =. openings+1
        queue =. ,start
        seen =. 1 (start})seen
        area =. (W*H)$0
        head =. 0
        while. head<#queue do.
            cell =. head{queue
            head =. head+1
            adjacent =. cell{::Neighbors
            area =. 1 (cell,adjacent)}area
            for_next. adjacent do.
                if. (next{blank)*.-.next{seen do.
                    seen =. 1 (next})seen
                    queue =. queue,next
                end.
            end.
        end.
        largest =. largest>.+/area
        covered =. covered+.area
    end.
    value =. openings++/(-.Mines)*.-.covered
    say '3bv';value;'openings';openings;'largest';largest;'mines';M;'safe';(W*H)-M
)
replay =: 3 : 0
    saved =. snapshot''
    kinds =. y{.MoveKinds
    cells =. y{.MoveCells
    say 'replay';(number y),'/',number #MoveCells
    reset_board''
    for_i. i.y do.
        kind =. i{::kinds
        cell =. i{cells
        kind record_move cell
        select. kind
        case. 'reveal';'auto-reveal';'guess' do. reveal_cell cell
        case. 'chord' do. chord_cells cell
        case. 'flag';'auto-flag' do. Marks =: 1 (cell})Marks
        case. 'unflag' do. Marks =: 0 (cell})Marks
        case. 'question' do. Marks =: (2*2~:cell{Marks) cell}Marks
        end.
        win_check''
    end.
    show_board''
    restore saved
)

layout =: 3 : 0
    'width height rows' =. y
    for_i. i.#rows do.
        row =. i{::rows
        if. (width~:#row)+.-.*./row e.'*.' do. fail 'bad row ',number i+1 end.
    end.
    mines =. '*'=;rows
    total =. +/mines
    if. (total=0)+.total=width*height do. fail 'bad mine count ',number total end.
    new_game width,height,total,0
    Mines =: mines
    Placed =: 1
    GameState =: 'playing'
    compute_numbers''
    say 'layout';(size_text'');'mines';M
)
command =: 3 : 0
    tokens =. ' ' split y
    op =. 0{::tokens
    index =. Commands i.<op
    if. index=#Commands do. fail 'unknown command ',op end.
    if. (#tokens)~:1+index{Arity do. fail 'bad arguments' end.
    values =. i.0
    if. op-:'PRESET' do.
        name =. 1{::tokens
        if. -.(<name)e.;:'beginner intermediate expert' do. fail 'bad arguments' end.
        seed =. number_word 2{::tokens
        preset =. (;:'beginner intermediate expert')i.<name
        values =. (preset{3 3$9 9 10 16 16 40 30 16 99),seed
    elseif. op-:'SAFETY' do.
        mode =. 1{::tokens
        if. -.(<mode)e.;:'block cell none' do. fail 'bad arguments' end.
    else.
        for_token. }.tokens do. values =. values,number_word >token end.
    end.
    if. (<op)e.;:'NEW PRESET' do.
        'width height total seed' =. values
        if. (width<1)+.(width>30)+.(height<1)+.(height>30)+.(total<1)+.(total>(width*height)-9)+.(seed<1)+.seed>2147483646 do. fail 'bad value' end.
        new_game values
        say 'new';(size_text'');'mines';M
        return.
    elseif. op-:'HISTORY' do.
        if. 0={.values do. fail 'bad value' end.
    end.
    if. op-:'SAFETY' do.
        Safety =: mode
        say 'safety';Safety
        return.
    elseif. op-:'STATS' do.
        rate =. fastest =. '-'
        if. Played do. rate =. (number <.(100*Won)%Played),'%' end.
        if. Fastest~:_1 do. fastest =. number Fastest end.
        say 'stats';'played';Played;'won';Won;'lost';Lost;'rate';rate;'streak';Streak;'best';BestStreak;'fastest';fastest
        return.
    end.
    if. -.HaveGame do. fail 'no game' end.
    if. (<op)e.CellCommands do.
        'x y' =. values
        if. (x>:W)+.y>:H do. fail 'out of range' end.
        cell =. x+W*y
    end.
    if. ((<op)e.LiveCommands)*.finished'' do. fail 'game over' end.
    if. ((<op)e.;:'ANALYZE BOARDINFO')*.-.Placed do. fail 'not started' end.
    before =. undo_snapshot''
    old_count =. #MoveCells
    select. op
    case. 'RESTART' do.
        reset_board''
        say 'restart';(size_text'');'mines';M
    case. 'REVEAL';'FLAG';'UNFLAG';'QUESTION';'PROB' do.
        if. cell{Revealed do. fail 'already revealed' end.
        select. op
        case. 'REVEAL';'PROB' do. if. 1=cell{Marks do. fail 'flagged' end.
        case. 'FLAG' do. if. 1=cell{Marks do. fail 'already flagged' end.
        case. 'UNFLAG' do. if. 1~:cell{Marks do. fail 'not flagged' end.
        end.
        select. op
        case. 'REVEAL' do.
            'reveal' record_move cell
            opened =. reveal_cell cell
            if. -.GameState-:'lost' do.
                say 'revealed';opened
                win_check''
            end.
            finish_output''
        case. 'FLAG' do.
            Marks =: 1 (cell})Marks
            'flag' record_move cell
            say 'flagged';(cell_text cell);'left';remaining''
        case. 'UNFLAG' do.
            Marks =: 0 (cell})Marks
            'unflag' record_move cell
            say 'unflagged';(cell_text cell);'left';remaining''
        case. 'QUESTION' do.
            marked =. 2~:cell{Marks
            Marks =: (2*marked) cell}Marks
            'question' record_move cell
            verb =. marked{::;:'unmarked questioned'
            say verb;(cell_text cell);'left';remaining''
        case. 'PROB' do.
            'frontier_mask components' =. frontier cell
            if. -.cell{frontier_mask do. say 'prob';(cell_text cell);'unconstrained'
            else.
                for_component. components do.
                    'cells counts total minimum maximum' =. >component
                    if. cell e.cells do.
                        if. total=0 do. say 'prob';(cell_text cell);'inconsistent'
                        else. say 'prob';(cell_text cell);(fraction ((cells i.cell){counts),total);'size';(#cells);'configs';total end.
                        break.
                    end.
                end.
            end.
        end.
    case. 'CHORD' do.
        if. -.cell{Revealed do. fail 'not revealed' end.
        value =. cell{Numbers
        if. value=0 do. fail 'no number' end.
        adjacent =. cell{::Neighbors
        flags =. +/1=adjacent{Marks
        if. flags~:value do. fail words 'flags';flags;'of';value end.
        if. -.+./adjacent{unknown'' do. fail 'nothing to reveal' end.
        'chord' record_move cell
        opened =. chord_cells cell
        if. -.GameState-:'lost' do.
            say 'chorded';opened
            win_check''
        end.
        finish_output''
    case. 'UNDO' do.
        if. 0=#Undos do. fail 'nothing to undo' end.
        'name saved' =. >{:Undos
        Undos =: }:Undos
        restore_undo saved
        say 'undo';name;'moves';#MoveCells
    case. 'SHOW' do. show_board''
    case. 'STATUS' do. say 'status';GameState;'left';(remaining'');'moves';(#MoveCells);'revealed';(number +/Revealed),'/',number (W*H)-M
    case. 'CELL' do.
        adjacent =. cell{::Neighbors
        if. cell{Revealed do. say 'cell';(cell_text cell);'number';(cell{Numbers);'flags';(+/1=adjacent{Marks);'unknown';+/adjacent{unknown''
        else. say 'cell';(cell_text cell);'hidden';'mark';((cell{Marks){::;:'none flag question');'open';+/adjacent{Revealed end.
    case. 'HISTORY' do.
        count =. {.values
        say 'history';#MoveCells
        for_i. (0>.(#MoveCells)-count)+i.count<.#MoveCells do. say (i+1);(i{::MoveKinds);cell_text i{MoveCells end.
    case. 'REPLAY' do.
        count =. {.values
        if. count>#MoveCells do. fail 'no move ',number count end.
        replay count
    case. 'HINT' do.
        'safe mine safe_why mine_why' =. deduction''
        if. +./safe do. say 'hint';'safe';(cell_text {.I.safe);'by';({.I.safe){::safe_why
        elseif. +./mine do. say 'hint';'mine';(cell_text {.I.mine);'by';({.I.mine){::mine_why
        else. emit 'hint none' end.
    case. 'AUTO' do.
        'rounds flagged opened' =. auto_play''
        say 'auto';'rounds';rounds;'flagged';flagged;'revealed';opened
        finish_output''
    case. 'ANALYZE' do.
        saved =. snapshot''
        'rounds flagged opened' =. auto_play''
        if. GameState-:'lost' do. text =. words 'analyze';'boom';(cell_text Explosion);'rounds';rounds
        elseif. GameState-:'won' do. text =. words 'analyze';'clear';'rounds';rounds
        else. text =. words 'analyze';'stuck';'rounds';rounds;'revealed';(number +/Revealed),'/',number (W*H)-M end.
        restore saved
        emit text
    case. 'FRONTIER' do.
        'frontier_mask components' =. frontier _1
        say 'frontier';(+/frontier_mask);'components';#components
        for_component. components do.
            'cells counts total minimum maximum' =. >component
            text =. words 'component';(cell_text {.cells);'size';#cells
            if. total do. text =. text,' ',words 'configs';total;'min';minimum;'max';maximum
            else. text =. text,' inconsistent' end.
            emit text
        end.
    case. 'SOLVE' do.
        'guesses rounds flagged opened' =. solve''
        say 'solve';'guesses';guesses;'rounds';rounds;'flagged';flagged;'revealed';opened
        finish_output''
    case. 'BOARDINFO' do. board_info''
    end.
    if. ((<op)e.UndoCommands)*.(#MoveCells)>old_count do.
        name =. ((a.i.op)+32){a.
        Undos =: Undos,<((<name),<before)
        if. finished'' do. update_stats'' end.
    end.
)
main =: 3 : 0
    lines =. <;._2 (1!:1 3),LF
    count =. 0".0{::lines
    position =. 1
    for_i. i.count do.
        line =. position{::lines
        position =. position+1
        tokens =. ' ' split line
        try.
            if. 'LAYOUT'-:0{::tokens do.
                width =. 0".1{::tokens
                height =. 0".2{::tokens
                rows =. height{.position}.lines
                position =. position+height
                layout (<width),(<height),<rows
            else. command line end.
        catcht. emit 'error: ',Error end.
    end.
)
main''
