LF =: 10{a.
Columns =: 'ABCDEFGHJKLMNOPQRST'
Letters =: 'abcdefghijklmnopqrstuvwxyz'
Commands =: ;:'BOARD KOMI SUPERKO HANDICAP PLAY PASS REPLAY UNDO SHOW MAP STATUS CAPTURES HISTORY MOVES GROUP GROUPS ATARI LEGAL EYES SAFE LADDER DEAD REGIONS SCORE'
Arities =: 2 1 1 1 2 1 1 0 0 0 0 0 0 0 1 0 0 1 1 1 1 1 0 1
emit =: 3 : '1!:2&2 y,LF'
num =: 3 : ',''0'' 8!:2 y'
split =: 4 : '<;._1 x,y'
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
other =: 3 : '(''BW''i.y){''WB'''
digits =: 3 : '(0<#y)*.*./y e.''0123456789'''
halfText =: 3 : 0
    value =. |y
    sign =. ''
    if. y<0 do. sign =. '-' end.
    sign,(num <.value%2),'.',(2|value){'05'
)
validKomi =: 3 : 0
    word =. y
    if. 0=#word do. 0 return. end.
    negative =. '-'={.word
    if. negative do. word =. }.word end.
    parts =. '.'split word
    if. (#parts)>2 do. 0 return. end.
    integer =. 0{::parts
    if. -.digits integer do. 0 return. end.
    if. (1<#integer)*.({.integer)='0' do. 0 return. end.
    if. (0".integer)>100 do. 0 return. end.
    fractional =. '0'
    if. 2=#parts do.
        fractional =. 1{::parts
        if. -.(fractional-:'0')+.(fractional-:'5') do. 0 return. end.
    end.
    if. negative*.((0".integer)=0)*.(fractional-:'0') do. 0 return. end.
    1
)
parseKomi =: 3 : 0
    word =. y
    negative =. '-'={.word
    if. negative do. word =. }.word end.
    parts =. '.'split word
    value =. 2*0".0{::parts
    if. 2=#parts do.
        if. (1{::parts)-:'5' do. value =. value+1 end.
    end.
    if. negative do. -value else. value end.
)
point =: 3 : 0
    if. (#y)<2 do. _1 return. end.
    column =. Columns i.{.y
    if. column>:N do. _1 return. end.
    row =. }.y
    if. -.digits row do. _1 return. end.
    if. ({.row)='0' do. _1 return. end.
    r =. 0".row
    if. (r<1)+.(r>N) do. _1 return. end.
    column+N*r-1
)
name =: 3 : 0
    ((N|y){Columns),num 1+<.y%N
)
sgf =: 3 : 0
    ((N|y){Letters),((N-1)-<.y%N){Letters
)
fromSgf =: 3 : 0
    col =. Letters i.{.y
    row =. Letters i.{:y
    ((N-1-row)*N)+col
)
neighbors =: 3 : 0
    p =. y
    r =. <.p%N
    c =. N|p
    result =. i.0
    if. r>0 do. result =. result,p-N end.
    if. r<N-1 do. result =. result,p+N end.
    if. c>0 do. result =. result,p-1 end.
    if. c<N-1 do. result =. result,p+1 end.
    /:~result
)
diagonals =: 3 : 0
    p =. y
    r =. <.p%N
    c =. N|p
    result =. i.0
    for_dr. _1 1 do.
        for_dc. _1 1 do.
            nr =. r+dr
            nc =. c+dc
            if. (0<:nr)*.(nr<N)*.(0<:nc)*.nc<N do.
                result =. result,nc+N*nr
            end.
        end.
    end.
    /:~result
)
flood =: 3 : 0
    'b origin allowed' =. y
    seen =. ,origin
    pending =. ,origin
    while. #pending do.
        q =. {:pending
        pending =. }:pending
        for_p. neighbors q do.
            if. (p{b)e.allowed do.
                if. -.p e.seen do.
                    seen =. seen,p
                    pending =. pending,p
                end.
            end.
        end.
    end.
    /:~seen
)
group =: 3 : 0
    'b p' =. y
    color =. p{b
    stones =. flood b;p;color
    liberties =. i.0
    for_q. stones do.
        for_t. neighbors q do.
            if. '.'=t{b do. liberties =. liberties,t end.
        end.
    end.
    color;({.stones);stones;(/:~~.liberties)
)
groups =: 3 : 0
    'b filter' =. y
    seen =. i.0
    result =. 0$a:
    for_p. i.#b do.
        color =. p{b
        if. color='.' do. continue. end.
        if. p e.seen do. continue. end.
        if. #filter do.
            if. color~:filter do. continue. end.
        end.
        entry =. group b;p
        seen =. seen,2{::entry
        result =. result,<entry
    end.
    result
)
placement =: 3 : 0
    'b color p' =. y
    if. '.'~:p{b do. b;0;'occupied' return. end.
    next =. color p}b
    captured =. 0
    seen =. i.0
    for_q. neighbors p do.
        if. ((q{next)=other color)*.-.q e.seen do.
            entry =. group next;q
            stones =. 2{::entry
            liberties =. 3{::entry
            seen =. seen,stones
            if. 0=#liberties do.
                next =. '.' stones}next
                captured =. captured+#stones
            end.
        end.
    end.
    if. 0=#3{::group next;p do.
        next;captured;'suicide'
    else.
        next;captured;''
    end.
)
regions =: 3 : 0
    b =. y
    seen =. i.0
    result =. 0$a:
    for_p. i.#b do.
        if. '.'~:p{b do. continue. end.
        if. p e.seen do. continue. end.
        points =. flood b;p;'.'
        seen =. seen,points
        border =. ''
        for_q. points do.
            for_t. neighbors q do.
                c =. t{b
                if. c~:'.' do. border =. border,c end.
            end.
        end.
        distinct =. ~.border
        owner =. 'neutral'
        if. 1=#distinct do. owner =. distinct end.
        result =. result,<p;points;owner
    end.
    result
)
safe =: 3 : 0
    'b color' =. y
    own =. groups b;color
    seen =. i.0
    areas =. 0$a:
    for_p. i.#b do.
        if. (p{b)=color do. continue. end.
        if. p e.seen do. continue. end.
        points =. flood b;p;'.',other color
        seen =. seen,points
        empty =. points#~'.'=points{b
        touch =. i.0
        vital =. i.0
        for_i. i.#own do.
            entry =. >i{own
            stones =. 2{::entry
            liberties =. 3{::entry
            if. *./empty e.liberties do. vital =. vital,i end.
            hits =. 0
            for_q. points do.
                if. +./(neighbors q)e.stones do. hits =. 1 break. end.
            end.
            if. hits do. touch =. touch,i end.
        end.
        areas =. areas,<touch;vital
    end.
    remaining =. i.#own
    active =. i.#areas
    while. 1 do.
        old =. (#remaining)+#active
        keep =. i.0
        for_i. remaining do.
            count =. 0
            for_j. active do.
                entry =. >j{areas
                if. i e.1{::entry do. count =. count+1 end.
            end.
            if. count>:2 do. keep =. keep,i end.
        end.
        remaining =. keep
        keep =. i.0
        for_j. active do.
            entry =. >j{areas
            if. *./(0{::entry)e.remaining do. keep =. keep,j end.
        end.
        active =. keep
        if. old=(#remaining)+#active do. break. end.
    end.
    remaining{own
)
ladderRead =: 3 : 0
    'b p depth defending' =. y
    if. depth>:40 do. defending;_1 return. end.
    'color rep stones liberties' =. group b;p
    attacker =. other color
    candidates =. liberties
    if. defending do.
        seen =. i.0
        for_q. stones do.
            for_t. neighbors q do.
                if. ((t{b)=attacker)*.-.t e.seen do.
                    enemy =. group b;t
                    seen =. seen,2{::enemy
                    if. 1=#3{::enemy do. candidates =. candidates,3{::enemy end.
                end.
            end.
        end.
    end.
    candidates =. /:~~.candidates
    for_q. candidates do.
        mover =. attacker
        if. defending do. mover =. color end.
        'next captured reason' =. placement b;mover;q
        if. #reason do. continue. end.
        'color2 rep2 stones2 libs2' =. group next;p
        if. defending do.
            success =. (#libs2)>:3
            if. 2=#libs2 do.
                'caught step' =. ladderRead next;p;(depth+1);0
                success =. -.caught
            end.
        else.
            success =. 0
            if. 1=#libs2 do.
                'escaped step' =. ladderRead next;p;(depth+1);1
                success =. -.escaped
            end.
        end.
        if. success do. 1;q return. end.
    end.
    0;_1
)
validSequence =: 3 : 0
    text =. y
    if. 0=#text do. 0 return. end.
    p =. 0
    while. p<#text do.
        if. (p+3)>:#text do. 0 return. end.
        if. ';'~:p{text do. 0 return. end.
        if. -.((p+1){text)e.'BW' do. 0 return. end.
        if. '['~:(p+2){text do. 0 return. end.
        p =. p+3
        content =. ''
        while. p<#text do.
            if. ']'=p{text do. break. end.
            content =. content,p{text
            p =. p+1
        end.
        if. p=#text do. 0 return. end.
        if. #content do.
            if. 2~:#content do. 0 return. end.
            if. +./N<:Letters i.content do. 0 return. end.
        end.
        p =. p+1
    end.
    1
)
starPoints =: 3 : 0
    base =. handicapNames''
    ix =. 0 1 2 3 8
    if. N=19 do. ix =. i.9 end.
    names =. ix{base
    result =. i.0
    for_word. names do. result =. result,point >word end.
    result
)
handicapNames =: 3 : 0
    select. N
    case. 9 do. ;:'C3 G7 C7 G3 C5 G5 E3 E7 E5'
    case. 13 do. ;:'D4 K10 D10 K4 D7 K7 G4 G10 G7'
    case. do. ;:'D4 Q16 D16 Q4 D10 Q10 K4 K16 K10'
    end.
)
reset =: 3 : 0
    'N Komi' =: y
    Board =: (N*N)$'.'
    Turn =: 'B'
    Caps =: 0 0
    Passes =: 0
    Over =: 0
    Handicap =: i.0
    History =: 0$a:
    Positions =: ,<Board
    Dead =: (N*N)$0
)
cleanBoard =: 3 : 0
    b =. Board
    for_p. I.Dead do. b =. '.' p}b end.
    b
)
checkMove =: 3 : 0
    'color p' =. y
    'b captured reason' =. placement Board;color;p
    if. 0=#reason do.
        if. 2<:#Positions do.
            old =. >((#Positions)-2){Positions
            if. b-:old do. reason =. 'ko' end.
        end.
    end.
    if. (0=#reason)*.Superko do.
        for_item. Positions do.
            if. b-:>item do. reason =. 'superko' break. end.
        end.
    end.
    b;captured;reason
)
playMove =: 3 : 0
    'color p' =. y
    before =. Board;Turn;Caps;Passes;Over
    captured =. 0
    if. p<0 do.
        Passes =: Passes+1
        if. Passes=2 do. Over =: 1 end.
    else.
        'nextBoard captured reason' =. checkMove color;p
        Board =: nextBoard
        idx =. 'BW'i.color
        Caps =: (captured+idx{Caps)idx}Caps
        Passes =: 0
    end.
    Turn =: other color
    History =: History,<color;p;captured;before
    Positions =: Positions,<Board
    Dead =: (N*N)$0
    captured
)
display =: 3 : 0
    mapped =. y
    b =. Board
    if. mapped do. b =. cleanBoard'' end.
    chars =. b
    if. mapped do.
        for_entry. regions b do.
            'rep points owner' =. >entry
            symbol =. '.'
            if. owner-:'B' do. symbol =. 'x'
            elseif. owner-:'W' do. symbol =. 'o' end.
            chars =. symbol points}chars
        end.
    end.
    stars =. starPoints''
    for_p. i.#b do.
        c =. p{b
        if. c='B' do.
            symbol =. 'X'
            if. (-.mapped)*.p{Dead do. symbol =. 'x' end.
            chars =. symbol p}chars
        elseif. c='W' do.
            symbol =. 'O'
            if. (-.mapped)*.p{Dead do. symbol =. 'o' end.
            chars =. symbol p}chars
        elseif. -.mapped do.
            if. p e.stars do. chars =. '+' p}chars
            else. chars =. '.' p}chars end.
        end.
    end.
    header =. '   ',(' ' join <"0 N{.Columns)
    emit header
    for_r. |.1+i.N do.
        row =. ((r-1)*N)+i.N
        emit (_2{.'  ',num r),' ',(' ' join <"0 row{chars),' ',num r
    end.
    emit header
)
reportScore =: 3 : 0
    method =. y
    b =. cleanBoard''
    blackTerritory =. whiteTerritory =. 0
    for_entry. regions b do.
        'rep points owner' =. >entry
        if. owner-:'B' do. blackTerritory =. blackTerritory+#points end.
        if. owner-:'W' do. whiteTerritory =. whiteTerritory+#points end.
    end.
    if. method-:'AREA' do.
        blackStones =. +/'B'=b
        whiteStones =. +/'W'=b
        bTotal =. 2*blackStones+blackTerritory
        wTotal =. (2*whiteStones+whiteTerritory)+Komi
        emit 'B stones ',(num blackStones),' territory ',(num blackTerritory),' total ',halfText bTotal
        emit 'W stones ',(num whiteStones),' territory ',(num whiteTerritory),' komi ',(halfText Komi),' total ',halfText wTotal
    else.
        blackPrisoners =. (0{Caps)+ +/Dead*Board='W'
        whitePrisoners =. (1{Caps)+ +/Dead*Board='B'
        bTotal =. 2*blackTerritory+blackPrisoners
        wTotal =. (2*whiteTerritory+whitePrisoners)+Komi
        emit 'B territory ',(num blackTerritory),' prisoners ',(num blackPrisoners),' total ',halfText bTotal
        emit 'W territory ',(num whiteTerritory),' prisoners ',(num whitePrisoners),' komi ',(halfText Komi),' total ',halfText wTotal
    end.
    d =. bTotal-wTotal
    if. d>0 do. emit 'result B+',halfText d
    elseif. d<0 do. emit 'result W+',halfText -d
    else. emit 'result Draw' end.
)
execute =: 3 : 0
    args =. ' 'split y
    cmd =. 0{::args
    args =. }.args
    index =. Commands i.<cmd
    if. index=#Commands do. emit 'ERROR unknown command' return. end.
    if. (#args)~:index{Arities do. emit 'ERROR bad arguments' return. end.
    a =. ''
    b =. ''
    if. #args do. a =. 0{::args end.
    if. 1<#args do. b =. 1{::args end.
    valid =. 1
    select. cmd
    case. 'BOARD' do. valid =. ((<a)e.;:'9 13 19')*.validKomi b
    case. 'KOMI' do. valid =. validKomi a
    case. 'SUPERKO' do. valid =. (<a)e.;:'ON OFF'
    case. 'HANDICAP' do. valid =. (<a)e.;:'2 3 4 5 6 7 8 9'
    case. 'PLAY';'PASS';'LEGAL';'EYES';'SAFE' do. valid =. (<a)e.;:'B W'
    case. 'SCORE' do. valid =. (<a)e.;:'AREA TERRITORY'
    end.
    if. -.valid do. emit 'ERROR bad arguments' return. end.
    p =. _1
    if. (<cmd)e.;:'PLAY GROUP LADDER DEAD' do.
        word =. a
        if. cmd-:'PLAY' do. word =. b end.
        p =. point word
        if. p<0 do. emit 'ERROR bad point' return. end.
    end.
    if. cmd-:'REPLAY' do.
        if. -.validSequence a do. emit 'ERROR bad sequence' return. end.
    end.
    if. ((<cmd)e.;:'PLAY PASS REPLAY')*.Over do. emit 'ERROR game over' return. end.
    select. cmd
    case. 'BOARD' do.
        reset (0".a);parseKomi b
        emit 'board ',(num N),' komi ',halfText Komi
    case. 'KOMI' do.
        Komi =: parseKomi a
        emit 'komi ',halfText Komi
    case. 'SUPERKO' do.
        Superko =: a-:'ON'
        if. Superko do. emit 'superko on' else. emit 'superko off' end.
    case. 'HANDICAP' do.
        if. (#History)+ +/Board~:'.' do. emit 'ERROR handicap not allowed' return. end.
        k =. 0".a
        ix =. i.k
        if. k=5 do. ix =. 0 1 2 3 8 end.
        if. k=7 do. ix =. 0 1 2 3 4 5 8 end.
        chosen =. ix{handicapNames''
        Handicap =: i.0
        line =. 'handicap ',num k
        for_word. chosen do.
            q =. point >word
            Handicap =: Handicap,q
            Board =: 'B' q}Board
            line =. line,' ',name q
        end.
        Turn =: 'W'
        Positions =: ,<Board
        Dead =: (N*N)$0
        emit line
    case. 'PLAY' do.
        if. a~:Turn do. emit 'ILLEGAL ',a,' ',b,' turn' return. end.
        'next taken reason' =. checkMove a;p
        if. #reason do.
            emit 'ILLEGAL ',a,' ',b,' ',reason
        else.
            taken =. playMove a;p
            line =. a,' ',b
            if. taken do. line =. line,' captures ',num taken end.
            emit line
        end.
    case. 'PASS' do.
        if. a~:Turn do. emit 'ILLEGAL ',a,' pass turn' return. end.
        playMove a;_1
        emit a,' pass'
        if. Over do. emit 'game over' end.
    case. 'REPLAY' do.
        count =. 0
        stopped =. ''
        remain =. a
        while. #remain do.
            color =. 1{remain
            indexClose =. remain i.']'
            content =. (3+i.indexClose-3){remain
            remain =. (indexClose+1)}.remain
            q =. _1
            desc =. 'pass'
            if. #content do.
                q =. fromSgf content
                desc =. name q
            end.
            reason =. ''
            if. Over do. reason =. 'game over'
            elseif. color~:Turn do. reason =. 'turn'
            elseif. q>:0 do.
                next =. checkMove color;q
                reason =. 2{::next
            end.
            if. #reason do.
                stopped =. ' stopped ',color,' ',desc,' ',reason
                break.
            end.
            playMove color;q
            count =. count+1
        end.
        emit 'replay ',(num count),' moves',stopped
        if. Over do. emit 'game over' end.
    case. 'UNDO' do.
        if. 0=#History do. emit 'ERROR nothing to undo' return. end.
        entry =. >{:History
        History =: }:History
        'color q taken before' =. entry
        'Board Turn Caps Passes Over' =: before
        Positions =: }:Positions
        Dead =: (N*N)$0
        if. q<0 do. emit 'undo ',color,' pass'
        else. emit 'undo ',color,' ',name q end.
    case. 'SHOW' do. display 0
    case. 'MAP' do. display 1
    case. 'STATUS' do.
        mode =. 'off'
        if. Superko do. mode =. 'on' end.
        emit 'size ',(num N),' komi ',(halfText Komi),' handicap ',(num #Handicap),' superko ',mode
        if. Over do. emit 'moves ',(num #History),' game over'
        else. emit 'moves ',(num #History),' next ',Turn,' passes ',num Passes end.
    case. 'CAPTURES' do.
        emit 'captures B ',(num 0{Caps),' W ',num 1{Caps
    case. 'HISTORY' do.
        emit 'history ',num #History
        for_i. i.#History do.
            'color q taken before' =. >i{History
            word =. 'pass'
            if. q>:0 do. word =. name q end.
            line =. (num i+1),' ',color,' ',word
            if. taken do. line =. line,' captures ',num taken end.
            emit line
        end.
    case. 'MOVES' do.
        line =. '(;GM[1]FF[4]SZ[',(num N),']KM[',(halfText Komi),']'
        if. #Handicap do.
            line =. line,'HA[',(num #Handicap),']AB'
            for_q. Handicap do. line =. line,'[',(sgf q),']' end.
        end.
        for_entry. History do.
            'color q taken before' =. >entry
            loc =. ''
            if. q>:0 do. loc =. sgf q end.
            line =. line,';',color,'[',loc,']'
        end.
        emit line,')'
    case. 'GROUP';'LADDER';'DEAD' do.
        if. '.'=p{Board do. emit 'ERROR no stone' return. end.
        'color rep stones liberties' =. group Board;p
        if. cmd-:'GROUP' do.
            emit 'group ',color,' ',(name rep),' size ',(num #stones),' liberties ',num #liberties
            line =. 'stones'
            for_q. stones do. line =. line,' ',name q end.
            emit line
            line =. 'liberties'
            for_q. liberties do. line =. line,' ',name q end.
            emit line
        elseif. cmd-:'DEAD' do.
            state =. p{Dead
            Dead =: (1-state)stones}Dead
            if. state do. prefix =. 'alive ' else. prefix =. 'dead ' end.
            emit prefix,color,' ',(name rep),' size ',num #stones
        else.
            if. (#liberties)>:3 do. emit 'ladder ',a,' safe'
            else.
                defending =. 1=#liberties
                'success q' =. ladderRead Board;p;0;defending
                if. defending do.
                    if. success do. emit 'ladder ',a,' escapes ',name q
                    else. emit 'ladder ',a,' captured' end.
                else.
                    if. success do. emit 'ladder ',a,' captured ',name q
                    else. emit 'ladder ',a,' escapes' end.
                end.
            end.
        end.
    case. 'GROUPS' do.
        all =. groups Board;''
        emit 'groups ',num #all
        for_entry. all do.
            'color rep stones liberties' =. >entry
            line =. color,' ',(name rep),' size ',(num #stones),' liberties ',num #liberties
            if. rep{Dead do. line =. line,' dead' end.
            emit line
        end.
    case. 'ATARI' do.
        all =. groups Board;''
        count =. 0
        for_entry. all do.
            'color rep stones liberties' =. >entry
            if. 1=#liberties do.
                count =. count+1
                emit 'atari ',color,' ',(name rep),' size ',(num #stones),' at ',name {.liberties
            end.
        end.
        if. count=0 do. emit 'atari none' end.
    case. 'LEGAL' do.
        count =. 0
        rejected =. 0$a:
        for_q. i.#Board do.
            if. '.'~:q{Board do. continue. end.
            'next taken reason' =. checkMove a;q
            if. 0=#reason do. count =. count+1
            else. rejected =. rejected,<q;reason end.
        end.
        emit 'legal ',a,' ',num count
        for_entry. rejected do.
            'q reason' =. >entry
            emit (name q),' ',reason
        end.
    case. 'EYES' do.
        eyes =. 0$a:
        for_q. i.#Board do.
            if. '.'~:q{Board do. continue. end.
            adjacent =. neighbors q
            if. *./a=adjacent{Board do.
                enemies =. +/(other a)=((diagonals q){Board)
                state =. 'false'
                if. (enemies<:1)*.(4=#adjacent) do. state =. 'real' end.
                if. (enemies=0)*.(4>#adjacent) do. state =. 'real' end.
                eyes =. eyes,<q;state
            end.
        end.
        emit 'eyes ',a,' ',num #eyes
        for_entry. eyes do.
            'q state' =. >entry
            emit (name q),' ',state
        end.
    case. 'SAFE' do.
        alive =. safe Board;a
        emit 'safe ',a,' ',num #alive
        for_entry. alive do.
            'color rep stones liberties' =. >entry
            emit (name rep),' size ',num #stones
        end.
    case. 'REGIONS' do.
        all =. regions cleanBoard''
        emit 'regions ',num #all
        for_entry. all do.
            'rep points owner' =. >entry
            emit (name rep),' size ',(num #points),' ',owner
        end.
    case. 'SCORE' do. reportScore a
    end.
)
main =: 3 : 0
    Superko =: 0
    reset 19;13
    lines =. <;._2 (1!:1 <'/dev/stdin'),LF
    count =. 0".0{::lines
    for_i. i.count do. execute (i+1){::lines end.
)
main''
