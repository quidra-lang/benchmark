decimal =: 4 : 0
    'numerator denominator' =. x
    scale =. 10^y
    rounded =. ((2*numerator*scale)+denominator)div 2*denominator
    digits =. number scale|rounded
    (number rounded div scale),'.',(-y){.(y$'0'),digits
)
grid_lines =: 3 : '<"1 (GridHeight,GridWidth)$y'
number_lines =: 3 : 0
    lines =. 0$a:
    for_row. i.GridHeight do.
        marks =. 0$a:
        for_column. i.GridWidth do.
            cell =. (row*GridWidth)+column
            if. '#'=cell{GridCells do. mark =. '##'
            elseif. cell{NumberMap do. mark =. _2{.' ',number cell{NumberMap
            else. mark =. ' .' end.
            marks =. marks,<mark
        end.
        lines =. lines,<' ' join marks
    end.
    lines
)
list_line =: 4 : 0
    'clue entry score theme' =. y
    text =. (number x{SlotNumbers),'. ',clue,' (',(number x{SlotLengths),') ',entry,' ',score
    if. theme do. text =. text,' theme' end.
    text
)
