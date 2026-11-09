isqrt =: 3 : 0
    if. y=0 do. 0 return. end.
    low =. high =. 1
    while. high<:y div high do. high =. 2*high end.
    while. (low+1)<high do.
        middle =. low+(high-low)div 2
        if. middle<:y div middle do. low =. middle
        else. high =. middle end.
    end.
    low
)
squared_distance =: 4 : '+/*:x-y'
scaled =: 4 : 0
    'step length' =. x
    if. y<0 do. -((-y)*step)div length
    else. (y*step)div length end.
)
advance_point =: 4 : 0
    'point goal' =. y
    delta =. goal-point
    squared =. +/*:delta
    if. squared<:*:x do. (<goal),<1 return. end.
    length =. isqrt squared
    moved =. point+((x,length)scaled 0{delta),(x,length)scaled 1{delta
    (<moved),<0
)
damage_dealt =: 3 : 0
    'hp power armor' =. y
    hp<.1>.power-armor
)
effect_receive =: 4 : 0
    'strength remaining source' =. y
    'amount duration tower' =. x
    if. amount>strength do. amount,duration,tower
    elseif. amount=strength do. strength,(remaining>.duration),source
    else. y end.
)
effect_advance =: 3 : 0
    'strength remaining source' =. y
    remaining =. remaining-1
    if. remaining=0 do. 0 0 0 else. strength,remaining,source end.
)
projectile_fly =: 3 : 0
    speed =. 7{::y
    if. speed=0 do. (<y),<1 return. end.
    'point arrived' =. speed advance_point (3{::y),:4{::y
    projectile =. (<point)3}y
    (<projectile),<arrived
)
