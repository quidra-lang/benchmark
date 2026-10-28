squared_distance =: 4 : '+/*:x-y'
grid_neighborhoods =: 4 : 0
    points =. x
    radius =. y
    locations =. <.\"1 points%radius
    cells =. ~.<\"1 locations
    members =. 0$a:
    for_cell. cells do.
        members =. members,<I.(<\"1 locations)e.cell
    end.
    neighborhoods =. 0$a:
    candidates =. 0
    for_index. i.#points do.
        'column row' =. index{locations
        neighbors =. i.0
        for_gy. (row-1)+i.3 do.
            for_gx. (column-1)+i.3 do.
                cell_index =. cells i.<gx,gy
                if. cell_index<#cells do.
                    for_other. cell_index{::members do.
                        candidates =. candidates+1
                        if. ((index{points)squared_distance other{points)<:radius*radius do.
                            neighbors =. neighbors,other
                        end.
                    end.
                end.
            end.
        end.
        neighborhoods =. neighborhoods,<neighbors
    end.
    sizes =. #&>members
    coordinates =. >cells
    busiest =. {. /:(-sizes),.(1{\"1 coordinates),.0{\"1 coordinates
    (<cells),(<members),(<neighborhoods),(<candidates),<busiest
)
brute_counts =: 4 : 0
    result =. i.0
    for_point. x do.
        count =. 0
        for_other. x do.
            count =. count+((point squared_distance other)<:y*y)
        end.
        result =. result,count
    end.
    result
)
