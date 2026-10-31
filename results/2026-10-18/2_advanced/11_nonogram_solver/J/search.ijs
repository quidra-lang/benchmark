guess_cell =: 3 : 0
    'height width' =. $y
    rows =. +/"1 y=Unknown
    columns =. +/y=Unknown
    best =. 0$0
    bestscore =. 1+height+width
    for_row. i.height do.
        for_column. i.width do.
            if. Unknown=(<row,column){y do.
                score =. (row{rows)+column{columns
                if. score<bestscore do. best =. row,column
                    bestscore =. score end.
            end.
        end.
    end.
    best
)
visit_search =: 4 : 0
    depth =. x
    grid =. y
    'height width' =. $grid
    'row column' =. guess_cell grid
    for_value. Filled,Empty do.
        child =. value (<row,column)}grid
        rowmarks =. 1 row}height$0
        columnmarks =. 1 column}width$0
        propagation =. propagate (<child),(<SearchRows),(<SearchColumns),(<1),(<rowmarks),<columnmarks
        child =. 'grid' get_key propagation
        known =. determined_count child
        conflict =. 'conflict' get_key propagation
        if. #conflict do.
            result =. 'contradiction at=',('row' get_key conflict) line_label 'index' get_key conflict
            SearchBacktracks =: SearchBacktracks+1
        elseif. known=height*width do.
            SearchSolutions =: SearchSolutions,<child
            result =. 'solution',number #SearchSolutions
        else. result =. 'open' end.
        guess =. 'number depth row column value solves known result' record (<1+#SearchGuesses),(<depth),(<row),(<column),(<value),(<#'steps' get_key propagation),(<known),<result
        SearchGuesses =: SearchGuesses,<guess
        if. result-:'open' do.
            if. (depth+1) visit_search child do. 1 return. end.
        elseif. 2=#SearchSolutions do. 1 return. end.
    end.
    0
)
search_grid =: 3 : 0
    'grid rows columns' =. y
    SearchRows =: rows
    SearchColumns =: columns
    SearchGuesses =: SearchSolutions =: 0$a:
    SearchBacktracks =: 0
    1 visit_search grid
    depth =. solves =. 0
    for_box. SearchGuesses do.
        guess =. >box
        depth =. depth>.'depth' get_key guess
        solves =. solves+'solves' get_key guess
    end.
    'guesses solutions backtracks max_depth line_solves' record (<SearchGuesses),(<SearchSolutions),(<SearchBacktracks),(<depth),<solves
)
