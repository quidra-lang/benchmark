clamped =: 4 : 0
    'height width' =. $x
    'column row' =. y
    column =. (width-1)<.0>.column
    row =. (height-1)<.0>.row
    (<row,column){x
)
smoothing =: 4 : 0
    'size kernel divisor' =. x
    'height width' =. $y
    half =. size intdiv 2
    result =. (height,width)$0x
    for_row. i.height do.
        for_column. i.width do.
            total =. 0x
            for_j. i.size do.
                for_i. i.size do.
                    point =. ((column+i)-half),(row+j)-half
                    total =. total+((i+size*j){kernel)*y clamped point
                end.
            end.
            result =. (total intdiv divisor)(<row,column)}result
        end.
    end.
    result
)
gradient =: 3 : 0
    'height width' =. $y
    gx =. (height,width)$0x
    gy =. gx
    magnitude =. gx
    for_row. i.height do.
        for_column. i.width do.
            q =. i.0x
            for_dy. _1 0 1 do.
                for_dx. _1 0 1 do.
                    q =. q,y clamped (column+dx),row+dy
                end.
            end.
            horizontal =. ((2{q)+(2*5{q)+8{q)-((0{q)+(2*3{q)+6{q)
            vertical =. ((6{q)+(2*7{q)+8{q)-((0{q)+(2*1{q)+2{q)
            gx =. horizontal (<row,column)}gx
            gy =. vertical (<row,column)}gy
            magnitude =. ((|horizontal)+|vertical)(<row,column)}magnitude
        end.
    end.
    (<gx),(<gy),<magnitude
)
