rho =: 4 : 0
    'angle trig step' =. x
    (+/y*angle{trig)intdiv 16384*step
)
circle_points =: 3 : 0
    radius =. y
    a =. radius
    b =. 0x
    error =. 1-radius
    points =. 0 2$0x
    while. a>:b do.
        symmetries =. 8 2$(a,b),(b,a),(-b,a),(-a,b),(-a,-b),(-b,-a),(b,-a),a,-b
        points =. ~.points,symmetries
        b =. b+1
        if. error<0 do.
            error =. error+(2*b)+1
        else.
            a =. a-1
            error =. error+(2*(b-a))+1
        end.
    end.
    points
)
circle_votes =: 3 : 0
    'edges width height low high' =. y
    cells =. ((1+high-low),height,width)$0x
    outlines =. 0$a:
    for_radius. low+i.1+high-low do.
        offsets =. circle_points radius
        outlines =. outlines,<offsets
        radius_index =. radius-low
        for_point. edges do.
            for_offset. offsets do.
                'column row' =. point+offset
                if. (column>:0)*.(column<width)*.(row>:0)*.row<height do.
                    position =. <radius_index,row,column
                    cells =. (1+position{cells)position}cells
                end.
            end.
        end.
    end.
    (<cells),(<outlines),(<low),<high
)
circle_peaks =: 4 : 0
    minimum =. x
    'cells outlines low high' =. y
    'radius_count height width' =. $cells
    sizes =. #&>outlines
    candidate_count =. 0
    peaks =. 0 5$0x
    for_radius_index. i.radius_count do.
        denominator =. radius_index{sizes
        for_row. i.height do.
            for_column. i.width do.
                count =. (<radius_index,row,column){cells
                if. (100*count)<minimum*denominator do.
                    continue.
                end.
                candidate_count =. candidate_count+1
                peak =. 1
                for_dr. _2 _1 0 1 2 do.
                    if. -.peak do.
                        break.
                    end.
                    other_radius =. radius_index+dr
                    if. (other_radius<0)+.other_radius>:radius_count do.
                        continue.
                    end.
                    for_dy. _2 _1 0 1 2 do.
                        if. -.peak do.
                            break.
                        end.
                        ny =. row+dy
                        if. (ny<0)+.ny>:height do.
                            continue.
                        end.
                        for_dx. _2 _1 0 1 2 do.
                            nx =. column+dx
                            if. (nx<0)+.nx>:width do.
                                continue.
                            end.
                            if. (dr=0)*.(dy=0)*.dx=0 do.
                                continue.
                            end.
                            other =. (<other_radius,ny,nx){cells
                            left =. count*other_radius{sizes
                            right =. other*denominator
                            earlier =. other_radius<radius_index
                            if. other_radius=radius_index do.
                                earlier =. (ny<row)+.(ny=row)*.nx<column
                            end.
                            if. (left<right)+.(left=right)*.earlier do.
                                peak =. 0
                                break.
                            end.
                        end.
                    end.
                end.
                if. peak do.
                    peaks =. peaks,(low+radius_index),column,row,count,denominator
                end.
            end.
        end.
    end.
    (<candidate_count),<peaks
)
line_votes =: 3 : 0
    'edges trig step low high' =. y
    votes =. (180,1+high-low)$0x
    for_point. edges do.
        radials =. (trig +/ . * point)intdiv 16384*step
        for_angle. i.180 do.
            column =. (angle{radials)-low
            position =. <angle,column
            votes =. (1+position{votes)position}votes
        end.
    end.
    votes
)
line_peaks =: 3 : 0
    'votes low threshold' =. y
    width =. 1{$votes
    peaks =. 0 3$0x
    for_angle. i.180 do.
        for_column. i.width do.
            count =. (<angle,column){votes
            if. count<threshold do.
                continue.
            end.
            peak =. 1
            for_dt. _2 _1 0 1 2 do.
                if. -.peak do.
                    break.
                end.
                other_angle =. angle+dt
                if. (other_angle<0)+.other_angle>:180 do.
                    continue.
                end.
                for_dr. _2 _1 0 1 2 do.
                    other_column =. column+dr
                    if. (other_column<0)+.other_column>:width do.
                        continue.
                    end.
                    if. (dt=0)*.dr=0 do.
                        continue.
                    end.
                    other =. (<other_angle,other_column){votes
                    earlier =. (other_angle<angle)+.(other_angle=angle)*.other_column<column
                    if. (other>count)+.(other=count)*.earlier do.
                        peak =. 0
                        break.
                    end.
                end.
            end.
            if. peak do.
                peaks =. peaks,angle,(low+column),count
            end.
        end.
    end.
    peaks
)
