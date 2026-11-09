ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
Uppercase =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
LetterPoints =: 1 3 3 2 1 4 2 4 1 8 5 1 3 1 1 3 10 1 1 1 1 4 4 8 4 10
div =: 4 : '_1 x:<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
number =: 3 : 0
    text =. ''
    while. y>0 do.
        text =. ((10|y){Digits),text
        y =. y div 10
    end.
    if. #text do. text else. '0' end.
)
split =: 4 : 0
    parts =. 0$a:
    while. 1 do.
        position =. y i.x
        parts =. parts,<position{.y
        if. position=#y do. parts return. end.
        y =. (position+1)}.y
    end.
)
join =: 4 : 0
    text =. ''
    for_index. i.#y do.
        if. index do. text =. text,x end.
        text =. text,index{::y
    end.
    text
)
joined =: 4 : 0
    if. #y do. x join y else. '-' end.
)
format =: 4 : 0
    parts =. '|' split x
    text =. 0{::parts
    for_index. i.#y do.
        value =. index{::y
        if. 2~:3!:0 value do. value =. number value end.
        text =. text,value,(index+1){::parts
    end.
    text
)
ascii_order =: 3 : '/: > (a.&i.)&.> y'
ascii_less =: 4 : 0
    first =. a.i.x
    second =. a.i.y
    for_index. i.(#first)<.#second do.
        if. (index{first)~:index{second do. (index{first)<index{second return. end.
    end.
    (#first)<#second
)
read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
ignored =: 3 : '(0=#y)+.''#''={.y,'' '' '
load SourceDirectory,'grid.ijs'
load SourceDirectory,'slots.ijs'
load SourceDirectory,'word_index.ijs'
load SourceDirectory,'filler.ijs'
load SourceDirectory,'render.ijs'
read_settings =: 3 : 0
    for_box. read_lines 'params.txt' do.
        line =. >box
        if. ignored line do. continue. end.
        'key value' =. ' ' split line
        if. key-:'node_budget' do. DefaultBudget =: num value
        elseif. key-:'min_score' do. DefaultMinimum =: num value
        elseif. key-:'symmetry' do. DefaultSymmetry =: value
        elseif. key-:'relax_step' do. RelaxStep =: num value
        else. WeakScore =: num value end.
    end.
    i.0
)
read_wordlist =: 3 : 0
    lines =. read_lines 'words.txt'
    WordLineCount =: #lines
    WordNames =: 0$a:
    WordScores =: FirstLines =: 0$0
    WordInvalid =: WordDuplicates =: 0$a:
    for_index. i.#lines do.
        line =. index{::lines
        error =. word_line_error line
        if. #error do.
            WordInvalid =: WordInvalid,<'invalid | |' format (<index+1),<error
            continue.
        end.
        'word score' =. ' ' split line
        position =. WordNames i.<word
        if. position<#WordNames do.
            WordDuplicates =: WordDuplicates,<'duplicate | | first=|' format (<index+1),(<word),<position{FirstLines
        else.
            WordNames =: WordNames,<word
            WordScores =: WordScores,num score
            FirstLines =: FirstLines,index+1
        end.
    end.
    alphabet =. /:ascii_order WordNames
    order =. /:(-WordScores),.alphabet
    WordNames =: order{WordNames
    WordScores =: order{WordScores
    FirstLines =: order{FirstLines
    build_word_index ''
    i.0
)
read_clues =: 3 : 0
    ClueEntries =: ClueAdded =: 0
    ClueTexts =: (#WordNames)$<0$a:
    ClueUses =: (#WordNames)$<0$0
    ClueInvalid =: ClueUnknown =: 0$a:
    lines =. read_lines 'clues.txt'
    for_index. i.#lines do.
        line =. index{::lines
        if. ignored line do. continue. end.
        ClueEntries =: ClueEntries+1
        error =. clue_line_error line
        if. #error do.
            ClueInvalid =: ClueInvalid,<'clue_invalid | |' format (<index+1),<error
            continue.
        end.
        'word clue' =. '|' split line
        position =. WordNames i.<word
        if. position=#WordNames do.
            ClueUnknown =: ClueUnknown,<'clue_unknown | |' format (<index+1),<word
        else.
            ClueTexts =: (<(position{::ClueTexts),<clue)position}ClueTexts
            ClueUses =: (<(position{::ClueUses),0)position}ClueUses
            ClueAdded =: ClueAdded+1
        end.
    end.
    i.0
)
choose_clue =: 3 : 0
    clues =. y{::ClueTexts
    if. 0=#clues do. '' return. end.
    uses =. y{::ClueUses
    chosen =. uses i.<./uses
    uses =. (1+chosen{uses)chosen}uses
    ClueUses =: (<uses)y}ClueUses
    chosen{::clues
)
read_blocks =: 3 : 0
    blocks =. 0$a:
    active =. 0
    for_box. read_lines 'templates.txt' do.
        line =. >box
        if. -.active do.
            if. 'TEMPLATE '-:9{.line do.
                name =. 9}.line
                options =. rows =. 0$a:
                active =. 1
            end.
        elseif. line-:'END' do.
            blocks =. blocks,<(<name),(<options),<rows
            active =. 0
        elseif. ' 'e.line do. options =. options,<line
        else. rows =. rows,<line end.
    end.
    blocks
)
valid_name =: 3 : '((0<#y)*.(#y)<:20)*.*./y e.''abcdefghijklmnopqrstuvwxyz0123456789_'''
check_template =: 3 : 0
    'TemplateName options GridRows' =: y
    Budget =: DefaultBudget
    Minimum =: DefaultMinimum
    RequiredSymmetry =: DefaultSymmetry
    Themes =: 0$a:
    if. -.valid_name TemplateName do. 'bad name' return. end.
    if. (<TemplateName)e.EarlierNames do. 'duplicate name' return. end.
    seen =. 0$a:
    for_index. i.#options do.
        line =. index{::options
        space =. line i.' '
        key =. space{.line
        value =. (space+1)}.line
        valid =. 1
        if. key-:'theme' do.
            if. (-.valid_word value)+.(<value)e.Themes do. valid =. 0
            else. Themes =: Themes,<value end.
        elseif. (<key)e.seen do. valid =. 0
        elseif. (key-:'node_budget')*.1 100000 valid_integer value do. Budget =: num value
        elseif. (key-:'min_score')*.1 100 valid_integer value do. Minimum =: num value
        elseif. (key-:'symmetry')*.(<value)e.('rot180';'mirror';'none') do. RequiredSymmetry =: value
        else. valid =. 0 end.
        if. -.valid do. 'bad option ',number index+1 return. end.
        seen =. seen,<key
    end.
    GridHeight =: #GridRows
    if. (GridHeight<3)+.GridHeight>15 do. 'bad height' return. end.
    GridWidth =: #0{::GridRows
    for_index. i.GridHeight do.
        row =. index{::GridRows
        if. ((#row)<3)+.((#row)>15)+.((#row)~:GridWidth)+.-.*./row e.'.#',Uppercase do.
            'bad row ',number index+1 return.
        end.
    end.
    GridCells =: ;GridRows
    if. -.RequiredSymmetry-:'none' do.
        cell =. asymmetric_cell RequiredSymmetry
        if. cell>:0 do. 'asymmetric at ',cell_location cell return. end.
    end.
    count =. component_count ''
    if. count~:1 do. 'disconnected components=',number count return. end.
    short =. find_short_run ''
    if. #short do. 'short slot at | |' format (<cell_location 0{::short),1{short return. end.
    build_layout ''
    orphan =. orphan_cell ''
    if. orphan>:0 do. 'orphan cell ',cell_location orphan return. end.
    InitialLetters =: GridCells
    InitialWords =: SlotCount$_1
    ThemeSlots =: 0$0
    for_index. i.#Themes do.
        theme =. index{::Themes
        word =. WordNames i.<theme
        if. word=#WordNames do. 'unknown theme ',number index+1 return. end.
        chosen =. _1
        for_slot. i.SlotCount do.
            if. (_1=slot{InitialWords)*.(#theme)=slot{SlotLengths do.
                if. theme matches InitialLetters state_pattern slot do. chosen =. slot break. end.
            end.
        end.
        if. chosen=_1 do. 'theme | does not fit' format <index+1 return. end.
        'letters words filled' =. ((<InitialLetters),<InitialWords)state_assign chosen,word
        InitialLetters =: letters
        InitialWords =: words
        ThemeSlots =: ThemeSlots,chosen
    end.
    ''
)
run_template =: 3 : 0
    minimum =. Minimum
    Attempts =: 0$a:
    while. 1 do.
        attempt =. ((<InitialLetters),<InitialWords)run_attempt minimum,Budget
        Attempts =: Attempts,<attempt
        outcome =. 0{::attempt
        if. (outcome-:'filled')+.(RelaxStep<1)+.minimum<:1 do. break. end.
        minimum =. 1>.minimum-RelaxStep
    end.
    FinalAttempt =: >{:Attempts
    Outcome =: 0{::FinalAttempt
    FinalMinimum =: 1{::FinalAttempt
    FinalLetters =: 11{::FinalAttempt
    FinalWords =: 12{::FinalAttempt
    ChosenClues =: SlotCount$<''
    for_across. 1 0 do.
        for_slot. I.SlotAcross=across do.
            word =. slot{FinalWords
            if. word>:0 do. ChosenClues =: (<choose_clue word)slot}ChosenClues end.
        end.
    end.
    i.0
)
entry_text =: 3 : 0
    word =. y{FinalWords
    (y{::SlotLabels),':',(word{::WordNames),':',number word{WordScores
)
grid_paragraph =: 3 : 0
    lines =. <'TEMPLATE ',TemplateName
    if. #y do. lines,<'error ',y return. end.
    lines =. lines,<'outcome=| attempts=| min_score=|' format (<Outcome),(<#Attempts),<FinalMinimum
    lines =. lines,(grid_lines FinalLetters),(<'numbers'),number_lines ''
    lines
)
clue_paragraph =: 3 : 0
    lines =. <'TEMPLATE ',TemplateName
    clued =. missing =. unfilled =. 0
    for_across. 1 0 do.
        slots =. I.SlotAcross=across
        if. #slots do.
            heading =. 'DOWN'
            if. across do. heading =. 'ACROSS' end.
            lines =. lines,<heading
        end.
        for_slot. slots do.
            word =. slot{FinalWords
            if. word=_1 do.
                unfilled =. unfilled+1
                pattern =. FinalLetters state_pattern slot
                lines =. lines,<slot list_line (<'(unfilled)'),(<pattern),(<'-'),<0
            else.
                clue =. slot{::ChosenClues
                if. 0=#clue do. missing =. missing+1
                    clue =. '(no clue)'
                else. clued =. clued+1 end.
                lines =. lines,<slot list_line (<clue),(word{WordNames),(<number word{WordScores),<slot e.ThemeSlots
            end.
        end.
    end.
    lines,<'clued=| missing=| unfilled=|' format (<clued),(<missing),<unfilled
)
worst_crossing =: 3 : 0
    worst =. _1
    worstsum =. 0
    for_cell. white_cells '' do.
        across =. cell{AcrossOwner
        down =. cell{DownOwner
        if. (across<0)+.down<0 do. continue. end.
        sum =. +/(across,down){FinalWords{WordScores
        if. (worst=_1)+.sum<worstsum do. worst =. cell
            worstsum =. sum end.
    end.
    if. worst=_1 do. '-' return. end.
    across =. worst{AcrossOwner
    down =. worst{DownOwner
    (cell_location worst),' ',(across{::SlotLabels),':',((across{FinalWords){::WordNames),'+',(down{::SlotLabels),':',((down{FinalWords){::WordNames),'=',number worstsum
)
stats_paragraph =: 3 : 0
    whites =. white_cells ''
    blocks =. (#GridCells)-#whites
    givens =. +/-.GridCells e.'.#'
    symmetries =. 0$a:
    for_symmetry. 'rot180';'mirror' do.
        if. _1=asymmetric_cell >symmetry do. symmetries =. symmetries,symmetry end.
    end.
    symmetrytext =. 'none'
    if. #symmetries do. symmetrytext =. ',' join symmetries end.
    lines =. <'TEMPLATE ',TemplateName
    lines =. lines,<'grid size=|x| blocks=| white=| density=| givens=| required=| symmetry=|' format (<GridWidth),(<GridHeight),(<blocks),(<#whites),(<((100*blocks),#GridCells)decimal 1),(<givens),(<RequiredSymmetry),<symmetrytext
    across =. +/SlotAcross
    lengths =. /:~~.SlotLengths
    lengthparts =. coverage =. 0$a:
    for_length. lengths do.
        lengthparts =. lengthparts,<(number length),':',number +/SlotLengths=length
        pool =. length{::ByLength
        count =. +/(pool{WordScores)>:Minimum
        coverage =. coverage,<(number length),':',number count
    end.
    unchecked =. +/1=owner_count whites
    lines =. lines,<'slots across=| down=| total=| lengths=| avg_length=| longest=| unchecked=|' format (<across),(<SlotCount-across),(<SlotCount),(<',' join lengthparts),(<((+/SlotLengths),SlotCount)decimal 2),(< >./SlotLengths),<unchecked
    if. #ThemeSlots do.
        parts =. 0$a:
        for_slot. i.SlotCount do. if. slot e.ThemeSlots do. parts =. parts,<entry_text slot end. end.
        lines =. lines,<'themes ',' ' join parts
    end.
    lines =. lines,<'coverage ',' ' join coverage
    tight =. 0 2$0
    for_slot. i.SlotCount do.
        if. slot e.ThemeSlots do. continue. end.
        available =. slot state_candidates (<InitialLetters),(<InitialWords),<Minimum
        tight =. tight,(#available),slot
    end.
    tight =. (3<.#tight){.(/:tight){tight
    parts =. 0$a:
    for_pair. tight do. parts =. parts,<((1{pair){::SlotLabels),':',number 0{pair end.
    lines =. lines,<'tightest ',' ' joined parts
    for_attempt. i.#Attempts do.
        result =. attempt{::Attempts
        lines =. lines,<'attempt | min_score=| budget=| outcome=| nodes=| backtracks=| prunes=| dead_ends=| max_depth=|' format (<attempt+1),(1{result),(2{result),(0{result),(3{result),(4{result),(5{result),(6{result),7{result
    end.
    lines =. lines,<'trace ',' ' joined 10{::FinalAttempt
    failures =. 9{::FinalAttempt
    failed =. I.failures>:1
    failed =. (3<.#failed){.failed{~/: (-(failed{failures)),.failed
    parts =. 0$a:
    for_slot. failed do. parts =. parts,<(slot{::SlotLabels),':',number slot{failures end.
    lines =. lines,<'hotspots ',' ' joined parts
    if. Outcome-:'filled' do.
        order =. (8{::FinalAttempt){SlotLabels
        lines =. lines,<'order ',' ' joined order
        scores =. FinalWords{WordScores
        total =. +/scores
        weakest =. scores i.<./scores
        weak =. 0$a:
        for_slot. I.scores<WeakScore do. weak =. weak,<entry_text slot end.
        lines =. lines,<'quality total=| average=| weakest=| weak=|' format (<total),(<(total,SlotCount)decimal 2),(<entry_text weakest),<',' joined weak
        letters =. whites{FinalLetters
        distinct =. ~.letters
        missing =. Uppercase#~-.Uppercase e.distinct
        missingtext =. missing
        pangram =. 'no'
        if. 0=#missing do. missingtext =. '-'
            pangram =. 'yes' end.
        points =. +/(Uppercase i.letters){LetterPoints
        lines =. lines,<'letters distinct=| pangram=| missing=| scrabble=| worst_crossing=|' format (<#distinct),(<pangram),(<missingtext),(<(points,#letters)decimal 2),<worst_crossing ''
    else.
        assigned =. +/FinalWords>:0
        lettered =. +/'.'~:whites{FinalLetters
        blocked =. 0$a:
        for_slot. I.FinalWords=_1 do.
            available =. slot state_candidates (<FinalLetters),(<FinalWords),<FinalMinimum
            if. 0=#available do. blocked =. blocked,slot{SlotLabels end.
        end.
        lines =. lines,<'partial assigned=|/| letters=|/| blocked=|' format (<assigned),(<SlotCount),(<lettered),(<#whites),<',' joined blocked
    end.
    lines
)
wordlist_report =: 3 : 0
    lines =. <'WORDLIST lines=| valid=| invalid=| duplicates=|' format (<WordLineCount),(<#WordNames),(<#WordInvalid),<#WordDuplicates
    lines =. lines,WordInvalid,WordDuplicates
    for_length. 3+i.13 do.
        pool =. length{::ByLength
        if. 0=#pool do. continue. end.
        total =. +/pool{WordScores
        best =. {.pool
        lines =. lines,<'length | words=| average=| best=|:|' format (<length),(<#pool),(<(total,#pool)decimal 2),(best{WordNames),<best{WordScores
    end.
    parts =. 0$a:
    for_low. 1+20*i.5 do.
        count =. +/(WordScores>:low)*.WordScores<:low+19
        parts =. parts,<'|-|=|' format (<low),(<low+19),<count
    end.
    lines =. lines,<'bands ',' ' join parts
    parts =. 0$a:
    for_word. i.5<.#WordNames do. parts =. parts,<(word{::WordNames),':',number word{WordScores end.
    lines =. lines,<'top ',' ' join parts
    counts =. 0$0
    for_letter. Uppercase do.
        count =. 0
        for_word. WordNames do. count =. count+letter e.>word end.
        counts =. counts,count
    end.
    order =. 5{./:counts,.i.26
    parts =. 0$a:
    for_letter. order do. parts =. parts,<((letter{Uppercase),':'),number letter{counts end.
    lines =. lines,<'rare_letters ',' ' join parts
    wordswithclues =. +/0<#&>ClueTexts
    lines =. lines,<'CLUES entries=| valid=| invalid=| unknown=| words=|' format (<ClueEntries),(<ClueAdded),(<#ClueInvalid),(<#ClueUnknown),<wordswithclues
    lines =. lines,ClueInvalid,ClueUnknown
    uses =. ;ClueUses
    lines =. lines,<'CLUE_USE used=| unused=| repeated=|' format (<+/uses>:1),(<+/uses=0),<+/uses>:2
    for_word. ascii_order WordNames do.
        counts =. word{::ClueUses
        for_clue. I.counts>:2 do.
            lines =. lines,<'repeated | clue=| uses=|' format (word{WordNames),(<clue+1),<clue{counts
        end.
    end.
    lines
)
ranking_paragraph =: 3 : 0
    order =. 0$0
    for_index. i.#FilledTemplates do.
        entry =. index{::FilledTemplates
        position =. #order
        for_prior. i.#order do.
            other =. (prior{order){::FilledTemplates
            left =. (1{::entry)*2{::other
            right =. (1{::other)*2{::entry
            if. (left>right)+.(left=right)*.(0{::entry)ascii_less 0{::other do. position =. prior break. end.
        end.
        order =. (position{.order),index,position}.order
    end.
    lines =. <'RANKING'
    for_rank. i.#order do.
        'name total count words' =. (rank{order){::FilledTemplates
        lines =. lines,<'rank | | average=| total=| entries=|' format (<rank+1),(<name),(<(total,count)decimal 2),(<total),<count
    end.
    lines
)
reuse_paragraph =: 3 : 0
    appearances =. (#WordNames)$<0$a:
    for_template. FilledTemplates do.
        'name total count words' =. >template
        for_word. words do. appearances =. (<(word{::appearances),<name)word}appearances end.
    end.
    counts =. #&>appearances
    reused =. I.counts>:2
    alphabetical =. /:ascii_order WordNames
    reused =. reused{~/: (-(reused{counts)),.reused{alphabetical
    lines =. <'REUSE'
    for_word. reused do.
        lines =. lines,<'reused | | |' format (word{WordNames),(<word{counts),<',' join word{::appearances
    end.
    lines
)
write_lines =: 4 : 0
    text =. ''
    if. #y do. text =. (LF join y),LF end.
    text 1!:2 <'output/',x
    i.0
)
paragraph_lines =: 3 : 0
    lines =. 0$a:
    for_paragraph. y do.
        if. #lines do. lines =. lines,<'' end.
        lines =. lines,>paragraph
    end.
    lines
)
main =: 3 : 0
    read_settings ''
    read_wordlist ''
    read_clues ''
    blocks =. read_blocks ''
    EarlierNames =: FilledTemplates =: 0$a:
    grids =. clues =. stats =. 0$a:
    invalid =. filled =. unfillable =. budget =. attempts =. nodes =. 0
    for_block. blocks do.
        error =. check_template >block
        EarlierNames =: EarlierNames,<TemplateName
        if. #error do.
            invalid =. invalid+1
            grids =. grids,<grid_paragraph error
            continue.
        end.
        run_template ''
        grids =. grids,<grid_paragraph ''
        clues =. clues,<clue_paragraph ''
        stats =. stats,<stats_paragraph ''
        attempts =. attempts+#Attempts
        for_attempt. Attempts do. nodes =. nodes+3{::>attempt end.
        if. Outcome-:'filled' do.
            filled =. filled+1
            total =. +/FinalWords{WordScores
            FilledTemplates =: FilledTemplates,<(<TemplateName),(<total),(<SlotCount),<FinalWords
        elseif. Outcome-:'budget' do. budget =. budget+1
        else. unfillable =. unfillable+1 end.
    end.
    stats =. stats,(<ranking_paragraph ''),<reuse_paragraph ''
    summary =. 'SUMMARY templates=| invalid=| filled=| unfillable=| budget=| attempts=| nodes=|' format (<#blocks),(<invalid),(<filled),(<unfillable),(<budget),(<attempts),<nodes
    stats =. stats,<<summary
    1!:5 ::0: <'output'
    'grid.txt' write_lines paragraph_lines grids
    'clues.txt' write_lines paragraph_lines clues
    'search_stats.txt' write_lines paragraph_lines stats
    'wordlist.txt' write_lines wordlist_report ''
    i.0
)
main ''
