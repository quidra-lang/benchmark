ordered_children =: 4 : 0
    minimum =. i.y
    children =. 0 2$0
    for_merge. x do.
        merge =. >merge
        a =. 0{::merge
        b =. 1{::merge
        if. (a{minimum)<b{minimum do. children =. children,a,b
        else. children =. children,b,a end.
        minimum =. minimum,(a{minimum)<.b{minimum
    end.
    children
)
leaf_order =: 4 : 0
    order =. 0$0
    pending =. ,x+(#y)-1
    while. #pending do.
        node =. {:pending
        pending =. }:pending
        if. node<x do. order =. order,node
        else. pending =. pending,|.(node-x){y end.
    end.
    order
)
height_column =: 4 : 0
    'maximum width' =. x
    position =. <.(y%maximum)*width
    if. position>width do. width+1 else. position end.
)
dendrogram_rows =: 3 : 0
    'tree maximum cut_columns' =. y
    'count merges heights children order members depths subtree_heights' =. tree
    grid =. (count,Width+1)$0
    anchor =. ((2*count)-1)$0
    anchor =. (i.count)order}anchor
    for_column. cut_columns do.
        if. column>Width do. continue. end.
        for_row. i.count do. grid =. 1 (<row,column)}grid end.
    end.
    columns =. 0$0
    for_height. heights do. columns =. columns,(maximum,Width)height_column height end.
    for_step. i.#merges do.
        'upper lower' =. step{children
        column =. step{columns
        for_child. upper,lower do. grid =. 4 (<(child{anchor),column)}grid end.
        start_row =. 1+upper{anchor
        end_row =. lower{anchor
        for_row. start_row+i.end_row-start_row do.
            cell =. <row,column
            grid =. (3>.cell{grid)cell}grid
        end.
        for_child. upper,lower do.
            start =. 0
            if. child>:count do. start =. 1+(child-count){columns end.
            for_position. start+i.0>.column-start do.
                cell =. <(child{anchor),position
                grid =. (2>.cell{grid)cell}grid
            end.
        end.
        anchor =. (((upper{anchor)+lower{anchor)div 2)(count+step)}anchor
    end.
    id_width =. >./#&>Ids
    label_width =. >./#&>Labels
    rows =. 0$a:
    for_row. i.count do.
        leaf =. row{order
        id =. leaf{::Ids
        label =. leaf{::Labels
        text =. id,((id_width-#id)$' '),' ',label,((label_width-#label)$' '),' ',(row{grid){' :-|+'
        while. ' '={:text do. text =. }:text end.
        rows =. rows,<text
    end.
    scale =. ''
    for_column. i.Width+1 do.
        if. 0=10|column do. scale =. scale,'+'
        else. scale =. scale,'-' end.
    end.
    rows,<((id_width+label_width+2)$' '),scale
)
