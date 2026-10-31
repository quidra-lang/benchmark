LF =: 10{a.
Faces =: 'URFDLB'
Colors =: 'WRGYOB'
Letters =: 'URFDLBMESudfblrxyz'
Solved =: 9#Colors
Output =: 0$a:
num =: 3 : ',''0'' 8!:2 y'
emit =: 3 : 'Output=:Output,<y'
join =: 4 : '(#x)}.;(<x),&.>y'
split =: 4 : 0
    parts=.0$a:
    start=.0
    for_i. i.#y do.
        if. x=i{y do.
            parts=.parts,<(i-start){.start}.y
            start=.i+1
        end.
    end.
    parts,<start}.y
)
fail =: 3 : 0
    Reason=:y
    throw.
)
numberWord =: 3 : 0
    if. (0=#y)+.10<#y do. 0 return. end.
    (*./y e.'0123456789') *. (1=#y)+.'0'~:{.y
)
nameWord =: 3 : '(0<#y)*.(8>:#y)*.*./y e.''abcdefghijklmnopqrstuvwxyz'''
moveText =: 3 : 0
    suffix=.''
    if. 1=3|y do. suffix=.'2' elseif. 2=3|y do. suffix=.'''' end.
    ((<.y%3){Letters),suffix
)
movesText =: 3 : ''' ''join moveText&.>y'
sequenceText =: 3 : 0
    out=.num #y
    if. #y do. out=.out,' ',movesText y end.
    out
)
inverse =: 3 : 0
    rev=.|.y
    (3*<.rev%3)+(2-3|rev)
)
plainMoves =: 3 : 0
    out=.i.0
    for_word. (' 'split y)-.<'' do.
        word=.>word
        amount=.0
        if. 1<#word do. amount=.1+''''=1{word end.
        out=.out,(3*Letters i.{.word)+amount
    end.
    out
)
axisLetter =: 3 : 0
    if. y e.'RLMrlx' do. 0 elseif. y e.'UDEudy' do. 1 else. 2 end.
)
axis =: 3 : 'Axes{~<.y%3'
quarter =: 4 : 0
    a=.3|x+1
    b=.3|x+2
    out=.y
    out=.(b{y)a}out
    (-a{y)b}out
)
initTables =: 3 : 0
    normals=.6 3$0 1 0 1 0 0 0 0 1 0 _1 0 _1 0 0 0 0 _1
    columns=.6 3$1 0 0 0 0 _1 1 0 0 1 0 0 0 0 1 _1 0 0
    rows=.6 3$0 0 1 0 _1 0 0 _1 0 0 0 _1 0 _1 0 0 _1 0
    places=.0 6$0
    for_f. i.6 do.
        for_r. _1 0 1 do.
            for_c. _1 0 1 do.
                position=.(f{normals)+(c*f{columns)+r*f{rows
                places=.places,position,f{normals
            end.
        end.
    end.
    Tables=:0 54$0
    Axes=:axisLetter"0 Letters
    for_letter. Letters do.
        ax=.axisLetter letter
        turns=.1+2*letter e.'LMDEldb'
        if. letter e.'xyz' do. layers=._1 0 1
        elseif. letter e.'MES' do. layers=.,0
        elseif. letter e.'udfblr' do.
            if. letter e.'ufr' do. layers=.0 1 else. layers=._1 0 end.
        elseif. letter e.'URF' do. layers=.,1
        else. layers=.,_1 end.
        perm=.i.54
        for_start. i.54 do.
            place=.start{places
            if. (ax{place)e.layers do.
                for_i. i.turns do. place=.(ax quarter 3{.place),ax quarter 3}.place end.
                perm=.start (places i.place)}perm
            end.
        end.
        power=.i.54
        for_a. 1 2 3 do.
            power=.perm{power
            Tables=:Tables,power
        end.
    end.
)
applyMoves =: 4 : 0
    for_move. y do. x=.(move{Tables){x end.
    x
)
effect =: 3 : '(i.54)applyMoves y'
findMove =: 3 : 'Tables i.y'
rotationFor =: 3 : '(RotationEffects i.y){::Rotations'
pieceKind =: 3 : 0
    'names layout'=.y
    width=.#' 'split 0{::layout
    stickers=.(0,width)$0
    colors=.0$a:
    for_row. layout do.
        indices=.i.0
        for_label. ' 'split >row do.
            label=.>label
            indices=.indices,(9*Faces i.{.label)+(0".}.label)-1
        end.
        stickers=.stickers,indices
    end.
    for_name. names do. colors=.colors,<Colors{~Faces i.>name end.
    (<names),(<stickers),<colors
)
contents =: 4 : 0
    'names stickers colors'=.x
    result=.0 2$0
    for_row. i.#stickers do.
        actual=.(row{stickers){y
        found=._1 0
        for_p. i.#colors do.
            for_t. i.#actual do.
                if. (t|.actual)-:p{::colors do. found=.p,t end.
            end.
        end.
        result=.result,found
    end.
    result
)
isSolved =: 3 : '*./,y=(9#4+9*i.6){y'
normalizing =: 3 : 0
    for_i. i.#Rotations do.
        moved=.y applyMoves i{::Rotations
        if. Colors-:(4+9*i.6){moved do. i return. end.
    end.
    _1
)
normalized =: 3 : 'y applyMoves (normalizing y){::Rotations'
parity =: 3 : 0
    p=.{."1 y
    2|+/,((i.#p)</i.#p)*.p>/p
)
invalid =: 3 : 0
    if. 54~:#y do. 'length ',num #y return. end.
    bad=.I.-.y e.Colors
    if. #bad do. 'char ',num 1+{.bad return. end.
    for_c. Colors do.
        n=.+/y=c
        if. n~:9 do. 'count ',c,' ',num n return. end.
    end.
    rotation=.normalizing y
    if. rotation<0 do. 'centers' return. end.
    cs=.Corners contents y
    es=.Edges contents y
    bad=.I._1={."1 cs
    if. #bad do. 'corner ',({.bad){::0{::Corners return. end.
    bad=.I._1={."1 es
    if. #bad do. 'edge ',({.bad){::0{::Edges return. end.
    for_kind. (<Corners),<Edges do.
        kind=.>kind
        pieces=.{."1 kind contents y
        names=.0{::kind
        for_i. i.#names do. if. -.i e.pieces do. 'missing ',i{::names return. end. end.
    end.
    normal=.y applyMoves rotation{::Rotations
    cs=.Corners contents normal
    es=.Edges contents normal
    if. 0~:3|+/{:"1 cs do. 'twist' return. end.
    if. 0~:2|+/{:"1 es do. 'flip' return. end.
    if. (parity cs)~:parity es do. 'parity' return. end.
    ''
)
cycles =: 4 : 0
    'names stickers colors'=.x
    pieces=.x contents y
    n=.#pieces
    loc=.n$0
    turns=.n$0
    for_i. i.n do.
        'piece orientation'=.i{pieces
        loc=.i piece}loc
        turns=.orientation piece}turns
    end.
    seen=.n$0
    output=.0$a:
    for_start. i.n do.
        if. start{seen do. continue. end.
        p=.start
        cycle=.i.0
        while. -.p{seen do.
            seen=.1 p}seen
            cycle=.cycle,p
            p=.p{loc
        end.
        remainder=.(#0{stickers)|+/cycle{turns
        mark=.remainder{::'';'+';'-'
        if. (1<#cycle)+.0<#mark do. output=.output,<'(',(' 'join cycle{names),')',mark end.
    end.
    if. #output do. ' 'join output else. 'none' end.
)
simplify =: 3 : 0
    while. 1 do.
        result=.i.0
        at=.0
        while. at<#y do.
            ax=.axis at{y
            letters=.i.0
            totals=.18$0
            while. at<#y do.
                move=.at{y
                if. ax~:axis move do. break. end.
                letter=.<.move%3
                if. -.letter e.letters do. letters=.letters,letter end.
                totals=.(4|(letter{totals)+1+3|move)letter}totals
                at=.at+1
            end.
            for_letter. letters do.
                amount=.letter{totals
                if. amount do. result=.result,(3*letter)+amount-1 end.
            end.
        end.
        if. result-:y do. result return. end.
        y=.result
    end.
)
unrotate =: 3 : 0
    expanded=.i.0
    for_move. y do.
        letter=.(<.move%3){Letters
        at=.'MESrludfb'i.letter
        if. at=9 do. expanded=.expanded,move
        else.
            amount=.1+3|move
            for_part. at{::Replacements do.
                expanded=.expanded,(3*<.part%3)+(4|amount*1+3|part)-1
            end.
        end.
    end.
    held=.i.0
    result=.i.0
    for_move. expanded do.
        if. ((<.move%3){Letters)e.'xyz' do. held=.rotationFor effect held,move
        else. result=.result,findMove effect held,move,inverse held end.
    end.
    result,held
)
permutationOrder =: 3 : 0
    seen=.54$0
    result=.1
    for_start. i.54 do.
        p=.start
        n=.0
        while. -.p{seen do. seen=.1 p}seen
            n=.n+1
            p=.p{y
        end.
        if. n do. result=.result*.n end.
    end.
    result
)
searchDepth =: 3 : 0
    'state depth previous'=.y
    if. depth=0 do.
        if. isSolved state do. 1;<i.0 else. 0;<i.0 end.
        return.
    end.
    for_move. i.18 do.
        face=.<.move%3
        if. face=previous do. continue. end.
        if. (previous e.3 4 5)*.face=previous-3 do. continue. end.
        'found tail'=.searchDepth (<state applyMoves ,move),(<depth-1),<face
        if. found do. 1;<move,tail return. end.
    end.
    0;<i.0
)
current =: 3 : 0
    if. Position<#Line do. Position{Line else. '' end.
)
accept =: 3 : 0
    if. -.y-:current'' do. 0 return. end.
    Position=:Position+1
    1
)
skip =: 3 : 0
    while. ' '-:current'' do. Position=:Position+1 end.
)
syntax =: 3 : 'fail ''syntax at '',num 1+(#Line)<.Position'
power =: 3 : 0
    n=.1
    c=.current''
    if. (0<#c)*.c e.'123456789' do.
        n=.0".c
        Position=:Position+1
        c=.current''
        if. (0<#c)*.c e.'0123456789' do. n=.(10*n)+0".c
            Position=:Position+1
        end.
    end.
    moves=.;n#<y
    if. accept '''' do. inverse moves else. moves end.
)
readSequence =: 3 : 0
    moves=.i.0
    while. 1 do.
        skip''
        c=.current''
        if. (0<#c)*.c e.Letters do.
            Position=:Position+1
            amount=.0
            if. accept '2' do. amount=.1 elseif. accept '''' do. amount=.2 end.
            moves=.moves,(3*Letters i.c)+amount
        elseif. accept '(' do.
            group=.readSequence''
            skip''
            if. -.accept ')' do. syntax'' end.
            moves=.moves,power group
        elseif. accept '[' do.
            first=.readSequence''
            skip''
            separator=.current''
            if. -. (<separator)e.',';':' do. syntax'' end.
            Position=:Position+1
            second=.readSequence''
            skip''
            if. -.accept ']' do. syntax'' end.
            group=.first,second,inverse first
            if. separator-:',' do. group=.group,inverse second end.
            moves=.moves,power group
        elseif. accept '{' do.
            start=.Position
            while. 1 do.
                c=.current''
                if. (0=#c)+.-.c e.'abcdefghijklmnopqrstuvwxyz' do. break. end.
                Position=:Position+1
            end.
            name=.(Position-start){.start}.Line
            if. (0=#name)+.-.'}'-:current'' do. syntax'' end.
            id=.MacroNames i.<name
            if. id=#MacroNames do. fail 'undefined ',name end.
            Position=:Position+1
            moves=.moves,power id{::Macros
        else. moves return. end.
    end.
)
parseSequence =: 3 : 0
    Position=:y
    moves=.readSequence''
    skip''
    if. #current'' do. syntax'' end.
    if. 500<#moves do. fail 'too long' end.
    moves
)
record =: 3 : 0
    State=:State applyMoves y
    History=:History,y
    Redo=:i.0
)
execute =: 3 : 0
    Line=:y
    at=.y i.' '
    command=.at{.y
    argument=.((at+1)<.#y)}.y
    words=.0$a:
    if. at<#y do. words=.' 'split argument end.
    moves=.i.0
    head=.''
    noargs=.;:'RESET SHOW STATE ISSOLVED HISTORY SOLUTION ANALYZE STAGE MACROS'
    wordcommands=.;:'CHECK LOAD UNDO REDO SEARCH WHERE SAVE RESTORE SCRAMBLE'
    sequencecommands=.;:'APPLY INVERT SIMPLIFY METRICS ORDER CYCLES UNROTATE UNTIL'
    if. (<command)e.noargs do.
        if. at<#y do. fail 'bad arguments' end.
    elseif. (<command)e.wordcommands do.
        if. (#words)~:1+command-:'SCRAMBLE' do. fail 'bad arguments' end.
        if. (<command)e.;:'UNDO REDO SEARCH SCRAMBLE' do.
            if. -.*./numberWord&>words do. fail 'bad arguments' end.
        elseif. (<command)e.'SAVE';'RESTORE' do.
            if. -.nameWord 0{::words do. fail 'bad arguments' end.
        end.
    elseif. (<command)e.sequencecommands do. moves=.parseSequence 1+#command
    elseif. (<command)e.'DEFINE';'MIRROR';'ROTATE' do.
        if. at=#y do. fail 'bad arguments' end.
        head=.(argument i.' '){.argument
        valid=.0
        if. command-:'DEFINE' do. valid=.nameWord head
        elseif. command-:'MIRROR' do. valid=.(<head)e.'LR';'UD';'FB'
        else. valid=.(<head)e.'x';'x2';'x''';'y';'y2';'y''';'z';'z2';'z''' end.
        if. -.valid do. fail 'bad arguments' end.
        moves=.parseSequence 2+(#command)+#head
    else. fail 'unknown command ',command end.
    select. command
    case. 'RESET' do. State=:Solved
        History=:Redo=:i.0
        emit 'reset'
    case. 'SHOW' do.
        for_r. i.3 do. emit '      ', ' 'join <"0 ((3*r)+i.3){State end.
        for_r. i.3 do.
            indices=.,(9*4 2 1 5)+/((3*r)+i.3)
            emit ' 'join <"0 indices{State
        end.
        for_r. i.3 do. emit '      ', ' 'join <"0 (27+(3*r)+i.3){State end.
    case. 'STATE' do. emit 'state ',State
    case. 'ISSOLVED' do.
        n=.+/State~:(9#4+9*i.6){State
        if. n do. emit 'unsolved ',num n else. emit 'solved' end.
    case. 'HISTORY' do. emit 'history ',sequenceText History
    case. 'SOLUTION' do. emit 'solution ',sequenceText simplify inverse History
    case. 'MACROS' do.
        emit 'macros ',num #MacroNames
        for_name. /:~MacroNames do. emit 'macro ',(>name),' ',sequenceText (MacroNames i.name){::Macros end.
    case. 'ANALYZE' do.
        rotation=.(normalizing State){::Rotations
        normal=.State applyMoves rotation
        text=.movesText rotation
        if. 0=#text do. text=.'none' end.
        emit 'rotation ',text
        emit 'corners ',Corners cycles normal
        emit 'edges ',Edges cycles normal
    case. 'STAGE';'WHERE' do.
        normal=.normalized State
        cs=.Corners contents normal
        es=.Edges contents normal
        if. command-:'WHERE' do.
            name=.0{::words
            if. (<name)e.0{::Corners do. kind=.Corners
                pieces=.cs
                label=.'twist'
            elseif. (<name)e.0{::Edges do. kind=.Edges
                pieces=.es
                label=.'flip'
            else. fail 'unknown piece ',name end.
            id=.(0{::kind)i.<name
            place=.({."1 pieces)i.id
            emit name,' at ',(place{::0{::kind),' ',label,' ',num 1{place{pieces
            return.
        end.
        cross=.+/*./"1 (4 5 6 7{es)=4 2$4 0 5 0 6 0 7 0
        slots=.+/(*./"1 (4 5 6 7{cs)=4 2$4 0 5 0 6 0 7 0)*.*./"1 (8 9 10 11{es)=4 2$8 0 9 0 10 0 11 0
        top=.+/'W'=9{.normal
        stage=.'none'
        if. isSolved normal do. stage=.'solved'
        elseif. (cross=4)*.(slots=4)*.top=9 do. stage=.'oll'
        elseif. (cross=4)*.slots=4 do. stage=.'f2l'
        elseif. cross=4 do. stage=.'cross' end.
        emit 'stage ',stage,' cross ',(num cross),' slots ',(num slots),' top ',num top
    case. 'CHECK';'LOAD' do.
        text=.0{::words
        reason=.invalid text
        if. command-:'CHECK' do.
            if. #reason do. emit 'invalid ',reason else. emit 'valid' end.
        else.
            if. #reason do. fail 'invalid ',reason end.
            State=:text
            History=:Redo=:i.0
            emit 'loaded'
        end.
    case. 'UNDO';'REDO' do.
        n=.0".0{::words
        if. n<1 do. fail 'bad value' end.
        if. command-:'UNDO' do. source=.History else. source=.Redo end.
        if. 0=#source do. fail 'nothing to ',(command-:'UNDO'){::'redo';'undo' end.
        n=.n<.#source
        for_i. i.n do.
            if. command-:'UNDO' do.
                move=.{:History
                History=:}:History
                State=:State applyMoves inverse ,move
                Redo=:Redo,move
            else.
                move=.{:Redo
                Redo=:}:Redo
                State=:State applyMoves ,move
                History=:History,move
            end.
        end.
        emit ((command-:'UNDO'){::'redone ';'undone '),num n
    case. 'SEARCH' do.
        depth=.0".0{::words
        if. depth>4 do. fail 'bad value' end.
        for_d. i.depth+1 do.
            'found moves'=.searchDepth (<State),(<d),<_1
            if. found do. emit 'found ',sequenceText moves return. end.
        end.
        emit 'not found'
    case. 'SAVE' do.
        name=.0{::words
        id=.SaveNames i.<name
        data=.(<State),<History
        if. id=#SaveNames do. SaveNames=:SaveNames,<name
            Saves=:Saves,<data
        else. Saves=:(<data)id}Saves end.
        emit 'saved ',name
    case. 'RESTORE' do.
        name=.0{::words
        id=.SaveNames i.<name
        if. id=#SaveNames do. fail 'no save ',name end.
        'State History'=:id{::Saves
        Redo=:i.0
        emit 'restored ',name
    case. 'SCRAMBLE' do.
        'n seed'=.0".&>words
        if. (n<1)+.(n>50)+.(seed<1)+.seed>2147483646 do. fail 'bad value' end.
        for_i. i.n do.
            faces=.i.6
            if. #moves do. faces=.faces-.<.({:moves)%3 end.
            if. 1<#moves do.
                if. (axis {:moves)=axis _2{moves do. faces=.faces#~(Axes{~faces)~:axis {:moves end.
            end.
            seed=.2147483647|48271*seed
            face=.(seed|~#faces){faces
            seed=.2147483647|48271*seed
            amount=.(3|seed){0 2 1
            moves=.moves,(3*face)+amount
        end.
        record moves
        emit 'scramble ',movesText moves
    case. 'APPLY' do. record moves
        emit 'applied ',num #moves
    case. 'INVERT' do. emit 'inverse ',sequenceText inverse moves
    case. 'SIMPLIFY' do. emit 'simplified ',sequenceText simplify moves
    case. 'METRICS' do.
        htm=.0
        qtm=.0
        stm=.0
        for_move. moves do.
            letter=.(<.move%3){Letters
            if. letter e.'xyz' do. continue. end.
            weight=.1+letter e.'MES'
            htm=.htm+weight
            qtm=.qtm+weight*1+1=3|move
            stm=.stm+1
        end.
        emit 'metrics htm ',(num htm),' qtm ',(num qtm),' stm ',(num stm),' etm ',num #moves
    case. 'ORDER' do. emit 'order ',num permutationOrder effect moves
    case. 'CYCLES' do.
        moved=.Solved applyMoves moves
        emit 'corners ',Corners cycles moved
        emit 'edges ',Edges cycles moved
        emit 'centers ',Centers cycles moved
    case. 'UNROTATE' do. emit 'unrotated ',sequenceText unrotate moves
    case. 'UNTIL' do.
        table=.effect moves
        state=.State
        for_i. >:i.permutationOrder table do.
            state=.table{state
            if. isSolved state do. emit 'until ',num i return. end.
        end.
        emit 'until never'
    case. 'DEFINE' do.
        id=.MacroNames i.<head
        if. id=#MacroNames do. MacroNames=:MacroNames,<head
            Macros=:Macros,<moves
        else. Macros=:(<moves)id}Macros end.
        emit 'defined ',head,' ',num #moves
    case. 'MIRROR' do.
        ax=.('LR';'UD';'FB')i.<head
        pairs=.'RLUDrludFBfb'
        result=.i.0
        for_move. moves do.
            letter=.(<.move%3){Letters
            amount=.1+3|move
            if. (axis move)~:ax do. amount=.4-amount
            elseif. letter e.pairs do.
                index=.pairs i.letter
                letter=.(index+1-2*2|index){pairs
                amount=.4-amount
            end.
            result=.result,(3*Letters i.letter)+amount-1
        end.
        emit 'mirror ',sequenceText result
    case. 'ROTATE' do.
        rotation=.plainMoves head
        result=.i.0
        for_move. moves do. result=.result,findMove effect rotation,move,inverse rotation end.
        emit 'rotated ',sequenceText result
    end.
)
main =: 3 : 0
    initTables''
    Corners=:pieceKind (<;:'URF UFL ULB UBR DFR DLF DBL DRB'),<('U9 R1 F3';'U7 F1 L3';'U1 L1 B3';'U3 B1 R3';'D3 F9 R7';'D1 L9 F7';'D7 B9 L7';'D9 R9 B7')
    Edges=:pieceKind (<;:'UR UF UL UB DR DF DL DB FR FL BL BR'),<('U6 R2';'U8 F2';'U4 L2';'U2 B2';'D6 R8';'D2 F8';'D4 L8';'D8 B8';'F6 R4';'F4 L6';'B6 L4';'B4 R6')
    Centers=:pieceKind (< <"0 Faces),<('U5';'R5';'F5';'D5';'L5';'B5')
    Rotations=:0$a:
    for_first. ''; 'x';'x2';'x''';'z';'z''' do.
        for_second. ''; 'y';'y2';'y''' do. Rotations=:Rotations,<plainMoves (>first),' ',>second end.
    end.
    RotationEffects=:>effect&.>Rotations
    Replacements=:plainMoves&.>'R L'' x''';'U D'' y''';'F'' B z';'L x';'R x''';'D y';'U y''';'B z';'F z'''
    State=:Solved
    History=:Redo=:i.0
    MacroNames=:Macros=:SaveNames=:Saves=:0$a:
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    for_line. (0".0{::lines){.}.lines do.
        try. execute >line
        catcht. emit 'error: ',Reason end.
    end.
    1!:2&2 ;Output,&.><LF
)
main''
