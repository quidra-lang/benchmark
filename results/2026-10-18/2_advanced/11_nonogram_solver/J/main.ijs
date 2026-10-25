ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
Lowercase =: 'abcdefghijklmnopqrstuvwxyz'
div =: 4 : '_1 x:<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
signed_num =: 3 : 0
    if. '-'={.y do. -num }.y else. num y end.
)
number =: 3 : 0
    if. y<0 do. '-',number -y return. end.
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
read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
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
record =: 4 : '('' '' split x),.y'
load SourceDirectory,'line_solver.ijs'
load SourceDirectory,'clues.ijs'
load SourceDirectory,'propagation.ijs'
load SourceDirectory,'search.ijs'
load SourceDirectory,'render.ijs'
text_line =: 3 : 0
    fields =. 0$a:
    for_box. y do.
        value =. >box
        if. 2~:3!:0 value do. value =. number value end.
        fields =. fields,<value
    end.
    ' ' join fields
)
kv =: 4 : 0
    if. 2~:3!:0 y do. y =. number y end.
    x,'=',y
)
valid_name =: 3 : '((1<:#y)*.(#y)<:20)*.*./y e.Lowercase,Digits,''_'''
number_list =: 3 : 0
    if. #y do. ',' join number&.><"0 y else. '-' end.
)
cell_text =: 3 : '(number 1+{.y),'','',number 1+{:y'
read_blocks =: 3 : 0
    blocks =. block =. 0$a:
    active =. 0
    for_box. read_lines y do.
        line =. >box
        if. -.active do.
            if. #line do.
                if. '#'~:{.line do. block =. <line
                    active =. 1 end.
            end.
        elseif. line-:'END' do.
            blocks =. blocks,<block
            block =. 0$a:
            active =. 0
        else. block =. block,<line end.
    end.
    blocks
)
join_paragraphs =: 3 : 0
    lines =. 0$a:
    for_box. y do.
        if. #lines do. lines =. lines,<'' end.
        lines =. lines,>box
    end.
    lines
)
parse_puzzle =: 3 : 0
    lines =. y
    name =. 7}.0{::lines
    size =. num&>}. ' ' split 1{::lines
    at =. lines i.<'COLUMNS'
    rows =. (at-3){.3}.lines
    columns =. givens =. 0$a:
    position =. at+1
    while. position<#lines do.
        line =. position{::lines
        if. -.is_clue_line line do. break. end.
        columns =. columns,<line
        position =. position+1
    end.
    while. position<#lines do.
        line =. position{::lines
        if. -.'GIVEN '-:6{.line do. break. end.
        fields =. ' ' split line
        givens =. givens,<(<num 1{::fields),(<num 2{::fields),3{fields
        position =. position+1
    end.
    hasanswer =. position<#lines
    answer =. (position+1)}.lines
    'name width height row_lines column_lines given_lines has_answer answer_lines row_clues column_clues givens answer error' record (<name),(<0{size),(<1{size),(<rows),(<columns),(<givens),(<hasanswer),(<answer),(<0$a:),(<0$a:),(<0 3$0),(<0 0$0),<''
)
invalid =: 4 : '((<''error''),<x) put_key y'
validate_puzzle =: 4 : 0
    earlier =. x
    block =. y
    name =. 'name' get_key block
    width =. 'width' get_key block
    height =. 'height' get_key block
    if. -.valid_name name do. 'bad name' invalid block return. end.
    if. (<name)e.earlier do. 'duplicate name' invalid block return. end.
    if. (width<1)+.(width>30)+.(height<1)+.height>30 do. 'bad size' invalid block return. end.
    rowlines =. 'row_lines' get_key block
    columnlines =. 'column_lines' get_key block
    if. height~:#rowlines do. ('row count ',(number #rowlines),' expected ',number height) invalid block return. end.
    if. width~:#columnlines do. ('column count ',(number #columnlines),' expected ',number width) invalid block return. end.
    rows =. columns =. 0$a:
    for_row. 1 0 do.
        if. row do. texts =. rowlines
            kind =. 'row'
            length =. width
        else. texts =. columnlines
            kind =. 'column'
            length =. height end.
        clues =. 0$a:
        for_index. i.#texts do.
            clue =. parse_clue index{::texts
            if. clue-:_1 do. ('bad clue ',kind,' ',number index+1) invalid block return. end.
            if. -.clue clue_fits length do. (kind,' ',(number index+1),' too long') invalid block return. end.
            clues =. clues,<clue
        end.
        if. row do. rows =. clues else. columns =. clues end.
    end.
    rowtotal =. +/;rows
    columntotal =. +/;columns
    if. rowtotal~:columntotal do. ('total mismatch rows=',(number rowtotal),' columns=',number columntotal) invalid block return. end.
    givens =. 0 3$0
    rawgivens =. 'given_lines' get_key block
    for_index. i.#rawgivens do.
        'row column value' =. index{::rawgivens
        if. (row<1)+.(row>height)+.(column<1)+.(column>width)+.-.value e.'#.' do. ('bad given ',number index+1) invalid block return. end.
        row =. row-1
        column =. column-1
        if. +./*./"1 (row,column)="1 (0 1){"1 givens do. ('duplicate given ',number index+1) invalid block return. end.
        givens =. givens,row,column,char_state value
    end.
    answer =. 0 0$0
    if. 'has_answer' get_key block do.
        texts =. 'answer_lines' get_key block
        if. height~:#texts do. 'bad answer' invalid block return. end.
        for_box. texts do.
            text =. >box
            if. (width~:#text)+.-.*./text e.'#.?' do. 'bad answer' invalid block return. end.
        end.
        answer =. state_grid texts
    end.
    block =. ((<'row_clues'),<rows) put_key block
    block =. ((<'column_clues'),<columns) put_key block
    block =. ((<'givens'),<givens) put_key block
    ((<'answer'),<answer) put_key block
)
logical_solve =: 3 : 0
    'rows columns givens precise' =. y
    height =. #rows
    width =. #columns
    grid =. (height,width)$Unknown
    for_given. givens do. grid =. (2{given) (<2{.given)}grid end.
    propagate (<grid),(<rows),(<columns),(<precise),(<height$1),<width$1
)
solving_result =: 3 : 0
    conflict =. 'conflict' get_key y
    if. #conflict do. 'contradiction at=',('row' get_key conflict) line_label 'index' get_key conflict return. end.
    grid =. 'grid' get_key y
    if. (determined_count grid)=*/$grid do. 'solved' else. 'stuck' end.
)
analyze =: 3 : 0
    'rows columns givens' =. y
    simple =. logical_solve (<rows),(<columns),(<givens),<0
    logic =. logical_solve (<rows),(<columns),(<givens),<1
    simpleresult =. solving_result simple
    logicresult =. solving_result logic
    search =. empty_table ''
    solutions =. 0$a:
    difficulty =. '-'
    if. #'conflict' get_key logic do. status =. 'contradiction'
    elseif. logicresult-:'solved' do.
        status =. 'unique'
        solutions =. <'grid' get_key logic
        if. simpleresult-:'solved' do. difficulty =. 'easy' else. difficulty =. 'medium' end.
    else.
        search =. search_grid (<'grid' get_key logic),(<rows),<columns
        solutions =. 'solutions' get_key search
        status =. (#solutions){::'none';'unique';'multiple'
        if. status-:'unique' do. difficulty =. 'hard' end.
    end.
    solves =. #'steps' get_key logic
    guesses =. depth =. 0
    if. #search do.
        solves =. solves+'line_solves' get_key search
        guesses =. #'guesses' get_key search
        depth =. 'max_depth' get_key search
    end.
    'simple logic simple_result logic_result search solutions status difficulty line_solves guesses max_depth' record (<simple),(<logic),(<simpleresult),(<logicresult),(<search),(<solutions),(<status),(<difficulty),(<solves),(<guesses),<depth
)
clue_statistics =: 3 : 0
    'rows columns' =. y
    rowblocks =. columnblocks =. filled =. maximum =. fixed =. 0
    for_box. rows do.
        clue =. >box
        rowblocks =. rowblocks+#clue
        filled =. filled++/clue
        fixed =. fixed+((0=#clue)+.(clue_span clue)=#columns)
    end.
    for_box. columns do.
        clue =. >box
        columnblocks =. columnblocks+#clue
        fixed =. fixed+((0=#clue)+.(clue_span clue)=#rows)
    end.
    for_box. rows,columns do. if. #>box do. maximum =. maximum>.>./>box end. end.
    text_line (<'row_blocks' kv rowblocks),(<'column_blocks' kv columnblocks),(<'filled' kv filled),(<'max_block' kv maximum),<'fixed_lines' kv fixed
)
step_statistics =: 3 : 0
    productive =. idle =. best =. 0
    at =. '-'
    for_box. 'steps' get_key y do.
        step =. >box
        if. 'contradiction' get_key step do. continue. end.
        gain =. 'gain' get_key step
        if. gain>0 do. productive =. productive+1 else. idle =. idle+1 end.
        if. gain>best do. best =. gain
            at =. ('row' get_key step) line_label 'index' get_key step end.
    end.
    text_line (<'productive' kv productive),(<'idle' kv idle),(<'best' kv best),<'at' kv at
)
differing_cells =: 4 : 0
    'height width' =. $x
    cells =. 0 2$0
    for_row. i.height do.
        for_column. i.width do.
            if. ((<row,column){x)~:(<row,column){y do. cells =. cells,row,column end.
        end.
    end.
    cells
)
features_text =: 3 : 0
    grid =. y
    'height width' =. $grid
    seen =. (height,width)$0
    sizes =. 0$0
    for_row. i.height do.
        for_column. i.width do.
            if. (Filled~:(<row,column){grid)+.(<row,column){seen do. continue. end.
            seen =. 1 (<row,column)}seen
            pending =. 1 2$row,column
            size =. 0
            while. #pending do.
                cell =. {:pending
                pending =. }:pending
                size =. size+1
                for_delta. 4 2$_1 0 1 0 0 _1 0 1 do.
                    'r c' =. cell+delta
                    if. (r<0)+.(r>:height)+.(c<0)+.c>:width do. continue. end.
                    if. (Filled=(<r,c){grid)*.-.(<r,c){seen do.
                        seen =. 1 (<r,c)}seen
                        pending =. pending,r,c
                    end.
                end.
            end.
            sizes =. sizes,size
        end.
    end.
    filledrows =. I.+./"1 grid=Filled
    filledcolumns =. I.+./grid=Filled
    bbox =. '-'
    if. #filledrows do. bbox =. ',' join number&.><"0 1+({.filledrows),({.filledcolumns),({:filledrows),{:filledcolumns end.
    symmetries =. 0$a:
    if. grid-:|."1 grid do. symmetries =. symmetries,<'lr' end.
    if. grid-:|.grid do. symmetries =. symmetries,<'ud' end.
    if. grid-:|.|."1 grid do. symmetries =. symmetries,<'rot180' end.
    symmetry =. 'none'
    if. #symmetries do. symmetry =. ',' join symmetries end.
    largest =. 0
    if. #sizes do. largest =. >./sizes end.
    text_line (<'filled' kv +/,grid=Filled),(<'components' kv #sizes),(<'largest' kv largest),(<'bbox' kv bbox),<'symmetry' kv symmetry
)
unknown_summary =: 4 : 0
    if. x do. counts =. +/"1 y=Unknown else. counts =. +/y=Unknown end.
    parts =. 0$a:
    for_index. I.counts>0 do. parts =. parts,<(number index+1),':',number index{counts end.
    ' ' join parts
)
evaluate_givens =: 3 : 0
    'block analysis' =. y
    givens =. 'givens' get_key block
    status =. 'status' get_key analysis
    if. (0=#givens)+.status-:'multiple' do. 0$a: return. end.
    if. status-:'unique' do. label =. 'redundant'
        accepted =. <'unique'
    else. label =. 'blame'
        accepted =. 'unique';'multiple' end.
    numbers =. 0$0
    for_index. i.#givens do.
        others =. givens#~index~:i.#givens
        trial =. analyze (<'row_clues' get_key block),(<'column_clues' get_key block),<others
        if. (<'status' get_key trial)e.accepted do. numbers =. numbers,index+1 end.
    end.
    <'givens ',label,'=',number_list numbers
)
grade_answer =: 3 : 0
    'block analysis' =. y
    answer =. 'answer' get_key block
    rowclues =. 'row_clues' get_key block
    columnclues =. 'column_clues' get_key block
    givens =. 'givens' get_key block
    'height width' =. $answer
    rows =. columns =. badgivens =. 0$0
    for_row. i.height do. if. -. (row{answer) has_placement row{::rowclues do. rows =. rows,row end. end.
    for_column. i.width do. if. -. (column{"1 answer) has_placement column{::columnclues do. columns =. columns,column end. end.
    for_index. i.#givens do.
        'row column state' =. index{givens
        value =. (<row,column){answer
        if. (value~:Unknown)*.value~:state do. badgivens =. badgivens,index+1 end.
    end.
    known =. determined_count answer
    mismatched =. 0<(#rows)+(#columns)+#badgivens
    if. known<height*width do. result =. 'partial'
    elseif. mismatched do. result =. 'wrong'
    else. result =. 'correct' end.
    fields =. (<'answer'),(<'result' kv result),(<'known' kv known),(<'rows' kv number_list rows+1),(<'columns' kv number_list columns+1),<'givens' kv number_list badgivens
    if. result-:'partial' do.
        extendable =. 'no'
        if. -.mismatched do.
            extra =. givens
            taken =. (height,width)$0
            for_given. givens do. taken =. 1 (<2{.given)}taken end.
            for_row. i.height do.
                for_column. i.width do.
                    state =. (<row,column){answer
                    if. (state~:Unknown)*.-.(<row,column){taken do. extra =. extra,row,column,state end.
                end.
            end.
            trial =. analyze (<rowclues),(<columnclues),<extra
            if. (<'status' get_key trial)e.'unique';'multiple' do. extendable =. 'yes' end.
        end.
        fields =. fields,<'extendable' kv extendable
    end.
    if. ('status' get_key analysis)-:'unique' do.
        solution =. 0{::'solutions' get_key analysis
        fields =. fields,<'differs' kv +/,(answer~:Unknown)*.answer~:solution
    end.
    lines =. <text_line fields
    for_isrow. 1 0 do.
        if. isrow do. indices =. rows
            clues =. rowclues
        else. indices =. columns
            clues =. columnclues end.
        for_index. indices do.
            cells =. line_cells (<answer),(<isrow),<index
            fields =. (<'mismatch'),(<isrow line_label index),<'expected' kv ',' clue_text index{::clues
            if. result-:'partial' do. fields =. fields,<'cells' kv state_string cells
            else. fields =. fields,<'got' kv ',' clue_text run_clue cells end.
            lines =. lines,<text_line fields
        end.
    end.
    'result lines' record (<result),<lines
)
puzzle_report =: 3 : 0
    block =. y
    rows =. 'row_clues' get_key block
    columns =. 'column_clues' get_key block
    givens =. 'givens' get_key block
    width =. 'width' get_key block
    height =. 'height' get_key block
    analysis =. analyze (<rows),(<columns),<givens
    simple =. 'simple' get_key analysis
    logic =. 'logic' get_key analysis
    simplegrid =. 'grid' get_key simple
    logicgrid =. 'grid' get_key logic
    status =. 'status' get_key analysis
    difficulty =. 'difficulty' get_key analysis
    simpleresult =. 'simple_result' get_key analysis
    logicresult =. 'logic_result' get_key analysis
    solutions =. 'solutions' get_key analysis
    grading =. empty_table ''
    if. 'has_answer' get_key block do. grading =. grade_answer (<block),<analysis end.
    lines =. <'PUZZLE ','name' get_key block
    fields =. (<'size' kv (number width),'x',number height),(<'givens' kv #givens),(<'status' kv status),<'difficulty' kv difficulty
    lines =. lines,(<text_line fields),<'clues ',clue_statistics (<rows),<columns
    fields =. (<'simple'),(<'known' kv determined_count simplegrid),(<'line_solves' kv #'steps' get_key simple),<'result' kv simpleresult
    lines =. lines,<text_line fields
    fields =. (<'logic'),(<'known' kv determined_count logicgrid),(<'line_solves' kv #'steps' get_key logic),<'result' kv logicresult
    lines =. lines,(<text_line fields),<'steps ',step_statistics logic
    if. (width*height)<:49 do.
        trace =. 0$a:
        for_box. 'steps' get_key logic do. trace =. trace,<step_text >box end.
        lines =. lines,<'trace ',' ' join trace
    end.
    if. logicresult-:'stuck' do. lines =. lines,<'stuck rows=',(1 unknown_summary logicgrid),' columns=',0 unknown_summary logicgrid end.
    if. status-:'contradiction' do.
        conflict =. 'conflict' get_key logic
        row =. 'row' get_key conflict
        index =. 'index' get_key conflict
        if. row do. clue =. index{::rows else. clue =. index{::columns end.
        cells =. line_cells (<logicgrid),(<row),<index
        fields =. (<'conflict'),(<'line' kv row line_label index),(<'clue' kv ',' clue_text clue),<'cells' kv state_string cells
        lines =. lines,<text_line fields
    end.
    search =. 'search' get_key analysis
    if. #search do.
        guesses =. 'guesses' get_key search
        fields =. (<'search'),(<'guesses' kv #guesses),(<'max_depth' kv 'max_depth' get_key search),(<'backtracks' kv 'backtracks' get_key search),(<'solutions' kv #solutions),<'line_solves' kv 'line_solves' get_key search
        lines =. lines,<text_line fields
        for_box. guesses do.
            guess =. >box
            cell =. ('row' get_key guess),'column' get_key guess
            fields =. (<'guess'),(<'number' get_key guess),(<'depth' kv 'depth' get_key guess),(<'cell' kv cell_text cell),(<'value' kv state_char 'value' get_key guess),(<'solves' kv 'solves' get_key guess),(<'known' kv 'known' get_key guess),<'result' kv 'result' get_key guess
            lines =. lines,<text_line fields
        end.
    end.
    if. status-:'multiple' do.
        cells =. (0{::solutions) differing_cells 1{::solutions
        listed =. 0$a:
        for_cell. cells do. listed =. listed,<cell_text cell end.
        lines =. lines,<text_line (<'differ'),(<'count' kv #cells),<'cells' kv ' ' join listed
    end.
    names =. grids =. 0$a:
    if. status-:'contradiction' do. names =. <'partial'
        grids =. <logicgrid
    else.
        if. simpleresult-:'stuck' do. names =. names,<'simple'
            grids =. grids,<simplegrid end.
        if. logicresult-:'stuck' do. names =. names,<'logic'
            grids =. grids,<logicgrid end.
        if. status-:'multiple' do. names =. names,'first';'second'
            grids =. grids,solutions end.
    end.
    if. #names do. lines =. lines,grid_display (<names),<grids end.
    if. status-:'unique' do.
        solution =. 0{::solutions
        lines =. lines,(<'sheet'),(answer_sheet (<rows),(<columns),<solution),<'picture ',features_text solution
    end.
    lines =. lines,evaluate_givens (<block),<analysis
    answerresult =. '-'
    if. #grading do. lines =. lines,'lines' get_key grading
        answerresult =. 'result' get_key grading end.
    solves =. 'line_solves' get_key analysis
    guesses =. 'guesses' get_key analysis
    fields =. (<'name' get_key block),(<status),(<difficulty),(<number width),(<number height),(<number #givens),(<number determined_count simplegrid),(<number determined_count logicgrid),(<number solves),(<number guesses),(<number 'max_depth' get_key analysis),(<number #solutions),<answerresult
    'block analysis lines stats score' record (<block),(<analysis),(<lines),(<',' join fields),<solves+25*guesses
)
write_lines =: 4 : 0
    ((LF join y),LF#~0<#y) 1!:2 <'output/',x
    i.0
)
process_puzzles =: 3 : 0
    names =. reports =. paragraphs =. 0$a:
    stats =. <'puzzle,status,difficulty,width,height,givens,simple_known,logic_known,line_solves,guesses,max_depth,solutions,answer'
    blocks =. y
    for_box. blocks do.
        block =. names validate_puzzle parse_puzzle >box
        name =. 'name' get_key block
        names =. names,<name
        error =. 'error' get_key block
        if. #error do.
            paragraphs =. paragraphs,< (<'PUZZLE ',name),<'error ',error
            stats =. stats,<name,',invalid',;11#<',-'
            continue.
        end.
        report =. puzzle_report block
        reports =. reports,<report
        paragraphs =. paragraphs,<'lines' get_key report
        stats =. stats,<'stats' get_key report
    end.
    ranked =. 0$a:
    keys =. 0 3$a:
    statuses =. difficulties =. 0$a:
    solves =. guesses =. 0
    for_box. reports do.
        report =. >box
        analysis =. 'analysis' get_key report
        status =. 'status' get_key analysis
        difficulty =. 'difficulty' get_key analysis
        statuses =. statuses,<status
        difficulties =. difficulties,<difficulty
        solves =. solves+'line_solves' get_key analysis
        guesses =. guesses+'guesses' get_key analysis
        if. status-:'unique' do.
            ranked =. ranked,<report
            level =. ('easy';'medium';'hard') i.<difficulty
            name =. 'name' get_key 'block' get_key report
            keys =. keys,1 3$(<level),(<'score' get_key report),<name
        end.
    end.
    ranked =. (/:keys){ranked
    ranking =. <'RANKING'
    for_index. i.#ranked do.
        report =. index{::ranked
        block =. 'block' get_key report
        analysis =. 'analysis' get_key report
        size =. (number 'width' get_key block),'x',number 'height' get_key block
        ranking =. ranking,<text_line (<'rank'),(<index+1),(<'name' get_key block),(<'difficulty' get_key analysis),(<'score' kv 'score' get_key report),<'size' kv size
    end.
    fields =. (<'SUMMARY'),(<'puzzles' kv #blocks),(<'invalid' kv (#blocks)-#reports),(<'contradiction' kv +/statuses=<'contradiction'),(<'none' kv +/statuses=<'none'),(<'unique' kv +/statuses=<'unique'),(<'multiple' kv +/statuses=<'multiple'),(<'easy' kv +/difficulties=<'easy'),(<'medium' kv +/difficulties=<'medium'),(<'hard' kv +/difficulties=<'hard'),(<'line_solves' kv solves),<'guesses' kv guesses
    paragraphs =. paragraphs,(<ranking),<<text_line fields
    'solutions.txt' write_lines join_paragraphs paragraphs
    'stats.csv' write_lines stats
    reports
)
validate_picture =: 3 : 0
    'name rows earlier' =. y
    if. -.valid_name name do. 'bad name' return. end.
    if. (<name)e.earlier do. 'duplicate name' return. end.
    if. ((#rows)<1)+.(#rows)>30 do. 'bad height' return. end.
    width =. #0{::rows
    for_index. i.#rows do.
        row =. index{::rows
        if. ((#row)<1)+.((#row)>30)+.(width~:#row)+.-.*./row e.'#.' do. 'bad row ',number index+1 return. end.
    end.
    ''
)
generate_puzzle =: 3 : 0
    grid =. y
    rows =. columns =. 0$a:
    for_row. grid do. rows =. rows,<run_clue row end.
    for_column. |:grid do. columns =. columns,<run_clue column end.
    givens =. 0 3$0
    log =. 0$a:
    initial =. latest =. analyze (<rows),(<columns),<givens
    while. ('status' get_key latest)-:'multiple' do.
        solutions =. 'solutions' get_key latest
        cell =. {. (0{::solutions) differing_cells 1{::solutions
        state =. (<cell){grid
        givens =. givens,cell,state
        latest =. analyze (<rows),(<columns),<givens
        log =. log,<text_line (<'# hint'),(<#givens),(<'cell' kv cell_text cell),(<'value' kv state_char state),<'status' kv 'status' get_key latest
    end.
    original =. givens
    for_given. original do.
        keep =. -.*./"1 given="1 givens
        others =. keep#givens
        trial =. analyze (<rows),(<columns),<others
        if. ('status' get_key trial)-:'unique' do.
            givens =. others
            log =. log,<'# drop cell=',cell_text 2{.given
        end.
    end.
    final =. analyze (<rows),(<columns),<givens
    count =. 0
    while. ('difficulty' get_key final)-:'hard' do.
        cell =. guess_cell 'grid' get_key 'logic' get_key final
        state =. (<cell){grid
        givens =. givens,cell,state
        final =. analyze (<rows),(<columns),<givens
        count =. count+1
        log =. log,<text_line (<'# logic hint'),(<count),(<'cell' kv cell_text cell),(<'value' kv state_char state),<'difficulty' kv 'difficulty' get_key final
    end.
    'grid rows columns givens initial final log' record (<grid),(<rows),(<columns),(<givens),(<initial),(<final),<log
)
picture_paragraph =: 3 : 0
    'name generation reports' =. y
    grid =. 'grid' get_key generation
    rows =. 'rows' get_key generation
    columns =. 'columns' get_key generation
    givens =. 'givens' get_key generation
    initial =. 'initial' get_key generation
    final =. 'final' get_key generation
    duplicate =. '-'
    for_box. reports do.
        block =. 'block' get_key >box
        if. (rows-:'row_clues' get_key block)*.columns-:'column_clues' get_key block do. duplicate =. 'name' get_key block break. end.
    end.
    size =. (number #columns),'x',number #rows
    lines =. <text_line (<'# picture'),(<name),(<'size' kv size),<features_text grid
    lines =. lines,<text_line (<'# clues'),(<clue_statistics (<rows),<columns),<'duplicate_of' kv duplicate
    fields =. (<'# plain'),(<'status' kv 'status' get_key initial),(<'difficulty' kv 'difficulty' get_key initial),(<'line_solves' kv 'line_solves' get_key initial),<'guesses' kv 'guesses' get_key initial
    lines =. lines,(<text_line fields),'log' get_key generation
    fields =. (<'# final'),(<'status' kv 'status' get_key final),(<'difficulty' kv 'difficulty' get_key final),(<'hints' kv #givens),(<'line_solves' kv 'line_solves' get_key final),<'guesses' kv 'guesses' get_key final
    lines =. lines,(<text_line fields),(<'PUZZLE ',name),(<text_line (<'SIZE'),(<#columns),<#rows),<'ROWS'
    for_box. rows do. lines =. lines,<' ' clue_text >box end.
    lines =. lines,<'COLUMNS'
    for_box. columns do. lines =. lines,<' ' clue_text >box end.
    givens =. (/:givens){givens
    for_given. givens do. lines =. lines,<text_line (<'GIVEN'),(<1+0{given),(<1+1{given),<state_char 2{given end.
    lines,<'END'
)
process_pictures =: 4 : 0
    reports =. x
    blocks =. y
    names =. generations =. paragraphs =. 0$a:
    for_box. blocks do.
        block =. >box
        name =. 8}.0{::block
        rows =. }.block
        error =. validate_picture (<name),(<rows),<names
        names =. names,<name
        if. #error do. paragraphs =. paragraphs,<<'# picture ',name,' error ',error
        else.
            generation =. generate_puzzle state_grid rows
            generations =. generations,<generation
            paragraphs =. paragraphs,<picture_paragraph (<name),(<generation),<reports
        end.
    end.
    unique =. line_logic =. hinted =. hints =. 0
    for_box. generations do.
        generation =. >box
        initial =. 'initial' get_key generation
        unique =. unique+('status' get_key initial)-:'unique'
        line_logic =. line_logic+(<'difficulty' get_key initial)e.'easy';'medium'
        count =. #'givens' get_key generation
        hinted =. hinted+count>0
        hints =. hints+count
    end.
    fields =. (<'# SUMMARY'),(<'pictures' kv #blocks),(<'invalid' kv (#blocks)-#generations),(<'unique' kv unique),(<'line_logic' kv line_logic),(<'hinted' kv hinted),<'hints' kv hints
    paragraphs =. paragraphs,<<text_line fields
    'generated.txt' write_lines join_paragraphs paragraphs
    i.0
)
main =: 3 : 0
    1!:5 <'output'
    reports =. process_puzzles read_blocks 'puzzles.txt'
    reports process_pictures read_blocks 'pictures.txt'
)
main ''
