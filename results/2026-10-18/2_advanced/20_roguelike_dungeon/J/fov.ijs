DirectionNames =: 'N';'NE';'E';'SE';'S';'SW';'W';'NW'
Directions =: 8 2$0 _1 1 _1 1 0 1 1 0 1 _1 1 _1 0 _1 _1
cell_index =: 3 : '(0{y)+MapWidth*1{y'
passable =: 3 : 0
    'column row' =. y
    if. (column<0)+.(row<0)+.(column>:MapWidth)+.row>:MapHeight do. 0
    else. (cell_index y){Terrain e.'.#+<>' end.
)
can_move =: 4 : 0
    target =. x+y
    if. -.passable target do. 0 return. end.
    if. *./y~:0 do.
        ('+'~:(cell_index x){Terrain)*.'+'~:(cell_index target){Terrain
    else. 1 end.
)
ray_cells =: 4 : 0
    'column row' =. x
    'lastcolumn lastrow' =. y
    dx =. |lastcolumn-column
    dy =. |lastrow-row
    sx =. _1+2*lastcolumn>column
    sy =. _1+2*lastrow>row
    error =. dx-dy
    cells =. 0 2$0
    while. (column~:lastcolumn)+.row~:lastrow do.
        doubled =. 2*error
        if. doubled > -dy do. error =. error-dy
            column =. column+sx end.
        if. doubled<dx do. error =. error+dx
            row =. row+sy end.
        cells =. cells,column,row
    end.
    cells
)
field_of_view =: 3 : 0
    visible =. (MapWidth*MapHeight)$0
    'px py' =. Position
    lowrow =. 0>.py-Radius
    highrow =. MapHeight<.py+Radius+1
    lowcolumn =. 0>.px-Radius
    highcolumn =. MapWidth<.px+Radius+1
    for_row. lowrow+i.highrow-lowrow do.
        for_column. lowcolumn+i.highcolumn-lowcolumn do.
            if. (((column-px)^2)+(row-py)^2)>Radius^2 do. continue. end.
            ray =. Position ray_cells column,row
            clear =. 1
            for_point. }:ray do.
                if. -.passable point do. clear =. 0 break. end.
            end.
            visible =. clear (cell_index column,row)}visible
        end.
    end.
    visible
)
distance_map =: 3 : 0
    distance =. (MapWidth*MapHeight)$_1
    distance =. 0 (cell_index Position)}distance
    queue =. ,:Position
    head =. 0
    while. head<#queue do.
        point =. head{queue
        head =. head+1
        for_direction. Directions do.
            if. point can_move direction do.
                target =. point+direction
                index =. cell_index target
                if. _1=index{distance do.
                    distance =. (1+(cell_index point){distance)index}distance
                    queue =. queue,target
                end.
            end.
        end.
    end.
    distance
)
