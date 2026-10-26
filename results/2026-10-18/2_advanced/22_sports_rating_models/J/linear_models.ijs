cholesky_solve =: 4 : 0
    count =. #y
    lower =. (count,count)$0.0
    for_i. i.count do.
        for_j. i.i+1 do.
            total =. 0.0
            for_k. i.j do. total =. total+((<i,k){lower)*(<j,k){lower end.
            if. i=j do. value =. %:((<i,i){x)-total
            else. value =. (((<i,j){x)-total)%(<j,j){lower end.
            lower =. value (<i,j)}lower
        end.
    end.
    forward =. result =. count$0.0
    for_i. i.count do.
        total =. 0.0
        for_k. i.i do. total =. total+((<i,k){lower)*k{forward end.
        forward =. (((i{y)-total)%(<i,i){lower)i}forward
    end.
    for_i. |.i.count do.
        total =. 0.0
        for_k. (i+1)+i.count-i+1 do. total =. total+((<k,i){lower)*k{result end.
        result =. (((i{forward)-total)%(<i,i){lower)i}result
    end.
    result
)
gaussian_solve =: 4 : 0
    count =. #y
    for_k. i.count do.
        pivot =. k
        for_row. (k+1)+i.count-k+1 do.
            if. (|(<row,k){x)>|(<pivot,k){x do. pivot =. row end.
        end.
        oldrow =. k{x
        x =. (pivot{x)k}x
        x =. oldrow pivot}x
        oldvalue =. k{y
        y =. (pivot{y)k}y
        y =. oldvalue pivot}y
        for_i. (k+1)+i.count-k+1 do.
            factor =. ((<i,k){x)%(<k,k){x
            for_j. k+i.count-k do. x =. (((<i,j){x)-factor*(<k,j){x)(<i,j)}x end.
            y =. ((i{y)-factor*k{y)i}y
        end.
    end.
    result =. count$0.0
    for_i. |.i.count do.
        total =. 0.0
        for_j. (i+1)+i.count-i+1 do. total =. total+((<i,j){x)*j{result end.
        result =. (((i{y)-total)%(<i,i){x)i}result
    end.
    result
)
colley_ratings =: 3 : 0
    matrix =. (TeamCount,TeamCount)$0.0
    balance =. TeamCount$0
    for_team. i.TeamCount do. matrix =. 2.0 (<team,team)}matrix end.
    for_match. y do.
        'round home away first second' =. match
        matrix =. (1+(<home,home){matrix)(<home,home)}matrix
        matrix =. (1+(<away,away){matrix)(<away,away)}matrix
        matrix =. (((<home,away){matrix)-1)(<home,away)}matrix
        matrix =. (((<away,home){matrix)-1)(<away,home)}matrix
        direction =. *first-second
        balance =. ((home{balance)+direction)home}balance
        balance =. ((away{balance)-direction)away}balance
    end.
    matrix cholesky_solve 1+balance%2
)
massey_ratings =: 3 : 0
    count =. TeamCount+1
    matrix =. (count,count)$0.0
    vector =. count$0.0
    for_match. y do.
        'round home away first second' =. match
        margin =. first-second
        positive =. 5 2$(home,home),(away,away),(home,TeamCount),(TeamCount,home),TeamCount,TeamCount
        for_pair. positive do.
            matrix =. (1+(<pair){matrix)(<pair)}matrix
        end.
        negative =. 4 2$(home,away),(away,home),(away,TeamCount),TeamCount,away
        for_pair. negative do.
            matrix =. (((<pair){matrix)-1)(<pair)}matrix
        end.
        vector =. ((home{vector)+margin)home}vector
        vector =. ((away{vector)-margin)away}vector
        vector =. ((TeamCount{vector)+margin)TeamCount}vector
    end.
    matrix =. ((TeamCount$1.0),0.0)(TeamCount-1)}matrix
    vector =. 0.0 (TeamCount-1)}vector
    solution =. matrix gaussian_solve vector
    (<TeamCount{.solution),<{:solution
)
