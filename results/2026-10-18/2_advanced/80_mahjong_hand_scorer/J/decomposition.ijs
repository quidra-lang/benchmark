sort_sets =: 3 : 0
    keys =. 0 2$0
    for_block. y do.
        block =. >block
        keys =. keys,({.block),({.block)~:{:block
    end.
    (/:keys){y
)
set_decompositions =: 4 : 0
    if. x=0 do.
        if. 0=+/y do.
            ,<0$a:
        else.
            0$a:
        end.
        return.
    end.
    present =. I.y>0
    if. 0=#present do.
        0$a: return.
    end.
    first =. {.present
    found =. 0$a:
    if. 3<:first{y do.
        remaining =. ((first{y)-3)first}y
        for_tail. (x-1)set_decompositions remaining do.
            found =. found,<(<3$first),>tail
        end.
    end.
    if. (first<27)*.(9|first)<:6 do.
        block =. first+i.3
        if. *./0<block{y do.
            remaining =. ((block{y)-1)block}y
            for_tail. (x-1)set_decompositions remaining do.
                found =. found,<(<block),>tail
            end.
        end.
    end.
    found
)
standard_decompositions =: 4 : 0
    needed =. 4-x
    if. (+/y)~:2+3*needed do.
        0$a: return.
    end.
    found =. 0$a:
    for_pair. I.y>:2 do.
        remaining =. ((pair{y)-2)pair}y
        for_sets. needed set_decompositions remaining do.
            sets =. sort_sets >sets
            found =. found,<( <pair),<sets
        end.
    end.
    ~.found
)
seven_pairs =: 3 : '(7=+/y=2)*.*./y e.0 2'
thirteen_orphans =: 3 : 0
    (14=+/y)*.(*./0<Yaochuu{y)*.*./0=((i.34)-.Yaochuu){y
)
winning_form =: 4 : 0
    if. #x standard_decompositions y do.
        1
    else.
        (x=0)*.(seven_pairs y)+.thirteen_orphans y
    end.
)
waiting_tiles =: 3 : 0
    'hand melds meld_count' =. y
    waiting =. i.0
    for_kind. i.34 do.
        if. 4<:kind{hand+melds do.
            continue.
        end.
        concealed =. ((kind{hand)+1)kind}hand
        if. meld_count winning_form concealed do.
            waiting =. waiting,kind
        end.
    end.
    waiting
)
wait_shape =: 3 : 0
    'form block winning hand_counts' =. y
    if. form-:'chiitoitsu' do.
        'tanki' return.
    elseif. form-:'kokushi' do.
        if. *./1=Yaochuu{hand_counts do.
            'thirteen'
        else.
            'single'
        end.
        return.
    end.
    if. 2=#block do.
        'tanki'
    elseif. ({.block)={:block do.
        'shanpon'
    elseif. winning=1+{.block do.
        'kanchan'
    elseif. (((9|{.block)=0)*.winning=2+{.block)+.(((9|{.block)=6)*.winning={.block) do.
        'penchan'
    else.
        'ryanmen'
    end.
)
