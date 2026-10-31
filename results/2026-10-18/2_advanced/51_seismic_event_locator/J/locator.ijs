PI =: 3.141592653589793
ordered_sum =: 3 : 0
    total =. 0.0
    for_value. y do.
        total =. total+value
    end.
    total
)
atan2 =: 3 : 0
    result =. 12 o.(1{y)j.0{y
    if. result<:-PI do.
        result =. result+2.0*PI
    end.
    result
)
distance =: 4 : 0
    dx =. (0{x)-0{y
    dy =. (1{x)-1{y
    dz =. (2{x)+2{y
    total =. (dx*dx)+dy*dy
    %:total+dz*dz
)
residuals =: 3 : 0
    'solution observations velocity' =. y
    result =. i.0
    for_observation. observations do.
        result =. result,((3{observation)-3{solution)-(solution distance observation)%velocity
    end.
    result
)
rms =: 3 : 0
    errors =. residuals y
    %:(ordered_sum errors*errors)%#errors
)
grid_search =: 3 : 0
    'observations velocity ranges' =. y
    'gx gy gz' =. ranges
    xs =. (0{gx)+(2{gx)*i.1+((1{gx)-0{gx)intdiv 2{gx
    ys =. (0{gy)+(2{gy)*i.1+((1{gy)-0{gy)intdiv 2{gy
    zs =. (0{gz)+(2{gz)*i.1+((1{gz)-0{gz)intdiv 2{gz
    profile =. (#zs)$_
    minimum =. _
    best =. i.0
    for_east. xs do.
        for_north. ys do.
            for_depth. zs do.
                solution =. 0.0+east,north,depth,0
                deltas =. i.0
                for_observation. observations do.
                    value =. (3{observation)-(solution distance observation)%velocity
                    deltas =. deltas,value
                end.
                origin =. (ordered_sum deltas)%#observations
                differences =. deltas-origin
                error =. ordered_sum differences*differences
                if. error<minimum do.
                    best =. origin 3}solution
                    minimum =. error
                end.
                index =. zs i.depth
                if. error<index{profile do.
                    profile =. error index}profile
                end.
            end.
        end.
    end.
    (<best),(<%:minimum%#observations),<%:profile%#observations
)
cholesky =: 3 : 0
    lower =. 4 4$0.0
    for_row. i.4 do.
        for_column. i.row+1 do.
            products =. (column{.row{lower)*column{.column{lower
            total =. ordered_sum products
            value =. ((<row,column){y)-total
            if. row=column do.
                value =. %:value
            else.
                value =. value%(<column,column){lower
            end.
            lower =. value (<row,column)}lower
        end.
    end.
    lower
)
solve_lower =: 3 : 0
    'lower right' =. y
    forward =. 4$0.0
    result =. 4$0.0
    for_row. i.4 do.
        total =. ordered_sum (row{.row{lower)*row{.forward
        value =. ((row{right)-total)%(<row,row){lower
        forward =. value row}forward
    end.
    for_row. |.i.4 do.
        total =. 0.0
        for_column. (row+1)+i.3-row do.
            total =. total+((<column,row){lower)*column{result
        end.
        value =. ((row{forward)-total)%(<row,row){lower
        result =. value row}result
    end.
    result
)
normals =: 3 : 0
    'solution observations velocity' =. y
    matrix =. 4 4$0.0
    right =. 4$0.0
    for_observation. observations do.
        radius =. solution distance observation
        residual =. ((3{observation)-3{solution)-radius%velocity
        dx =. (0{solution)-0{observation
        dy =. (1{solution)-1{observation
        dz =. (2{solution)+2{observation
        derivatives =. ((dx,dy,dz)%(velocity*radius)),1.0
        matrix =. matrix+derivatives */ derivatives
        right =. right+derivatives*residual
    end.
    (<matrix),<right
)
geiger =: 3 : 0
    'initial observations velocity' =. y
    solution =. initial
    trace =. 0 5$0.0
    for_iteration. i.8 do.
        'matrix right' =. normals (<solution),(<observations),<velocity
        change =. solve_lower (<cholesky matrix),<right
        solution =. solution+change
        if. (2{solution)<0.0 do.
            solution =. 0.0 2}solution
        end.
        error =. rms (<solution),(<observations),<velocity
        trace =. trace,solution,error
    end.
    args =. (<solution),(<observations),<velocity
    (<solution),(<trace),(<residuals args),<rms args
)
run_location =: 3 : 0
    'observations velocity ranges' =. y
    grid =. grid_search y
    result =. geiger (0{grid),(<observations),<velocity
    (<grid),<result
)
error_ellipse =: 3 : 0
    'solution observations velocity' =. y
    'matrix right' =. normals y
    lower =. cholesky matrix
    columns =. 0 4$0.0
    for_column. i.4 do.
        unit =. (i.4)=column
        columns =. columns,solve_lower (<lower),<0.0+unit
    end.
    errors =. residuals y
    variance =. (ordered_sum errors*errors)%((#observations)-4)
    covariance =. variance*|:columns
    xx =. (<0,0){covariance
    yy =. (<1,1){covariance
    xy =. (<0,1){covariance
    midpoint =. (xx+yy)%2.0
    difference =. (xx-yy)%2.0
    radius =. %:(difference*difference)+xy*xy
    angle =. atan2 (2.0*xy),xx-yy
    theta =. ((angle%2.0)*180.0)%PI
    azimuth =. 90.0-theta
    if. azimuth>:180.0 do.
        azimuth =. azimuth-180.0
    elseif. azimuth<0.0 do.
        azimuth =. azimuth+180.0
    end.
    (%:midpoint+radius),(%:midpoint-radius),azimuth,(%:(<2,2){covariance),%:(<3,3){covariance
)
