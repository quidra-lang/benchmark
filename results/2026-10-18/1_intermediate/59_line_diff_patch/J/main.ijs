DataCommands =: ;:'FILE PATCH EDIT'
FormatsWithArgument =: ;:'IFDEF UNIFIED CONTEXT SIDE'
Offsets =: 0 1 _1 2 _2 3 _3
GraphWidth =: 20
Digits =: '0123456789'
Separator =: '======='
NB. marker kinds: 1 start, 2 base, 3 end, 4 separator
MarkerPrefixes =: '<<<<<<<';'|||||||';'>>>>>>>'
KindNames =: ;:'stable a b both conflict'
Names =: 0$a:
Exists =: 0$0
Contents =: 0$a:
History =: 0$a:
Output =: 0$a:

num =: 3 : 0
    text =. ": y
    '-' (I. text = '_')} text
)
emit =: 3 : 'Output =: Output , < y'
emitAll =: 3 : 'Output =: Output , y'
fail =: 3 : 0
    emit y
    throw.
)
patchError =: 4 : 'fail ''PATCH ERROR line '' , (num x) , '': '' , y'
editError =: 4 : 'fail ''EDIT ERROR line '' , (num x) , '': '' , y'
join =: 4 : '(# x) }. ; (< x) ,&.> y'
prefix =: 4 : '(< x) ,&.> y'
section =: 4 : 0
    'from to' =. y
    (to - from) {. from }. x
)

rangeR =: 4 : 0
    if. y >: 2 do. (num x + 1) , ',' , num x + y
    elseif. y = 1 do. num x + 1
    else. num x end.
)
rangeU =: 4 : 0
    if. y >: 2 do. (num x + 1) , ',' , num y
    elseif. y = 1 do. num x + 1
    else. (num x) , ',0' end.
)
rangeM =: 4 : '(num x + 1) , '','' , num y'

comparisonKey =: 4 : 0
    if. (< 'ICASE') e. x do. y =. tolower y end.
    if. (< 'IWHITE') e. x do. y =. y -. ' ' end.
    if. (< 'ISPACE') e. x do. y =. y #~ -. '  ' E. y end.
    y
)

matchedPairs =: 4 : 0
    combined =. x , y
    first =. combined i. x
    second =. combined i. y
    row =. (1 + # y) $ 0
    lengths =. ,: row
    for_equal. first =/ second do.
        row =. 0 , >./\ (}. row) >. equal * 1 + }: row
        lengths =. lengths , row
    end.
    i =. # x
    j =. # y
    pairs =. ,: (i + 1) , j + 1
    while. (i >: 1) *. j >: 1 do.
        if. ((i - 1) { first) = (j - 1) { second do.
            pairs =. pairs , i , j
            i =. i - 1
            j =. j - 1
        elseif. ((< (i - 1) , j) { lengths) >: (< i , j - 1) { lengths do.
            i =. i - 1
        else.
            j =. j - 1
        end.
    end.
    |. pairs , 0 0
)

changeBlocks =: 4 : 0
    pairs =. x matchedPairs y
    starts =. }: pairs
    sizes =. (}. pairs) - 1 + starts
    (+./"1 sizes > 0) # starts ,. sizes
)

walk =: 4 : 0
    'i j stop' =. y
    steps =. 0 3 $ 0
    for_block. x do.
        'p q del ins' =. block
        common =. p - i
        steps =. steps , ((i. common) +/ i , j) ,. _1
        steps =. steps , p , (j + common) , block_index
        i =. p + del
        j =. q + ins
    end.
    steps , ((i. stop - i) +/ i , j) ,. _1
)

lineDiff =: 4 : 0
    'Old New' =: y
    Blocks =: ((< x) comparisonKey&.> Old) changeBlocks (< x) comparisonKey&.> New
)
deleted =: 3 : 0
    'p q del ins' =. y
    (p + i. del) { Old
)
inserted =: 3 : 0
    'p q del ins' =. y
    (q + i. ins) { New
)
blockLetter =: 3 : 0
    'p q del ins' =. y
    if. (del >: 1) *. ins >: 1 do. 'c'
    elseif. ins = 0 do. 'd'
    else. 'a' end.
)

