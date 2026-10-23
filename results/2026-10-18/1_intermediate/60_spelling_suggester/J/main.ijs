Lower =: 'abcdefghijklmnopqrstuvwxyz'
Upper =: toupper Lower
Letters =: Upper , Lower
Digits =: '0123456789'
AdjacentKeys =: ;:'qswz ghnv dfvx cefrsx drsw cdgrtv bfhtvy bgjnuy jkou hikmnu ijlmo kop jkn'
AdjacentKeys =: AdjacentKeys , ;:'bhjm iklp lo aw deft adewxz fgry hijy bcfg aeqs cdsz ghtu asx'
NB. h and w map to 0: that is their value as a first letter, and they are skipped elsewhere
SoundexDigits =: '01230120022455012623010202'
SentenceMarks =: '.!?'
FindingKinds =: ;:'unknown case capital repeats'
CounterNames =: ;:'checked unknown case capital repeats corrected'
OptionNames =: ;:'LIMIT SUGGESTIONS'
OptionMaximums =: 3 10
KeyboardModes =: ;:'OFF ON'
MaxWordLength =: 30
MaxFrequency =: 1000000
MaxListed =: 20
ReportSize =: 10

Words =: 0$a:
Frequencies =: 0$0
Ignored =: 0$a:
RuleSources =: 0$a:
RuleTargets =: 0$a:
Keyboard =: 0
BaseLimit =: 2
SuggestionCount =: 5
UndoHistory =: 0$a:
UnknownLog =: (0$a:) ; 0$0
CorrectionLog =: (0$a:) ; 0$0
Counters =: 6$0
Output =: 0$a:

join =: 4 : '(# x) }. ; (x&,)&.> y'
emit =: 3 : 'Output =: Output , < y'
say =: 3 : 'emit '' '' join ":&.> y'
field =: 4 : 'x , ''='' , ": y'
entry =: 4 : 'x , '':'' , ": y'
atMost =: 4 : '(x <. # y) {. y'
wordRank =: 3 : '/: /: > y'

fail =: 3 : 0
    emit 'ERROR ' , y
    throw.
)

wordArgument =: 3 : 0
    if. (-. *./ y e. Letters) +. -. (# y) e. >: i. MaxWordLength do. fail 'BAD WORD ' , y end.
    tolower y
)

numberArgument =: 4 : 0
    'minimum maximum' =. x
    if. (-. *./ y e. Digits) +. -. (# y) e. >: i. 7 do. fail 'BAD NUMBER ' , y end.
    value =. ". y
    if. (value < minimum) +. value > maximum do. fail 'BAD NUMBER ' , y end.
    value
)

decimal =: 4 : 0
    'numerator denominator' =. y
    scale =. 10 ^ x
    value =. <. (denominator + 2 * numerator * scale) % 2 * denominator
    (": <. value % scale) , '.' , (-x) {. (x # '0') , ": scale | value
)

capitalize =: 3 : '(toupper {. y) , }. y'

applyCase =: 4 : 0
    upper =. x e. Upper
    if. (2 <: # x) *. *./ upper do. toupper y
    elseif. {. upper do. capitalize y
    else. y end.
)

slice =: 4 : 0
    'start stop' =. x
    (stop - start) {. start }. y
)

tokenize =: 3 : 0
    letter =. y e. Letters
    starts =. I. letter > }: 0 , letter
    ends =. >: I. letter > }. letter , 0
    texts =. (starts ,. ends) <@slice"1 _ y
    gaps =. ((}: 0 , ends) ,. starts) <@slice"1 _ y
    words =. tolower&.> texts
    sentences =. (0 = i. # texts) +. +./@(e.&SentenceMarks)&> gaps
    repeats =. (words = }: a: , words) *. *./@(=&' ')&> gaps
    texts ; gaps ; sentences ; < repeats
)

mixedCase =: 3 : '(+./ }. y e. Upper) *. -. *./ y e. Upper'

