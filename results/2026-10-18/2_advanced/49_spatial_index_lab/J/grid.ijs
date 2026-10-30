grid_position =: 3 : '<.(x:1 2{y)%GridSize'
grid_index =: 3 : 0
    'column row' =. grid_position y
    column+GridSide*row
)
grid_insert =: 3 : 0
    index =. grid_index y
    points =. (index{::GridCells),y
    points =. points /: 0{"1 points
    GridCells =: (<points)index}GridCells
    i.0
)
grid_delete =: 3 : 0
    index =. grid_index y
    points =. index{::GridCells
    points =. points#~(0{"1 points)~:0{y
    GridCells =: (<points)index}GridCells
    i.0
)
grid_build =: 4 : 0
    'world GridSize' =: x
    GridSide =: <.(x:world)%GridSize
    GridCells =: (GridSide*GridSide)$<0 3$0x
    GridBounds =: 0 4$0x
    for_row. i.GridSide do.
        for_column. i.GridSide do.
            lower =. GridSize*column,row
            GridBounds =: GridBounds,lower,(lower+GridSize)-1
        end.
    end.
    for_point. y do.
        grid_insert point
    end.
    i.0
)
