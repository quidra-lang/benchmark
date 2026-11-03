queens =: 3 : 0
    n =. y
    clauses =. 0$a:
    for_row. i.n do.
        clauses =. clauses,<(row*n)+1+i.n
    end.
    for_first. 1+i.n*n do.
        row_first =. (first-1)intdiv n
        column_first =. n|first-1
        for_second. (first+1)+i.(n*n)-first do.
            row_second =. (second-1)intdiv n
            column_second =. n|second-1
            if. (row_first=row_second)+.(column_first=column_second)+.(|row_first-row_second)=|column_first-column_second do.
                clauses =. clauses,<(-first),-second
            end.
        end.
    end.
    (<n*n),(<clauses),<''
)
pigeon =: 3 : 0
    'pigeons holes' =. y
    clauses =. 0$a:
    for_bird. i.pigeons do.
        clauses =. clauses,<(bird*holes)+1+i.holes
    end.
    for_bird. i.pigeons do.
        for_first. 1+i.holes do.
            for_second. (first+1)+i.holes-first do.
                clauses =. clauses,<(-((bird*holes)+first)),-((bird*holes)+second)
            end.
        end.
    end.
    for_hole. 1+i.holes do.
        for_first. i.pigeons do.
            for_second. (first+1)+i.(pigeons-1)-first do.
                clauses =. clauses,<(-((first*holes)+hole)),-((second*holes)+hole)
            end.
        end.
    end.
    (<pigeons*holes),(<clauses),<''
)
coloring =: 3 : 0
    'vertices edges colors' =. y
    clauses =. 0$a:
    for_vertex. i.vertices do.
        clauses =. clauses,<(vertex*colors)+1+i.colors
    end.
    for_vertex. i.vertices do.
        for_first. 1+i.colors do.
            for_second. (first+1)+i.colors-first do.
                clauses =. clauses,<(-((vertex*colors)+first)),-((vertex*colors)+second)
            end.
        end.
    end.
    for_edge. edges do.
        for_color. 1+i.colors do.
            first =. (((0{edge)-1)*colors)+color
            second =. (((1{edge)-1)*colors)+color
            clauses =. clauses,<(-first),-second
        end.
    end.
    (<vertices*colors),(<clauses),<''
)
positions =: 4 : 0
    'rows width' =. y
    matrix =. (rows,width)$x
    result =. i.0
    for_row. matrix do.
        result =. result,1+row i.1
    end.
    result
)
