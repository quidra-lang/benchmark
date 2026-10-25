line_label =: 4 : '(x{::''C'';''R''),number y+1'
line_cells =: 3 : 0
    'grid row index' =. y
    if. row do. index{grid else. index{"1 grid end.
)
determined_count =: 3 : '+/,y~:Unknown'
step_text =: 3 : 0
    label =. ('row' get_key y) line_label 'index' get_key y
    if. 'contradiction' get_key y do. label,'!' else. label,'+',number 'gain' get_key y end.
)
propagate =: 3 : 0
    'grid rows columns precise rowmarks columnmarks' =. y
    steps =. 0$a:
    conflict =. empty_table ''
    while. (+./rowmarks)+.+./columnmarks do.
        row =. +./rowmarks
        if. row do.
            index =. {.I.rowmarks
            rowmarks =. 0 index}rowmarks
            clue =. index{::rows
        else.
            index =. {.I.columnmarks
            columnmarks =. 0 index}columnmarks
            clue =. index{::columns
        end.
        cells =. line_cells (<grid),(<row),<index
        solved =. solve_line (<cells),(<clue),<precise
        if. solved-:_1 do.
            conflict =. 'row index gain contradiction' record (<row),(<index),(<0),<1
            steps =. steps,<conflict
            break.
        end.
        changed =. I.(cells=Unknown)*.solved~:Unknown
        if. row do.
            grid =. solved index}grid
            columnmarks =. 1 changed}columnmarks
        else.
            grid =. |:solved index}|:grid
            rowmarks =. 1 changed}rowmarks
        end.
        steps =. steps,<'row index gain contradiction' record (<row),(<index),(<#changed),<0
    end.
    'grid steps conflict' record (<grid),(<steps),<conflict
)
