LF =: 10{a.
Upper =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
Lower =: 'abcdefghijklmnopqrstuvwxyz'
Letters =: Upper,Lower
Digits =: '0123456789'
KwicWidth =: 30
StepNames =: '1a';'1b';'1c';(,'2');(,'3');(,'4');'5a';'5b'

num =: 3 : ',''0'' 8!:2 y'
split =: 4 : '<;._1 x,y'
lower =: 3 : '(Lower,a.) {~ (Upper,a.) i. y'
ends =: 4 : '(,x) -: (-#x) {. y'
prefixOf =: 4 : '(,x) -: (#x) {. y'
yesNo =: 3 : 'y {:: ''NO'';''YES'''
join =: 4 : 0
    r =. ''
    for_i. i.#y do.
        if. i do. r =. r,x end.
        r =. r,i{::y
    end.
    r
)
words =: 3 : 0
    r =. 0$a:
    for_v. y do.
        v =. >v
        if. 2~:3!:0 v do. v =. num v end.
        r =. r,<,v
    end.
    ' 'join r
)
emit =: 3 : 'Output =: Output,<y'
say =: 3 : 'emit words y'
fail =: 3 : 0
    emit 'ERROR ',y
    throw.
)

pattern =: 3 : 0
    r =. ''
    for_c. y do.
        if. c e. 'aeiou' do. r =. r,'V'
        elseif. (c = 'y') *. 0 < #r do. r =. r,('C' = {:r) { 'CV'
        else. r =. r,'C' end.
    end.
    r
)
measure =: 3 : '+/ ''VC'' E. pattern y'
hasVowel =: 3 : '''V'' e. pattern y'
endsDouble =: 3 : 0
    if. 2 > #y do. 0 return. end.
    ('CC' -: _2 {. pattern y) *. =/ _2 {. y
)
endsCvc =: 3 : 0
    if. 3 > #y do. 0 return. end.
    ('CVC' -: _3 {. pattern y) *. -. ({:y) e. 'wxy'
)
NB. Condition codes: 0 none, 1 m>0, 2 m>1, 3 ion rule, 4 final e, 5 *v*.
holds =: 4 : 0
    select. x
    case. 0 do. 1
    case. 1 do. 0 < measure y
    case. 2 do. 1 < measure y
    case. 3 do. (1 < measure y) *. ({:y) e. 'st'
    case. 4 do.
        m =. measure y
        (m > 1) +. (m = 1) *. -. endsCvc y
    case. 5 do. hasVowel y
    end.
)
withCondition =: 4 : '(_2 ]\ y) ,. <x'
Rules1a =: 0 withCondition 'sses';'ss';'ies';'i';'ss';'ss';'s';''
Rules1b =: _3 ]\ 'eed';'ee';1;'ed';'';5;'ing';'';5
Rules1c =: _3 ]\ 'y';'i';5
Rules2 =: 1 withCondition 'ational';'ate';'tional';'tion';'enci';'ence';'anci';'ance';'izer';'ize'
Rules2 =: Rules2 , 1 withCondition 'abli';'able';'alli';'al';'entli';'ent';'eli';'e';'ousli';'ous'
Rules2 =: Rules2 , 1 withCondition 'ization';'ize';'ation';'ate';'ator';'ate';'alism';'al'
Rules2 =: Rules2 , 1 withCondition 'iveness';'ive';'fulness';'ful';'ousness';'ous';'aliti';'al'
Rules2 =: Rules2 , 1 withCondition 'iviti';'ive';'biliti';'ble'
Rules3 =: 1 withCondition 'icate';'ic';'ative';'';'alize';'al';'iciti';'ic';'ical';'ic'
Rules3 =: Rules3 , 1 withCondition 'ful';'';'ness';''
Step4 =: ;:'al ance ence er ic able ible ant ement ment ent ion ou ism ate iti ous ive ize'
Rules4 =: Step4 ,. a: ,. <"0 (2 + Step4 = <'ion')
Rules5a =: _3 ]\ 'e';'';4
StepRules =: Rules1a;Rules1b;Rules1c;Rules2;Rules3;Rules4;<Rules5a

NB. Applies the rule with the longest matching suffix; returns the word and the applied suffix.
applyRules =: 4 : 0
    suffixes =. 0 {"1 x
    lengths =. (#&> suffixes) * suffixes ends&> <y
    if. 0 = >./ lengths do. y;'' return. end.
    'suffix replacement code' =. ((i. >./) lengths) { x
    remainder =. (-#suffix) }. y
    if. -. code holds remainder do. y;'' return. end.
    (remainder,replacement);suffix
)
tidy1b =: 3 : 0
    if. +./ ('at';'bl';'iz') ends&> <y do. y,'e' return. end.
    if. (endsDouble y) *. -. ({:y) e. 'lsz' do. }:y return. end.
    if. (1 = measure y) *. endsCvc y do. y,'e' return. end.
    y
)
applyStep =: 4 : 0
    if. x = 7 do.
        if. (1 < measure y) *. (endsDouble y) *. 'l' = {:y do. }:y return. end.
        y return.
    end.
    'result suffix' =. (x {:: StepRules) applyRules y
    if. (x = 1) *. (<suffix) e. 'ed';'ing' do. tidy1b result return. end.
    result
)
stemSteps =: 3 : 0
    changes =. 0$a:
    if. 2 < #y do.
        for_step. i.8 do.
            result =. step applyStep y
            if. -. result -: y do. changes =. changes,<(step{::StepNames),':',result end.
            y =. result
        end.
    end.
    y;<changes
)
stem =: 3 : '0 {:: stemSteps y'

Output =: 0$a:
Stopwords =: 0$a:
DocNumbers =: i.0
DocLines =: 0$a:
TokDoc =: TokLine =: TokPos =: TokStart =: i.0
TokText =: TokForm =: TokStem =: 0$a:
Kinds =: Spellings =: 0$a:
Position =: 0
Indexed =: i.0

addDocument =: 3 : 0
    DocNumbers =: DocNumbers,y
    DocLines =: DocLines,<0$a:
)
addLine =: 4 : 0
    slot =. DocNumbers i. x
    lines =. (slot{::DocLines),<y
    DocLines =: (<lines) slot} DocLines
    letters =. y e. Letters
    starts =. I. letters > }: 0,letters
    lengths =. (>: I. letters > }. letters,0) - starts
    texts =. 0$a:
    for_s. starts do. texts =. texts,<(s_index{lengths) {. s }. y end.
    forms =. lower&.> texts
    n =. #starts
    base =. +/ TokDoc = x
    TokDoc =: TokDoc , n # x
    TokLine =: TokLine , n # #lines
    TokPos =: TokPos , base + >: i.n
    TokStart =: TokStart , starts
    TokText =: TokText , texts
    TokForm =: TokForm , forms
    TokStem =: TokStem , stem&.> forms
    n
)
removeDocument =: 3 : 0
    keep =. TokDoc ~: y
    TokDoc =: keep # TokDoc
    TokLine =: keep # TokLine
    TokPos =: keep # TokPos
    TokStart =: keep # TokStart
    TokText =: keep # TokText
    TokForm =: keep # TokForm
    TokStem =: keep # TokStem
    others =. DocNumbers ~: y
    DocLines =: others # DocLines
    DocNumbers =: others # DocNumbers
)
lineCount =: 3 : '# (DocNumbers i. y) {:: DocLines'
indexed =: 3 : '-. TokForm e. Stopwords'
docMask =: 3 : '(indexed '''') *. TokDoc = y'
stemSet =: 3 : '~. (docMask y) # TokStem'
termCounts =: 3 : 0
    stems =. y # TokStem
    (~. stems);#/.~ stems
)
byCount =: 3 : 0
    'stems counts' =. y
    order =. /: > stems
    stems =. order { stems
    counts =. order { counts
    order =. \: counts
    (order { stems);order { counts
)
occurrences =: 3 : 0
    tokens =. I. y
    tokens /: (tokens { TokDoc) ,. tokens { TokPos
)
reference =: 3 : '(num y{TokDoc),'':'',(num y{TokLine),'':'',num y{TokPos'
references =: 3 : 0
    r =. 0$a:
    for_token. y do. r =. r,<reference token end.
    r
)
closest =: 3 : 0
    'positions others same' =. y
    if. same do. gaps =. (}. - }:) positions
    else.
        NB. The closest pair of different stems is adjacent in the merged order.
        merged =. /:~ (positions ,. 0) , others ,. 1
        gaps =. ((}. - }:) {."1 merged) #~ (}. ~: }:) {:"1 merged
    end.
    if. 0 = #gaps do. _1 else. <./ gaps end.
)

