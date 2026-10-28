read_lines =: 3 : '<;._2 (1!:1 <y)'
num =: 3 : 'x: 0".y'
intdiv =: 4 : '<.(x: x)%x: y'
split =: 4 : 0
    parts =. 0$a:
    start =. 0
    for_index. I.x E.y do.
        parts =. parts,<(index-start){.start}.y
        start =. index+#x
    end.
    parts,<start}.y
)
partition =: 4 : 0
    matches =. I.x E.y
    if. 0=#matches do.
        (<y),(<''),<0
    else.
        index =. {.matches
        (<index{.y),(<(index+#x)}.y),<1
    end.
)
join =: 4 : 0
    text =. ''
    for_index. i.#y do.
        if. index do.
            text =. text,x
        end.
        text =. text,index{::y
    end.
    text
)
text =: 3 : 0
    value =. ":y
    '-'(I.value='_')}value
)
body_kind =: 3 : '(<y)e.''paragraph'';''item'';''enum'';''quote'';''term'''
dictionary_word =: 3 : 0
    if. 0=#y do.
        0 return.
    end.
    (*./y e.'abcdefghijklmnopqrstuvwxyz-')*.('-'~:{.y)*.('-'~:{:y)*.-.+./'--'E.y
)
valid_argument =: 4 : 0
    name =. x
    argument =. y
    if. (<name)e.'width';'indent';'page' do.
        if. (0=#argument)+.(9<#argument)+.-.*./argument e.'0123456789' do.
            0 return.
        end.
        value =. num argument
        if. name-:'width' do.
            (value>:20)*.value<:80
        elseif. name-:'indent' do.
            value<:8
        else.
            (value>:10)*.value<:100
        end.
    elseif. name-:'align' do.
        (<argument)e.'left';'right';'center';'justify'
    elseif. (<name)e.'header';'footer' do.
        2=+/'|'=argument
    elseif. (<name)e.'newpage';'verbatim';'toc';'lot';'index';'bibliography' do.
        0=#argument
    elseif. name-:'hyphenation' do.
        */dictionary_word&>' 'split argument
    elseif. name-:'bib' do.
        'key fields separated' =. ' 'partition argument
        parts =. '|'split fields
        valid =. separated*.(0<#key)*.*./key e.'abcdefghijklmnopqrstuvwxyz0123456789'
        if. (3~:#parts)+.-.valid do.
            0 return.
        end.
        author =. 0{::parts
        year =. 1{::parts
        title =. 2{::parts
        (0<#author)*.(0<#title)*.(4=#year)*.*./year e.'0123456789'
    elseif. name-:'term' do.
        'term description separated' =. '|'partition argument
        separated*.(0<#term)*.0<#description
    elseif. name-:'table' do.
        columns =. 0{::' 'partition argument
        (0<#columns)*.*./columns e.'lrc'
    else.
        0<#argument
    end.
)
b_kind =: 0&{::
b_line =: 1&{::
b_argument =: 2&{::
b_page_break =: 3&{::
b_width =: 4&{::
b_indent =: 5&{::
b_align =: 6&{::
b_body =: 7&{::
b_inner =: 8&{::
b_term =: 9&{::
b_columns =: 10&{::
b_caption =: 11&{::
b_text =: 12&{::
b_label =: 13&{::
b_number =: 14&{::
b_item_number =: 15&{::
b_paragraph =: 16&{::
b_rows =: 17&{::
b_table_lines =: 18&{::
new_block =: 3 : 0
    'kind line argument page_break width indent align' =. y
    (<kind),(<line),(<argument),(<page_break),(<width),(<indent),(<align),(<0$a:),(<0$a:),(<''),(<''),(<''),(<''),(<''),(<''),(<0),(<0),(<0$a:),<0$a:
)
parse_document =: 3 : 0
    Blocks =: 0$a:
    DocumentWarnings =: 0$a:
    PageHeight =: 40
    PageWidth =: 60
    Header =: '';'';''
    Footer =: '';'';''
    HyphenationWords =: 0$a:
    Bibliography =: 0$a:
    width =. 60
    indent =. 0
    align =. 'left'
    accepted =. 0$a:
    open_body =. _1
    inner_block =. _1
    pending =. 0
    setting_names =. 'width';'indent';'align'
    preamble_names =. 'page';'header';'footer'
    block_names =. 'title';'author';'h1';'h2';'item';'enum';'quote';'term';'table';'verbatim';'toc';'lot';'index';'bibliography'
    for_offset. i.#y do.
        number =. offset+1
        line =. offset{::y
        if. inner_block>:0 do.
            if. line-:'.end' do.
                inner_block =. _1
            else.
                block =. inner_block{::Blocks
                block =. (<(b_inner block),<(<number),<line)8}block
                Blocks =: (<block)inner_block}Blocks
            end.
            continue.
        end.
        if. 0=#line do.
            open_body =. _1
            continue.
        end.
        if. '.'~:{.line do.
            if. open_body<0 do.
                if. 0=#Blocks do.
                    PageWidth =: width
                end.
                open_body =. #Blocks
                block =. new_block (<'paragraph'),(<number),(<''),(<pending),(<width),(<indent),<align
                Blocks =: Blocks,<block
                pending =. 0
            end.
            block =. open_body{::Blocks
            block =. (<(b_body block),<(<number),<line)7}block
            Blocks =: (<block)open_body}Blocks
            continue.
        end.
        open_body =. _1
        'name argument separated' =. ' 'partition }.line
        setting =. (<name)e.setting_names
        preamble =. (<name)e.preamble_names
        block_kind =. (<name)e.block_names
        warning =. ''
        if. -.setting+.preamble+.block_kind+.(<name)e.'newpage';'hyphenation';'bib' do.
            warning =. 'unknown directive .',name
        elseif. -.name valid_argument argument do.
            warning =. 'bad argument for .',name
        elseif. preamble*.0<#Blocks do.
            warning =. '.',name,' ignored after the preamble'
        elseif. preamble*.(<name)e.accepted do.
            warning =. 'duplicate .',name
        end.
        if. #warning do.
            DocumentWarnings =: DocumentWarnings,<(<number),<warning
        elseif. setting do.
            if. name-:'width' do.
                width =. num argument
            elseif. name-:'indent' do.
                indent =. num argument
            else.
                align =. argument
            end.
        elseif. preamble do.
            accepted =. accepted,<name
            if. name-:'page' do.
                PageHeight =: num argument
            elseif. name-:'header' do.
                Header =: '|'split argument
            else.
                Footer =: '|'split argument
            end.
        elseif. name-:'newpage' do.
            pending =. 1
        elseif. name-:'hyphenation' do.
            HyphenationWords =: HyphenationWords,' 'split argument
        elseif. name-:'bib' do.
            'key fields separated' =. ' 'partition argument
            'author year title' =. '|'split fields
            Bibliography =: Bibliography,<(<number),(<key),(<author),(<year),(<title),(<0),(<''),<''
        else.
            if. 0=#Blocks do.
                PageWidth =: width
            end.
            block =. new_block (<name),(<number),(<argument),(<pending),(<width),(<indent),<align
            pending =. 0
            index =. #Blocks
            if. (<name)e.'item';'enum';'quote' do.
                body =. ,<(<number),<argument
                block =. (<body)7}block
                open_body =. index
            elseif. name-:'term' do.
                'term description separated' =. '|'partition argument
                block =. (<term)9}block
                block =. (<,<(<number),<description)7}block
                open_body =. index
            elseif. name-:'table' do.
                'columns caption separated' =. ' 'partition argument
                block =. (<columns)10}block
                block =. (<caption)11}block
                inner_block =. index
            elseif. name-:'verbatim' do.
                inner_block =. index
            end.
            Blocks =: Blocks,<block
        end.
    end.
    if. inner_block>:0 do.
        block =. inner_block{::Blocks
        DocumentWarnings =: DocumentWarnings,<(<b_line block),<'unterminated ',b_kind block
    end.
    0
)
