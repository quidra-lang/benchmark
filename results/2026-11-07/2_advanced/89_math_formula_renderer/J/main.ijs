load 'lexer.ijs'
load 'parser.ijs'
load 'boxes.ijs'
load 'layout.ijs'
load 'canvas.ijs'

intdiv =: 4 : '<.(x:x)%x:y'
integer =: 3 : 0
    text =. ,":y
    '-'(I.text='_')}text
)
parse_integer =: 3 : '".y'
join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do.
            text =. text,x
        end.
        text =. text,i{::y
    end.
    text
)
split_words =: 3 : '<;._1 '' '',y'
parameter =: 3 : '(ParameterNames i.<y){ParameterValues'
reference_display =: 3 : 0
    index =. ReferenceNames i.<y
    if. index=#ReferenceNames do.
        '(??)'
    else.
        index{::ReferenceValues
    end.
)
center_box =: 4 : '(x-box_width y)intdiv 2'
draw_delimiter =: 4 : 0
    'delimiter position height' =. y
    glyph =. delimiter delimiter_glyph height
    for_i. i.#glyph do.
        x add_string(i{glyph),(<position),<i
    end.
    x
)
delimit_box =: 3 : 0
    'body left right' =. y
    left_width =. -.left-:,'.'
    right_width =. -.right-:,'.'
    width =. left_width+(box_width body)+right_width
    height =. box_height body
    description =. 'delim ',left,' ',right
    box =. new_box(<width),(<height),(<box_baseline body),<description
    box add_child(<body),(<left_width),(<0),<''
    box draw_delimiter(<left),(<0),<height
    box draw_delimiter(<right),(<left_width+box_width body),<height
    box
)
typeset_atom =: 4 : 0
    'kind children value column' =. y{::NodePool
    display =. value
    if. kind-:'text' do.
        description =. 'text "',value,'"'
    elseif. kind-:'reference' do.
        description =. 'eqref "',value,'"'
        display =. reference_display value
    else.
        description =. 'atom "',value,'"'
        if. kind-:'command' do.
            display =. command_display value
        end.
    end.
    large =. (kind-:'command')*.(x-:'normal')*.(<value)e.'\sum';'\prod';'\int'
    if. large do.
        glyph =. large_glyph value
        box =. new_box(<#0{::glyph),(<3),(<1),<description
        for_i. i.#glyph do.
            box add_string(i{glyph),(<0),<i
        end.
    else.
        box =. new_box(<#display),(<1),(<0),<description
        box add_string(<display),(<0),<0
    end.
    box
)
typeset_row =: 4 : 0
    nodes =. y
    'types gaps' =. x row_spacing nodes
    children =. i.0
    for_node. nodes do.
        children =. children,x typeset_node node
    end.
    roles =. (#children)$<''
    assemble_row(<children),(<gaps),(<'row'),<roles
)
typeset_script =: 4 : 0
    style =. x
    'kind children value column' =. y{::NodePool
    'base_node sub_node sup_node' =. children
    base =. style typeset_node base_node
    sub =. sup =. _1
    sub_width =. sub_height =. sup_width =. sup_height =. 0
    if. sub_node~:_1 do.
        sub =. 'script'typeset_node sub_node
        sub_width =. box_width sub
        sub_height =. box_height sub
    end.
    if. sup_node~:_1 do.
        sup =. 'script'typeset_node sup_node
        sup_width =. box_width sup
        sup_height =. box_height sup
    end.
    'base_kind base_children base_value base_column' =. base_node{::NodePool
    stacked =. 0
    if. style-:'normal' do.
        if. base_kind-:'command' do.
            stacked =. (<base_value)e.'\sum';'\prod';'\lim';'\max';'\min'
        elseif. base_kind-:'accent' do.
            stacked =. (<base_value)e.'overbrace';'underbrace'
        end.
    end.
    if. stacked do.
        width =. (box_width base)>.sub_width>.sup_width
        height =. sup_height+(box_height base)+sub_height
        baseline =. sup_height+box_baseline base
        box =. new_box(<width),(<height),(<baseline),<'limits'
        box add_child(<base),(<width center_box base),(<sup_height),<'base: '
        if. sub~:_1 do.
            box add_child(<sub),(<width center_box sub),(<sup_height+box_height base),<'sub: '
        end.
        if. sup~:_1 do.
            box add_child(<sup),(<width center_box sup),(<0),<'sup: '
        end.
    else.
        sup_bottom =. 0
        if. 0=box_baseline base do.
            sup_bottom =. _1
        end.
        sup_top =. (sup_bottom-sup_height)+1
        sub_top =. box_height base
        if. 0<box_descent base do.
            sub_top =. sub_top-1
        end.
        top =. 0
        if. sup~:_1 do.
            top =. 0<.sup_top
        end.
        bottom =. (box_height base)-1
        if. sub~:_1 do.
            bottom =. bottom>.(sub_top+sub_height)-1
        end.
        width =. (box_width base)+sub_width>.sup_width
        height =. (bottom-top)+1
        baseline =. (box_baseline base)-top
        box =. new_box(<width),(<height),(<baseline),<'scripts'
        box add_child(<base),(<0),(<-top),<'base: '
        if. sub~:_1 do.
            box add_child(<sub),(<box_width base),(<sub_top-top),<'sub: '
        end.
        if. sup~:_1 do.
            box add_child(<sup),(<box_width base),(<sup_top-top),<'sup: '
        end.
    end.
    box
)
typeset_fraction =: 4 : 0
    'kind children value column' =. y{::NodePool
    numerator =. x typeset_node 0{children
    denominator =. x typeset_node 1{children
    if. x-:'normal' do.
        width =. 2+(box_width numerator)>.box_width denominator
        baseline =. box_height numerator
        height =. baseline+1+box_height denominator
        box =. new_box(<width),(<height),(<baseline),<'frac'
        box add_child(<numerator),(<width center_box numerator),(<0),<'num: '
        box add_child(<denominator),(<width center_box denominator),(<baseline+1),<'den: '
        box add_string(<width$'-'),(<0),<baseline
    else.
        for_i. i.2 do.
            node =. (i{children){::NodePool
            if. (0{node)e.'row';'frac' do.
                if. i=0 do.
                    numerator =. delimit_box(<numerator),(<,'('),<,')'
                else.
                    denominator =. delimit_box(<denominator),(<,'('),<,')'
                end.
            end.
        end.
        slash =. new_box(<1),(<1),(<0),<'atom "/"'
        slash add_string(<,'/'),(<0),<0
        roles =. 'num: ';'';'den: '
        box =. assemble_row(<numerator,slash,denominator),(<0 0),(<'slash'),<roles
    end.
    box
)
typeset_binomial =: 4 : 0
    children =. 1{::y{::NodePool
    upper =. x typeset_node 0{children
    lower =. x typeset_node 1{children
    width =. (box_width upper)>.box_width lower
    baseline =. box_height upper
    height =. baseline+1+box_height lower
    box =. new_box(<width+2),(<height),(<baseline),<'binom'
    box add_child(<upper),(<1+width center_box upper),(<0),<'upper: '
    box add_child(<lower),(<1+width center_box lower),(<baseline+1),<'lower: '
    box draw_delimiter(<,'('),(<0),<height
    box draw_delimiter(<,')'),(<width+1),<height
    box
)
typeset_placed =: 4 : 0
    'kind children value column' =. y{::NodePool
    placed =. 'script'typeset_node 0{children
    base =. x typeset_node 1{children
    width =. (box_width placed)>.box_width base
    height =. (box_height placed)+box_height base
    baseline =. box_baseline base
    if. kind-:'overset' do.
        baseline =. baseline+box_height placed
    end.
    box =. new_box(<width),(<height),(<baseline),<kind
    if. kind-:'overset' do.
        box add_child(<placed),(<width center_box placed),(<0),<'over: '
        box add_child(<base),(<width center_box base),(<box_height placed),<'base: '
    else.
        box add_child(<base),(<width center_box base),(<0),<'base: '
        box add_child(<placed),(<width center_box placed),(<box_height base),<'under: '
    end.
    box
)
typeset_radical =: 4 : 0
    'kind children value column' =. y{::NodePool
    index =. _1
    extra =. top =. 0
    if. kind-:'root' do.
        index =. 'script'typeset_node 0{children
        body =. x typeset_node 1{children
        extra =. 0>.(box_width index)-1
        top =. 0>.(box_height index)-box_height body
    else.
        body =. x typeset_node 0{children
    end.
    k =. box_height body
    width =. extra+k+1+box_width body
    height =. k+1+top
    baseline =. (box_baseline body)+1+top
    box =. new_box(<width),(<height),(<baseline),<kind
    box add_string(<(box_width body)$'_'),(<extra+k+1),<top
    box add_string(<,'\'),(<extra),<k+top
    for_row. 1+i.k do.
        position =. extra+((k-row)+1)
        box add_string(<,'/'),(<position),<row+top
    end.
    if. index~:_1 do.
        box add_child(<index),(<0),(<top+k-box_height index),<'index: '
        box add_child(<body),(<extra+k+1),(<1+top),<'body: '
    else.
        box add_child(<body),(<extra+k+1),(<1),<''
    end.
    box
)
typeset_matrix =: 4 : 0
    'kind rows environment column' =. y{::NodePool
    row_count =. #rows
    column_count =. #0{::rows
    cells =. (row_count,column_count)$0
    for_i. i.row_count do.
        row =. i{::rows
        for_j. i.column_count do.
            child =. x typeset_node j{row
            cells =. child(<i,j)}cells
        end.
    end.
    widths =. column_count$0
    ascents =. row_count$0
    descents =. row_count$0
    for_i. i.row_count do.
        for_j. i.column_count do.
            child =. (<i,j){cells
            widths =. ((j{widths)>.box_width child)j}widths
            ascents =. ((i{ascents)>.box_baseline child)i}ascents
            descents =. ((i{descents)>.box_descent child)i}descents
        end.
    end.
    heights =. 1+ascents+descents
    col_gap =. parameter 'col_gap'
    row_gap =. parameter 'row_gap'
    body_width =. (+/widths)+col_gap*column_count-1
    body_height =. (+/heights)+row_gap*row_count-1
    shift =. 2
    extra =. 4
    if. environment-:'matrix' do.
        shift =. extra =. 0
    elseif. environment-:'cases' do.
        extra =. 2
    end.
    description =. environment,' rows=',(integer row_count),' cols=',integer column_count
    box =. new_box(<body_width+extra),(<body_height),(<(body_height-1)intdiv 2),<description
    yy =. 0
    for_i. i.row_count do.
        xx =. shift
        for_j. i.column_count do.
            child =. (<i,j){cells
            offset =. 0
            if. -.environment-:'cases' do.
                offset =. (j{widths)center_box child
            end.
            role =. 'cell ',(integer i+1),',',(integer j+1),': '
            top =. yy+(i{ascents)-box_baseline child
            box add_child(<child),(<xx+offset),(<top),<role
            xx =. xx+(j{widths)+col_gap
        end.
        yy =. yy+(i{heights)+row_gap
    end.
    if. environment-:'cases' do.
        box draw_delimiter(<'\{'),(<0),<body_height
    elseif. -.environment-:'matrix' do.
        select. environment
        case. 'pmatrix' do. 'left right' =. ( <,'('),<,')'
        case. 'bmatrix' do. 'left right' =. ( <,'['),<,']'
        case. 'vmatrix' do. 'left right' =. ( <,'|'),<,'|'
        end.
        box draw_delimiter(<left),(<0),<body_height
        box draw_delimiter(<right),(<body_width+3),<body_height
    end.
    box
)
typeset_accent =: 4 : 0
    'kind children name column' =. y{::NodePool
    body =. x typeset_node 0{children
    width =. box_width body
    if. (<name)e.'hat';'dot';'tilde' do.
        width =. width>.1
    elseif. name-:'vec' do.
        width =. width>.2
    elseif. (<name)e.'overbrace';'underbrace' do.
        width =. width+2
    end.
    baseline =. 1+box_baseline body
    if. name-:'underbrace' do.
        baseline =. box_baseline body
    end.
    box =. new_box(<width),(<1+box_height body),(<baseline),<name
    if. name-:'underbrace' do.
        box add_child(<body),(<1),(<0),<''
        text =. '\',((box_width body)$'-'),'/'
        box add_string(<text),(<0),<box_height body
    elseif. name-:'overbrace' do.
        box add_child(<body),(<1),(<1),<''
        text =. '/',((box_width body)$'-'),'\'
        box add_string(<text),(<0),<0
    else.
        box add_child(<body),(<0),(<1),<''
        if. name-:'overline' do.
            box add_string(<width$'_'),(<0),<0
        elseif. name-:'vec' do.
            box add_string(<((width-1)$'-'),'>'),(<0),<0
        else.
            symbol =. ((;:'hat dot tilde')i.<name){'^.~'
            box add_string(<,symbol),(<(width-1)intdiv 2),<0
        end.
    end.
    box
)
typeset_node =: 4 : 0
    'kind children value column' =. y{::NodePool
    select. kind
    case. 'identifier';'number';'symbol';'command';'text';'reference' do. x typeset_atom y
    case. 'row' do. x typeset_row children
    case. 'script' do. x typeset_script y
    case. 'frac' do. x typeset_fraction y
    case. 'binom' do. x typeset_binomial y
    case. 'overset';'underset' do. x typeset_placed y
    case. 'sqrt';'root' do. x typeset_radical y
    case. 'delim' do.
        body =. x typeset_node 0{children
        delimit_box(<body),value
    case. 'matrix' do. x typeset_matrix y
    case. 'accent' do. x typeset_accent y
    end.
)

build_lines =: 3 : 0
    'breaks types children starts' =. y
    count =. #children
    result =. 0 4$0
    position =. 0
    alignment =. _1
    relation_width =. 0
    while. position<count do.
        indentation =. 0
        if. position do.
            indentation =. parameter 'indent'
            if. alignment~:_1 do.
                indentation =. alignment
                if. 3~:(<position,0){types do.
                    indentation =. alignment+relation_width+parameter 'rel_space'
                end.
            end.
        end.
        ends =. (breaks#~breaks>position),count
        selected =. {.ends
        selected_width =. 0
        for_end. ends do.
            occupied =. ((end-1){starts)+(box_width(end-1){children)-position{starts
            if. end={.ends do.
                selected_width =. occupied
            end.
            if. (indentation+occupied)<:parameter 'width' do.
                selected =. end
                selected_width =. occupied
            end.
        end.
        result =. result,position,selected,indentation,selected_width
        if. position=0 do.
            for_i. i.selected do.
                if. 3=(<i,0){types do.
                    alignment =. i{starts
                    relation_width =. box_width i{children
                    break.
                end.
            end.
        end.
        position =. selected
    end.
    result
)
place_formula =: 3 : 0
    'nodes tag' =. y
    'types gaps' =. 'normal'row_spacing nodes
    children =. starts =. i.0
    position =. 0
    for_i. i.#nodes do.
        child =. 'normal'typeset_node i{nodes
        children =. children,child
        starts =. starts,position
        position =. position+box_width child
        if. i<#gaps do.
            position =. position+i{gaps
        end.
    end.
    relation =. plus_minus =. punctuation =. i.0
    for_i. 1+i.(#nodes)-1 do.
        if. 3=(<i,0){types do.
            relation =. relation,i
        end.
        'kind child value column' =. (i{nodes){::NodePool
        if. (kind-:'symbol')*.((<value)e.(<,'+'),<,'-')*.2=(<i,0){types do.
            plus_minus =. plus_minus,i
        end.
        if. 6=(<(i-1),1){types do.
            punctuation =. punctuation,i
        end.
    end.
    breaks =. relation
    for_trial. i.3 do.
        if. trial=1 do.
            breaks =. /:~~.breaks,plus_minus
        elseif. trial=2 do.
            breaks =. /:~~.breaks,punctuation
        end.
        plan =. build_lines(<breaks),(<types),(<children),<starts
        if. *./((2{"1 plan)+3{"1 plan)<:parameter 'width' do.
            break.
        end.
    end.
    roots =. 0 3$0
    overfull =. 0 2$0
    width =. height =. 0
    for_k. i.#plan do.
        'start end indentation occupied' =. k{plan
        selected =. (start+i.end-start){children
        selected_gaps =. (start+i.(end-start)-1){gaps
        roles =. (#selected)$<''
        line =. assemble_row(<selected),(<selected_gaps),(<'line ',integer k+1),<roles
        roots =. roots,line,indentation,height
        height =. height+box_height line
        width =. width>.indentation+box_width line
        if. (indentation+occupied)>parameter 'width' do.
            overfull =. overfull,(k+1),indentation+occupied
        end.
    end.
    if. #tag do.
        tx =. (parameter 'width')-#tag
        'last last_x last_y' =. _1{roots
        if. tx>:last_x+(box_width last)+2 do.
            ty =. last_y+box_baseline last
        else.
            ty =. height
            height =. height+1
        end.
        tag_box =. new_box(<#tag),(<1),(<0),<'tag "',tag,'"'
        tag_box add_string(<tag),(<0),<0
        roots =. roots,tag_box,tx,ty
        width =. width>.tx+#tag
    end.
    (<roots),(<#plan),(<width),(<height),<overfull
)
node_warnings =: 3 : 0
    'kind children value column' =. y{::NodePool
    if. (kind-:'identifier')*.(<value)e.CommandNames do.
        message =. value,' is a command name; write \',value
        CurrentWarnings =: CurrentWarnings,<(<column),<message
    elseif. (kind-:'reference')*.-.(<value)e.ReferenceNames do.
        CurrentWarnings =: CurrentWarnings,<(<column),<'undefined reference "',value,'"'
    elseif. kind-:'delim' do.
        'left right' =. value
        if. (-.left-:,'.')*.-.right-:,'.' do.
            index =. ((<,'('),(<,'['),(<,'|'),<'\{')i.<left
            expected =. ''
            if. index<4 do.
                expected =. index{::(<,')'),(<,']'),(<,'|'),<'\}'
            end.
            if. -.right-:expected do.
                message =. '\left',left,' closed by \right',right
                CurrentWarnings =: CurrentWarnings,<(<column),<message
            end.
        end.
    end.
    if. kind-:'matrix' do.
        for_row. children do.
            for_child. >row do.
                node_warnings child
            end.
        end.
    else.
        for_child. children do.
            if. child~:_1 do.
                node_warnings child
            end.
        end.
    end.
)
tree_notation =: 3 : 0
    'kind children value column' =. y{::NodePool
    apostrophe =. 39{a.
    select. kind
    case. 'identifier';'number';'command' do. value return.
    case. 'symbol' do. apostrophe,value,apostrophe return.
    case. 'text' do. '"',value,'"' return.
    case. 'reference' do. '(eqref "',value,'")' return.
    case. 'matrix' do.
        text =. '(',value
        for_row. children do.
            cells =. 0$a:
            for_cell. >row do.
                cells =. cells,<tree_notation cell
            end.
            text =. text,' [',(' 'join cells),']'
        end.
        text,')' return.
    case. 'delim' do.
        delimiters =. 0$a:
        for_delimiter. value do.
            text =. >delimiter
            if. 1=#text do.
                text =. apostrophe,text,apostrophe
            end.
            delimiters =. delimiters,<text
        end.
        '(delim ',(' 'join delimiters),' ',(tree_notation 0{children),')' return.
    case. 'script' do.
        'base sub sup' =. children
        name =. 'subsup'
        if. sub=_1 do.
            name =. 'sup'
        elseif. sup=_1 do.
            name =. 'sub'
        end.
        children =. children#~children~:_1
    case. 'accent' do. name =. value
    case. do. name =. kind
    end.
    text =. '(',name
    for_child. children do.
        text =. text,' ',tree_notation child
    end.
    text,')'
)
linear_parenthesized =: 4 : 0
    'node kinds' =. y
    text =. x linear_notation node
    if. (<0{::node{::NodePool)e.kinds do.
        '(',text,')'
    else.
        text
    end.
)
linear_row =: 4 : 0
    'types gaps' =. x row_spacing y
    text =. ''
    for_i. i.#y do.
        if. i do.
            text =. text,((i-1){gaps)$' '
        end.
        text =. text,x linear_notation i{y
    end.
    text
)
delimiter_string =: 3 : 0
    if. y-:,'.' do.
        ''
    else.
        ,{:y
    end.
)
linear_notation =: 4 : 0
    'kind children value column' =. y{::NodePool
    select. kind
    case. 'identifier';'number';'symbol';'text' do. value return.
    case. 'command' do. command_display value return.
    case. 'reference' do. reference_display value return.
    case. 'row' do. x linear_row children return.
    case. 'frac' do.
        kinds =. ;:'row frac'
        top =. x linear_parenthesized(<0{children),<kinds
        bottom =. x linear_parenthesized(<1{children),<kinds
        top,'/',bottom return.
    case. 'script' do.
        'base sub sup' =. children
        text =. x linear_parenthesized(<base),<;:'row frac script'
        kinds =. ;:'row frac'
        if. sub~:_1 do.
            text =. text,'_','script'linear_parenthesized(<sub),<kinds
        end.
        if. sup~:_1 do.
            text =. text,'^','script'linear_parenthesized(<sup),<kinds
        end.
        text return.
    case. 'delim' do.
        (delimiter_string 0{::value),(x linear_notation 0{children),delimiter_string 1{::value return.
    case. 'matrix' do.
        rows =. 0$a:
        for_row. children do.
            cells =. 0$a:
            for_cell. >row do.
                cells =. cells,<x linear_notation cell
            end.
            rows =. rows,<', 'join cells
        end.
        value,'[',('; 'join rows),']' return.
    case. 'root';'overset';'underset' do.
        first =. 'script'linear_notation 0{children
        second =. x linear_notation 1{children
        kind,'(',first,', ',second,')' return.
    case. 'accent' do. name =. value
    case. do. name =. kind
    end.
    parts =. 0$a:
    for_child. children do.
        parts =. parts,<x linear_notation child
    end.
    name,'(',(', 'join parts),')'
)
read_formulas =: 3 : 0
    Formulas =: 0$a:
    for_line. <;._2(1!:1 <'input/formulas.txt') do.
        line =. >line
        'tokens error' =. lex_formula line
        pool =. 0$a:
        elements =. i.0
        tag =. label =. 0$a:
        if. 0=#error do.
            'pool elements tag label error' =. parse_formula tokens
        end.
        formula =. (<line),(<tokens),(<pool),(<elements),(<tag),(<label),(<'')
        Formulas =: Formulas,<formula,(<error),<0$a:
    end.
)
build_references =: 3 : 0
    ReferenceNames =: ReferenceValues =: 0$a:
    counter =. 0
    for_i. i.#Formulas do.
        'line tokens pool elements tag label tag_string error warnings' =. i{::Formulas
        if. #error do.
            continue.
        end.
        if. #tag do.
            tag_string =. '(', (1{::tag), ')'
        elseif. #label do.
            counter =. counter+1
            tag_string =. '(',(integer counter),')'
        end.
        if. #label do.
            'kind name column' =. label
            if. (<name)e.ReferenceNames do.
                warnings =. warnings,<(<column),<'duplicate label "',name,'"'
            else.
                ReferenceNames =: ReferenceNames,<name
                ReferenceValues =: ReferenceValues,<tag_string
            end.
        end.
        formula =. (<line),(<tokens),(<pool),(<elements),(<tag),(<label),(<tag_string),(<error),<warnings
        Formulas =: (<formula)i}Formulas
    end.
)
diagnostic =: 3 : 0
    'number source column message warning' =. y
    prefix =. ''
    if. warning do.
        prefix =. 'warning: '
    end.
    header =. 'formula ',(integer number),', column ',(integer column),': ',prefix,message
    (<header),(<'  ',source),<((column+1)$' '),'^'
)
write_lines =: 4 : 0
    text =. ''
    for_line. y do.
        text =. text,(>line),LF
    end.
    text 1!:2 <'output/',x
)
run =: 3 : 0
    initialize_lexicon ''
    ParameterNames =: 0$a:
    ParameterValues =: i.0
    for_line. <;._2(1!:1 <'input/params.txt') do.
        fields =. split_words >line
        ParameterNames =: ParameterNames,0{fields
        ParameterValues =: ParameterValues,parse_integer 1{::fields
    end.
    read_formulas ''
    build_references ''
    rendered =. boxes =. trees =. errors =. all_kinds =. 0$a:
    total_boxes =. max_depth =. valid_count =. error_count =. warning_count =. overfull_count =. 0
    for_i. i.#Formulas do.
        'line tokens pool elements tag label tag_string error warnings' =. i{::Formulas
        number =. i+1
        header =. 'formula ',integer number
        if. i do.
            rendered =. rendered,<''
        end.
        rendered =. rendered,<header
        if. #error do.
            error_count =. error_count+1
            rendered =. rendered,<'(error)'
            boxes =. boxes,<header,': error'
            trees =. trees,<header,': error'
            'column message' =. error
            errors =. errors,diagnostic(<number),(<line),(<column),(<message),<0
            continue.
        end.
        valid_count =. valid_count+1
        NodePool =: pool
        BoxPool =: 0$a:
        CurrentWarnings =: warnings
        for_element. elements do.
            node_warnings element
        end.
        if. #CurrentWarnings do.
            columns =. 0{::&>CurrentWarnings
            CurrentWarnings =: (/:columns){CurrentWarnings
        end.
        'roots line_count width height overfull' =. place_formula(<elements),<tag_string
        rendered =. rendered,draw_formula(<roots),(<width),<height
        'entries depth kinds' =. box_lines roots
        total_boxes =. total_boxes+#entries
        max_depth =. max_depth>.depth
        all_kinds =. all_kinds,kinds
        detail =. header,': lines=',(integer line_count),' width=',(integer width),' height=',integer height
        detail =. detail,' boxes=',(integer #entries),' depth=',integer depth
        boxes =. boxes,(<detail),entries
        notations =. 0$a:
        for_element. elements do.
            notations =. notations,<tree_notation element
        end.
        trees =. trees,<header,': ',' 'join notations
        linear =. trim_spaces 'normal'linear_row elements
        detail =. '  linear:'
        if. #linear do.
            detail =. detail,' ',linear
        end.
        trees =. trees,<detail
        if. #tag_string do.
            trees =. trees,<'  tag: ',tag_string
        end.
        warning_count =. warning_count+#CurrentWarnings
        for_warning. CurrentWarnings do.
            'column message' =. >warning
            errors =. errors,diagnostic(<number),(<line),(<column),(<message),<1
        end.
        overfull_count =. overfull_count+#overfull
        for_row. overfull do.
            'line_number occupied' =. row
            detail =. header,': line ',(integer line_number),' is overfull (width ',integer occupied
            errors =. errors,<detail,' > ',(integer parameter 'width'),')'
        end.
    end.
    boxes =. boxes,<'summary: boxes=',(integer total_boxes),' max_depth=',integer max_depth
    for_kind. /:~~.all_kinds do.
        count =. +/all_kinds=kind
        boxes =. boxes,<'  ',(>kind),': ',integer count
    end.
    detail =. 'formulas=',(integer #Formulas),' rendered=',(integer valid_count),' errors=',integer error_count
    errors =. errors,<detail,' warnings=',(integer warning_count),' overfull=',integer overfull_count
    try.
        1!:5 <'output'
    catch.
    end.
    'rendered.txt'write_lines rendered
    'boxes.txt'write_lines boxes
    'trees.txt'write_lines trees
    'errors.txt'write_lines errors
)
run ''
