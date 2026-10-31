parse_dice =: 3 : 'num&> ''d'' split y'
resolve_attack =: 3 : 0
    'tohit defense count sides bonus' =. y
    value =. 1+rnd 20
    if. value=1 do. 0 0 return. end.
    if. value=20 do.
        first =. roll_dice count,sides
        second =. roll_dice count,sides
        2,1>.first+second+bonus
    elseif. (value+tohit)>:defense do.
        damage =. roll_dice count,sides
        1,1>.damage+bonus
    else. 0 0 end.
)
record_attack =: 4 : 0
    'outcome damage' =. y
    stats =. x
    stats =. (1+0{stats)0}stats
    if. outcome do.
        stats =. (1+1{stats)1}stats
        stats =. (damage+3{stats)3}stats
    end.
    stats =. ((2{stats)+outcome=2)2}stats
    stats
)
