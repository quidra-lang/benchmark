expected_score =: 3 : 0
    'home away advantage' =. y
    1%1+10^((away-home)-advantage)%400
)
run_elo =: 4 : 0
    'coefficient advantage initial' =. x
    ratings =. TeamCount$initial+0.0
    expected =. changes =. 0$0.0
    snapshots =. 0$a:
    for_index. i.#y do.
        'round home away first second' =. index{y
        homerat =. home{ratings
        awayrat =. away{ratings
        probability =. expected_score homerat,awayrat,advantage
        margin =. first-second
        multiplier =. 1.0
        if. margin~:0 do.
            if. margin>0 do. difference =. (homerat+advantage)-awayrat
            else. difference =. (awayrat-homerat)-advantage end.
            multiplier =. ((^.1+|margin)*2.2)%2.2+0.001*difference
        end.
        result =. (match_result index{y)%2
        change =. (coefficient*multiplier)*(result-probability)
        ratings =. (homerat+change)home}ratings
        ratings =. (awayrat-change)away}ratings
        expected =. expected,probability
        changes =. changes,change
        last =. index=(#y)-1
        if. -.last do. last =. round~:(< (index+1),0){y end.
        if. last do. snapshots =. snapshots,<ratings end.
    end.
    (<ratings),(<expected),(<changes),<snapshots
)
