new_grid =: 3 : 0
    ' '$~|.y
)
frame =: 3 : 0
    border =. '+',((1{$y)#'-'),'+'
    lines =. <border
    for_row. y do.
        lines =. lines,<'|',row,'|'
    end.
    lines,<border
)
point_cell =: 3 : 0
    'x y maximum_x maximum_y width height' =. y
    column =. (width-1)<.<.((x+maximum_x)%(2.0*maximum_x))*width
    row =. (height-1)<.<.((maximum_y-y)%(2.0*maximum_y))*height
    row,column
)
diagnostic_cell =: 3 : 0
    't2 spe maximum_x maximum_y width height' =. y
    column =. (width-1)<.<.(t2%maximum_x)*width
    row =. (height-1)-((height-1)<.<.(spe%maximum_y)*height)
    row,column
)
shaft =: 3 : 0
    'origin_row origin_column tip_row tip_column' =. y
    dc =. tip_column-origin_column
    dr =. tip_row-origin_row
    steps =. (|dc)>.|dr
    if. (2*|dr)<:|dc do.
        character =. '-'
    elseif. (2*|dc)<:|dr do.
        character =. '|'
    elseif. (dc*dr)<0 do.
        character =. '/'
    else.
        character =. '\'
    end.
    cells =. 0 3$0
    for_step. 1+i.0>.steps-1 do.
        column =. origin_column+(*dc)*<.(((2*step)*|dc)+steps)%(2*steps)
        row =. origin_row+(*dr)*<.(((2*step)*|dr)+steps)%(2*steps)
        cells =. cells,row,column,a.i.character
    end.
    cells
)
scree_line =: 3 : 0
    'width length kaiser broken' =. y
    cells =. ''
    for_position. 1+i.width do.
        if. position=broken do.
            character =. 'o'
        elseif. position=kaiser do.
            character =. ':'
        elseif. position<:length do.
            character =. '#'
        else.
            character =. ' '
        end.
        cells =. cells,character
    end.
    cells
)
