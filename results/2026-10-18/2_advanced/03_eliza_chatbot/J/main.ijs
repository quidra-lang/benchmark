ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
Lowercase =: 'abcdefghijklmnopqrstuvwxyz'
div =: 4 : '<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
number =: 3 : 0
    value =. y
    text =. ''
    while. value>0 do.
        text =. ((10|value){Digits),text
        value =. value div 10
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
words_of =: 3 : 0
    parts =. ' ' split y
    parts#~0<#&>parts
)
read_lines =: 3 : '<;._2 (1!:1 <y)'
empty_table =: 3 : '0 2$a:'
table_keys =: 3 : '0{"1 y'
has_key =: 4 : '(<x)e.table_keys y'
get_key =: 4 : '((table_keys y)i.<x){::1{"1 y'
put_key =: 4 : 0
    'key value' =. x
    position =. (table_keys y)i.<key
    if. position<#y do. (<value) (<position,1)}y
    else. y,1 2$(<key),<value end.
)
load SourceDirectory,'script_loader.ijs'
load SourceDirectory,'matcher.ijs'
load SourceDirectory,'linter.ijs'
load SourceDirectory,'responder.ijs'
load SourceDirectory,'memory.ijs'

Sources =: ;:'keyword memory question default repeat'
NoArgumentCommands =: ' ' split ':keys :why :history :memory :forget :reset :unused :stats :undo'
TextCommands =: ' ' split ':prepare :reflect :say :explain'
SingleArgumentCommands =: ' ' split ':groups :find :script :cycles :coverage'
KeywordCommands =: ' ' split ':script :cycles :coverage :test'
Commands =: NoArgumentCommands,TextCommands,SingleArgumentCommands,' ' split ':trace :test'

