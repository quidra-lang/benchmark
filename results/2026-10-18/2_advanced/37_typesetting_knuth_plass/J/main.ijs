load 'document_parser.ijs'
load 'hyphenation.ijs'
load 'line_breaker.ijs'
load 'page_builder.ijs'
load 'renderer.ijs'
words_in =: 3 : 0
    parts =. ' 'split y
    (0<#&>parts)#parts
)
pad_right =: 4 : 'y,(0>.x-#y)#'' '''
string_less =: 4 : 0
    if. x-:y do.
        0 return.
    end.
    0={./:(<x),<y
)
tuple_less =: 4 : 0
    for_index. i.#x do.
        if. -.(index{::x)-:index{::y do.
            (index{::x)string_less index{::y return.
        end.
    end.
    0
)
split_label =: 3 : 0
    if. 0=#y do.
        (<''),<'' return.
    end.
    matches =. I.' {#'E.y
    if. (0<#matches)*.'}'={:y do.
        index =. {:matches
        (<index{.y),<}:((index+3)}.y)
    else.
        (<y),<''
    end.
)
new_metrics =: 3 : 0
    'words first_capacity later_capacity' =. y
    offsets =. i.0
    breaks =. 1 6$0
    offset =. 0
    for_index. i.#words do.
        word =. index{::words
        offsets =. offsets,offset
        offset =. offset+1+#word
        for_point. split_points word do.
            'position appended' =. point
            breaks =. breaks,index,position,index,position,1,appended
        end.
        breaks =. breaks,(index+1),0,index,(#word),0,0
    end.
    offsets =. offsets,offset
    starts =. ((0{"1 breaks){offsets)+1{"1 breaks
    ends =. (((2{"1 breaks){offsets)+3{"1 breaks)+5{"1 breaks
    midword =. 4{"1 breaks
    input =. (<starts),(<ends),(<midword),(<first_capacity),<later_capacity
    (<words),(<first_capacity),(<later_capacity),(<offsets),(<breaks),<input
)
measure_line =: 4 : 0
    'start end' =. y
    words =. 0{::x
    breaks =. 4{::x
    first =. start{breaks
    last =. end{breaks
    pieces =. 0$a:
    ranges =. 0 3$0
    for_word. (0{first)+i.1+(2{last)-0{first do.
        left =. 0
        right =. #word{::words
        if. word=0{first do.
            left =. 1{first
        end.
        if. word=2{last do.
            right =. 3{last
        end.
        pieces =. pieces,<(right-left){.left}.word{::words
        ranges =. ranges,word,left,right
    end.
    if. 5{last do.
        index =. (#pieces)-1
        pieces =. (<(index{::pieces),'-')index}pieces
    end.
    space =. (5{::x)slack start,end
    (<pieces),(<ranges),(<space),(<end=(#breaks)-1),<4{last
)
warn =: 4 : 0
    DocumentWarnings =: DocumentWarnings,<(<x),<y
    0
)
register_document =: 3 : 0
    Labels =: 0$a:
    LabelBlocks =: i.0
    BodyBlocks =: i.0
    Headings =: i.0
    NumberedTables =: i.0
    chapter =. 0
    section =. 0
    table_number =. 0
    for_index. i.#Blocks do.
        block =. index{::Blocks
        kind =. b_kind block
        if. (<kind)e.'h1';'h2' do.
            'value label' =. split_label b_argument block
            block =. (<value)12}block
            block =. (<label)13}block
            if. kind-:'h1' do.
                chapter =. chapter+1
                section =. 0
                number =. text chapter
                if. index do.
                    block =. (<1)3}block
                end.
            else.
                section =. section+1
                number =. (text chapter),'.',text section
            end.
            block =. (<number)14}block
            Headings =: Headings,index
        elseif. kind-:'enum' do.
            number =. 1
            if. index do.
                previous =. (index-1){::Blocks
                if. 'enum'-:b_kind previous do.
                    number =. 1+b_item_number previous
                end.
            end.
            block =. (<number)15}block
            block =. (<text number)14}block
        elseif. kind-:'table' do.
            'caption label' =. split_label b_caption block
            block =. (<caption)11}block
            block =. (<label)13}block
            if. #caption do.
                table_number =. table_number+1
                block =. (<text table_number)14}block
                NumberedTables =: NumberedTables,index
            end.
        end.
        label =. b_label block
        if. #label do.
            if. (<label)e.Labels do.
                (b_line block)warn 'duplicate label ',label
                block =. (<'')13}block
            else.
                Labels =: Labels,<label
                LabelBlocks =: LabelBlocks,index
            end.
        end.
        if. (kind-:'paragraph')*.index>0 do.
            if. (<b_kind (index-1){::Blocks)e.'h1';'h2' do.
                block =. (<0)5}block
            end.
        end.
        if. body_kind kind do.
            BodyBlocks =: BodyBlocks,index
            block =. (<#BodyBlocks)16}block
        end.
        Blocks =: (<block)index}Blocks
    end.
    keys =. 0$a:
    entries =. 0$a:
    for_box. Bibliography do.
        entry =. >box
        key =. 1{::entry
        if. (<key)e.keys do.
            (0{::entry)warn 'duplicate bibliography key ',key
        else.
            keys =. keys,<key
            entries =. entries,<entry
        end.
    end.
    Bibliography =: entries
    BibliographyKeys =: keys
    0
)
accept_command =: 4 : 0
    number =. x
    'name argument' =. y
    ordinal =. _1
    if. (<name)e.'ref';'page' do.
        if. -.(<argument)e.Labels do.
            number warn 'undefined label ',argument
        end.
    elseif. name-:'cite' do.
        for_key_box. ','split argument do.
            key =. >key_box
            index =. BibliographyKeys i.<key
            if. index=#BibliographyKeys do.
                number warn 'undefined citation ',key
            else.
                entry =. index{::Bibliography
                entry =. (<1)5}entry
                Bibliography =: (<entry)index}Bibliography
            end.
        end.
    elseif. name-:'fn' do.
        ordinal =. #Footnotes
        Footnotes =: Footnotes,<argument
    elseif. name-:'idx' do.
        ordinal =. #IndexMarks
        IndexMarks =: IndexMarks,<argument
    end.
    (<name),(<argument),<ordinal
)
parse_body_line =: 4 : 0
    number =. x
    value =. y
    tokens =. 0$a:
    position =. 0
    while. position<#value do.
        opening =. position+('{'i.~position}.value)
        if. opening=#value do.
            tokens =. tokens,<(<''),(<position}.value),<_1
            break.
        end.
        if. opening>position do.
            tokens =. tokens,<(<''),(<(opening-position){.position}.value),<_1
        end.
        closing =. (opening+1)+('}'i.~(opening+1)}.value)
        if. closing=#value do.
            number warn 'unclosed brace'
            tokens =. tokens,<(<''),(<opening}.value),<_1
            break.
        end.
        content =. ((closing-opening)-1){.(opening+1)}.value
        'name argument separated' =. ':'partition content
        if. ((<name)e.'ref';'page';'fn';'idx';'cite')*.separated*.0<#argument do.
            tokens =. tokens,<number accept_command (<name),<argument
        else.
            number warn 'bad command {',content,'}'
        end.
        position =. closing+1
    end.
    tokens
)
trim_spaces =: 3 : 0
    first =. 0
    last =. #y
    while. first<last do.
        if. ' '~:first{y do.
            break.
        end.
        first =. first+1
    end.
    while. last>first do.
        if. ' '~:(last-1){y do.
            break.
        end.
        last =. last-1
    end.
    (last-first){.first}.y
)
check_document =: 3 : 0
    Footnotes =: 0$a:
    IndexMarks =: 0$a:
    BlockTokens =: (#Blocks)$<0$a:
    for_index. i.#Blocks do.
        block =. index{::Blocks
        kind =. b_kind block
        if. kind-:'table' do.
            count =. #b_columns block
            rows =. 0$a:
            for_inner_box. b_inner block do.
                'line value' =. >inner_box
                cells =. trim_spaces&.>'|'split value
                if. count~:#cells do.
                    line warn 'table row has ',(text #cells),' cells, expected ',text count
                end.
                if. count>#cells do.
                    cells =. cells,(count-#cells)#<''
                end.
                rows =. rows,<count{.cells
            end.
            block =. (<rows)17}block
            lines =. format_table (<rows),(<b_columns block),(<b_caption block),<b_number block
            block =. (<lines)18}block
            longest =. >./#&>lines
            if. longest>b_width block do.
                (b_line block)warn 'table too wide by ',text longest-b_width block
            end.
        elseif. kind-:'verbatim' do.
            for_inner_box. b_inner block do.
                'line value' =. >inner_box
                if. (#value)>b_width block do.
                    line warn 'verbatim line too long by ',text (#value)-b_width block
                end.
            end.
        elseif. body_kind kind do.
            tokens =. 0$a:
            body =. b_body block
            for_line_index. i.#body do.
                if. line_index do.
                    tokens =. tokens,<(<''),(<' '),<_1
                end.
                'line value' =. line_index{::body
                tokens =. tokens,line parse_body_line value
            end.
            BlockTokens =: (<tokens)index}BlockTokens
        end.
        Blocks =: (<block)index}Blocks
    end.
    for_box. Bibliography do.
        entry =. >box
        if. -.5{::entry do.
            (0{::entry)warn 'unused bibliography entry ',1{::entry
        end.
    end.
    0
)
assign_bibliography_labels =: 3 : 0
    CitedEntries =: i.0
    ordering =. 0$a:
    for_index. i.#Bibliography do.
        entry =. index{::Bibliography
        if. -.5{::entry do.
            continue.
        end.
        surnames =. ' and 'split 2{::entry
        base =. ''
        if. 1=#surnames do.
            surname =. 0{::surnames
            base =. (3<.#surname){.surname
        else.
            count =. #surnames
            if. count>:5 do.
                count =. 3
            end.
            for_surname. count{.surnames do.
                base =. base,{.>surname
            end.
            if. 5<:#surnames do.
                base =. base,'+'
            end.
        end.
        base =. base,_2{.3{::entry
        entry =. (<base)6}entry
        Bibliography =: (<entry)index}Bibliography
        CitedEntries =: CitedEntries,index
        ordering =. ordering,<(<base),(2{entry),(4{entry),1{entry
    end.
    CitedEntries =: (/:ordering){CitedEntries
    index =. 0
    suffixes =. 'abcdefghijklmnopqrstuvwxyz'
    while. index<#CitedEntries do.
        end =. index
        base =. 6{::(index{CitedEntries){::Bibliography
        while. (end+1)<#CitedEntries do.
            if. -.base-:6{::((end+1){CitedEntries){::Bibliography do.
                break.
            end.
            end =. end+1
        end.
        for_current. index+i.1+end-index do.
            selected =. current{CitedEntries
            entry =. selected{::Bibliography
            suffix =. ''
            if. end>index do.
                suffix =. ,(current-index){suffixes
            end.
            entry =. (<base,suffix)7}entry
            Bibliography =: (<entry)selected}Bibliography
        end.
        index =. end+1
    end.
    0
)
prepare_index =: 3 : 0
    IndexEntries =: 0$a:
    for_number. i.#IndexMarks do.
        'entry_part reference has_reference' =. '|'partition number{::IndexMarks
        'parent_name child_name has_child' =. '!'partition entry_part
        parent =. _1
        for_index. i.#IndexEntries do.
            entry =. index{::IndexEntries
            if. ((1{::entry)<0)*.(0{::entry)-:parent_name do.
                parent =. index
            end.
        end.
        if. parent<0 do.
            parent =. #IndexEntries
            IndexEntries =: IndexEntries,<(<parent_name),(<_1),(<i.0),<0$a:
        end.
        selected =. parent
        if. has_child do.
            selected =. _1
            for_index. i.#IndexEntries do.
                entry =. index{::IndexEntries
                if. (parent=1{::entry)*.(0{::entry)-:child_name do.
                    selected =. index
                end.
            end.
            if. selected<0 do.
                selected =. #IndexEntries
                IndexEntries =: IndexEntries,<(<child_name),(<parent),(<i.0),<0$a:
            end.
        end.
        entry =. selected{::IndexEntries
        if. has_reference do.
            references =. 3{::entry
            if. -.(<reference)e.references do.
                entry =. (<references,<reference)3}entry
            end.
        else.
            entry =. (<(2{::entry),number)2}entry
        end.
        IndexEntries =: (<entry)selected}IndexEntries
    end.
    0
)
citation_text =: 3 : 0
    labels =. 0$a:
    undefined =. 0
    for_key_box. ','split y do.
        selected =. BibliographyKeys i.key_box
        if. selected=#BibliographyKeys do.
            undefined =. 1
        else.
            label =. 7{::selected{::Bibliography
            labels =. labels,<label
        end.
    end.
    labels =. /:~ ~.labels
    if. undefined do.
        labels =. labels,<'?'
    end.
    '[',(', 'join labels),']'
)
expand_body =: 4 : 0
    block =. x
    page_values =. y
    expanded =. ''
    marks =. 0 3$0
    for_token_box. block{::BlockTokens do.
        'kind argument ordinal' =. >token_box
        value =. ''
        if. 0=#kind do.
            value =. argument
        elseif. kind-:'idx' do.
            marks =. marks,((#expanded)-1),1,ordinal
        elseif. kind-:'fn' do.
            marks =. marks,(#expanded),0,ordinal
            value =. '[',(text ordinal+1),']'
        elseif. kind-:'ref' do.
            selected =. Labels i.<argument
            value =. '??'
            if. selected<#Labels do.
                value =. b_number (selected{LabelBlocks){::Blocks
            end.
        elseif. kind-:'page' do.
            selected =. Labels i.<argument
            value =. '??'
            if. selected<#Labels do.
                value =. selected{::page_values
            end.
        else.
            value =. citation_text argument
        end.
        expanded =. expanded,value
    end.
    words =. 0$a:
    starts =. i.0
    position =. 0
    while. position<#expanded do.
        if. ' '=position{expanded do.
            position =. position+1
            continue.
        end.
        start =. position
        while. position<#expanded do.
            if. ' '=position{expanded do.
                break.
            end.
            position =. position+1
        end.
        words =. words,<(position-start){.start}.expanded
        starts =. starts,start
    end.
    word_marks =. 0 4$0
    for_mark. marks do.
        'offset kind ordinal' =. mark
        word =. ({:I.starts<:offset)
        word_marks =. word_marks,word,(offset-word{starts),kind,ordinal
    end.
    (<words),<word_marks
)
t_lines =: 0&{::
t_broken =: 1&{::
t_cost =: 2&{::
lay_out_text =: 3 : 0
    'words capacities alignment prefixes method marks' =. y
    metrics =. new_metrics (<words),(<0{capacities),<1{capacities
    'breaking cost' =. break_text (<5{::metrics),(<method),<Costs
    lines =. 0$a:
    measured_lines =. 0$a:
    start =. 0
    for_index. i.#breaking do.
        end =. index{breaking
        measured =. metrics measure_line start,end
        'pieces ranges space last midword' =. measured
        value =. display_line (<pieces),(<space),(<alignment),<last
        prefix =. 1{::prefixes
        if. index=0 do.
            prefix =. 0{::prefixes
        end.
        line =. new_line prefix,value
        footnotes =. i.0
        indexes =. i.0
        for_range. ranges do.
            'word first last' =. range
            for_mark. marks do.
                'owner position kind number' =. mark
                if. (owner=word)*.(position>:first)*.position<last do.
                    if. kind=0 do.
                        footnotes =. footnotes,number
                    else.
                        indexes =. indexes,number
                    end.
                end.
            end.
        end.
        line =. (<footnotes)1}line
        line =. (<indexes)2}line
        lines =. lines,<line
        measured_lines =. measured_lines,<measured
        start =. end
    end.
    (<lines),(<measured_lines),<cost
)
lay_out_body =: 3 : 0
    'index page_values method' =. y
    block =. index{::Blocks
    'words marks' =. index expand_body page_values
    kind =. b_kind block
    width =. b_width block
    if. kind-:'paragraph' do.
        indent =. b_indent block
        capacities =. (width-indent),width
        prefixes =. (<indent#' '),<''
    elseif. kind-:'item' do.
        capacities =. 2$width-2
        prefixes =. '- ';'  '
    elseif. kind-:'enum' do.
        capacities =. 2$width-4
        value =. text b_item_number block
        prefix =. ((2-#value)#' '),value,'. '
        prefixes =. (<prefix),<'    '
    elseif. kind-:'quote' do.
        capacities =. 2$width-8
        prefixes =. '    ';'    '
    else.
        capacities =. 2$width-12
        prefix =. 12#' '
        if. 10>:#b_term block do.
            prefix =. 12 pad_right b_term block
        end.
        prefixes =. (<prefix),<12#' '
    end.
    result =. lay_out_text (<words),(<capacities),(<b_align block),(<prefixes),(<method),<marks
    if. (kind-:'term')*.11<:#b_term block do.
        lines =. (<new_line b_term block),t_lines result
        result =. (<lines)0}result
    end.
    result
)
lay_out_footnotes =: 3 : 0
    results =. 0$a:
    for_number. i.#Footnotes do.
        prefix =. '[',(text number+1),'] '
        capacity =. PageWidth-#prefix
        prefixes =. (<prefix),<(#prefix)#' '
        result =. lay_out_text (<words_in number{::Footnotes),(<2$capacity),(<'left'),(<prefixes),(<y),<0 4$0
        results =. results,<result
    end.
    results
)
lay_out_reference =: 3 : 0
    'index width method' =. y
    labels =. 7&{::&.>CitedEntries{Bibliography
    margin =. 3+>./#&>labels
    entry =. index{::Bibliography
    prefix =. margin pad_right '[',(7{::entry),']'
    value =. (2{::entry),'. ',(3{::entry),'. ',4{::entry
    prefixes =. (<prefix),<margin#' '
    lay_out_text (<words_in value),(<2$width-margin),(<'left'),(<prefixes),(<method),<0 4$0
)
page_list =: 3 : 0
    numbers =. /:~ ~.y
    parts =. 0$a:
    index =. 0
    while. index<#numbers do.
        end =. index
        while. (end+1)<#numbers do.
            if. ((end+1){numbers)~:1+end{numbers do.
                break.
            end.
            end =. end+1
        end.
        if. (end-index)>:2 do.
            parts =. parts,<(text index{numbers),'-',text end{numbers
        else.
            for_current. index+i.1+end-index do.
                parts =. parts,<text current{numbers
            end.
        end.
        index =. end+1
    end.
    ', 'join parts
)
index_entry_line =: 4 : 0
    entry =. x{::IndexEntries
    value =. 0{::entry
    if. (1{::entry)>:0 do.
        value =. '  ',value
    end.
    numbers =. i.0
    for_number. 2{::entry do.
        if. number<#y do.
            if. (number{y)>:0 do.
                numbers =. numbers,number{y
            end.
        end.
    end.
    if. #numbers do.
        value =. value,', ',page_list numbers
    end.
    references =. 3{::entry
    if. #references do.
        value =. value,', see ',', 'join /:~references
    end.
    value
)
index_order =: 3 : 0
    order =. i.0
    names =. 0$a:
    for_index. i.#IndexEntries do.
        entry =. index{::IndexEntries
        if. y=1{::entry do.
            name =. 0{::entry
            order =. order,index
            names =. names,<(<lower_ascii name),<name
        end.
    end.
    (/:names){order
)
index_lines =: 3 : 0
    lines =. 0$a:
    previous_group =. ''
    for_parent. index_order _1 do.
        name =. 0{::parent{::IndexEntries
        group =. 'Symbols'
        if. is_letter {.name do.
            group =. upper_ascii ,{.name
        end.
        if. -.group-:previous_group do.
            lines =. lines,<group
            previous_group =. group
        end.
        lines =. lines,<parent index_entry_line y
        for_child. index_order parent do.
            lines =. lines,<child index_entry_line y
        end.
    end.
    lines
)
contents_lines =: 3 : 0
    'index pages block_pages' =. y
    block =. index{::Blocks
    entries =. NumberedTables
    if. 'toc'-:b_kind block do.
        entries =. Headings
    end.
    lines =. 0$a:
    for_selected. entries do.
        entry =. selected{::Blocks
        if. 'toc'-:b_kind block do.
            left =. (b_number entry),' ',b_text entry
            if. 'h2'-:b_kind entry do.
                left =. '  ',left
            end.
        else.
            left =. 'Table ',(b_number entry),'. ',b_caption entry
        end.
        number =. '??'
        if. selected<#block_pages do.
            if. (selected{block_pages)>:0 do.
                number =. 8{::(selected{block_pages){::pages
            end.
        end.
        dots =. (b_width block)-((#left)+(#number)+2)
        lines =. lines,<left,' ',(dots#'.'),' ',number
    end.
    lines
)
new_layout_block =: 3 : 0
    'source kind lines list_mark first' =. y
    block =. source{::Blocks
    if. first do.
        line =. 0{::lines
        line =. (<source)3}line
        line =. (<'h1'-:b_kind block)4}line
        lines =. (<line)0}lines
    end.
    (<kind),(<lines),(<list_mark),<first*.b_page_break block
)
text_lines =: new_line&.>
build_layout_blocks =: 3 : 0
    'page_values method' =. y
    layout =. 0$a:
    empty =. (<0$a:),(<0$a:),<0
    bodies =. (#Blocks)$<empty
    warning_texts =. 0$a:
    generated =. i.0
    for_index. i.#Blocks do.
        block =. index{::Blocks
        kind =. b_kind block
        if. body_kind kind do.
            body =. lay_out_body (<index),(<page_values),<method
            bodies =. (<body)index}bodies
            warning_texts =. warning_texts,< (<'paragraph ',text b_paragraph block),(<body),<'justify'-:b_align block
            list_mark =. (<kind)e.'item';'enum';'term'
            layout =. layout,<new_layout_block (<index),(<'flow'),(<t_lines body),(<list_mark),<1
        elseif. (<kind)e.'title';'author' do.
            value =. b_argument block
            if. kind-:'title' do.
                value =. upper_ascii value
            end.
            value =. (((b_width block)-#value)intdiv 2)#' '
            argument =. b_argument block
            if. kind-:'title' do.
                argument =. upper_ascii argument
            end.
            value =. value,argument
            layout =. layout,<new_layout_block (<index),(<'heading'),(<,<new_line value),(<0),<1
        elseif. (<kind)e.'h1';'h2' do.
            value =. b_text block
            symbol =. '-'
            if. kind-:'h1' do.
                value =. upper_ascii value
                symbol =. '='
            end.
            value =. (b_number block),' ',value
            lines =. text_lines (<value),<(#value)#symbol
            layout =. layout,<new_layout_block (<index),(<'heading'),(<lines),(<0),<1
        elseif. kind-:'table' do.
            layout =. layout,<new_layout_block (<index),(<'solid'),(<text_lines b_table_lines block),(<0),<1
        elseif. kind-:'verbatim' do.
            texts =. 1&{::&.>b_inner block
            layout =. layout,<new_layout_block (<index),(<'flow'),(<text_lines texts),(<0),<1
        elseif. (<kind)e.'toc';'lot';'index' do.
            title =. (('toc';'lot';'index')i.<kind){::'CONTENTS';'TABLES';'INDEX'
            lines =. text_lines (<title),<(#title)#'='
            layout =. layout,<new_layout_block (<index),(<'heading'),(<lines),(<0),<1
            if. kind-:'index' do.
                texts =. index_lines i.0
            else.
                texts =. contents_lines (<index),(<0$a:),<i.0
            end.
            lines =. text_lines texts
            for_line_index. i.#lines do.
                line =. line_index{::lines
                line =. (<index)5}line
                line =. (<line_index)6}line
                lines =. (<line)line_index}lines
            end.
            layout =. layout,<new_layout_block (<index),(<'flow'),(<lines),(<0),<0
            generated =. generated,index
        else.
            lines =. text_lines 'REFERENCES';'=========='
            layout =. layout,<new_layout_block (<index),(<'heading'),(<lines),(<0),<1
            for_selected. CitedEntries do.
                reference =. lay_out_reference (<selected),(<b_width block),<method
                label =. 7{::selected{::Bibliography
                warning_texts =. warning_texts,< (<'reference ',label),(<reference),<0
                layout =. layout,<new_layout_block (<index),(<'flow'),(<t_lines reference),(<1),<0
            end.
        end.
    end.
    (<layout),(<bodies),(<warning_texts),<generated
)
roman =: 3 : 0
    units =. ''; 'i';'ii';'iii';'iv';'v';'vi';'vii';'viii';'ix'
    ((y intdiv 10)#'x'),(10|y){::units
)
number_pages =: 3 : 0
    numbered =. 0$a:
    for_box. y do.
        page =. >box
        chapter_start =. 4{::0{::0{::page
        serial =. 1+#numbered
        if. chapter_start*.0=2|serial do.
            blank =. new_page (<0$a:),(<i.0),(<0),<1
            blank =. (<1)4}blank
            blank =. (<serial)6}blank
            numbered =. numbered,<blank
            serial =. serial+1
        end.
        page =. (<serial)6}page
        page =. (<chapter_start)5}page
        numbered =. numbered,<page
    end.
    block_pages =. (#Blocks)$_1
    for_index. i.#numbered do.
        for_line_box. 0{::index{::numbered do.
            line =. >line_box
            anchor =. 3{::line
            if. anchor>:0 do.
                block_pages =. index anchor}block_pages
            end.
        end.
    end.
    front_matter =. 0
    if. #Headings do.
        page =. (({.Headings){block_pages){::numbered
        front_matter =. (6{::page)-1
    end.
    mark_pages =. (#IndexMarks)$_1
    for_index. i.#numbered do.
        page =. index{::numbered
        serial =. 6{::page
        body_number =. serial-front_matter
        number =. text body_number
        if. serial<:front_matter do.
            number =. roman serial
        end.
        page =. (<body_number)7}page
        page =. (<number)8}page
        for_line_box. 0{::page do.
            for_mark. 2{::>line_box do.
                mark_pages =. body_number mark}mark_pages
            end.
        end.
        numbered =. (<page)index}numbered
    end.
    label_values =. 0$a:
    for_block. LabelBlocks do.
        label_values =. label_values,<8{::(block{block_pages){::numbered
    end.
    (<numbered),(<front_matter),(<block_pages),(<mark_pages),<label_values
)
r_method =: 0&{::
r_bodies =: 1&{::
r_footnotes =: 2&{::
r_warning_texts =: 3&{::
r_generated =: 4&{::
r_pages =: 5&{::
r_front =: 6&{::
r_block_pages =: 7&{::
r_mark_pages =: 8&{::
r_label_values =: 9&{::
layout_once =: 4 : 0
    page_values =. x
    method =. y
    footnotes =. lay_out_footnotes method
    'layout bodies warning_texts generated' =. build_layout_blocks (<page_values),<method
    heights =. i.0
    for_note_box. footnotes do.
        heights =. heights,#t_lines >note_box
    end.
    pages =. choose_pages (<layout),(<heights),(<PageHeight),(<OrphanLines),<WidowLines
    'pages front block_pages mark_pages label_values' =. number_pages pages
    for_number. i.#footnotes do.
        warning_texts =. warning_texts,< (<'footnote ',text number+1),(<number{::footnotes),<0
    end.
    (<method),(<bodies),(<footnotes),(<warning_texts),(<generated),(<pages),(<front),(<block_pages),(<mark_pages),<label_values
)
assemble_pages =: 3 : 0
    result =. y
    pages =. r_pages result
    generated_texts =. (#Blocks)$<0$a:
    for_index. r_generated result do.
        block =. index{::Blocks
        if. 'index'-:b_kind block do.
            texts =. index_lines r_mark_pages result
        else.
            texts =. contents_lines (<index),(<pages),<r_block_pages result
        end.
        generated_texts =. (<texts)index}generated_texts
    end.
    chapter =. ''
    section =. ''
    total =. (#pages)-r_front result
    for_index. i.#pages do.
        page =. index{::pages
        if. 4{::page do.
            page =. (<'')9}page
            page =. (<'')10}page
            page =. (<PageHeight#<'')11}page
            pages =. (<page)index}pages
            continue.
        end.
        content =. 0{::page
        for_line_index. i.#content do.
            line =. line_index{::content
            source =. 5{::line
            if. source>:0 do.
                texts =. source{::generated_texts
                line =. ((6{::line){texts)0}line
                content =. (<line)line_index}content
            end.
            anchor =. 3{::line
            if. anchor>:0 do.
                block =. anchor{::Blocks
                if. 'h1'-:b_kind block do.
                    chapter =. (b_number block),' ',b_text block
                    section =. ''
                elseif. 'h2'-:b_kind block do.
                    section =. (b_number block),' ',b_text block
                end.
            end.
        end.
        page =. (<content)0}page
        values =. (8{page),(<text total),(<chapter),<section
        header =. ''
        if. -.5{::page do.
            header =. running_head (<Header),(<values),(<PageWidth),<6{::page
        end.
        footer =. running_head (<Footer),(<values),(<PageWidth),<6{::page
        page =. (<header)9}page
        page =. (<footer)10}page
        body =. 0&{::&.>content
        notes =. 0$a:
        for_number. 1{::page do.
            note =. number{::r_footnotes result
            notes =. notes,0&{::&.>t_lines note
        end.
        padding =. ((PageHeight-#body)-#notes)-0<#notes
        body =. body,padding#<''
        if. #notes do.
            body =. body,(<'----------'),notes
        end.
        page =. (<body)11}page
        pages =. (<page)index}pages
    end.
    (<pages)5}result
)
layout_document =: 3 : 0
    method =. y
    values =. (#Labels)#<'??'
    result =. values layout_once method
    changed =. 1
    while. changed do.
        changed =. -.values-:r_label_values result
        if. changed do.
            values =. r_label_values result
            result =. values layout_once method
        end.
    end.
    assemble_pages result
)
layout_warnings =: 3 : 0
    result =. y
    messages =. 0$a:
    for_box. r_warning_texts result do.
        'name value justify' =. >box
        broken =. t_broken value
        for_index. i.#broken do.
            line =. index{::broken
            space =. 2{::line
            if. space<0 do.
                messages =. messages,<name,' line ',(text index+1),': overfull by ',text -space
            elseif. justify*.-.3{::line do.
                if. space>:UnderfullSlack do.
                    messages =. messages,<name,' line ',(text index+1),': underfull, slack ',text space
                end.
            end.
        end.
    end.
    for_box. r_pages result do.
        page =. >box
        if. (4{::page)+.3{::page do.
            continue.
        end.
        empty =. PageHeight-2{::page
        if. empty>:UnderfullPage do.
            messages =. messages,<'page ',(text 6{::page),': underfull, ',(text empty),' empty lines'
        end.
    end.
    hyphenated =. 0
    for_index. BodyBlocks do.
        for_box. t_broken index{::r_bodies result do.
            hyphenated =. hyphenated+4{::>box
        end.
    end.
    messages =. messages,<(text #r_pages result),' pages, ',(text hyphenated),' hyphenated lines'
    prefix =. (r_method result),': '
    output =. 0$a:
    for_box. messages do.
        output =. output,<prefix,>box
    end.
    output
)
statistics =: 4 : 0
    lines =. ,<'paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy'
    totals =. 4$0
    for_index. BodyBlocks do.
        first =. index{::r_bodies x
        second =. index{::r_bodies y
        values =. (#t_broken first),(t_cost first),(#t_broken second),t_cost second
        totals =. totals+values
        fields =. (<text b_paragraph index{::Blocks),text&.>values
        lines =. lines,<','join fields
    end.
    lines,<'total,',','join text&.>totals
)
write_lines =: 4 : 0
    content =. ''
    for_box. y do.
        content =. content,(>box),LF
    end.
    content 1!:2 <'output/',x
)
run =: 3 : 0
    parameter_names =. 'line_penalty';'hyphen_penalty';'double_hyphen_demerit';'final_hyphen_demerit';'fitness_demerit';'overfull_penalty';'left_min';'right_min';'orphan_lines';'widow_lines';'underfull_slack';'underfull_page'
    parameters =. 12$0
    for_box. read_lines 'input/params.txt' do.
        'name value separated' =. ' 'partition >box
        index =. parameter_names i.<name
        parameters =. (num value)index}parameters
    end.
    Costs =: 6{.parameters
    OrphanLines =: 8{parameters
    WidowLines =: 9{parameters
    UnderfullSlack =: 10{parameters
    UnderfullPage =: 11{parameters
    parse_document read_lines 'input/document.txt'
    (6 7{parameters)new_dictionary (read_lines 'input/hyphenation.txt'),HyphenationWords
    register_document 0
    check_document 0
    assign_bibliography_labels 0
    prepare_index 0
    DocumentWarnings =: (/:0&{::&>DocumentWarnings){DocumentWarnings
    optimal =. layout_document 'kp'
    greedy =. layout_document 'greedy'
    warnings =. 0$a:
    for_box. DocumentWarnings do.
        'number message' =. >box
        warnings =. warnings,<'line ',(text number),': ',message
    end.
    warnings =. warnings,(layout_warnings optimal),layout_warnings greedy
    try.
        1!:5 <'output'
    catch.
    end.
    'pages.txt'write_lines pages_lines r_pages optimal
    'greedy_pages.txt'write_lines pages_lines r_pages greedy
    'stats.csv'write_lines optimal statistics greedy
    'log.txt'write_lines warnings
    i.0 0
)
run 0
