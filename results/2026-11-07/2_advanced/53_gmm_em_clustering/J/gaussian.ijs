Pi =: 1p1
determinant =: 3 : '((0{y)*2{y)-*:1{y'
mahalanobis =: 4 : 0
    'weight mx my a b c' =. y
    'dx dy' =. x-mx,my
    ((((c*dx)*dx)-((2.0*b)*dx)*dy)+(a*dy)*dy)%determinant a,b,c
)
weighted_log_density =: 4 : 0
    (((^.0{y)-^.2.0*Pi)-(^.determinant 3}.y)%2.0)-(x mahalanobis y)%2.0
)
eigen_data =: 3 : 0
    'a b c' =. y
    h =. (a+c)%2.0
    delta =. (a-c)%2.0
    g =. %:(delta*delta)+b*b
    leading =. h+g
    trailing =. h-g
    ux =. 1.0
    uy =. 0.0
    if. b=0.0 do.
        if. a<c do.
            ux =. 0.0
            uy =. 1.0
        end.
    else.
        if. a>:c do.
            vx =. leading-c
            vy =. b
        else.
            vx =. b
            vy =. leading-a
        end.
        length =. %:(vx*vx)+vy*vy
        ux =. vx%length
        uy =. vy%length
        if. vx<0.0 do.
            ux =. -ux
            uy =. -uy
        end.
    end.
    angle =. ((12 o.ux j.uy)*180.0)%Pi
    leading,trailing,ux,uy,angle,(%:leading),(%:trailing),(Pi*%:leading*trailing),b%%:a*c
)
bhattacharyya =: 4 : 0
    cov =. ((3}.x)+3}.y)%2.0
    average =. (3{.x),cov
    ratio =. (determinant cov)%%:(determinant 3}.x)*determinant 3}.y
    distance =. ((1 2{y)mahalanobis average)%8.0
    distance =. distance+(^.ratio)%2.0
    distance,^-distance
)
