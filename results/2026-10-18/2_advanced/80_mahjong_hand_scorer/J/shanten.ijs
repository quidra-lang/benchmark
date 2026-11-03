patterns =: 4 : 0 M.
    size =. 7+2*x
    counts =. (size#5)#:y
    present =. I.counts>0
    if. 0=#present do.
        ,:0 0 0 return.
    end.
    first =. {.present
    choices =. ,<(<,first),<0 0 0
    if. 3<:first{counts do.
        choices =. choices,<( <3$first),<1 0 0
    end.
    if. 2<:first{counts do.
        choices =. choices,<( <2$first),<0 1 0
        choices =. choices,<( <2$first),<0 0 1
    end.
    if. x do.
        if. first<:6 do.
            block =. first+i.3
            if. *./0<block{counts do.
                choices =. choices,<( <block),<1 0 0
            end.
        end.
        for_difference. 1 2 do.
            other =. first+difference
            if. other<9 do.
                if. other{counts do.
                    choices =. choices,<( <first,other),<0 1 0
                end.
            end.
        end.
    end.
    best =. 5 2$_1
    for_choice. choices do.
        'removed extra' =. >choice
        remaining =. counts
        for_kind. removed do.
            remaining =. ((kind{remaining)-1)kind}remaining
        end.
        for_tail. x patterns 5#.remaining do.
            'sets partial pair' =. tail+extra
            if. (sets>4)+.pair>1 do.
                continue.
            end.
            partial =. 4<.partial
            position =. <sets,pair
            best =. (partial>.position{best)position}best
        end.
    end.
    result =. 0 3$0
    for_sets. i.5 do.
        for_pair. i.2 do.
            partial =. (<sets,pair){best
            if. partial>:0 do.
                result =. result,sets,partial,pair
            end.
        end.
    end.
    result
)
standard_shanten =: 3 : 0
    states =. ,:0 0 0
    for_suit. i.4 do.
        size =. 9
        if. suit=3 do.
            size =. 7
        end.
        counts =. size{.(9*suit)}.y
        local =. (suit<3)patterns 5#.counts
        best =. 5 2$_1
        for_state. states do.
            for_part. local do.
                'sets partial pair' =. state+part
                if. (sets>4)+.pair>1 do.
                    continue.
                end.
                partial =. 4<.partial
                position =. <sets,pair
                best =. (partial>.position{best)position}best
            end.
        end.
        states =. 0 3$0
        for_sets. i.5 do.
            for_pair. i.2 do.
                partial =. (<sets,pair){best
                if. partial>:0 do.
                    states =. states,sets,partial,pair
                end.
            end.
        end.
    end.
    answer =. 8
    for_state. states do.
        'sets partial pair' =. state
        value =. 8-((2*sets)+(partial<.4-sets)+pair)
        answer =. answer<.value
    end.
    answer
)
shanten_numbers =: 3 : 0
    pairs =. +/y>:2
    kinds =. +/y>:1
    seven =. (6-pairs)+0>.7-kinds
    orphans =. 13-((+/0<Yaochuu{y)+(+./2<:Yaochuu{y))
    (standard_shanten y),seven,orphans
)