hunkRange =: 4 : 0
    'p q' =. 2 {. {. y
    'lastP lastQ lastDel lastIns' =. {: y
    before =. x <. p
    after =. x <. (# Old) - lastP + lastDel
    oldStart =. p - before
    newStart =. q - before
    oldEnd =. lastP + lastDel + after
    newEnd =. lastQ + lastIns + after
    oldStart , (oldEnd - oldStart) , newStart , newEnd - newStart
)
hunks =: 3 : 0
    'p q del ins' =. |: Blocks
    starts =. 1 , (2 * y) < (}. p) - }: p + del
    groups =. starts <;.1 Blocks
    (y&hunkRange&.> groups) ,. groups
)

normal =: 3 : 0
    lines =. 0 $ a:
    for_block. Blocks do.
        'p q del ins' =. block
        letter =. blockLetter block
        lines =. lines , < (p rangeR del) , letter , q rangeR ins
        lines =. lines , '< ' prefix deleted block
        if. letter = 'c' do. lines =. lines , < '---' end.
        lines =. lines , '> ' prefix inserted block
    end.
    lines
)

ed =: 3 : 0
    lines =. 0 $ a:
    for_block. |. Blocks do.
        'p q del ins' =. block
        letter =. blockLetter block
        lines =. lines , < (p rangeR del) , letter
        if. letter ~: 'd' do. lines =. lines , (inserted block) , < , '.' end.
    end.
    lines
)

rcs =: 3 : 0
    lines =. 0 $ a:
    for_block. Blocks do.
        'p q del ins' =. block
        if. del >: 1 do. lines =. lines , < 'd' , (num p + 1) , ' ' , num del end.
        if. ins >: 1 do.
            lines =. lines , (< 'a' , (num p + del) , ' ' , num ins) , inserted block
        end.
    end.
    lines
)

ifdef =: 3 : 0
    lines =. 0 $ a:
    for_step. Blocks walk 0 0 , # Old do.
        'i j b' =. step
        if. b < 0 do.
            lines =. lines , i { Old
            continue.
        end.
        block =. b { Blocks
        'del ins' =. 2 }. block
        if. (del >: 1) *. ins >: 1 do.
            lines =. lines , (< '#ifndef ' , y) , (deleted block) , < '#else /* ' , y , ' */'
            lines =. lines , (inserted block) , < '#endif /* ' , y , ' */'
        elseif. ins = 0 do.
            lines =. lines , (< '#ifndef ' , y) , (deleted block) , < '#endif /* ! ' , y , ' */'
        else.
            lines =. lines , (< '#ifdef ' , y) , (inserted block) , < '#endif /* ' , y , ' */'
        end.
    end.
    lines
)