isWord =: 3 : '(1 <: #y) *. (30 >: #y) *. *./ y e. Letters'
wordArg =: 3 : 0
    if. -. isWord y do. fail 'BAD WORD ',y end.
    lower y
)
numberArg =: 4 : 0
    if. -. (1 <: #y) *. (7 >: #y) *. *./ y e. Digits do. fail 'BAD NUMBER ',y end.
    value =. 0 ". y
    if. (value < {.x) +. value > {:x do. fail 'BAD NUMBER ',y end.
    value
)
termArg =: 3 : 0
    word =. wordArg y
    if. (<word) e. Stopwords do. fail 'STOPWORD ',word end.
    stem word
)
docArg =: 3 : 0
    d =. 1 999 numberArg y
    if. -. d e. DocNumbers do. fail 'NO DOC ',num d end.
    d
)
splitArguments =: 4 : 0
    if. x -: 'SEARCH' do. <y return. end.
    if. x -: 'APPEND' do.
        space =. y i. ' '
        if. space = #y do. <y return. end.
        (space {. y);(>: space) }. y return.
    end.
    ' ' split y
)

lexemes =: 3 : 0
    r =. 0$a:
    current =. ''
    for_c. y do.
        if. c e. ' ()' do.
            if. #current do. r =. r,<current end.
            current =. ''
            if. c ~: ' ' do. r =. r,<,c end.
        else.
            current =. current,c
        end.
    end.
    if. #current do. r =. r,<current end.
    r
)
classify =: 3 : 0
    if. (<y) e. 'AND';'OR';'NOT';(,'(');,')' do. y;y return. end.
    if. isWord y do. 'term';lower y return. end.
    if. ('*' = {:y) *. isWord }:y do. 'prefix';lower }:y return. end.
    fail 'BAD TERM ',y
)
peek =: 3 : 0
    if. Position < #Kinds do. Position{::Kinds else. '' end.
)
expression =: 3 : 0
    'canonical documents' =. conjunction ''
    while. 'OR' -: peek '' do.
        Position =: Position + 1
        'right others' =. conjunction ''
        canonical =. '(',canonical,' OR ',right,')'
        documents =. documents +. others
    end.
    canonical;documents
)
conjunction =: 3 : 0
    'canonical documents' =. negation ''
    while. (<peek '') e. 'AND';'NOT';(,'(');'term';'prefix' do.
        if. 'AND' -: peek '' do. Position =: Position + 1 end.
        'right others' =. negation ''
        canonical =. '(',canonical,' AND ',right,')'
        documents =. documents *. others
    end.
    canonical;documents
)
negation =: 3 : 0
    if. -. 'NOT' -: peek '' do. element '' return. end.
    Position =: Position + 1
    'canonical documents' =. negation ''
    ('(NOT ',canonical,')');-. documents
)
element =: 3 : 0
    if. Position >: #Kinds do. fail 'SYNTAX' end.
    kind =. Position{::Kinds
    spelling =. Position{::Spellings
    Position =: Position + 1
    if. kind -: ,'(' do.
        result =. expression ''
        if. -. (,')') -: peek '' do. fail 'SYNTAX' end.
        Position =: Position + 1
        result
    elseif. kind -: 'term' do.
        s =. stem spelling
        s;DocNumbers e. (Indexed *. TokStem = <s) # TokDoc
    elseif. kind -: 'prefix' do.
        (spelling,'*');DocNumbers e. (Indexed *. spelling&prefixOf&> TokStem) # TokDoc
    else.
        fail 'SYNTAX'
    end.
)

stemWords =: 3 : 0
    ws =. wordArg&.> y
    say 'STEM';ws ,&.> ':' ,&.> stem&.> ws
)
showSteps =: 3 : 0
    word =. wordArg 0{::y
    changes =. 1 {:: stemSteps word
    if. 0 = #changes do. say 'STEPS';word;'NONE' else. say 'STEPS';word;changes end.
)
showMeasure =: 3 : 0
    word =. wordArg 0{::y
    flags =. ('vowel=',yesNo hasVowel word);('double=',yesNo endsDouble word)
    flags =. flags,<'cvc=',yesNo endsCvc word
    say ('MEASURE';word;(pattern word);'m=',num measure word),flags
)
showIndex =: 3 : 0
    prefix =. ''
    if. #y do. prefix =. wordArg 0{::y end.
    hits =. occurrences (indexed '') *. prefix&prefixOf&> TokStem
    hits =. hits /: > hits { TokStem
    groups =. (~: hits { TokStem) <;.1 hits
    emit 'INDEX stems=',num #groups
    for_group. groups do.
        tokens =. >group
        df =. # ~. tokens { TokDoc
        say ((0{tokens){::TokStem);('df=',num df);references tokens
    end.
)
search =: 3 : 0
    Kinds =: Spellings =: 0$a:
    for_lexeme. lexemes 0{::y do.
        'kind spelling' =. classify >lexeme
        Kinds =: Kinds,<kind
        Spellings =: Spellings,<spelling
    end.
    Position =: 0
    Indexed =: indexed ''
    'canonical documents' =. expression ''
    if. Position < #Kinds do. fail 'SYNTAX' end.
    terms =. (Kinds = <'term') # Spellings
    stopped =. terms e. Stopwords
    if. +./ stopped do. fail 'STOPWORD ',> {. stopped # terms end.
    numbers =. /:~ documents # DocNumbers
    say ('SEARCH';canonical;'count=',num #numbers),<"0 numbers
)
phrase =: 3 : 0
    ws =. wordArg&.> y
    stops =. ws e. Stopwords
    if. *./ stops do. fail 'STOPWORDS ONLY' end.
    targets =. (<,'?') (I. stops)} stem&.> ws
    n =. #targets
    mask =. indexed ''
    found =. 0$a:
    for_d. /:~ DocNumbers do.
        tokens =. I. TokDoc = d
        hits =. (#tokens) $ 1
        for_target. targets do.
            if. -. target -: <,'?' do.
                hits =. hits *. target_index |.!.0 (tokens { mask) *. target = tokens { TokStem
            end.
        end.
        hits =. hits *. (i. #tokens) <: (#tokens) - n
        found =. found,references (I. hits) { tokens
    end.
    header =. 'PHRASE "',(' 'join targets),'"'
    say header;('matches=',num #found);found
)
near =: 3 : 0
    first =. termArg 0{::y
    second =. termArg 1{::y
    limit =. 1 100 numberArg 2{::y
    mask =. indexed ''
    found =. 0$a:
    for_d. /:~ DocNumbers do.
        tokens =. I. mask *. TokDoc = d
        positions =. (tokens { TokPos) #~ (tokens { TokStem) = <first
        others =. (tokens { TokPos) #~ (tokens { TokStem) = <second
        distance =. closest positions;others;first -: second
        if. (distance >: 0) *. distance <: limit do. found =. found,<(num d),':',num distance end.
    end.
    say ('NEAR';first;second;limit;'count=',num #found),found
)
top =: 3 : 0
    limit =. 1 100 numberArg 0{::y
    header =. 'TOP ',num limit
    mask =. indexed ''
    if. 2 = #y do.
        d =. docArg 1{::y
        mask =. docMask d
        header =. header,' doc=',num d
    end.
    'stems counts' =. byCount termCounts mask
    items =. stems ,&.> ':' ,&.> <@num"0 counts
    say header;(limit <. #items) {. items
)
kwic =: 3 : 0
    s =. termArg 0{::y
    hits =. occurrences (indexed '') *. TokStem = <s
    emit 'KWIC ',s,' count=',num #hits
    for_hit. hits do.
        text =. (<: hit{TokLine) {:: (DocNumbers i. hit{TokDoc) {:: DocLines
        start =. hit{TokStart
        token =. hit{::TokText
        before =. (-KwicWidth) {. start {. text
        after =. KwicWidth {. (start + #token) }. text
        emit '|',before,'[',token,']',after,'| ',reference hit
    end.
)
termFrequency =: 3 : 0
    d =. docArg 0{::y
    s =. termArg 1{::y
    say 'TF';d;s;+/ (docMask d) *. TokStem = <s
)
documentFrequency =: 3 : 0
    s =. termArg 0{::y
    say 'DF';s;# ~. ((indexed '') *. TokStem = <s) # TokDoc
)
variants =: 3 : 0
    s =. termArg 0{::y
    forms =. ((indexed '') *. TokStem = <s) # TokForm
    keys =. ~. forms
    counts =. #/.~ forms
    order =. /: > keys
    items =. (order { keys) ,&.> ':' ,&.> <@num"0 order { counts
    say ('VARIANTS';s;'count=',num #keys),items
)
similar =: 3 : 0
    d =. docArg 0{::y
    limit =. 1 100 numberArg 1{::y
    stems =. stemSet d
    numbers =. /:~ DocNumbers -. d
    fractions =. 0 2$0
    for_other. numbers do.
        otherStems =. stemSet other
        shared =. +/ stems e. otherStems
        union =. (#stems) + (#otherStems) - shared
        fraction =. 0 1
        if. union do. fraction =. <. (shared,union) % shared +. union end.
        fractions =. fractions,fraction
    end.
    items =. 0$a:
    for_index. (limit <. #numbers) {. \: %/"1 fractions do.
        'numerator denominator' =. index { fractions
        items =. items,<(num index{numbers),':',(num numerator),'/',num denominator
    end.
    say ('SIMILAR';d),items
)
rank =: 3 : 0
    limit =. 1 100 numberArg 0{::y
    query =. ~. termArg&.> }.y
    mask =. indexed ''
    rows =. 0 3$0
    for_d. /:~ DocNumbers do.
        counts =. +/"1 query =/ (mask *. TokDoc = d) # TokStem
        matched =. +/ counts > 0
        if. matched do. rows =. rows,matched,(+/ counts),d end.
    end.
    items =. 0$a:
    for_row. (limit <. #rows) {. rows \: 2 {."1 rows do.
        'matched total number' =. row
        items =. items,<(num number),':',(num matched),':',num total
    end.
    say (<'RANK count=',num #rows),items
)
info =: 3 : 0
    d =. docArg 0{::y
    'stems counts' =. byCount termCounts docMask d
    best =. '-'
    if. #stems do. best =. (0{::stems),':',num {.counts end.
    head =. 'INFO';d;('lines=',num lineCount d);'tokens=',num +/ TokDoc = d
    say head,('indexed=',num +/ counts);('stems=',num #stems);'top=',best
)
showLine =: 3 : 0
    d =. docArg 0{::y
    lineNumber =. 1 999 numberArg 1{::y
    if. lineNumber > lineCount d do. fail 'NO LINE ',(num d),':',num lineNumber end.
    tokens =. I. (TokDoc = d) *. TokLine = lineNumber
    items =. 0$a:
    for_token. tokens do.
        form =. token{::TokForm
        if. (<form) e. Stopwords do. items =. items,<form,'/-'
        else. items =. items,<form,'/',token{::TokStem end.
    end.
    say ('LINE ',(num d),':',num lineNumber);('tokens=',num #tokens);items
)
stats =: 3 : 0
    'stems counts' =. termCounts indexed ''
    head =. 'STATS';('docs=',num #DocNumbers);('lines=',num +/ #&> DocLines)
    head =. head,('tokens=',num #TokDoc);('indexed=',num +/ counts)
    say head,('stems=',num #stems);'stopwords=',num #Stopwords
)
stop =: 3 : 0
    word =. wordArg 0{::y
    if. (<word) e. Stopwords do. fail 'ALREADY STOPWORD ',word end.
    Stopwords =: Stopwords,<word
    say 'STOP';word;'unindexed=',num +/ TokForm = <word
)
unstop =: 3 : 0
    word =. wordArg 0{::y
    if. -. (<word) e. Stopwords do. fail 'NOT STOPWORD ',word end.
    Stopwords =: Stopwords -. <word
    say 'UNSTOP';word;'indexed=',num +/ TokForm = <word
)
append =: 3 : 0
    d =. 1 999 numberArg 0{::y
    created =. -. d e. DocNumbers
    if. created do. addDocument d end.
    n =. d addLine 1{::y
    indexedCount =. +/ -. ((-n) {. TokForm) e. Stopwords
    head =. 'APPEND';d;('line=',num lineCount d);'tokens=',num n
    say head,('indexed=',num indexedCount);'new=',yesNo created
)
delete =: 3 : 0
    d =. docArg 0{::y
    lines =. lineCount d
    tokens =. +/ TokDoc = d
    removeDocument d
    say 'DELETE';d;('lines=',num lines);'tokens=',num tokens
)

Commands =: ;:'STEM STEPS MEASURE INDEX SEARCH PHRASE NEAR TOP KWIC TF DF VARIANTS SIMILAR RANK'
Commands =: Commands,;:'INFO LINE STATS STOP UNSTOP APPEND DELETE'
Minimums =: 1 1 1 0 1 2 3 1 1 2 1 1 2 2 1 2 0 1 1 2 1
Maximums =: 10 1 1 1 1 10 3 2 1 2 1 1 2 11 1 2 0 1 1 2 1
Handlers =: stemWords`showSteps`showMeasure`showIndex`search`phrase`near`top`kwic`termFrequency
Handlers =: Handlers,documentFrequency`variants`similar`rank`info`showLine`stats`stop`unstop
Handlers =: Handlers,append`delete

execute =: 3 : 0
    space =. y i. ' '
    name =. space {. y
    command =. Commands i. <name
    if. command = #Commands do. fail 'UNKNOWN COMMAND ',name end.
    arguments =. 0$a:
    if. space < #y do. arguments =. name splitArguments (>: space) }. y end.
    count =. #arguments
    if. (count < command{Minimums) +. count > command{Maximums do. fail 'BAD ARGUMENTS ',name end.
    (Handlers @. command) arguments
)
main =: 3 : 0
    lines =. <;._2 (1!:1 <'/dev/stdin'),LF
    Stopwords =: }. ' ' split 0{::lines
    i =. 1
    while. 'DOC ' -: 4 {. i{::lines do.
        d =. 0 ". 4 }. i{::lines
        addDocument d
        i =. i + 1
        while. -. 'ENDDOC' -: i{::lines do.
            d addLine i{::lines
            i =. i + 1
        end.
        i =. i + 1
    end.
    while. -. 'END' -: i{::lines do.
        try. execute i{::lines catcht. end.
        i =. i + 1
    end.
    1!:2&2 (LF join Output),LF
)
main''
