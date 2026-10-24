LF =: 10{a.
num =: 3 : ',''0'' 8!:2 y'
emit =: 3 : '1!:2&2 y,LF'
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
split =: 4 : '<;._1 x,y'
opponent =: 3 : '(''BW''i.y){''WB'''
inside =: 3 : '((0<:0{y)*.((0{y)<8))*.((0<:1{y)*.((1{y)<8))'
name =: 3 : '((8|y){''abcdefgh''),num 1+<.y%8'
square =: 3 : '(8*((0".,1{y)-1))+''abcdefgh''i.{.y'
initial =: 3 : 0
    board =. 64$'.'
    board =. 'W' 27 36}board
    'B' 28 35}board
)
flips =: 3 : 0
    'board side p' =. y
    if. '.'~:p{board do. i.0 return. end.
    row =. <.p%8
    col =. 8|p
    result =. i.0
    for_dr. _1 0 1 do.
        for_dc. _1 0 1 do.
            if. (dr=0)*.dc=0 do. continue. end.
            r =. row+dr
            c =. col+dc
            line =. i.0
            while. inside r,c do.
                q =. c+8*r
                if. (q{board)~:opponent side do. break. end.
                line =. line,q
                r =. r+dr
                c =. c+dc
            end.
            if. (#line)*.inside r,c do.
                if. side=(c+8*r){board do. result =. result,line end.
            end.
        end.
    end.
    /:~result
)
legal =: 3 : 0
    'board side' =. y
    result =. i.0
    for_p. i.64 do.
        if. ('.'=p{board)*.0<#flips board;side;p do.
            result =. result,p
        end.
    end.
    result
)
place =: 3 : 0
    'board side p' =. y
    targets =. flips board;side;p
    board =. side p}board
    side targets}board
)
discCount =: 4 : '+/y=x'
terminal =: 3 : 0
    (0=#legal y;'B')*.0=#legal y;'W'
)
gameOver =: 3 : 0
    b =. y discCount 'B'
    w =. y discCount 'W'
    if. b>w do. winner =. 'winner B'
    elseif. w>b do. winner =. 'winner W'
    else. winner =. 'draw' end.
    'game over B ',(num b),' W ',(num w),' ',winner
)
weights =: 100 _20 10 5 5 10 _20 100, _20 _50 _2 _2 _2 _2 _50 _20, 10 _2 _1 _1 _1 _1 _2 10, 5 _2 _1 _1 _1 _1 _2 5, 5 _2 _1 _1 _1 _1 _2 5, 10 _2 _1 _1 _1 _1 _2 10, _20 _50 _2 _2 _2 _2 _50 _20, 100 _20 10 5 5 10 _20 100
evaluate =: 3 : 0
    'board side' =. y
    other =. opponent side
    w =. +/ (weights*(board=side)) - weights*(board=other)
    m1 =. #legal board;side
    m2 =. #legal board;other
    ((w+10*m1-m2*10),w,m1,m2)
)
search =: 3 : 0
    'board side depth' =. y
    moves =. legal board;side
    enemy =. opponent side
    if. (0=#moves)*.0=#legal board;enemy do.
        factor =. 1000
        if. depth<0 do. factor =. 1 end.
        factor*((board discCount side)-board discCount enemy) return.
    end.
    if. depth=0 do. {.evaluate board;side return. end.
    next =. depth-1
    if. depth<0 do. next =. _1 end.
    if. 0=#moves do. -search board;enemy;next return. end.
    best =. _1000000
    for_p. moves do.
        value =. -search (place board;side;p);enemy;next
        best =. best>.value
    end.
    best
)
ranked =: 3 : 0
    'board side depth' =. y
    moves =. legal board;side
    values =. i.0
    next =. depth-1
    if. depth<0 do. next =. _1 end.
    for_p. moves do.
        values =. values,-search (place board;side;p);(opponent side);next
    end.
    if. #moves do.
        order =. /: (-values),.moves
        moves =. order{moves
        values =. order{values
    end.
    (<moves),<values
)
variation =: 3 : 0
    'board side depth' =. y
    steps =. 0$a:
    while. (depth~:0)*.-.terminal board do.
        'moves values' =. ranked board;side;depth
        if. #moves do.
            p =. {.moves
            steps =. steps,<name p
            board =. place board;side;p
        else.
            steps =. steps,<'pass'
        end.
        side =. opponent side
        if. depth>0 do. depth =. depth-1 end.
    end.
    (<steps),<board
)
perft =: 3 : 0
    'board side depth' =. y
    if. depth=0 do. 1 return. end.
    moves =. legal board;side
    enemy =. opponent side
    if. 0=#moves do.
        if. 0=#legal board;enemy do. 1 return. end.
        perft board;enemy;depth-1 return.
    end.
    result =. 0
    for_p. moves do.
        result =. result+perft (place board;side;p);enemy;depth-1
    end.
    result
)
stable =: 3 : 0
    board =. y
    known =. 64$0
    axes =. 4 2$0 1 1 0 1 1 1 _1
    while. 1 do.
        found =. i.0
        for_p. i.64 do.
            if. (p{board)='.' do. continue. end.
            if. p{known do. continue. end.
            valid =. 1
            for_axis. i.4 do.
                'dr dc' =. axis{axes
                full =. 1
                anchor =. 0
                for_sign. _1 1 do.
                    r =. (<.p%8)+dr*sign
                    c =. (8|p)+dc*sign
                    if. -.inside r,c do.
                        anchor =. 1
                    elseif. ((c+8*r){known)*.((c+8*r){board)=p{board do.
                        anchor =. 1
                    end.
                    while. inside r,c do.
                        if. ((c+8*r){board)='.' do. full =. 0 end.
                        r =. r+dr*sign
                        c =. c+dc*sign
                    end.
                end.
                if. (-.full)*.-.anchor do. valid =. 0 break. end.
            end.
            if. valid do. found =. found,p end.
        end.
        if. 0=#found do. break. end.
        known =. 1 found}known
    end.
    (+/known*board='B'),+/known*board='W'
)
transformSquare =: 3 : 0
    'p op' =. y
    r =. <.p%8
    c =. 8|p
    select. op
    case. 'rot90' do. (8*c)+7-r
    case. 'rot180' do. 63-p
    case. 'rot270' do. (8*(7-c))+r
    case. 'mirror' do. (8*r)+7-c
    case. 'flip' do. (8*(7-r))+c
    case. 'diag' do. (8*c)+r
    case. do. (8*(7-c))+7-r
    end.
)
transformBoard =: 3 : 0
    'board op' =. y
    result =. 64$'.'
    for_p. i.64 do.
        target =. transformSquare p;op
        result =. (p{board)target}result
    end.
    result
)
nextRandom =: 3 : 0
    Seed =: 2147483647|48271x*Seed
    Seed
)
randomGame =: 3 : 0
    'board side' =. y
    while. 1 do.
        moves =. legal board;side
        if. #moves do.
            index =. (#moves)|nextRandom''
            board =. place board;side;index{moves
        elseif. 0=#legal board;opponent side do.
            board return.
        end.
        side =. opponent side
    end.
)
average =: 3 : 0
    'total moves' =. y
    scaled =. <.100*total%moves
    (num <.scaled%100),'.',(_2{.'00',num 100|scaled)
)
reset =: 3 : 0
    State =: (initial'');'B';0
    History =: Redo =: 0$a:
)
status =: 3 : 0
    'board side over' =. State
    if. over do. gameOver board else. side,' to move' end.
)
adjust =: 3 : 0
    'board side over' =. State
    if. #legal board;side do. 0 return. end.
    enemy =. opponent side
    if. #legal board;enemy do.
        if. -.y do. emit side,' passes' end.
        State =: board;enemy;0
        1 return.
    end.
    State =: board;side;1
    if. -.y do. emit gameOver board end.
    0
)
play =: 3 : 0
    'p quiet value' =. y
    'board side over' =. State
    before =. State
    flipped =. #flips board;side;p
    next =. place board;side;p
    if. -.quiet do.
        text =. side,' ',(name p),' flips ',num flipped
        if. value~:1000000 do. text =. text,' value ',num value end.
        emit text
    end.
    State =: next;(opponent side);0
    passed =. adjust quiet
    History =: History,<side;p;flipped;passed;before;State
    Redo =: 0$a:
    passed
)
reason =: 3 : 0
    p =. y
    'board side over' =. State
    if. over do. 'game over' return. end.
    if. '.'~:p{board do. 'occupied' return. end.
    if. 0=#flips board;side;p do. 'no flips' return. end.
    ''
)
validSquare =: 3 : '(2=#y)*.(({.y)e.''abcdefgh'')*.({:y)e.''12345678'''
validRecord =: 3 : 0
    if. (0=#y)+.(120<#y)+.2|#y do. 0 return. end.
    for_i. i.<.((#y)%2) do.
        if. -.validSquare ((2*i)+i.2){y do. 0 return. end.
    end.
    1
)
validBoard =: 3 : '(64=#y)*.*./y e.''.BW'''
digits =: 3 : '(0<#y)*.*./y e.''0123456789'''
validNum =: 3 : 0
    'word minimum maximum' =. y
    if. -.digits word do. 0 return. end.
    n =. 0".word
    (minimum<:n)*.n<:maximum
)
record =: 3 : 0
    text =. y
    before =. State
    oldHistory =. History
    oldRedo =. Redo
    reset''
    moves =. i.0
    passes =. 0
    for_i. i.<.((#text)%2) do.
        sq =. ((2*i)+i.2){text
        p =. square sq
        why =. reason p
        if. #why do.
            State =: before
            History =: oldHistory
            Redo =: oldRedo
            emit 'ILLEGAL move ',(num i+1),' ',sq,' ',why
            return.
        end.
        moves =. moves,p
        passes =. passes+play p;1;1000000
    end.
    first =. name {.moves
    op =. ''
    if. first-:'e6' do. op =. 'diag'
    elseif. first-:'d3' do. op =. 'anti'
    elseif. first-:'c4' do. op =. 'rot180' end.
    normalized =. ''
    for_p. moves do.
        chosen =. p
        if. #op do. chosen =. transformSquare p;op end.
        normalized =. normalized,name chosen
    end.
    emit 'record ',(num #moves),' moves ',(num passes),' passes'
    emit 'normal ',normalized
    emit status''
)
sheet =: 3 : 0
    'board side over' =. State
    if. #History do.
        entry =. >0{History
        snapshot =. 4{::entry
        board =. 0{::snapshot
    end.
    fields =. <"0 board
    for_i. i.#History do.
        entry =. >i{History
        p =. 1{::entry
        fields =. (<num i+1)p}fields
    end.
    heading =. ' '
    for_c. 'abcdefgh' do. heading =. heading,'  ',c end.
    emit heading
    for_r. i.8 do.
        line =. num r+1
        for_c. i.8 do.
            s =. >(c+8*r){fields
            line =. line,((0>.3-#s)$' '),s
        end.
        emit line
    end.
)
stats =: 3 : 0
    n =. #History
    total =. passes =. 0
    for_entry. History do.
        'side p flipped passed before after' =. >entry
        total =. total+flipped
        passes =. passes+passed
    end.
    if. 0=n do. emit 'moves 0'
    else. emit 'moves ',(num n),' flips ',(num total),' avg ',(average total;n),' passes ',num passes end.
    for_side. 'BW' do.
        count =. sum =. corners =. 0
        maximum =. _1
        best =. 0
        for_entry. History do.
            'who p flipped passed before after' =. >entry
            if. who~:side do. continue. end.
            count =. count+1
            sum =. sum+flipped
            if. flipped>maximum do. maximum =. flipped [ best =. p end.
            corners =. corners+p e.0 7 56 63
        end.
        if. count=0 do. emit side,' moves 0'
        else.
            emit side,' moves ',(num count),' flips ',(num sum),' avg ',(average sum;count),' max ',(num maximum),' ',(name best),' corners ',num corners
        end.
    end.
)
transformGame =: 3 : 0
    op =. y
    'board side over' =. State
    State =: (transformBoard board;op);side;over
    groups =. History;Redo
    transformed =. 0$a:
    for_group. groups do.
        result =. 0$a:
        for_item. >group do.
            'who p flipped passed before after' =. >item
            'b s o' =. before
            before =. (transformBoard b;op);s;o
            'b s o' =. after
            after =. (transformBoard b;op);s;o
            result =. result,<who;(transformSquare p;op);flipped;passed;before;after
        end.
        transformed =. transformed,<result
    end.
    History =: 0{::transformed
    Redo =: 1{::transformed
)
automatic =: 3 : 0
    'black white random seed' =. y
    Seed =: x:seed
    sequence =. ''
    moves =. passes =. 0
    while. 1 do.
        'board side over' =. State
        if. over do. break. end.
        if. random do.
            candidates =. legal board;side
            index =. (#candidates)|nextRandom''
            p =. index{candidates
        else.
            depth =. black
            if. side-:'W' do. depth =. white end.
            'candidates values' =. ranked board;side;depth
            p =. {.candidates
        end.
        sequence =. sequence,name p
        passes =. passes+play p;1;1000000
        moves =. moves+1
    end.
    kind =. 'autoplay'
    if. random do. kind =. 'random' end.
    emit kind,' ',(num moves),' moves ',(num passes),' passes'
    emit 'moves ',sequence
    'board side over' =. State
    emit gameOver board
)
monteCarlo =: 3 : 0
    'trials seed' =. y
    Seed =: x:seed
    'board side over' =. State
    best =. _1
    bestp =. _1
    for_p. legal board;side do.
        w =. d =. l =. 0
        start =. place board;side;p
        for_i. i.trials do.
            last =. randomGame start;opponent side
            diff =. (last discCount side)-last discCount opponent side
            if. diff>0 do. w =. w+1
            elseif. diff=0 do. d =. d+1
            else. l =. l+1 end.
        end.
        emit (name p),' ',(num w),' ',(num d),' ',num l
        points =. 2*w+d
        if. points>best do. best =. points [ bestp =. p end.
    end.
    emit 'best ',(name bestp),' ',num best
)
Zero =: ;:'NEW DUMP SHOW SCORE LEGAL HISTORY SHEET STATS EVAL STABLE SOLVE'
Numeric =: ;:'UNDO REDO HINT PV AI ANALYZE RANDOM PERFT DIVIDE'
Additional =: ;:'LOAD TRANSFORM AUTOPLAY MC FLIPS MOVE PLAY RECORD'
Active =: ;:'FLIPS MOVE PLAY HINT PV AI SOLVE AUTOPLAY RANDOM MC DIVIDE'
execute =: 3 : 0
    tokens =. ' 'split y
    cmd =. 0{::tokens
    args =. }.tokens
    n =. #args
    if. -. (<cmd)e.Zero,Numeric,Additional do. emit 'ERROR unknown command' return. end.
    error =. ''
    if. cmd-:'LOAD' do.
        if. n~:2 do. error =. 'bad board'
        elseif. -. (validBoard 0{::args)*.(<1{::args)e.;:'B W' do. error =. 'bad board' end.
    elseif. (<cmd)e.;:'MOVE FLIPS' do.
        if. n~:1 do. error =. 'bad arguments'
        elseif. -.validSquare 0{::args do. error =. 'bad square' end.
    elseif. (<cmd)e.;:'PLAY RECORD' do.
        if. n~:1 do. error =. 'bad arguments'
        elseif. -.validRecord 0{::args do. error =. 'bad record' end.
    elseif. (<cmd)e.Zero do.
        if. n do. error =. 'bad arguments' end.
    elseif. cmd-:'TRANSFORM' do.
        if. n~:1 do. error =. 'bad arguments'
        elseif. -.(<0{::args)e.;:'rot90 rot180 rot270 mirror flip diag anti' do. error =. 'bad arguments' end.
    else.
        expected =. 1
        if. (<cmd)e.;:'MC AUTOPLAY' do. expected =. 2 end.
        if. n~:expected do. error =. 'bad arguments'
        else.
            a =. 0{::args
            if. -.digits a do. error =. 'bad arguments' end.
            if. expected=2 do.
                if. -.digits 1{::args do. error =. 'bad arguments' end.
            end.
            if. 0=#error do.
                first =. 0".a
                second =. 0
                if. expected=2 do. second =. 0".1{::args end.
                ok =. first>:1
                select. cmd
                case. 'AUTOPLAY' do. ok =. (first e.1 2 3 4)*.second e.1 2 3 4
                case. 'HINT';'PV';'AI';'ANALYZE' do. ok =. first e.1 2 3 4
                case. 'PERFT';'DIVIDE' do. ok =. first e.1+i.8
                case. 'MC' do. ok =. (first>:1)*.(first<:100)*.(second>:1)*.second<2147483647
                case. 'RANDOM' do. ok =. (first>:1)*.first<2147483647
                end.
                if. -.ok do. error =. 'bad arguments' end.
            end.
        end.
    end.
    if. #error do. emit 'ERROR ',error return. end.
    'board side over' =. State
    if. over*.(<cmd)e.Active do. emit 'ERROR game over' return. end.
    value =. 0
    if. (<cmd)e.Numeric do. value =. 0".0{::args end.
    if. (<cmd)e.;:'MC AUTOPLAY' do. value =. 0".0{::args end.
    select. cmd
    case. 'NEW' do.
        reset''
        emit 'OK'
    case. 'LOAD' do.
        State =: (0{::args);(1{::args);0
        History =: Redo =: 0$a:
        emit 'OK'
        adjust 0
    case. 'DUMP' do. emit 'board ',board,' ',side
    case. 'SHOW' do.
        emit '  a b c d e f g h'
        moves =. i.0
        if. -.over do. moves =. legal board;side end.
        for_r. i.8 do.
            row =. num r+1
            for_c. i.8 do.
                p =. c+8*r
                symbol =. p{board
                if. p e.moves do. symbol =. '*' end.
                row =. row,' ',symbol
            end.
            emit row
        end.
        emit status''
    case. 'SCORE' do.
        emit 'score B ',(num board discCount 'B'),' W ',(num board discCount 'W'),' empty ',num board discCount '.'
    case. 'LEGAL' do.
        moves =. i.0
        if. -.over do. moves =. legal board;side end.
        line =. 'legal ',num #moves
        for_p. moves do. line =. line,' ',name p end.
        emit line
    case. 'MOVE';'FLIPS' do.
        p =. square 0{::args
        why =. reason p
        if. #why do. emit 'ILLEGAL ',why
        elseif. cmd-:'MOVE' do. play p;0;1000000
        else.
            targets =. flips board;side;p
            line =. 'flips ',(0{::args),' ',num #targets
            for_target. targets do. line =. line,' ',name target end.
            emit line
        end.
    case. 'PLAY' do.
        recordText =. 0{::args
        for_i. i.<.((#recordText)%2) do.
            word =. ((2*i)+i.2){recordText
            p =. square word
            why =. reason p
            if. #why do.
                emit 'ILLEGAL move ',(num i+1),' ',word,' ',why
                break.
            end.
            play p;0;1000000
        end.
    case. 'RECORD' do. record 0{::args
    case. 'UNDO' do.
        if. value>#History do. emit 'ERROR cannot undo'
        else.
            start =. (#History)-value
            removed =. start}.History
            entry =. >0{removed
            State =: 4{::entry
            History =: start{.History
            Redo =: removed,Redo
            emit status''
        end.
    case. 'REDO' do.
        if. value>#Redo do. emit 'ERROR cannot redo'
        else.
            restored =. value{.Redo
            entry =. >{:restored
            State =: 5{::entry
            History =: History,restored
            Redo =: value}.Redo
            emit status''
        end.
    case. 'HISTORY' do.
        emit 'history ',num #History
        for_i. i.#History do.
            'who p flipped passed before after' =. >i{History
            line =. (num i+1),' ',who,' ',(name p),' ',num flipped
            if. passed do. line =. line,' pass' end.
            emit line
        end.
    case. 'SHEET' do. sheet''
    case. 'STATS' do. stats''
    case. 'TRANSFORM' do.
        transformGame 0{::args
        emit 'OK'
    case. 'EVAL' do.
        'v w m1 m2' =. evaluate board;side
        emit 'eval ',(num v),' weights ',(num w),' mobility ',(num m1),' ',num m2
    case. 'STABLE' do.
        'b w' =. stable board
        emit 'stable B ',(num b),' W ',num w
    case. 'HINT' do.
        'moves scores' =. ranked board;side;value
        for_i. i.#moves do. emit (name i{moves),' ',num i{scores end.
    case. 'PV' do.
        'path last' =. variation board;side;value
        emit 'pv ',(num search board;side;value),' ',' 'join path
    case. 'AI' do.
        'moves scores' =. ranked board;side;value
        play ({.moves);0;{.scores
    case. 'ANALYZE' do.
        loss =. 0 0
        for_i. i.#History do.
            'who p flipped passed before after' =. >i{History
            'beforeBoard beforeSide beforeOver' =. before
            'choices scores' =. ranked beforeBoard;who;value
            best =. {.scores
            played =. (choices i.p){scores
            k =. 'BW'i.who
            loss =. ((k{loss)+best-played)k}loss
            emit (num i+1),' ',who,' ',(name p),' ',(num played),' best ',(name {.choices),' ',num best
        end.
        emit 'loss B ',(num 0{loss),' W ',num 1{loss
    case. 'SOLVE' do.
        if. (board discCount '.')>:9 do. emit 'ERROR too many empties'
        else.
            'moves values' =. ranked board;side;_1
            for_i. i.#moves do. emit (name i{moves),' ',num i{values end.
            'path final' =. variation board;side;_1
            emit 'line ',' 'join path
            emit 'final B ',(num final discCount 'B'),' W ',num final discCount 'W'
        end.
    case. 'AUTOPLAY' do. automatic value;(0".1{::args);0;0
    case. 'RANDOM' do. automatic 0;0;1;value
    case. 'MC' do. monteCarlo value;0".1{::args
    case. 'PERFT' do. emit 'perft ',(num value),' ',num perft board;side;value
    case. 'DIVIDE' do.
        total =. 0
        for_p. legal board;side do.
            count =. perft (place board;side;p);(opponent side);value-1
            emit (name p),' ',num count
            total =. total+count
        end.
        emit 'total ',num total
    end.
)
main =: 3 : 0
    reset''
    lines =. <;._2 (1!:1 <'/dev/stdin'),LF
    count =. 0".0{::lines
    for_i. i.count do.
        execute (i+1){::lines
    end.
)
main''