gapCost =: 3 : '1 + Keyboard'
limit =: 3 : 'BaseLimit * 1 + Keyboard'

substitution =: 4 : 0
    adjacent =. y e. (Lower i. x) {:: AdjacentKeys
    (x ~: y) * 1 + Keyboard * -. adjacent
)

distanceTable =: 4 : 0
    gap =. gapCost ''
    columns =. gap * i. >: {: $ y
    previous =. (# y) # ,: columns
    table =. ,: previous
    for_i. >: i. # x do.
        letter =. (i - 1) { x
        best =. (}."1 previous + gap) <. (}:"1 previous) + letter substitution y
        if. i >: 2 do.
            swapped =. 0 ,. (letter = }:"1 y) *. ((i - 2) { x) = }."1 y
            best =. best <. swapped } best ,: 1 + 0 ,. _2 }."1 before
        end.
        before =. previous
        previous =. columns +"1 <./\"1 ((i * gap) ,. best) -"1 columns
        table =. table , ,: previous
    end.
    table
)

lastRow =: 3 : '{: y distanceTable > Words'
distances =: 3 : '(#&> Words) {"0 1 lastRow y'
prefixDistances =: 3 : '(>: #&> Words) <./@:{."0 1 lastRow y'

swapAt =: 4 : 0
    'i j' =. x
    'first second' =. y
    if. (i < 2) +. j < 2 do. 0 return. end.
    (((i - 1) { first) = (j - 2) { second) *. ((i - 2) { first) = (j - 1) { second
)

editOperations =: 4 : 0
    table =. {."2 x distanceTable ,: y
    gap =. gapCost ''
    operations =. 0$a:
    i =. # x
    j =. # y
    while. (i > 0) +. j > 0 do.
        here =. (<i , j) { table
        if. (i > 0) *. j > 0 do.
            from =. (i - 1) { x
            into =. (j - 1) { y
            if. here = (from substitution into) + (<(i - 1) , j - 1) { table do.
                if. from ~: into do. operations =. (<'sub:' , from , '>' , into) , operations end.
                i =. i - 1
                j =. j - 1
                continue.
            end.
        end.
        if. (i , j) swapAt x ; y do.
            if. here = 1 + (<(i - 2) , j - 2) { table do.
                operations =. (<'swap:' , ((i - 2) , i - 1) { x) , operations
                i =. i - 2
                j =. j - 2
                continue.
            end.
        end.
        if. (i > 0) *. here = gap + (<(i - 1) , j) { table do.
            operations =. (<'del:' , (i - 1) { x) , operations
            i =. i - 1
        else.
            operations =. (<'ins:' , (j - 1) { y) , operations
            j =. j - 1
        end.
    end.
    ({: {: table) ; < operations
)

soundex =: 3 : 0
    codes =. SoundexDigits {~ Lower i. ({. y) , (}. y) -. 'hw'
    kept =. (}. codes) #~ ('0' ~: }. codes) *. (}. codes) ~: }: codes
    4 {. (toupper {. y) , kept , '000'
)

precedes =: 4 : 0
    if. (# x) ~: # y do. (# x) < # y return. end.
    index =. (x ~: y) i. 1
    0 = {. /: > (index { x) , index { y
)

segment =: 3 : 0
    length =. # y
    ways =. (length # 0) , 1
    best =. (length # a:) , < 0$a:
    for_start. |. i. length do.
        for_stop. start + >: i. length - start do.
            piece =. (stop - start) {. start }. y
            if. (-. (< piece) e. Words) +. 0 = stop { ways do. continue. end.
            candidate =. (< piece) , stop {:: best
            if. (0 = start { ways) +. candidate precedes start {:: best do.
                best =. (< candidate) start } best
            end.
            ways =. ((start { ways) + stop { ways) start } ways
        end.
    end.
    (0 { ways) ; < 0 {:: best
)

known =: 3 : '(< y) e. Words , Ignored'
hasRule =: 3 : '(< y) e. RuleSources'
ruleFor =: 3 : '(RuleSources i. < y) {:: RuleTargets'
frequencyOrder =: 3 : '/: (- Frequencies) ,. wordRank Words'
distanceOrder =: 4 : 'y /: (y { x) ,. (- y { Frequencies) ,. wordRank y { Words'

requireEntry =: 3 : 0
    index =. Words i. < y
    if. index = # Words do. fail 'NOT FOUND ' , y end.
    index
)

candidates =: 3 : 0
    distance =. distances y
    found =. distance distanceOrder I. (distance <: limit '') *. Words ~: < y
    (found { Words) ; found { distance
)

correction =: 3 : 0
    if. known y do. '' return. end.
    if. hasRule y do. ruleFor y return. end.
    found =. 0 {:: candidates y
    if. # found do. 0 {:: found else. '' end.
)

recordUndo =: 3 : 0
    UndoHistory =: UndoHistory , < y ; Words ; Frequencies ; Ignored ; RuleSources ; < RuleTargets
)

increment =: 4 : 0
    'keys counts' =. x
    index =. keys i. < y
    if. index = # keys do. (keys , < y) ; counts , 1
    else. keys ; (>: index { counts) index } counts end.
)

NB. keys are "word>correction", which sort like the pairs because > precedes every letter
logCorrection =: 3 : 0
    CorrectionLog =: CorrectionLog increment y
    Counters =: Counters + CounterNames = < 'corrected'
)

topEntries =: 3 : 0
    'keys counts' =. y
    order =. ReportSize atMost /: (- counts) ,. wordRank keys
    (order { keys) entry&.> order { counts
)

unknownFinding =: 3 : 0
    if. hasRule y do. 'RULE ' , ruleFor y return. end.
    found =. 0 {:: candidates y
    if. 0 = # found do. 'NONE' return. end.
    ' ' join (< 'SUGGEST') , SuggestionCount atMost found
)

check =: 3 : 0
    'texts sentences repeats' =. 0 2 3 { tokenize y
    lines =. 0$a:
    kinds =. i. 0
    for_i. i. # texts do.
        text =. i {:: texts
        word =. tolower text
        label =. (": >: i) , ' ' , text
        if. -. known word do.
            lines =. lines , < 'UNKNOWN ' , label , ' ' , unknownFinding word
            kinds =. kinds , 0
            UnknownLog =: UnknownLog increment word
        end.
        if. mixedCase text do.
            lines =. lines , < 'CASE ' , label
            kinds =. kinds , 1
        end.
        if. (i { sentences) *. ({. text) e. Lower do.
            lines =. lines , < 'CAPITAL ' , label
            kinds =. kinds , 2
        end.
        if. i { repeats do.
            lines =. lines , < 'REPEAT ' , label
            kinds =. kinds , 3
        end.
    end.
    counts =. +/ kinds =/ i. # FindingKinds
    Counters =: Counters + (# texts) , counts , 0
    say ('CHECK' ; 'words' field # texts) , FindingKinds field&.> counts
    Output =: Output , lines
)

correct =: 3 : 0
    'texts gaps' =. 2 {. tokenize y
    pieces =. ''
    changed =. 0
    for_i. i. # texts do.
        text =. i {:: texts
        word =. tolower text
        replacement =. correction word
        if. # replacement do.
            text =. text applyCase replacement
            logCorrection word , '>' , replacement
            changed =. >: changed
        end.
        pieces =. pieces , (i {:: gaps) , text
    end.
    tail =. (+/ #&> texts , gaps) }. y
    say 'CORRECT' ; (('changed' field changed) , ':') ; pieces , tail
)

fix =: 3 : 0
    'texts gaps sentences repeats' =. tokenize y
    pieces =. ''
    'removed replaced recased' =. 0 0 0
    for_i. i. # texts do.
        if. i { repeats do.
            removed =. >: removed
            continue.
        end.
        text =. i {:: texts
        word =. tolower text
        replacement =. correction word
        target =. word
        if. # replacement do. target =. replacement end.
        result =. text applyCase target
        if. (i { sentences) *. ({. result) e. Lower do. result =. capitalize result end.
        if. # replacement do.
            logCorrection word , '>' , replacement
            replaced =. >: replaced
        elseif. -. result -: text do.
            recased =. >: recased
        end.
        pieces =. pieces , (i {:: gaps) , result
    end.
    tail =. (+/ #&> texts , gaps) }. y
    counts =. ('removed' field removed) ; ('replaced' field replaced) ; ('recased' field recased) , ':'
    say 'FIX' ; counts , < pieces , tail
)

profile =: 3 : 0
    'texts sentences' =. 0 2 { tokenize y
    words =. tolower&.> texts
    count =. # texts
    unknown =. +/ -. known&> words
    if. count do.
        lengths =. #&> texts
        rate =. 1 decimal (100 * unknown) , count
        average =. 2 decimal (+/ lengths) , count
        longest =. ((i. >./) lengths) {:: words
    else.
        'rate average longest' =. '0.0' ; '0.00' ; '-'
    end.
    line =. 'PROFILE' ; ('words' field count) ; ('distinct' field # ~. words) ; 'unknown' field unknown
    line =. line , ('rate' field rate) ; ('avglen' field average) ; 'longest' field longest
    say line , < 'sentences' field +/ sentences
)

learn =: 3 : 0
    recordUndo 'LEARN'
    'updated added skipped' =. 0 0 0
    for_text. 0 {:: tokenize y do.
        word =. tolower > text
        if. MaxWordLength < # word do.
            skipped =. >: skipped
        elseif. (< word) e. Words do.
            index =. Words i. < word
            Frequencies =: (>: index { Frequencies) index } Frequencies
            updated =. >: updated
        else.
            Words =: Words , < word
            Frequencies =: Frequencies , 1
            Ignored =: Ignored -. < word
            added =. >: added
        end.
    end.
    say 'LEARN' ; ('updated' field updated) ; ('added' field added) ; 'skipped' field skipped
)

suggest =: 3 : 0
    word =. wordArgument 0 {:: y
    if. known word do. say 'SUGGEST' ; word ; 'KNOWN'
    elseif. hasRule word do. say 'SUGGEST' ; word ; 'RULE' ; ruleFor word
    else.
        'others distance' =. candidates word
        shown =. SuggestionCount atMost others entry&.> distance
        say ('SUGGEST' ; word ; 'found' field # others) , shown
    end.
)

dist =: 3 : 0
    first =. wordArgument 0 {:: y
    second =. wordArgument 1 {:: y
    'distance operations' =. first editOperations second
    say ('DIST' ; first ; second ; ": distance) , operations
)

soundexCode =: 3 : 0
    word =. wordArgument 0 {:: y
    say 'SOUNDEX' ; word ; soundex word
)

sounds =: 3 : 0
    word =. wordArgument 0 {:: y
    code =. soundex word
    ordered =. (frequencyOrder '') { Words
    matches =. ordered #~ (ordered ~: < word) *. (< code) = soundex&.> ordered
    say ('SOUNDS' ; word ; code ; 'count' field # matches) , ReportSize atMost matches
)

split =: 3 : 0
    word =. wordArgument 0 {:: y
    'ways best' =. segment word
    if. ways = 0 do. say 'SPLIT' ; word ; 'ways=0' ; '->' ; 'NONE'
    else. say ('SPLIT' ; word ; ('ways' field ways) ; '->') , best end.
)

prefix =: 3 : 0
    word =. wordArgument 0 {:: y
    count =. (1 , MaxListed) numberArgument 1 {:: y
    order =. frequencyOrder ''
    matches =. order #~ (< word) = (# word) {.&.> order { Words
    shown =. count atMost matches
    say ('PREFIX' ; word ; 'count' field # matches) , (shown { Words) entry&.> shown { Frequencies
)

complete =: 3 : 0
    word =. wordArgument 0 {:: y
    count =. (1 , MaxListed) numberArgument 1 {:: y
    distance =. prefixDistances word
    matches =. distance distanceOrder I. distance <: <. 2 %~ limit ''
    shown =. count atMost matches
    say ('COMPLETE' ; word ; 'count' field # matches) , (shown { Words) entry&.> shown { distance
)

listWords =: 3 : 0
    word =. wordArgument 0 {:: y
    count =. (1 , MaxListed) numberArgument 1 {:: y
    order =. /: > (< word) , Words
    matches =. <: (>: order i. 0) }. order
    shown =. count atMost matches
    say ('LIST' ; word ; 'count' field # matches) , (shown { Words) entry&.> shown { Frequencies
)

wordInfo =: 3 : 0
    word =. wordArgument 0 {:: y
    index =. requireEntry word
    rank =. >: (frequencyOrder '') i. index
    line =. 'WORD' ; word ; ('freq' field index { Frequencies) ; 'rank' field rank
    say line , ('soundex' field soundex word) ; 'neighbors' field # 0 {:: candidates word
)

add =: 3 : 0
    word =. wordArgument 0 {:: y
    frequency =. (1 , MaxFrequency) numberArgument 1 {:: y
    if. (< word) e. Words do. fail 'DUPLICATE ' , word end.
    recordUndo 'ADD'
    Words =: Words , < word
    Frequencies =: Frequencies , frequency
    Ignored =: Ignored -. < word
    say 'ADD' ; word ; frequency
)

remove =: 3 : 0
    word =. wordArgument 0 {:: y
    index =. requireEntry word
    frequency =. index { Frequencies
    recordUndo 'REMOVE'
    Words =: (<<<index) { Words
    Frequencies =: (<<<index) { Frequencies
    say 'REMOVE' ; word ; frequency
)

ignore =: 3 : 0
    word =. wordArgument 0 {:: y
    if. (< word) e. Words do. fail 'IN DICTIONARY ' , word end.
    if. (< word) e. Ignored do. fail 'ALREADY IGNORED ' , word end.
    recordUndo 'IGNORE'
    Ignored =: Ignored , < word
    say 'IGNORE' ; word
)

unignore =: 3 : 0
    word =. wordArgument 0 {:: y
    if. -. (< word) e. Ignored do. fail 'NOT IGNORED ' , word end.
    recordUndo 'UNIGNORE'
    Ignored =: Ignored -. < word
    say 'UNIGNORE' ; word
)

rule =: 3 : 0
    source =. wordArgument 0 {:: y
    target =. wordArgument 1 {:: y
    if. (< source) e. Words do. fail 'IN DICTIONARY ' , source end.
    if. -. (< target) e. Words do. fail 'NOT FOUND ' , target end.
    recordUndo 'RULE'
    index =. RuleSources i. < source
    if. index = # RuleSources do.
        RuleSources =: RuleSources , < source
        RuleTargets =: RuleTargets , < target
        say 'RULE' ; source ; target
    else.
        previous =. index {:: RuleTargets
        RuleTargets =: (< target) index } RuleTargets
        say 'RULE' ; source ; target ; 'REPLACED' ; previous
    end.
)

unrule =: 3 : 0
    word =. wordArgument 0 {:: y
    if. -. hasRule word do. fail 'NO RULE ' , word end.
    recordUndo 'UNRULE'
    index =. RuleSources i. < word
    target =. index {:: RuleTargets
    RuleSources =: (<<<index) { RuleSources
    RuleTargets =: (<<<index) { RuleTargets
    say 'UNRULE' ; word ; target
)

showRules =: 3 : 0
    order =. /: > RuleSources
    rules =. (order { RuleSources) ,&.> '>' ,&.> order { RuleTargets
    say ('RULES' ; 'count' field # RuleSources) , rules
)

keyboardMode =: 3 : 0
    mode =. 0 {:: y
    if. -. (< mode) e. KeyboardModes do. fail 'BAD MODE ' , mode end.
    Keyboard =: KeyboardModes i. < mode
    say 'KEYBOARD' ; mode
)

setOption =: 3 : 0
    option =. 0 {:: y
    index =. OptionNames i. < option
    if. index = # OptionNames do. fail 'BAD OPTION ' , option end.
    value =. (1 , index { OptionMaximums) numberArgument 1 {:: y
    if. option -: 'LIMIT' do. BaseLimit =: value else. SuggestionCount =: value end.
    say 'SET' ; option ; value
)

undo =: 3 : 0
    if. 0 = # UndoHistory do. fail 'NOTHING TO UNDO' end.
    record =. _1 {:: UndoHistory
    UndoHistory =: }: UndoHistory
    'Words Frequencies Ignored RuleSources RuleTargets' =: }. record
    say 'UNDO' ; 0 {:: record
)

report =: 3 : 0
    say ('REPORT' ; 'distinct' field # 0 {:: UnknownLog) , topEntries UnknownLog
)

history =: 3 : 0
    say ('HISTORY' ; 'distinct' field # 0 {:: CorrectionLog) , topEntries CorrectionLog
)

stats =: 3 : 0
    top =. {. frequencyOrder ''
    average =. 2 decimal (+/ #&> Words) , # Words
    line =. 'STATS' ; ('words' field # Words) ; 'total' field +/ Frequencies
    line =. line , ('avglen' field average) ; 'top' field (top {:: Words) entry top { Frequencies
    line =. line , ('ignored' field # Ignored) ; 'rules' field # RuleSources
    line =. line , ('keyboard' field Keyboard {:: KeyboardModes) ; 'limit' field limit ''
    line =. line , ('suggestions' field SuggestionCount) ; 'undo' field # UndoHistory
    say line
    say 'SESSION' ; CounterNames field&.> Counters
)

Commands =: ;:'CHECK CORRECT FIX PROFILE LEARN SUGGEST DIST SOUNDEX SOUNDS SPLIT PREFIX'
Commands =: Commands , ;:'COMPLETE LIST WORD ADD REMOVE IGNORE UNIGNORE RULE UNRULE'
Commands =: Commands , ;:'RULES KEYBOARD SET UNDO REPORT HISTORY STATS'
Arities =: _1 _1 _1 _1 _1 1 2 1 1 1 2 2 2 1 2 1 1 1 2 1 0 1 2 0 0 0 0
Handlers =: check`correct`fix`profile`learn`suggest`dist`soundexCode`sounds`split`prefix
Handlers =: Handlers , complete`listWords`wordInfo`add`remove`ignore`unignore`rule`unrule
Handlers =: Handlers , showRules`keyboardMode`setOption`undo`report`history`stats

execute =: 3 : 0
    name =. y {.~ y i. ' '
    index =. Commands i. < name
    if. index = # Commands do. fail 'UNKNOWN COMMAND ' , name end.
    arity =. index { Arities
    if. arity < 0 do.
        if. name -: y do. fail 'BAD ARGUMENTS ' , name end.
        (Handlers @. index) (>: # name) }. y
    else.
        arguments =. <;._1 (# name) }. y
        if. arity ~: # arguments do. fail 'BAD ARGUMENTS ' , name end.
        (Handlers @. index) arguments
    end.
)

main =: 3 : 0
    lines =. <;._2 (1!:1 < '/dev/stdin') , LF
    count =. ". 0 {:: lines
    entries =. > <;._1@(' '&,)&.> count {. }. lines
    Words =: {."1 entries
    Frequencies =: ".&> {:"1 entries
    commandCount =. ". (>: count) {:: lines
    for_line. (count + 2 + i. commandCount) { lines do.
        try. execute > line catcht. end.
    end.
    1!:2&2 ; Output ,&.> LF
)

main ''
exit 0
