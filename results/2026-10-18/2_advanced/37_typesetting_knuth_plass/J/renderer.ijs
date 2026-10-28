literal_replace =: 4 : 0
    'pattern replacement' =. y
    result =. ''
    position =. 0
    width =. #pattern
    while. position<#x do.
        if. pattern-:width{.position}.x do.
            result =. result,replacement
            position =. position+width
        else.
            result =. result,position{x
            position =. position+1
        end.
    end.
    result
)
trim_right =: 3 : 0
    end =. #y
    while. end>0 do.
        if. ' '~:(end-1){y do.
            break.
        end.
        end =. end-1
    end.
    end{.y
)
display_line =: 3 : 0
    'pieces slack alignment last' =. y
    displayed =. 0$a:
    for_box. pieces do.
        piece =. >box
        displayed =. displayed,<' '(I.piece='~')}piece
    end.
    text =. ' 'join displayed
    if. slack<:0 do.
        text return.
    end.
    gaps =. (#displayed)-1
    if. ((alignment-:'justify')*.-.last)*.gaps>0 do.
        text =. 0{::displayed
        for_index. 1+i.(#displayed)-1 do.
            spaces =. ((slack intdiv gaps)+1)+(index-1)<gaps|slack
            text =. text,(spaces#' '),index{::displayed
        end.
        text return.
    elseif. alignment-:'right' do.
        (slack#' '),text
    elseif. alignment-:'center' do.
        ((slack intdiv 2)#' '),text
    else.
        text
    end.
)
format_table =: 3 : 0
    'rows columns caption number' =. y
    widths =. (#columns)$0
    for_box. rows do.
        row =. >box
        widths =. widths>.#&>row
    end.
    lines =. 0$a:
    if. #caption do.
        lines =. lines,<'Table ',number,'. ',caption
    end.
    for_row_index. i.#rows do.
        row =. row_index{::rows
        cells =. 0$a:
        for_index. i.#columns do.
            text =. index{::row
            missing =. (index{widths)-#text
            alignment =. index{columns
            if. alignment='l' do.
                cell =. text,missing#' '
            elseif. alignment='r' do.
                cell =. (missing#' '),text
            else.
                before =. missing intdiv 2
                cell =. (before#' '),text,(missing-before)#' '
            end.
            cells =. cells,<cell
        end.
        lines =. lines,<trim_right ' | 'join cells
        if. row_index=0 do.
            rules =. 0$a:
            for_width. widths do.
                rules =. rules,<width#'-'
            end.
            lines =. lines,<'-+-'join rules
        end.
    end.
    lines
)
running_head =: 3 : 0
    'fields values width serial' =. y
    names =. 'page';'pages';'chapter';'section'
    expanded =. 0$a:
    for_box. fields do.
        field =. >box
        for_index. i.4 do.
            pattern =. '{',(index{::names),'}'
            field =. field literal_replace (<pattern),<index{::values
        end.
        expanded =. expanded,<field
    end.
    if. 0=2|serial do.
        expanded =. 2 1 0{expanded
    end.
    line =. width#' '
    starts =. 0,((width-#1{::expanded)intdiv 2),width-#2{::expanded
    for_index. i.3 do.
        field =. index{::expanded
        selected =. (index{starts)+i.#field
        line =. field selected}line
    end.
    trim_right line
)
pages_lines =: 3 : 0
    lines =. 0$a:
    for_box. y do.
        page =. >box
        lines =. lines,(<'--- page ',(text 6{::page),' ---'),(<9{::page),(<''),(11{::page),(<''),<10{::page
    end.
    lines
)
