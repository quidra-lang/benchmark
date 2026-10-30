render_grid =: 4 : 0
    'polygons operands' =. x
    'x0 y0 width height columns rows' =. y
    result_rings =. ;polygons
    lines =. 0$a:
    counts =. 4$0
    for_row. i.rows do.
        cells =. ''
        remaining =. rows-(1+row)
        yy =. y0+((x:1+2*remaining)*height)%2
        for_column. i.columns do.
            xx =. x0+((x:1+2*column)*width)%2
            point =. xx,yy
            character =. '.'
            if. result_rings interior point do.
                character =. '#'
            elseif. #operands do.
                a =. (2{::0{::operands)interior point
                b =. (2{::1{::operands)interior point
                if. a*.b do.
                    character =. '+'
                elseif. a do.
                    character =. 'a'
                elseif. b do.
                    character =. 'b'
                end.
            end.
            cells =. cells,character
            index =. '#ab+'i.character
            if. index<4 do.
                counts =. (1+index{counts)index}counts
            end.
        end.
        lines =. lines,<cells
    end.
    (<lines),<counts
)
