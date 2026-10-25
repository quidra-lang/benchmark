LF =: 10{a.
Directions =: 'udlr'
Upper =: 'UDLR'
Offsets =: _12 12 _1 1
Digits =: '0123456789'
LevelChars =: '#-.$*@+'
Output =: 0$a:
num =: 3 : ',''0'' 8!:2 y'
lower =: 3 : '(Directions,a.) {~ (Upper,a.) i. y'
emit =: 3 : 'Output =: Output,<y'
fail =: 3 : 0
    emit 'error: ',y
    throw.
)
join =: 4 : '(#x) }. ; (<x) ,&.> y'
split =: 4 : 0
    result =. 0$a:
    part =. ''
    for_ch. y do.
        if. ch = x do.
            result =. result,<part
            part =. ''
        else. part =. part,ch end.
    end.
    result,<part
)
cellText =: 3 : '(num <. y%12),'' '',num 12|y'
pushCount =: 3 : '+/ y e. Upper'

decode =: 4 : 0
    result =. ''
    i =. 0
    while. i < #y do.
        start =. i
        while. i < #y do.
            if. -. (i{y) e. Digits do. break. end.
            i =. i+1
        end.
        count =. 1
        if. i > start do.
            if. ((i-start)>2) +. '0'=start{y do. 0;'' return. end.
            count =. 0 ". (i-start) {. start }. y
        end.
        if. i = #y do. 0;'' return. end.
        if. -. (i{y) e. x do. 0;'' return. end.
        result =. result,count#i{y
        i =. i+1
    end.
    1;result
)
encode =: 3 : 0
    result =. ''
    i =. 0
    while. i < #y do.
        j =. i+1
        while. j < #y do.
            if. (j{y) ~: i{y do. break. end.
            j =. j+1
        end.
        if. 1 < j-i do. result =. result,num j-i end.
        result =. result,i{y
        i =. j
    end.
    result
)
moveBox =: 4 : 0
    'source target' =. y
    /:~ target (x i. source)} x
)

walk =: 3 : 0
    'player boxes' =. y
    reached =. player = i.144
    previous =. 144$_1
    directions =. 144$0
    queue =. ,player
    head =. 0
    while. head < #queue do.
        p =. head{queue
        head =. head+1
        for_d. i.4 do.
            q =. p+d{Offsets
            if. (q{Interior) *. (-.q e. boxes) *. -.q{reached do.
                reached =. 1 q} reached
                previous =. p q} previous
                directions =. d q} directions
                queue =. queue,q
            end.
        end.
    end.
    reached;previous;directions
)
representative =: 3 : '{. I. 0{::walk y'
path =: 4 : 0
    'player boxes' =. x
    'reached previous directions' =. walk x
    result =. ''
    p =. y
    while. p ~: player do.
        result =. ((p{directions){Directions),result
        p =. p{previous
    end.
    result
)
solved =: 3 : '*./ y{Goals'
pushable =: 3 : 0
    'box d boxes reached' =. y
    delta =. d{Offsets
    ((box-delta){reached) *. ((box+delta){Interior) *. -. (box+delta) e. boxes
)
analyze =: 3 : 0
    GoalCells =: I. Goals
    Distances =: 0$a:
    Dead =: Interior
    for_goal. GoalCells do.
        distance =. 0 goal} 144$_1
        queue =. ,goal
        head =. 0
        while. head < #queue do.
            p =. head{queue
            head =. head+1
            for_delta. Offsets do.
                q =. p-delta
                behind =. q-delta
                if. (behind>:0) *. behind<144 do.
                    if. (q{Interior) *. (behind{Interior) *. 0>q{distance do.
                        distance =. (1+p{distance) q} distance
                        queue =. queue,q
                    end.
                end.
            end.
        end.
        Dead =: Dead *. distance<0
        Distances =: Distances,<distance
    end.
)
loadLevel =: 3 : 0
    H =: #y
    W =: #0{::y
    Walls =: 144$1
    Goals =: 144$0
    Interior =: Dead =: 144$0
    Distances =: 0$a:
    players =. boxes =. i.0
    for_r. i.H do.
        row =. r{::y
        for_c. i.W do.
            p =. (12*>:r)+>:c
            ch =. c{row
            Walls =: ('#'=ch) p} Walls
            Goals =: (ch e. '.*+') p} Goals
            if. ch e. '@+' do. players =. players,p end.
            if. ch e. '$*' do. boxes =. boxes,p end.
        end.
    end.
    GoalCells =: I. Goals
    player =. 0
    if. 1 = #players do.
        player =. {.players
        queue =. players
        Interior =: 1 player} Interior
        head =. 0
        while. head < #queue do.
            p =. head{queue
            head =. head+1
            for_delta. Offsets do.
                q =. p+delta
                if. (-.q{Walls) *. -.q{Interior do.
                    Interior =: 1 q} Interior
                    queue =. queue,q
                end.
            end.
        end.
    end.
    Reason =: ''
    if. 1 ~: #players do. Reason =: 'players ',num #players
    elseif. 0 = #boxes do. Reason =: 'no boxes'
    elseif. (#boxes) ~: #GoalCells do.
        Reason =: 'boxes ',(num #boxes),' goals ',num #GoalCells
    else.
        for_p. I.Interior do.
            r =. <.p%12
            c =. 12|p
            if. (r e. 1,H) +. c e. 1,W do.
                Reason =: 'open ',cellText p
                break.
            end.
        end.
        if. 0 = #Reason do.
            outside =. /:~ (boxes,GoalCells) -. I.Interior
            if. #outside do. Reason =: 'outside ',cellText {.outside end.
        end.
    end.
    if. 0 = #Reason do. analyze '' end.
    Initial =: Current =: player;boxes
    History =: Redo =: ''
    SnapNames =: SnapPositions =: SnapHistories =: 0$a:
    HasSolution =: 0
    SolutionPosition =: Current
    SolutionNotation =: ''
)
loaded =: 3 : 'emit ''loaded '',(num H),''x'',num W'

frozen =: 3 : 0
    'box boxes assumed' =. y
    next =. assumed,box
    for_axis. 1 12 do.
        a =. box-axis
        b =. box+axis
        blocked =. (a{Walls) +. (b{Walls) +. (a e. assumed) +. b e. assumed
        blocked =. blocked +. (a{Dead) *. b{Dead
        if. -.blocked do.
            if. a e. boxes do. blocked =. frozen a;boxes;next end.
        end.
        if. -.blocked do.
            if. b e. boxes do. blocked =. frozen b;boxes;next end.
        end.
        if. -.blocked do. 0 return. end.
    end.
    1
)
hasFrozen =: 3 : 0
    for_box. y do.
        if. -.box{Goals do.
            if. frozen box;y;i.0 do. 1 return. end.
        end.
    end.
    0
)
simulate =: 3 : 0
    'player boxes steps' =. y
    letters =. ''
    failure =. ''
    for_letter. lower steps do.
        d =. Directions i. letter
        delta =. d{Offsets
        target =. player+delta
        if. target{Walls do. failure =. 'wall'
        elseif. target e. boxes do.
            if. ((target+delta){Walls) +. (target+delta) e. boxes do. failure =. 'blocked' end.
        end.
        if. #failure do.
            player;boxes;letters;'step ',(num >:letter_index),' ',failure return.
        end.
        if. target e. boxes do.
            boxes =. boxes moveBox target,target+delta
            letters =. letters,d{Upper
        else. letters =. letters,d{Directions end.
        player =. target
    end.
    player;boxes;letters;''
)
takeSteps =: 3 : 0
    'player boxes letters failure' =. simulate Current,<y
    Current =: player;boxes
    History =: History,letters
    if. #letters do. Redo =: '' end.
    letters;failure
)
progress =: 3 : 0
    count =. +/y{Goals
    result =. 'goals ',(num count),'/',num #y
    if. count = #y do. result =. result,' solved' end.
    result
)
render =: 3 : 0
    'player boxes' =. Current
    rows =. 0$a:
    for_r. >:i.H do.
        row =. ''
        for_c. >:i.W do.
            p =. (12*r)+c
            ch =. '-'
            if. p{Walls do. ch =. '#'
            elseif. y do.
                if. p{Goals do. ch =. '.' elseif. p{Dead do. ch =. 'x' end.
            elseif. p=player do. ch =. (p{Goals){'@+'
            elseif. p e. boxes do. ch =. (p{Goals){'$*'
            elseif. p{Goals do. ch =. '.' end.
            row =. row,ch
        end.
        rows =. rows,<row
    end.
    rows
)

stateKey =: 3 : 0
    'player boxes' =. y
    145 #. player,boxes
)
pushSearch =: 3 : 0
    'fixed target limit' =. y
    'player boxes' =. Current
    reps =. ,representative Current
    placements =. ,<boxes
    parents =. pushBoxes =. pushDirections =. ,_1
    buckets =. 65521$<i.0
    key =. stateKey ({.reps);boxes
    slot =. 65521|key
    buckets =. (<,key) slot} buckets
    expanded =. 0
    while. expanded < #reps do.
        if. (limit>0) *. expanded=limit do.
            'limit';expanded;(#reps);'' return.
        end.
        parent =. expanded
        bxs =. parent{::placements
        reached =. 0{::walk (parent{reps);bxs
        expanded =. expanded+1
        for_box. bxs -. fixed do.
            for_d. i.4 do.
                if. -.pushable box;d;bxs;reached do. continue. end.
                destination =. box+d{Offsets
                nextBoxes =. bxs moveBox box,destination
                if. target<0 do.
                    if. destination{Dead do. continue. end.
                    if. hasFrozen nextBoxes do. continue. end.
                end.
                rep =. representative box;nextBoxes
                key =. stateKey rep;nextBoxes
                slot =. 65521|key
                bucket =. slot{::buckets
                if. key e. bucket do. continue. end.
                buckets =. (<bucket,key) slot} buckets
                reps =. reps,rep
                placements =. placements,<nextBoxes
                parents =. parents,parent
                pushBoxes =. pushBoxes,box
                pushDirections =. pushDirections,d
                reachedGoal =. destination=target
                if. target<0 do. reachedGoal =. solved nextBoxes end.
                if. reachedGoal do.
                    route =. i.0
                    index =. <:#reps
                    while. index>0 do.
                        route =. index,route
                        index =. index{parents
                    end.
                    position =. Current
                    notation =. ''
                    for_index. route do.
                        b =. index{pushBoxes
                        d =. index{pushDirections
                        delta =. d{Offsets
                        notation =. notation,(position path b-delta),d{Upper
                        bs =. (1{::position) moveBox b,b+delta
                        position =. b;bs
                    end.
                    'found';expanded;(#reps);notation return.
                end.
            end.
        end.
    end.
    'no solution';expanded;(#reps);''
)

bound =: 3 : 0
    boxes =. 1{::Current
    m =. #boxes
    best =. _1
    bestOrder =. i.0
    for_index. i.!m do.
        order =. index A. i.m
        distances =. i.0
        for_i. i.m do.
            distances =. distances,(i{boxes){(i{order){::Distances
        end.
        if. *./distances>:0 do.
            total =. +/distances
            if. (best<0) +. total<best do.
                best =. total
                bestOrder =. order
            end.
        end.
    end.
    if. best<0 do. emit 'bound none' return. end.
    emit 'bound ',num best
    for_box. boxes do.
        g =. box_index{bestOrder
        distance =. box{g{::Distances
        emit 'box ',(cellText box),' goal ',(cellText g{GoalCells),' pushes ',num distance
    end.
)
transformSteps =: 4 : 0
    table =. 'durlDURL'
    select. x
    case. 'ROT90' do. table =. 'rludRLUD'
    case. 'ROT270' do. table =. 'lrduLRDU'
    case. 'FLIPH' do. table =. 'udrlUDRL'
    case. 'FLIPV' do. table =. 'dulrDULR'
    end.
    table {~ (Directions,Upper) i.y
)
mapPosition =: 4 : 0
    'player boxes' =. y
    (player{x);/:~boxes{x
)
transform =: 3 : 0
    mapping =. i.144
    walls =. 144$1
    goals =. inside =. 144$0
    for_r. >:i.H do.
        for_c. >:i.W do.
            p =. (12*r)+c
            select. y
            case. 'ROT90' do. q =. (12*c)+(H+1)-r
            case. 'ROT180' do. q =. (12*((H+1)-r))+((W+1)-c)
            case. 'ROT270' do. q =. (12*((W+1)-c))+r
            case. 'FLIPH' do. q =. (12*r)+(W+1)-c
            case. 'FLIPV' do. q =. (12*((H+1)-r))+c
            end.
            mapping =. q p} mapping
            walls =. (p{Walls) q} walls
            goals =. (p{Goals) q} goals
            inside =. (p{Interior) q} inside
        end.
    end.
    Walls =: walls
    Goals =: goals
    Interior =: inside
    if. (<y) e. 'ROT90';'ROT270' do. 'H W' =: W,H end.
    analyze ''
    Initial =: mapping mapPosition Initial
    Current =: mapping mapPosition Current
    History =: y transformSteps History
    Redo =: y transformSteps Redo
    for_i. i.#SnapNames do.
        SnapPositions =: (<mapping mapPosition i{::SnapPositions) i} SnapPositions
        SnapHistories =: (<y transformSteps i{::SnapHistories) i} SnapHistories
    end.
    if. HasSolution do.
        SolutionPosition =: mapping mapPosition SolutionPosition
        SolutionNotation =: y transformSteps SolutionNotation
    end.
    emit 'transformed ',(num H),'x',num W
)

Commands =: ;:'IMPORT VALID INFO SHOW EXPORT MOVE PUSH BRING PATH UNDO REDO RESET STATUS HISTORY BOXES REACH DEADSQUARES DEADLOCK BOUND SAVE RESTORE CHECK SOLVE HINT PLAY TRANSFORM'
Formats =: 'a';'';'';'';'';'s';'nnd';'nnnn';'nn';'n';'n';'';'';'';'';'';'';'';'';'k';'k';'s';'n';'n';'';'t'
validArgument =: 4 : 0
    select. x
    case. 'n' do.
        if. -. (1<:#y) *. (6>:#y) *. *./y e.Digits do. 0 return. end.
        (1=#y) +. '0'~:{.y
    case. 'k' do. (1<:#y) *. (8>:#y) *. *./ y e.'abcdefghijklmnopqrstuvwxyz'
    case. 'd' do. (1=#y) *. *./y e.Directions
    case. 't' do. (<y) e. 'ROT90';'ROT180';'ROT270';'FLIPH';'FLIPV'
    case. 's' do. 0{::(Directions,Upper) decode y
    case. do. 1
    end.
)
execute =: 3 : 0
    'words rows' =. y
    name =. 0{::words
    args =. }.words
    if. name -: 'LOAD' do.
        width =. 0 ". 1{::args
        for_row. rows do.
            text =. >row
            if. (width~:#text) +. -. *./text e.LevelChars do.
                fail 'bad row ',num >:row_index
            end.
        end.
        loadLevel rows
        loaded ''
        return.
    end.
    command =. Commands i.<name
    if. command=#Commands do. fail 'unknown command ',name end.
    format =. command{::Formats
    if. (#args)~:#format do. fail 'bad arguments' end.
    for_arg. args do.
        if. -. (arg_index{format) validArgument >arg do. fail 'bad arguments' end.
    end.
    if. name -: 'IMPORT' do.
        rows =. 0$a:
        for_part. '|' split 0{::args do.
            'ok row' =. LevelChars decode >part
            if. -.ok do. fail 'bad level' end.
            rows =. rows,<row
        end.
        widths =. #&>rows
        if. ((#rows)>10) +. (0={.widths) +. (10<{.widths) +. -. *./widths={.widths do.
            fail 'bad level'
        end.
        loadLevel rows
        loaded ''
        return.
    end.
    if. name -: 'VALID' do.
        if. #Reason do. emit 'invalid ',Reason else. emit 'valid' end.
        return.
    end.
    if. #Reason do. fail 'invalid level' end.
    pairCount =. 0
    if. (<name) e. 'PATH';'PUSH' do. pairCount =. 1 end.
    if. name -: 'BRING' do. pairCount =. 2 end.
    cells =. i.0
    for_i. i.pairCount do.
        r =. 0 ". (2*i){::args
        c =. 0 ". (1+2*i){::args
        if. (r<1) +. (r>H) +. (c<1) +. c>W do. fail 'bad value' end.
        cells =. cells,(12*r)+c
    end.
    if. (<name) e. 'UNDO';'REDO';'SOLVE';'HINT' do.
        amount =. 0 ". 0{::args
        if. amount<1 do. fail 'bad value' end.
        if. (<name) e. 'SOLVE';'HINT' do.
            if. amount>100000 do. fail 'bad value' end.
        end.
    end.
    'player boxes' =. Current
    select. name
    case. 'INFO' do.
        actual =. ,(12*>:i.H) +/ >:i.W
        emit 'size ',(num H),'x',(num W),' walls ',(num +/actual{Walls),' cells ',(num +/Interior),' boxes ',(num #boxes),' dead ',num +/Dead
    case. 'SHOW' do. Output =: Output,render 0
    case. 'EXPORT' do. emit 'level ','|' join encode&.> render 0
    case. 'DEADSQUARES' do.
        emit 'dead ',num +/Dead
        Output =: Output,render 1
    case. 'MOVE' do.
        steps =. 1{::(Directions,Upper) decode 0{::args
        'letters failure' =. takeSteps steps
        if. #letters do. emit 'moved ',letters end.
        if. #failure do. fail failure end.
    case. 'CHECK' do.
        steps =. 1{::(Directions,Upper) decode 0{::args
        'p bs letters failure' =. simulate Current,<steps
        if. #failure do. emit 'check fail ',failure
        else.
            emit 'check ok moves ',(num #letters),' pushes ',(num pushCount letters),' ',progress bs
        end.
    case. 'PATH';'PUSH' do.
        reached =. 0{::walk Current
        target =. {.cells
        suffix =. ''
        if. name -: 'PUSH' do.
            d =. Directions i. {.2{::args
            delta =. d{Offsets
            if. -.target e.boxes do. fail 'no box' end.
            if. (-.(target+delta){Interior) +. (target+delta) e.boxes do. fail 'blocked' end.
            target =. target-delta
            suffix =. d{Directions
        end.
        if. -.target{reached do. fail 'unreachable' end.
        route =. (Current path target),suffix
        'letters failure' =. takeSteps route
        if. name -: 'PUSH' do. emit 'pushed ',letters
        elseif. #route do. emit 'path ',(num #route),' ',letters
        else. emit 'path 0' end.
    case. 'BRING' do.
        'source target' =. cells
        if. -.source e.boxes do. fail 'no box' end.
        if. source=target do. emit 'brought 0'
        else.
            'outcome expanded states notation' =. pushSearch (boxes-.source);target;0
            if. -.outcome -: 'found' do. fail 'no route' end.
            takeSteps notation
            emit 'brought ',(num pushCount notation),' ',notation
        end.
    case. 'UNDO' do.
        if. 0=#History do. fail 'nothing to undo' end.
        count =. amount <. #History
        for_i. i.count do.
            letter =. {:History
            History =: }:History
            delta =. (Directions i.lower letter){Offsets
            if. letter e.Upper do. boxes =. boxes moveBox (player+delta),player end.
            player =. player-delta
            Redo =: Redo,lower letter
        end.
        Current =: player;boxes
        emit 'undone ',num count
    case. 'REDO' do.
        if. 0=#Redo do. fail 'nothing to redo' end.
        count =. amount <. #Redo
        for_i. i.count do.
            letter =. {:Redo
            Redo =: }:Redo
            'p bs letters failure' =. simulate Current,<,letter
            Current =: p;bs
            History =: History,letters
        end.
        emit 'redone ',num count
    case. 'RESET' do.
        Current =: Initial
        History =: Redo =: ''
        emit 'reset'
    case. 'STATUS' do.
        emit 'moves ',(num #History),' pushes ',(num pushCount History),' ',progress boxes
    case. 'HISTORY' do.
        if. #History do. emit 'history ',(num #History),' ',History
        else. emit 'history 0' end.
    case. 'REACH' do.
        reached =. 0{::walk Current
        emit 'reach ',(num +/reached),' first ',cellText {.I.reached
    case. 'BOXES' do.
        emit 'boxes ',num #boxes
        reached =. 0{::walk Current
        for_box. boxes do.
            ds =. i.0
            for_distance. Distances do. ds =. ds,box{>distance end.
            ds =. ds#~ds>:0
            distance =. 'dead'
            if. #ds do. distance =. num <./ds end.
            directions =. ''
            for_d. i.4 do.
                if. pushable box;d;boxes;reached do. directions =. directions,d{Directions end.
            end.
            if. 0=#directions do. directions =. '-' end.
            emit 'box ',(cellText box),' ',distance,' ',directions
        end.
    case. 'DEADLOCK' do.
        for_box. boxes do.
            if. box{Dead do. emit 'deadlock dead ',cellText box return. end.
        end.
        for_box. boxes do.
            if. -.box{Goals do.
                if. frozen box;boxes;i.0 do. emit 'deadlock frozen ',cellText box return. end.
            end.
        end.
        emit 'no deadlock'
    case. 'BOUND' do. bound ''
    case. 'SAVE' do.
        key =. 0{::args
        index =. SnapNames i.<key
        if. index=#SnapNames do.
            SnapNames =: SnapNames,<key
            SnapPositions =: SnapPositions,<Current
            SnapHistories =: SnapHistories,<History
        else.
            SnapPositions =: (<Current) index}SnapPositions
            SnapHistories =: (<History) index}SnapHistories
        end.
        emit 'saved ',key,' moves ',num #History
    case. 'RESTORE' do.
        key =. 0{::args
        index =. SnapNames i.<key
        if. index=#SnapNames do. fail 'no snapshot ',key end.
        Current =: index{::SnapPositions
        History =: index{::SnapHistories
        Redo =: ''
        emit 'restored ',key,' moves ',num #History
    case. 'SOLVE';'HINT' do.
        if. name -: 'SOLVE' do. HasSolution =: 0 end.
        if. solved boxes do. emit 'already solved' return. end.
        'outcome expanded states notation' =. pushSearch (i.0);_1;amount
        counts =. ' expanded ',(num expanded),' states ',num states
        if. -.outcome -: 'found' do. emit outcome,counts
        elseif. name -: 'SOLVE' do.
            emit 'solution pushes ',(num pushCount notation),' moves ',(num #notation),counts
            emit notation
            HasSolution =: 1
            SolutionPosition =: Current
            SolutionNotation =: notation
        else.
            part =. (>: (notation e.Upper) i.1) {. notation
            takeSteps part
            emit 'hint ',part
        end.
    case. 'PLAY' do.
        if. (-.HasSolution) +. -.Current -: SolutionPosition do. fail 'no solution' end.
        takeSteps SolutionNotation
        emit 'played pushes ',(num pushCount SolutionNotation),' moves ',num #SolutionNotation
    case. 'TRANSFORM' do. transform 0{::args
    end.
)
main =: 3 : 0
    lines =. <;._2 (1!:1 <'/dev/stdin'),LF
    header =. 0 ". 0{::lines
    height =. {.header
    loadLevel height {. }.lines
    index =. >:height
    commands =. 0 ". index{::lines
    index =. >:index
    for_i. i.commands do.
        words =. ' ' split index{::lines
        index =. >:index
        rows =. 0$a:
        if. 'LOAD' -: 0{::words do.
            height =. 0 ". 1{::words
            rows =. height {. index }.lines
            index =. index+height
        end.
        try. execute (<words),<rows catcht. end.
    end.
    1!:2&2 (LF join Output),LF
)
main''
