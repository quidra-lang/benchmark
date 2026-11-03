initialize_canvas =: 3 : 0
    'CanvasDirection CanvasMainLength secondary_length' =: y
    CanvasVertical =: (<CanvasDirection)e.;:'TB BT'
    CanvasRows =: secondary_length
    CanvasColumns =: CanvasMainLength
    CanvasMainBit =: 2
    CanvasSecondaryBit =: 1
    if. CanvasVertical do.
        CanvasRows =: CanvasMainLength
        CanvasColumns =: secondary_length
        CanvasMainBit =: 1
        CanvasSecondaryBit =: 2
    end.
    cells =. CanvasRows*CanvasColumns
    CanvasBits =: cells$0
    CanvasArrows =: cells$' '
    CanvasBoxes =: cells$' '
    CanvasHighlighted =: cells$0
)
canvas_cell =: 3 : 0
    'main secondary' =. y
    if. (<CanvasDirection)e.;:'BT RL' do.
        main =. CanvasMainLength-(1+main)
    end.
    if. CanvasVertical do.
        main,secondary
    else.
        secondary,main
    end.
)
canvas_index =: 3 : '(1{y)+CanvasColumns*0{y'
canvas_add_line =: 3 : 0
    'main secondary bit' =. y
    index =. canvas_index canvas_cell main,secondary
    CanvasBits =: ((index{CanvasBits)23 b.bit)index}CanvasBits
)
canvas_main_line =: 3 : 0
    'first last secondary' =. y
    for_main. first+i.0>.1+last-first do.
        canvas_add_line main,secondary,CanvasMainBit
    end.
)
canvas_segment =: 3 : 0
    'start gap first second offset' =. y
    if. first=second do.
        canvas_main_line start,((start+gap)-1),first
        i.0 return.
    end.
    canvas_main_line start,((start+offset)-1),first
    canvas_add_line (start+offset),first,4
    canvas_add_line (start+offset),second,4
    low =. first<.second
    high =. first>.second
    for_secondary. (low+1)+i.0>.high-(low+1) do.
        canvas_add_line (start+offset),secondary,CanvasSecondaryBit
    end.
    canvas_main_line (start+offset+1),((start+gap)-1),second
)
canvas_arrow =: 4 : 0
    direction =. (;:'TB BT LR RL')i.<CanvasDirection
    characters =. 'v^><'
    if. x do.
        characters =. '^v<>'
    end.
    index =. canvas_index canvas_cell y
    CanvasArrows =: (direction{characters)index}CanvasArrows
)
canvas_highlight =: 3 : 0
    for_i. i.(#y)-1 do.
        'row1 column1' =. i{y
        'row2 column2' =. (i+1){y
        row_step =. *row2-row1
        column_step =. *column2-column1
        distance =. (|row2-row1)+|column2-column1
        for_step. i.distance+1 do.
            point =. (row1+step*row_step),column1+step*column_step
            index =. canvas_index point
            CanvasHighlighted =: 1 index}CanvasHighlighted
        end.
    end.
)
canvas_box =: 3 : 0
    'label band coordinate left on_path' =. y
    text =. '[',label,']'
    if. on_path do.
        text =. '{',label,'}'
    end.
    if. CanvasVertical do.
        'row column' =. canvas_cell band,coordinate-left
    elseif. CanvasDirection-:'LR' do.
        row =. coordinate
        column =. band
    else.
        row =. coordinate
        column =. CanvasMainLength-(band+#text)
    end.
    indices =. (CanvasColumns*row)+column+i.#text
    CanvasBoxes =: text indices}CanvasBoxes
)
canvas_character =: 3 : 0
    if. ' '~:y{CanvasBoxes do.
        y{CanvasBoxes
    elseif. ' '~:y{CanvasArrows do.
        y{CanvasArrows
    elseif. y{CanvasHighlighted do.
        '#'
    else.
        (y{CanvasBits){' |-+++++'
    end.
)
canvas_crossings =: 3 : '+/3=3 (17 b.)CanvasBits'
trim_spaces =: 3 : 0
    text =. y
    while. #text do.
        if. ' '~:{:text do.
            break.
        end.
        text =. }:text
    end.
    text
)
canvas_drawing =: 3 : 0
    lines =. <'    ',(10|i.CanvasColumns){'0123456789'
    for_row. i.CanvasRows do.
        text =. ''
        for_column. i.CanvasColumns do.
            text =. text,canvas_character column+CanvasColumns*row
        end.
        prefix =. _3{.'   ',integer row
        lines =. lines,<trim_spaces prefix,' ',text
    end.
    lines
)