normalize =: 3 : 0
    text =. tolower y
    text =. LF (I.text e.',.?!;')}text
    clauses =. 0$a:
    for_box. LF split text do.
        part =. >box
        part =. ' ' (I.-.part e.Lowercase,Digits,'''')}part
        words =. 0$a:
        for_wordbox. words_of part do.
            word =. >wordbox
            while. #word do.
                if. ''''~:{.word do. break. end.
                word =. }.word
            end.
            while. #word do.
                if. ''''~:{:word do. break. end.
                word =. }:word
            end.
            if. #word do. words =. words,<word end.
        end.
        if. #words do. clauses =. clauses,<words end.
    end.
    clauses
)
all_words =: 3 : 0
    words =. 0$a:
    for_box. y do. words =. words,>box end.
    words
)
pre_substitute =: 3 : 0
    clauses =. 0$a:
    for_box. y do.
        words =. 0$a:
        for_wordbox. >box do.
            word =. >wordbox
            if. word has_key PreTable do. words =. words,word get_key PreTable
            else. words =. words,wordbox end.
        end.
        clauses =. clauses,<words
    end.
    clauses
)
prepared =: 3 : 'pre_substitute normalize y'
is_quit =: 3 : 0
    words =. all_words normalize y
    if. 1~:#words do. 0 return. end.
    (0{words)e.QuitWords
)
select_clause =: 3 : 0
    for_index. i.#y do.
        if. +./(index{::y)e.KeywordWords do. index return. end.
    end.
    _1
)
keyword_list =: 3 : 0
    ids =. ~.KeywordWords i.y
    ids =. ids#~ids<#Keywords
    ranks =. 0$0
    for_id. ids do. ranks =. ranks,1{::id{::Keywords end.
    (/: (-ranks),.i.#ids){ids
)
rule_entries =: 3 : 0
    entries =. 0$a:
    for_kind. i.2 do.
        ids =. (kind+3){::y
        label =. kind{::'memory';'decomp'
        for_index. i.#ids do. entries =. entries,<(<label),(<index+1),<index{ids end.
    end.
    entries
)
increment_count =: 4 : 0
    count =. 0
    if. x has_key y do. count =. x get_key y end.
    ((<x),<count+1) put_key y
)
cycle_reset =: 3 : 0
    RulePositions =: (#Rules)$0
    ListPositions =: 3$0
    i.0
)
take_text =: 3 : 0
    listindex =. (;:'DEFAULT QUESTION REPEAT')i.<y
    texts =. y get_key Texts
    position =. listindex{ListPositions
    ListPositions =: ((#texts)|position+1) listindex}ListPositions
    position{::texts
)
take_item =: 3 : 0
    items =. 3{::y{::Rules
    position =. y{RulePositions
    itemid =. position{items
    ItemUses =: (1+itemid{ItemUses) itemid}ItemUses
    RulePositions =: ((#items)|position+1) y}RulePositions
    (<position+1),<itemid{::Items
)
find_rule =: 4 : 0
    for_index. i.#x do.
        id =. index{x
        result =. (1{::id{::Rules) match_pattern y
        if. 0{::result do. (<1),(<index+1),(<id),<1{::result return. end.
    end.
    (<0),(<0),(<0),<0$a:
)
keyword_reply =: 3 : 0
    selected =. select_clause y
    if. selected=_1 do.
        DecisionTrace =: DecisionTrace,<'CLAUSE none'
        (<0),<'' return.
    end.
    original =. selected{::y
    keys =. keyword_list original
    labels =. 0$a:
    for_id. keys do. labels =. labels,0{id{::Keywords end.
    DecisionTrace =: DecisionTrace,<'CLAUSE ',(number selected+1),' ',' ' join original
    DecisionTrace =: DecisionTrace,<'KEYS ',' ' join labels
    keyword =. ({.keys){::Keywords
    found =. (3{::keyword) find_rule original
    if. 0{::found do.
        'matched rulenum ruleid bindings' =. found
        DecisionTrace =: DecisionTrace,<'MEMORY ',(0{::keyword),' ',number rulenum
        RuleHits =: (1+ruleid{RuleHits) ruleid}RuleHits
        if. #3{::ruleid{::Rules do.
            'itemnum item' =. take_item ruleid
            (0{::keyword) memory_store bindings build_reply 1{::item
        end.
    end.
    entered =. 0$0
    for_id. keys do.
        if. id e.entered do. continue. end.
        current =. id
        words =. original
        DecisionTrace =: DecisionTrace,<'ENTER ',0{::current{::Keywords
        while. 1 do.
            entered =. entered,current
            KeywordUses =: (1+current{KeywordUses) current}KeywordUses
            keyword =. current{::Keywords
            word =. 0{::keyword
            found =. (4{::keyword) find_rule words
            if. -.0{::found do.
                DecisionTrace =: DecisionTrace,<'NOMATCH ',word
                break.
            end.
            'matched rulenum ruleid bindings' =. found
            RuleHits =: (1+ruleid{RuleHits) ruleid}RuleHits
            if. 0=#3{::ruleid{::Rules do.
                DecisionTrace =: DecisionTrace,<'DECOMP ',word,' ',(number rulenum),' 0'
                break.
            end.
            'itemnum item' =. take_item ruleid
            DecisionTrace =: DecisionTrace,<'DECOMP ',word,' ',(number rulenum),' ',number itemnum
            'kind text args itemline' =. item
            if. kind-:'REASM' do.
                KeywordReplies =: (1+current{KeywordReplies) current}KeywordReplies
                Topics =: word increment_count Topics
                (<1),<bindings build_reply text return.
            elseif. kind-:'NEWKEY' do. break.
            end.
            target =. 0{::args
            targetid =. KeywordWords i.<target
            if. (targetid=#Keywords)+.targetid e.entered do.
                DecisionTrace =: DecisionTrace,<'BLOCKED ',target
                break.
            end.
            if. kind-:'RESTATE' do.
                words =. bindings restated_words }.args
                DecisionTrace =: DecisionTrace,<' ' join (<'RESTATE'),(<target),words
            else. DecisionTrace =: DecisionTrace,<'GOTO ',target end.
            current =. targetid
        end.
    end.
    (<0),<''
)
decide =: 3 : 0
    clauses =. normalize y
    DecisionTrace =: 0$a:
    repeated =. (0<#'REPEAT' get_key Texts)*.(0<#clauses)*.clauses-:Previous
    if. repeated do.
        DecisionTrace =: <'REPEAT'
        reply =. take_text 'REPEAT'
        source =. 4
    else.
        result =. keyword_reply pre_substitute clauses
        source =. 0
        if. 0{::result do. reply =. 1{::result
        elseif. #Memory do.
            reply =. memory_recall ''
            source =. 1
        elseif. ('?'={:y)*.0<#'QUESTION' get_key Texts do.
            reply =. take_text 'QUESTION'
            source =. 2
        else.
            reply =. take_text 'DEFAULT'
            source =. 3
        end.
    end.
    Previous =: clauses
    SourceCounts =: (1+source{SourceCounts) source}SourceCounts
    if. source e.2 3 do. Unrecognized =: Unrecognized,Turns end.
    DecisionTrace =: DecisionTrace,<'REPLY ',source{::Sources
    (<reply),<DecisionTrace
)
save_state =: 3 : 0
    saved =. (<RulePositions),(<RuleHits),(<ItemUses),(<KeywordUses),(<KeywordReplies),<ListPositions
    saved =. saved,(<Memory),(<MemoryLog),(<SessionName),(<Turns),(<SourceCounts),<Previous
    saved =. saved,(<History),(<LastTrace),(<TraceOn),(<Topics),(<WordCounts),(<StoreCount),(<RecallCount),<Unrecognized
    if. y do. saved,<UndoSnapshot else. saved,<0$a: end.
)
restore_state =: 3 : 0
    'RulePositions RuleHits ItemUses KeywordUses KeywordReplies ListPositions Memory MemoryLog SessionName Turns SourceCounts Previous History LastTrace TraceOn Topics WordCounts StoreCount RecallCount Unrecognized UndoSnapshot' =: y
    i.0
)
new_session =: 3 : 0
    SessionName =: y
    Turns =: StoreCount =: RecallCount =: TraceOn =: 0
    SourceCounts =: 5$0
    Previous =: History =: LastTrace =: UndoSnapshot =: 0$a:
    Unrecognized =: 0$0
    Topics =: WordCounts =: empty_table ''
    i.0
)
source_line =: 4 : 0
    parts =. 0$a:
    for_index. i.5 do. parts =. parts,<(index{::Sources),'=',number index{y end.
    'turns=',(number x),' ',' ' join parts
)
grouped_lines =: 4 : 0
    lines =. 0$a:
    while. #y do.
        lines =. lines,<' ' join (x<.#y){.y
        y =. x}.y
    end.
    lines
)
ranked_counts =: 3 : 0
    if. 0=#y do. 'none' return. end.
    keys =. table_keys y
    counts =. >1{"1 y
    order =. /:(-counts),./:/:keys
    order =. (5<.#order){.order
    parts =. 0$a:
    for_index. order do. parts =. parts,<(index{::keys),' ',number index{counts end.
    ', ' join parts
)
indent_lines =: 3 : 0
    lines =. 0$a:
    for_box. y do. lines =. lines,<'  ',>box end.
    lines
)
arguments_fit =: 4 : 0
    'text args' =. y
    if. (<x)e.NoArgumentCommands do. 0=#args
    elseif. (<x)e.TextCommands do. 0<#text
    elseif. (<x)e.SingleArgumentCommands do. 1=#args
    elseif. x-:':trace' do.
        if. 1~:#args do. 0 return. end.
        (0{args)e.;:'on off'
    else. 2<:#args end.
)
debug_command =: 3 : 0
    parts =. ' ' split y
    name =. 0{::parts
    args =. }.parts
    text =. ' ' join args
    if. -.(<name)e.Commands do. <'unknown command ',name return. end.
    if. -.name arguments_fit (<text),<args do. <'bad arguments' return. end.
    if. (<name)e.KeywordCommands do.
        if. -.(0{args)e.KeywordWords do. <'unknown keyword ',0{::args return. end.
        keyword =. (KeywordWords i.0{args){::Keywords
        entries =. rule_entries keyword
    end.
    select. name
    case. ':prepare' do.
        clauses =. prepared text
        output =. 0$a:
        for_index. i.#clauses do. output =. output,<'clause ',(number index+1),': ',' ' join index{::clauses end.
        if. 0=#clauses do. output =. <'no words' end.
        selected =. select_clause clauses
        if. selected=_1 do. output,<'selected none' return. end.
        labels =. 0$a:
        for_id. keyword_list selected{::clauses do.
            key =. id{::Keywords
            labels =. labels,<(0{::key),'/',number 1{::key
        end.
        output,(<'selected ',number selected+1),<'keys ',' ' join labels
    case. ':test' do.
        words =. all_words prepared ' ' join }.args
        output =. 0$a:
        for_box. entries do.
            'label index ruleid' =. >box
            result =. (1{::ruleid{::Rules) match_pattern words
            if. -.0{::result do. value =. 'no match'
            elseif. 0=#1{::result do. value =. 'match'
            else.
                bindings =. 0$a:
                for_bound. 1{::result do. bindings =. bindings,<'[',(' ' join >bound),']' end.
                value =. ' ' join bindings
            end.
            output =. output,<label,' ',(number index),': ',value
        end.
        if. #output do. output else. <'no rules' end.
    case. ':reflect' do.
        output =. 0$a:
        for_box. prepared text do. output =. output,<' ' join reflect_words >box end.
        if. #output do. output else. <'no words' end.
    case. ':keys' do.
        ranks =. 0$0
        for_box. Keywords do. ranks =. ranks,1{::>box end.
        order =. /:(-ranks),./:/:KeywordWords
        labels =. 0$a:
        for_index. order do. labels =. labels,<(index{::KeywordWords),'/',number index{ranks end.
        8 grouped_lines labels
    case. ':groups' do.
        found =. 0$a:
        for_box. Groups do.
            group =. >box
            if. (0{args)e.1{::group do. found =. found,0{group end.
        end.
        if. #found do. <' ' join /:~found else. <'none' end.
    case. ':find' do.
        word =. 0{::args
        output =. 0$a:
        if. (<word)e.KeywordWords do.
            key =. (KeywordWords i.<word){::Keywords
            output =. <'keyword rank ',number 1{::key
        end.
        for_kind. i.2 do.
            if. kind do. substitutions =. Posts
            else. substitutions =. Pres end.
            label =. kind{::'pre';'post'
            for_box. substitutions do.
                'source replacement line' =. >box
                if. (word-:source)+.(<word)e.replacement do.
                    output =. output,<label,' ',(number line),': ',source,' -> ',' ' join replacement
                end.
            end.
        end.
        for_box. Groups do.
            'group members line' =. >box
            if. (<word)e.members do. output =. output,<'group ',group,' line ',number line end.
        end.
        for_box. Keywords do.
            key =. >box
            for_entrybox. rule_entries key do.
                'label index ruleid' =. >entrybox
                if. (<word)e.1{::ruleid{::Rules do. output =. output,<'pattern ',(0{::key),' ',label,' ',number index end.
            end.
        end.
        if. (<word)e.StopWords do. output =. output,<'stop word' end.
        if. (<word)e.QuitWords do. output =. output,<'quit word' end.
        if. #output do. output else. <'not found' end.
    case. ':script' do.
        numbers =. ,2{::keyword
        for_box. entries do.
            rule =. (2{::>box){::Rules
            numbers =. numbers,2{::rule
            for_itemid. 3{::rule do. numbers =. numbers,3{::itemid{::Items end.
        end.
        output =. 0$a:
        for_line. /:~numbers do. output =. output,<(number line),' ',(line-1){::ScriptLines end.
        output
    case. ':why' do.
        if. #LastTrace do. LastTrace else. <'no reply yet' end.
    case. ':trace' do.
        TraceOn =: 'on'-:0{::args
        <'trace ',0{::args
    case. ':history' do.
        if. #History do. (-5<.#History){.History else. <'no turns yet' end.
    case. ':memory' do.
        output =. <'memory ',(number #Memory),'/',number Capacity
        for_index. i.#Memory do. output =. output,<(number index+1),': ',index{::Memory end.
        output
    case. ':forget' do.
        count =. #Memory
        memory_clear log_prefix ''
        <'forgot ',number count
    case. ':cycles';':coverage' do.
        output =. 0$a:
        for_box. entries do.
            'label index ruleid' =. >box
            itemids =. 3{::ruleid{::Rules
            if. name-:':cycles' do.
                if. #itemids do. value =. 'next ',(number 1+ruleid{RulePositions),'/',number #itemids
                else. value =. 'empty' end.
            else.
                uses =. '-'
                if. #itemids do. uses =. ' ' join number&.><"0 itemids{ItemUses end.
                value =. 'hits ',(number ruleid{RuleHits),' entries ',uses
            end.
            output =. output,<label,' ',(number index),': ',value
        end.
        if. #output do. output else. <'no rules' end.
    case. ':reset' do.
        cycle_reset ''
        <'cycles reset'
    case. ':unused' do.
        numbers =. 0$0
        for_index. I.ItemUses=0 do. numbers =. numbers,3{::index{::Items end.
        output =. <'unused ',number #numbers
        output,12 grouped_lines number&.><"0 /:~numbers
    case. ':stats' do. <Turns source_line SourceCounts
    case. ':undo' do.
        if. 0=#UndoSnapshot do. <'nothing to undo' return. end.
        restore_state UndoSnapshot
        <'undone turn ',number Turns+1
    case. ':say';':explain' do.
        if. is_quit text do. <'would quit' return. end.
        saved =. save_state 1
        result =. decide text
        restore_state saved
        if. name-:':say' do. <0{::result else. 1{::result end.
    end.
)
write_notes =: 3 : 0
    notes =. <Turns source_line SourceCounts
    notes =. notes,<'topics: ',ranked_counts Topics
    notes =. notes,<'words: ',ranked_counts WordCounts
    notes =. notes,<'memory: stored=',(number StoreCount),' recalled=',(number RecallCount),' pending=',number #Memory
    text =. 'none'
    if. #Unrecognized do. text =. ' ' join number&.><"0 Unrecognized end.
    notes =. notes,<'unrecognized: ',text
    Transcript =: Transcript,(<'NOTES ',SessionName),indent_lines notes
    TotalTurns =: TotalTurns+Turns
    TotalSources =: TotalSources+SourceCounts
    i.0
)
run_session =: 4 : 0
    'name lines' =. y
    if. x>0 do.
        Transcript =: Transcript,<''
        if. -.(<'cycles')e.Persist do. cycle_reset '' end.
        if. -.(<'memory')e.Persist do. memory_clear name,' 0' end.
    end.
    new_session name
    greetings =. 'INITIAL' get_key Texts
    Transcript =: Transcript,(<'SESSION ',name),eliza_lines ((#greetings)|x){::greetings
    for_box. lines do.
        line =. >box
        if. ':'={.line do.
            Transcript =: Transcript,<line
            output =. debug_command line
            Transcript =: Transcript,indent_lines output
            continue.
        end.
        Transcript =: Transcript,<'YOU: ',line
        if. is_quit line do.
            farewells =. 'FINAL' get_key Texts
            Transcript =: Transcript,eliza_lines ((#farewells)|x){::farewells
            break.
        end.
        UndoSnapshot =: save_state 0
        Turns =: Turns+1
        for_wordbox. all_words normalize line do.
            if. -.wordbox e.StopWords do. WordCounts =: (>wordbox) increment_count WordCounts end.
        end.
        History =: History,<(number Turns),': ',line
        result =. decide line
        Transcript =: Transcript,eliza_lines 0{::result
        LastTrace =: 1{::result
        if. TraceOn do. Transcript =: Transcript,indent_lines LastTrace end.
    end.
    write_notes ''
)
keyword_stats =: 3 : 0
    order =. /:(-KeywordUses),./:/:KeywordWords
    lines =. <'keyword,rank,uses,replies,decomposition_hits'
    for_index. order do.
        keyword =. index{::Keywords
        hits =. '-'
        ids =. 4{::keyword
        if. #ids do. hits =. '/' join number&.><"0 ids{RuleHits end.
        lines =. lines,<(0{::keyword),',',(number 1{::keyword),',',(number index{KeywordUses),',',(number index{KeywordReplies),',',hits
    end.
    lines
)
write_lines =: 4 : 0
    text =. ''
    for_box. y do. text =. text,(>box),LF end.
    text 1!:2 <x
    i.0
)
main =: 3 : 0
    load_script 'input/script.txt'
    lint_script ''
    lintlines =. <'OK'
    if. #Diagnostics do.
        lintlines =. 0$a:
        errors =. 0
        for_box. Diagnostics do.
            'line code message' =. >box
            lintlines =. lintlines,<(number line),' ',code,' ',message
            errors =. errors+(<code)e.ErrorCodes
        end.
        lintlines =. lintlines,<'TOTAL ',(number #Diagnostics),' errors=',(number errors),' warnings=',number (#Diagnostics)-errors
    end.
    cycle_reset ''
    RuleHits =: (#Rules)$0
    ItemUses =: (#Items)$0
    KeywordUses =: KeywordReplies =: (#Keywords)$0
    Memory =: MemoryLog =: Transcript =: 0$a:
    TotalTurns =: 0
    TotalSources =: 5$0
    sessions =. 0$a:
    name =. ''
    lines =. 0$a:
    for_box. read_lines 'input/dialogue.txt' do.
        line =. >box
        if. 'SESSION '-:(8<.#line){.line do.
            if. #name do. sessions =. sessions,<(<name),<lines end.
            name =. 8}.line
            lines =. 0$a:
        else. lines =. lines,box end.
    end.
    sessions =. sessions,<(<name),<lines
    for_index. i.#sessions do. index run_session index{::sessions end.
    Transcript =: Transcript,(<''),<'SUMMARY sessions=',(number #sessions),' ',TotalTurns source_line TotalSources
    1!:5 <'output'
    'output/lint.txt' write_lines lintlines
    'output/transcript.txt' write_lines Transcript
    'output/keyword_stats.csv' write_lines keyword_stats ''
    'output/memory_log.txt' write_lines MemoryLog
    i.0
)
main ''
