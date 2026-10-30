harris_candidates =: 3 : 0
    'gx gy window threshold' =. y
    'height width' =. $gx
    half =. window intdiv 2
    response =. (height,width)$0x
    for_row. i.height do.
        for_column. i.width do.
            xx =. 0x
            yy =. 0x
            xy =. 0x
            for_dy. (-half)+i.1+2*half do.
                for_dx. (-half)+i.1+2*half do.
                    point =. (column+dx),row+dy
                    horizontal =. gx clamped point
                    vertical =. gy clamped point
                    xx =. xx+horizontal*horizontal
                    yy =. yy+vertical*vertical
                    xy =. xy+horizontal*vertical
                end.
            end.
            value =. ((xx*yy)-xy*xy)-((xx+yy)*(xx+yy))intdiv 25
            response =. value (<row,column)}response
        end.
    end.
    candidates =. 0 3$0x
    for_row. i.height do.
        for_column. i.width do.
            value =. (<row,column){response
            if. value<threshold do.
                continue.
            end.
            peak =. 1
            for_dy. _1 0 1 do.
                if. -.peak do.
                    break.
                end.
                for_dx. _1 0 1 do.
                    nx =. column+dx
                    ny =. row+dy
                    if. (nx<0)+.(nx>:width)+.(ny<0)+.ny>:height do.
                        continue.
                    end.
                    if. (dx=0)*.dy=0 do.
                        continue.
                    end.
                    other =. (<ny,nx){response
                    earlier =. (ny<row)+.(ny=row)*.nx<column
                    if. (other>value)+.(other=value)*.earlier do.
                        peak =. 0
                        break.
                    end.
                end.
            end.
            if. peak do.
                candidates =. candidates,column,row,value
            end.
        end.
    end.
    keys =. (-2{"1 candidates),.(1{"1 candidates),.0{"1 candidates
    candidates =. candidates /: keys
    (<response),<candidates
)
