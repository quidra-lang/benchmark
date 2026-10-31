g_value =: 4 : 0
    terms =. i.0
    for_direction. i.4 do.
        neighbor =. (<x,direction){Neighbors
        g =. (<x,direction){FaceG
        if. neighbor>:0 do. terms =. terms,g*neighbor{y
        elseif. (<x,direction){BoundaryFaces do. terms =. terms,g*(<x,direction){Theta
        end.
    end.
    (ordered_sum terms)+x{SourceAll
)
iterate =: 3 : 0
    'initial tolerance maximum method omega' =. y
    field =. CellCount#initial
    changes =. i.0
    for_iteration. i.maximum do.
        previous =. field
        updated =. CellCount$0.0
        for_p. i.CellCount do.
            if. 'jacobi'-:method do. target =. (p g_value previous)%p{Diagonal
            else. target =. (p g_value field)%p{Diagonal
            end.
            if. 'jacobi'-:method do. updated =. target p}updated
            elseif. 'gauss_seidel'-:method do. field =. target p}field
            else. field =. ((p{field)+omega*(target-p{field))p}field
            end.
        end.
        if. 'jacobi'-:method do. field =. updated end.
        change =. >./|field-previous
        changes =. changes,change
        if. change<tolerance do. break. end.
    end.
    (<method),(<field),(<changes),(<({:changes)<tolerance),<omega
)
band_solve =: 3 : 0
    vectors =. y
    matrix =. (CellCount,1+2*Width)$0.0
    for_p. i.CellCount do.
        matrix =. (p{Diagonal)(<p,Width)}matrix
        for_direction. i.4 do.
            neighbor =. (<p,direction){Neighbors
            if. neighbor>:0 do.
                offset =. Width+neighbor-p
                matrix =. (-((<p,direction){FaceG))(<p,offset)}matrix
            end.
        end.
    end.
    for_column. i.CellCount do.
        stop =. (CellCount-1)<.column+Width
        for_row. (column+1)+i.stop-column do.
            factor =. ((<row,Width+column-row){matrix)%(<column,Width){matrix
            matrix =. 0.0 (<row,Width+column-row)}matrix
            for_following. (column+1)+i.stop-column do.
                at =. <row,Width+following-row
                value =. (at{matrix)-factor*(<column,Width+following-column){matrix
                matrix =. value at}matrix
            end.
            for_i. i.#vectors do.
                value =. ((<i,row){vectors)-factor*(<i,column){vectors
                vectors =. value (<i,row)}vectors
            end.
        end.
    end.
    solutions =. (0,CellCount)$0.0
    for_values. vectors do.
        field =. CellCount$0.0
        for_row. |.i.CellCount do.
            value =. row{values
            stop =. (CellCount-1)<.row+Width
            for_column. (row+1)+i.stop-row do.
                value =. value-((<row,Width+column-row){matrix)*column{field
            end.
            field =. (value%(<row,Width){matrix)row}field
        end.
        solutions =. solutions,field
    end.
    solutions
)
maximum_residual =: 4 : 0
    maximum =. 0.0
    for_p. i.CellCount do.
        value =. p{x
        for_direction. i.4 do.
            neighbor =. (<p,direction){Neighbors
            if. neighbor>:0 do. value =. value+((<p,direction){FaceG)*neighbor{y end.
        end.
        value =. value-(p{Diagonal)*p{y
        maximum =. maximum>.|value
    end.
    maximum
)
