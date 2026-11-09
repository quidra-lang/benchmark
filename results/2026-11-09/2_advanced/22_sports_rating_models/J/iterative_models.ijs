bradley_terry =: 3 : 0
    wins =. TeamCount$0.0
    homewins =. 0.0
    for_match. y do.
        home =. 1{match
        away =. 2{match
        result =. (match_result match)%2
        wins =. ((home{wins)+result)home}wins
        wins =. ((away{wins)+1-result)away}wins
        homewins =. homewins+result
    end.
    strengths =. TeamCount$1.0
    theta =. 1.0
    for_iteration. i.BtIterations do.
        zeta =. TeamCount$0.0
        for_match. y do.
            home =. 1{match
            away =. 2{match
            denominator =. (theta*home{strengths)+away{strengths
            zeta =. ((home{zeta)+theta%denominator)home}zeta
            zeta =. ((away{zeta)+1%denominator)away}zeta
        end.
        strengths =. wins%zeta
        total =. sequential_sum strengths
        strengths =. (strengths*TeamCount)%total
        denominator =. 0.0
        for_match. y do.
            home =. (1{match){strengths
            away =. (2{match){strengths
            denominator =. denominator+home%(theta*home)+away
        end.
        theta =. homewins%denominator
    end.
    (<strengths),<theta
)
offense_defense =: 3 : 0
    points =. (TeamCount,TeamCount)$0
    for_match. y do.
        'round home away first second' =. match
        points =. (((<home,away){points)+second)(<home,away)}points
        points =. (((<away,home){points)+first)(<away,home)}points
    end.
    offense =. TeamCount$0.0
    defense =. TeamCount$1.0
    for_iteration. i.OdIterations do.
        for_j. i.TeamCount do.
            total =. 0.0
            for_i. i.TeamCount do. total =. total+((<i,j){points)%i{defense end.
            offense =. total j}offense
        end.
        for_i. i.TeamCount do.
            total =. 0.0
            for_j. i.TeamCount do. total =. total+((<i,j){points)%j{offense end.
            defense =. total i}defense
        end.
    end.
    (<offense),(<defense),<offense%defense
)
