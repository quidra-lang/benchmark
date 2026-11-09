matches =: 4 : 0
    mask =. fold x
    value =. fold y
    pattern =. 0
    position =. 0
    star =. _1
    restart =. 0
    while. position<#value do.
        matched =. 0
        if. pattern<#mask do.
            character =. pattern{mask
            if. character='*' do.
                star =. pattern
                pattern =. pattern+1
                restart =. position
                continue.
            end.
            matched =. (character='?')+.character=position{value
        end.
        if. matched do.
            pattern =. pattern+1
            position =. position+1
        elseif. star~:_1 do.
            restart =. restart+1
            position =. restart
            pattern =. star+1
        else.
            0 return.
        end.
    end.
    while. pattern<#mask do.
        if. '*'~:pattern{mask do.
            break.
        end.
        pattern =. pattern+1
    end.
    pattern=#mask
)
normalize_mask =: 3 : 0
    bang =. '!'e.y
    at =. '@'e.y
    if. bang*.at do.
        y
    elseif. at do.
        '*!',y
    elseif. bang do.
        y,'@*'
    elseif. '.'e.y do.
        '*!*@',y
    else.
        y,'!*@*'
    end.
)