unified =: 3 : 0
    'size oldName newName' =. y
    lines =. ('--- ' , oldName) ; '+++ ' , newName
    for_hunk. hunks size do.
        'range group' =. hunk
        'oldStart oldCount newStart newCount' =. range
        header =. '@@ -' , (oldStart rangeU oldCount) , ' +' , newStart rangeU newCount
        lines =. lines , < header , ' @@'
        for_step. group walk oldStart , newStart , oldStart + oldCount do.
            'i j b' =. step
            if. b < 0 do.
                lines =. lines , < ' ' , i {:: Old
            else.
                block =. b { group
                lines =. lines , ('-' prefix deleted block) , '+' prefix inserted block
            end.
        end.
    end.
    lines
)

context =: 3 : 0
    'size oldName newName' =. y
    lines =. ('*** ' , oldName) ; '--- ' , newName
    for_hunk. hunks size do.
        'range group' =. hunk
        'oldStart oldCount newStart newCount' =. range
        steps =. group walk oldStart , newStart , oldStart + oldCount
        lines =. lines , (< 15 # '*') , < '*** ' , (oldStart rangeR oldCount) , ' ****'
        if. +./ 0 < 2 {"1 group do.
            for_step. steps do.
                'i j b' =. step
                if. b < 0 do.
                    lines =. lines , < '  ' , i {:: Old
                else.
                    block =. b { group
                    marker =. (0 < 3 { block) {:: '- ' ; '! '
                    lines =. lines , marker prefix deleted block
                end.
            end.
        end.
        lines =. lines , < '--- ' , (newStart rangeR newCount) , ' ----'
        if. +./ 0 < 3 {"1 group do.
            for_step. steps do.
                'i j b' =. step
                if. b < 0 do.
                    lines =. lines , < '  ' , j {:: New
                else.
                    block =. b { group
                    marker =. (0 < 2 { block) {:: '+ ' ; '! '
                    lines =. lines , marker prefix inserted block
                end.
            end.
        end.
    end.
    lines
)

sideRow =: 4 : 0
    'left symbol right' =. y
    dtb (x {. left) , ' ' , symbol , ' ' , (x <. # right) {. right
)
sideBySide =: 3 : 0
    lines =. 0 $ a:
    for_step. Blocks walk 0 0 , # Old do.
        'i j b' =. step
        if. b < 0 do.
            lines =. lines , < y sideRow (i {:: Old) ; ' ' ; j {:: New
            continue.
        end.
        'p q del ins' =. b { Blocks
        for_row. i. del >. ins do.
            if. (row < del) *. row < ins do.
                cells =. ((p + row) {:: Old) ; '|' ; (q + row) {:: New
            elseif. row < del do.
                cells =. ((p + row) {:: Old) ; '<' ; ''
            else.
                cells =. '' ; '>' ; (q + row) {:: New
            end.
            lines =. lines , < y sideRow cells
        end.
    end.
    lines
)

statGraph =: 4 : 0
    total =. x + y
    plus =. x
    minus =. y
    if. total > GraphWidth do.
        plus =. (x >: 1) >. <. GraphWidth * x % total
        minus =. (y >: 1) >. <. GraphWidth * y % total
    end.
    (plus # '+') , minus # '-'
)

tokens =: 4 : 0
    if. x do. cut y else. <"0 y end.
)
deletion =: 4 : '''[-'' , (x join y) , ''-]'''
insertion =: 4 : '''{+'' , (x join y) , ''+}'''
compareTokens =: 4 : 0
    'old new' =. y
    blocks =. old changeBlocks new
    parts =. 0 $ a:
    for_step. blocks walk 0 0 , # old do.
        'i j b' =. step
        if. b < 0 do.
            parts =. parts , i { old
            Totals =: Totals + 0 0 1
        else.
            'p q del ins' =. b { blocks
            if. del >: 1 do. parts =. parts , < x deletion (p + i. del) { old end.
            if. ins >: 1 do. parts =. parts , < x insertion (q + i. ins) { new end.
            Totals =: Totals + del , ins , 0
        end.
    end.
    x join parts
)

isNumber =: 3 : '((# y) e. 1 2 3 4) *. *./ y e. Digits'
numberPair =: 3 : 0
    parts =. <;._1 ',' , y
    if. ((# parts) e. 1 2) *. *./ isNumber&> parts do. ".&> parts else. i. 0 end.
)
parseRange =: 4 : 0
    if. x ~: {. y do. i. 0 return. end.
    numbers =. numberPair }. y
    if. 0 = # numbers do. i. 0 return. end.
    numbers =. 2 {. numbers , 1
    if. (0 = {. numbers) *. 0 ~: {: numbers do. i. 0 return. end.
    numbers
)
hunkHeader =: 4 : 0
    parts =. <;._1 ' ' , x
    if. 4 ~: # parts do. y patchError 'bad hunk header' end.
    if. -. (0 3 { parts) -: 2 # < '@@' do. y patchError 'bad hunk header' end.
    oldRange =. '-' parseRange 1 {:: parts
    newRange =. '+' parseRange 2 {:: parts
    if. (0 = # oldRange) +. 0 = # newRange do. y patchError 'bad hunk header' end.
    y , oldRange , newRange
)
parsePatch =: 3 : 0
    index =. (2 {.&.> y) i. < '@@'
    if. index = # y do. fail 'PATCH ERROR no hunks' end.
    hunks =. 0 3 $ a:
    while. index < # y do.
        lineNumber =. index + 1
        header =. (index {:: y) hunkHeader lineNumber
        'oldCount newCount' =. 2 4 { header
        index =. index + 1
        kinds =. ''
        texts =. 0 $ a:
        oldSeen =. newSeen =. 0
        while. (oldSeen < oldCount) +. newSeen < newCount do.
            if. index = # y do. lineNumber patchError 'truncated hunk' end.
            line =. index {:: y
            kind =. {. line
            inOld =. kind e. ' -'
            inNew =. kind e. ' +'
            invalid =. (2 > # line) +. -. inOld +. inNew
            invalid =. invalid +. (inOld *. oldSeen = oldCount) +. inNew *. newSeen = newCount
            if. invalid do. (index + 1) patchError 'bad hunk line' end.
            kinds =. kinds , kind
            texts =. texts , < }. line
            oldSeen =. oldSeen + inOld
            newSeen =. newSeen + inNew
            index =. index + 1
        end.
        if. *./ kinds = ' ' do. lineNumber patchError 'no changes' end.
        hunks =. hunks , header ; kinds ; < texts
    end.
    hunks
)

sequences =: 4 : 0
    'kinds texts' =. }. y
    oldSide =. (kinds e. x { ' -' ,: ' +') # texts
    newSide =. (kinds e. x { ' +' ,: ' -') # texts
    oldSide ; < newSide
)
hunkStart =: 4 : '(x { 1 3) { 0 {:: y'
searchHunk =: 4 : 0
    'adjustment reverse maxFuzz' =. x
    'hunk lines' =. y
    'old new' =. reverse sequences hunk
    expected =. (reverse hunkStart hunk) + adjustment - 0 < # old
    isContext =. ' ' = 1 {:: hunk
    leading =. +/ *./\ isContext
    trailing =. +/ *./\. isContext
    for_fuzz. i. maxFuzz + 1 do.
        head =. fuzz <. leading
        tail =. fuzz <. trailing
        oldPart =. (- tail) }. head }. old
        newPart =. (- tail) }. head }. new
        for_delta. Offsets do.
            position =. expected + head + delta
            stop =. position + # oldPart
            if. (position >: 0) *. stop <: # lines do.
                if. oldPart -: (position + i. # oldPart) { lines do.
                    fuzz ; delta ; position ; < (position {. lines) , newPart , stop }. lines
                    return.
                end.
            end.
        end.
    end.
    0 $ a:
)
report =: 4 : 0
    'fuzz delta position' =. 3 {. y
    text =. 'Hunk #' , (num x) , ' succeeded at ' , num position + 1
    if. fuzz >: 1 do. text =. text , ' with fuzz ' , num fuzz end.
    if. 1 = | delta do. text =. text , ' (offset ' , (num delta) , ' line)'
    elseif. delta ~: 0 do. text =. text , ' (offset ' , (num delta) , ' lines)' end.
    text
)

parseEditCommand =: 3 : 0
    instruction =. {: y
    numbers =. numberPair }: y
    if. (-. instruction e. 'acd') +. (0 = # numbers) +. (instruction = 'a') *. 2 = # numbers do.
        '' return.
    end.
    instruction ; 2 {. numbers , numbers
)
runEditScript =: 4 : 0
    lines =. y
    executed =. index =. 0
    while. index < # x do.
        lineNumber =. index + 1
        command =. parseEditCommand index {:: x
        if. 0 = # command do. lineNumber editError 'bad command' end.
        'instruction range' =. command
        'first last' =. range
        if. instruction = 'a' do. valid =. first <: # lines
        else. valid =. (1 <: first) *. (first <: last) *. last <: # lines end.
        if. -. valid do. lineNumber editError 'bad range' end.
        index =. index + 1
        text =. 0 $ a:
        if. instruction ~: 'd' do.
            stop =. index + (index }. x) i. < , '.'
            if. stop = # x do. lineNumber editError 'missing terminator' end.
            text =. x section index , stop
            index =. stop + 1
        end.
        select. instruction
        case. 'a' do. lines =. (first {. lines) , text , first }. lines
        case. 'c' do. lines =. ((first - 1) {. lines) , text , last }. lines
        case. 'd' do. lines =. ((first - 1) {. lines) , last }. lines
        end.
        executed =. executed + 1
    end.
    executed ; < lines
)

matchTable =: 4 : 0
    pairs =. }. }: x matchedPairs y
    (1 {"1 pairs) (0 {"1 pairs)} (2 + # x) $ 0
)
chunkKind =: 3 : 0
    'base ours theirs' =. y
    if. ours -: base do. 2
    elseif. theirs -: base do. 1
    elseif. ours -: theirs do. 3
    else. 4 end.
)
threeWayChunks =: 3 : 0
    'base ours theirs' =. y
    oursMatch =. base matchTable ours
    theirsMatch =. base matchTable theirs
    anchors =. (0 < oursMatch) *. 0 < theirsMatch
    chunks =. 0 5 $ a:
    i =. j =. k =. 0
    while. (i < # base) +. (j < # ours) +. k < # theirs do.
        if. (i < # base) *. (((i + 1) { oursMatch) = j + 1) *. ((i + 1) { theirsMatch) = k + 1 do.
            stable =. ((, i) { base) ; ((, j) { ours) ; < (, k) { theirs
            chunks =. chunks , 0 ; (i , j , k) ; stable
            i =. i + 1
            j =. j + 1
            k =. k + 1
        else.
            anchor =. i + 1 + ((i + 1) }. anchors) i. 1
            if. anchor <: # base do.
                next =. _1 + anchor , (anchor { oursMatch) , anchor { theirsMatch
            else.
                next =. (# base) , (# ours) , # theirs
            end.
            'nextI nextJ nextK' =. next
            parts =. (base section i , nextI) ; (ours section j , nextJ) ; < theirs section k , nextK
            chunks =. chunks , (chunkKind parts) ; (i , j , k) ; parts
            'i j k' =. next
        end.
    end.
    chunks
)
kindCounts =: 3 : 0
    'a b both conflicts' =. +/ (> 0 {"1 y) =/ 1 2 3 4
    'a=' , (num a) , ' b=' , (num b) , ' both=' , (num both) , ' conflicts=' , num conflicts
)
location =: 3 : 0
    'starts base ours theirs' =. }. y
    'i j k' =. starts
    'base ' , (i rangeM # base) , ' a ' , (j rangeM # ours) , ' b ' , k rangeM # theirs
)
conflictLines =: 4 : 0
    'mode baseName oursName theirsName' =. x
    'base ours theirs' =. 2 }. y
    select. mode
    case. 'OURS' do. ours
    case. 'THEIRS' do. theirs
    case. 'DIFF3' do.
        opening =. (< '<<<<<<< ' , oursName) , ours , (< '||||||| ' , baseName) , base
        opening , (< Separator) , theirs , < '>>>>>>> ' , theirsName
    case. do.
        size =. (# ours) <. # theirs
        head =. +/ *./\ (size {. ours) = size {. theirs
        limit =. size - head
        tail =. +/ *./\ (limit {. |. ours) = limit {. |. theirs
        oursMiddle =. (- tail) }. head }. ours
        theirsMiddle =. (- tail) }. head }. theirs
        if. mode -: 'UNION' do.
            middle =. oursMiddle , theirsMiddle
        else.
            opening =. (< '<<<<<<< ' , oursName) , oursMiddle , < Separator
            middle =. opening , theirsMiddle , < '>>>>>>> ' , theirsName
        end.
        (head {. ours) , middle , (- tail) {. ours
    end.
)

markerKind =: 3 : 0
    if. y -: Separator do. 4 return. end.
    index =. MarkerPrefixes i. < 7 {. y
    if. (index < 3) *. ' ' = 7 { 8 {. y do. index + 1 else. 0 end.
)
nextMarker =: 4 : 'y + 1 + (0 < (y + 1) }. x) i. 1'
regionAt =: 4 : 0
    if. 1 ~: y { x do. i. 0 return. end.
    middle =. x nextMarker y
    baseMarker =. _1
    if. 2 = middle { x , 0 do.
        baseMarker =. middle
        middle =. x nextMarker middle
    end.
    if. 4 ~: middle { x , 0 do. i. 0 return. end.
    stop =. x nextMarker middle
    if. 3 ~: stop { x , 0 do. i. 0 return. end.
    y , baseMarker , middle , stop
)
conflictRegions =: 3 : 0
    kinds =. markerKind&> y
    regions =. 0 4 $ 0
    index =. 0
    while. index < # y do.
        region =. kinds regionAt index
        if. 0 = # region do.
            index =. index + 1
        else.
            regions =. regions , region
            index =. 1 + {: region
        end.
    end.
    regions
)

save =: 4 : 0
    if. -. (< x) e. Names do.
        Names =: Names , < x
        Exists =: Exists , 0
        Contents =: Contents , < 0 $ a:
        History =: History , < 0 $ a:
    end.
    i =. Names i. < x
    state =. (i { Exists) ; < i {:: Contents
    History =: (< (i {:: History) , < state) i} History
    Exists =: 1 i} Exists
    Contents =: (< y) i} Contents
)
exists =: 3 : '(Names i. < y) { Exists , 0'
contents =: 3 : 0
    for_name. y do.
        if. -. exists > name do. fail 'ERROR no such file ' , > name end.
    end.
    (Names i. y) { Contents
)
contentOf =: 3 : '0 {:: contents , < y'

loadFile =: 4 : 0
    name =. 0 {:: y
    name save x
    emit 'FILE ' , name , ' lines=' , num # x
)
copy =: 3 : 0
    'source target' =. y
    lines =. contentOf source
    target save lines
    emit 'COPY ' , source , ' ' , target , ' lines=' , num # lines
)
printFile =: 3 : 0
    name =. 0 {:: y
    lines =. contentOf name
    emit 'PRINT ' , name , ' lines=' , num # lines
    for_line. lines do.
        emit (_3 {. num line_index + 1) , '| ' , > line
    end.
)
listFiles =: 3 : 0
    present =. I. Exists
    emit 'FILES count=' , num # present
    for_i. present /: > present { Names do.
        emit (i {:: Names) , ' lines=' , (num # i {:: Contents) , ' undo=' , num # i {:: History
    end.
)
undo =: 3 : 0
    name =. 0 {:: y
    i =. Names i. < name
    states =. i {:: History , a:
    if. 0 = # states do. fail 'ERROR nothing to undo ' , name end.
    'present lines' =. > {: states
    History =: (< }: states) i} History
    Exists =: present i} Exists
    Contents =: (< lines) i} Contents
    if. present do. emit 'UNDO ' , name , ' lines=' , num # lines
    else. emit 'UNDO ' , name , ' removed' end.
)

diff =: 3 : 0
    'oldName newName form' =. 3 {. y
    'old new' =. contents 2 {. y
    hasParameter =. (< form) e. FormatsWithArgument
    ((3 + hasParameter) }. y) lineDiff old ; < new
    if. 0 = # Blocks do.
        emit 'Files ' , oldName , ' and ' , newName , ' are identical'
        return.
    end.
    if. hasParameter do. parameter =. 3 {:: y end.
    select. form
    case. 'BRIEF' do. emit 'Files ' , oldName , ' and ' , newName , ' differ'
    case. 'NORMAL' do. emitAll normal ''
    case. 'ED' do. emitAll ed ''
    case. 'RCS' do. emitAll rcs ''
    case. 'IFDEF' do. emitAll ifdef parameter
    case. 'UNIFIED' do. emitAll unified (". parameter) ; oldName ; newName
    case. 'CONTEXT' do. emitAll context (". parameter) ; oldName ; newName
    case. 'SIDE' do. emitAll sideBySide ". parameter
    end.
)

tokenDiff =: 4 : 0
    'oldName newName' =. y
    'old new' =. contents y
    blocks =. old changeBlocks new
    if. 0 = # blocks do.
        emit 'Files ' , oldName , ' and ' , newName , ' are identical'
        return.
    end.
    separator =. x # ' '
    Totals =: 0 0 0
    for_block. blocks do.
        'p q del ins' =. block
        for_row. i. del >. ins do.
            oldNumber =. p + row + 1
            newNumber =. q + row + 1
            if. (row < del) *. row < ins do.
                oldTokens =. x tokens (oldNumber - 1) {:: old
                newTokens =. x tokens (newNumber - 1) {:: new
                text =. separator compareTokens oldTokens ; < newTokens
                emit 'a' , (num oldNumber) , ' b' , (num newNumber) , ': ' , text
            elseif. row < del do.
                oldTokens =. x tokens (oldNumber - 1) {:: old
                Totals =: Totals + (# oldTokens) , 0 0
                emit 'a' , (num oldNumber) , ': ' , separator deletion oldTokens
            else.
                newTokens =. x tokens (newNumber - 1) {:: new
                Totals =: Totals + 0 , (# newTokens) , 0
                emit 'b' , (num newNumber) , ': ' , separator insertion newTokens
            end.
        end.
    end.
    'deletedCount insertedCount commonCount' =. Totals
    counts =. ' deleted=' , (num deletedCount) , ' inserted=' , num insertedCount
    emit (x {:: 'CHARS' ; 'WORDS') , counts , ' common=' , num commonCount
)

stat =: 3 : 0
    'oldName newName' =. 2 {. y
    'old new' =. contents 2 {. y
    (2 }. y) lineDiff old ; < new
    deletedCount =. +/ 2 {"1 Blocks
    insertedCount =. +/ 3 {"1 Blocks
    total =. deletedCount + insertedCount
    unchanged =. (# old) - deletedCount
    summary =. oldName , ' -> ' , newName , ' | ' , num total
    if. total > 0 do.
        summary =. summary , ' ' , insertedCount statGraph deletedCount
    end.
    emit summary
    lineTotal =. (# old) + # new
    similarity =. 100
    if. lineTotal > 0 do. similarity =. <. (200 * unchanged) % lineTotal end.
    counts =. 'changes=' , (num # Blocks) , ' insertions=' , (num insertedCount)
    counts =. counts , ' deletions=' , (num deletedCount) , ' unchanged=' , num unchanged
    emit counts , ' similarity=' , (num similarity) , '%'
)

patch =: 4 : 0
    name =. 0 {:: y
    lines =. contentOf name
    options =. 2 }. y
    reverse =. (< 'REVERSE') e. options
    dryRun =. (< 'DRYRUN') e. options
    maxFuzz =. 0
    fuzzAt =. options i. < 'FUZZ'
    if. fuzzAt < # options do. maxFuzz =. ". (fuzzAt + 1) {:: options end.
    hunks =. parsePatch x
    emit (dryRun {:: 'patching file ' ; 'checking file ') , name
    first =. {. hunks
    forward =. (0 , reverse , maxFuzz) searchHunk first ; < lines
    backward =. (0 , (-. reverse) , maxFuzz) searchHunk first ; < lines
    if. (0 = # forward) *. 0 < # backward do.
        emit 'Reversed (or previously applied) patch detected! Skipping patch.'
        emit 'RESULT applied=0 failed=0 ignored=' , (num # hunks) , ' lines=' , num # lines
        return.
    end.
    adjustment =. applied =. failed =. 0
    for_hunk. hunks do.
        number =. hunk_index + 1
        match =. (adjustment , reverse , maxFuzz) searchHunk hunk ; < lines
        if. 0 = # match do.
            failed =. failed + 1
            emit 'Hunk #' , (num number) , ' FAILED at ' , num reverse hunkStart hunk
        else.
            'old new' =. reverse sequences hunk
            lines =. 3 {:: match
            adjustment =. adjustment + (1 {:: match) + (# new) - # old
            applied =. applied + 1
            emit number report match
        end.
    end.
    summary =. 'RESULT applied=' , (num applied) , ' failed=' , num failed
    emit summary , ' ignored=0 lines=' , num # lines
    if. (-. dryRun) *. applied >: 1 do. name save lines end.
)

edit =: 4 : 0
    name =. 0 {:: y
    'executed lines' =. x runEditScript contentOf name
    emit 'EDIT ' , name , ' commands=' , (num executed) , ' lines=' , num # lines
    name save lines
)

diff3 =: 3 : 0
    chunks =. threeWayChunks contents y
    changes =. chunks #~ 0 < > 0 {"1 chunks
    for_chunk. changes do.
        kind =. 0 {:: chunk
        'base ours theirs' =. 2 }. chunk
        emit '==== ' , (kind {:: KindNames) , ' ' , location chunk
        emitAll 'O ' prefix base
        if. kind ~: 2 do. emitAll 'A ' prefix ours end.
        if. kind e. 2 4 do. emitAll 'B ' prefix theirs end.
    end.
    emit 'DIFF3 chunks=' , (num # changes) , ' ' , kindCounts chunks
)

merge =: 3 : 0
    target =. 3 {:: y
    mode =. 'MARKERS'
    if. 5 = # y do. mode =. 4 {:: y end.
    chunks =. threeWayChunks contents 3 {. y
    result =. 0 $ a:
    conflicting =. 0 5 $ a:
    for_chunk. chunks do.
        kind =. 0 {:: chunk
        'base ours theirs' =. 2 }. chunk
        if. kind = 2 do.
            result =. result , theirs
        elseif. kind = 4 do.
            result =. result , (mode ; 3 {. y) conflictLines chunk
            conflicting =. conflicting , chunk
        else.
            result =. result , ours
        end.
    end.
    emit 'MERGE ' , target , ' lines=' , (num # result) , ' ' , kindCounts chunks
    for_chunk. conflicting do.
        emit 'CONFLICT ' , (num chunk_index + 1) , ' ' , location chunk
    end.
    target save result
)

conflicts =: 3 : 0
    name =. 0 {:: y
    regions =. conflictRegions contentOf name
    emit 'CONFLICTS ' , name , ' count=' , num # regions
    for_region. regions do.
        'g b h r' =. region
        base =. 'none'
        if. b >: 0 do. base =. num h - b + 1 end.
        ours =. ((b < 0) { b , h) - g + 1
        lineRange =. (num region_index + 1) , ': lines ' , (num g + 1) , '-' , num r + 1
        emit lineRange , ' ours=' , (num ours) , ' base=' , base , ' theirs=' , num r - h + 1
    end.
)

resolve =: 3 : 0
    'name numberText side' =. y
    lines =. contentOf name
    number =. ". numberText
    regions =. conflictRegions lines
    if. number > # regions do. fail 'ERROR no conflict ' , (num number) , ' in ' , name end.
    'g b h r' =. (number - 1) { regions
    if. (side -: 'BASE') *. b < 0 do. fail 'ERROR no base section in conflict ' , num number end.
    ours =. lines section (g + 1) , (b < 0) { b , h
    theirs =. lines section (h + 1) , r
    select. side
    case. 'OURS' do. part =. ours
    case. 'THEIRS' do. part =. theirs
    case. 'BASE' do. part =. lines section (b + 1) , h
    case. 'BOTH' do. part =. ours , theirs
    end.
    content =. (g {. lines) , part , (r + 1) }. lines
    remaining =. # conflictRegions content
    summary =. 'RESOLVE ' , name , ' ' , (num number) , ' ' , side
    emit summary , ' lines=' , (num # content) , ' remaining=' , num remaining
    name save content
)

execute =: 4 : 0
    arguments =. }. y
    select. 0 {:: y
    case. 'FILE' do. x loadFile arguments
    case. 'COPY' do. copy arguments
    case. 'PRINT' do. printFile arguments
    case. 'FILES' do. listFiles ''
    case. 'DIFF' do. diff arguments
    case. 'WORDDIFF' do. 1 tokenDiff arguments
    case. 'CHARDIFF' do. 0 tokenDiff arguments
    case. 'STAT' do. stat arguments
    case. 'PATCH' do. x patch arguments
    case. 'EDIT' do. x edit arguments
    case. 'DIFF3' do. diff3 arguments
    case. 'MERGE' do. merge arguments
    case. 'CONFLICTS' do. conflicts arguments
    case. 'RESOLVE' do. resolve arguments
    case. 'UNDO' do. undo arguments
    end.
)

main =: 3 : 0
    lines =. <;._2 ((1!:1 < '/dev/stdin') -. CR) , LF
    position =. 1
    for. i. ". 0 {:: lines do.
        words =. <;._1 ' ' , position {:: lines
        position =. position + 1
        data =. 0 $ a:
        if. ({. words) e. DataCommands do.
            count =. ". 2 {:: words
            data =. count {. position }. lines
            position =. position + count
        end.
        try. data execute words catcht. end.
    end.
    1!:2&2 (LF join Output) , LF
)
main ''
