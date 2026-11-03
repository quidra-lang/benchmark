is_open =: 3 : 0
    'row column' =. y
    if. (row<0)+.(column<0)+.(row>:GridHeight)+.column>:GridWidth do. 0
    else. '#'~:((row*GridWidth)+column){GridCells end.
)
cell_location =: 3 : '((number 1+y div GridWidth),'','',number 1+GridWidth|y)'
white_cells =: 3 : 'I.GridCells~:''#'''
asymmetric_cell =: 3 : 0
    for_row. i.GridHeight do.
        for_column. i.GridWidth do.
            otherrow =. row
            if. y-:'rot180' do. otherrow =. GridHeight-(1+row) end.
            othercolumn =. GridWidth-(1+column)
            if. (is_open row,column)~:is_open otherrow,othercolumn do. (row*GridWidth)+column return. end.
        end.
    end.
    _1
)
component_count =: 3 : 0
    seen =. (#GridCells)$0
    count =. 0
    for_start. white_cells '' do.
        if. start{seen do. continue. end.
        count =. count+1
        seen =. 1 start}seen
        stack =. ,start
        while. #stack do.
            cell =. {:stack
            stack =. }:stack
            point =. (cell div GridWidth),GridWidth|cell
            for_offset. 4 2$_1 0 1 0 0 _1 0 1 do.
                child =. point+offset
                if. is_open child do.
                    index =. (GridWidth*0{child)+1{child
                    if. -.index{seen do. seen =. 1 index}seen
                        stack =. stack,index end.
                end.
            end.
        end.
    end.
    count
)
