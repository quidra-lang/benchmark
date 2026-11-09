Suits =: 'mpsz'
Winds =: 'ESWN'
Yaochuu =: 0 8 9 17 18 26 27 28 29 30 31 32 33
Green =: 19 20 21 23 25 32
parse_tiles =: 4 : 0
    if. (,y)-:,'-' do.
        if. x do.
            0 2$0
        else.
            _1
        end.
        return.
    end.
    result =. 0 2$0
    digits =. i.0
    for_character. y do.
        if. character e.'0123456789' do.
            digits =. digits,'0123456789'i.character
        elseif. (character e.Suits)*.0<#digits do.
            suit =. Suits i.character
            for_digit. digits do.
                if. (suit=3)*.-.digit e.1 2 3 4 5 6 7 do.
                    _1 return.
                end.
                number =. digit
                if. digit=0 do.
                    number =. 5
                end.
                kind =. (9*suit)+number-1
                result =. result,kind,digit=0
            end.
            digits =. i.0
        else.
            _1 return.
        end.
    end.
    if. (0=#result)+.0<#digits do.
        _1
    else.
        result
    end.
)
invalid_tiles =: 3 : '0=#$y'
tile_name =: 3 : '(integer 1+9|y),(y intdiv 9){Suits'
block_notation =: 3 : 0
    ordered =. /:~y
    (;integer&.>1+9|ordered),(({.ordered)intdiv 9){Suits
)
tile_counts =: 3 : 0
    counts =. 34$0
    for_kind. 0{"1 y do.
        counts =. ((kind{counts)+1)kind}counts
    end.
    counts
)
honor =: 3 : 'y>:27'
terminal =: 3 : '(y<27)*.(9|y)e.0 8'
yaochuu =: 3 : 'y e.Yaochuu'
next_dora =: 3 : 0
    if. y<27 do.
        (9*y intdiv 9)+9|1+9|y
    elseif. y<31 do.
        27+4|y-26
    else.
        31+3|y-30
    end.
)
