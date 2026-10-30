triplet_fu =: 3 : 0
    'block concealed kan' =. y
    if. kan do.
        name =. concealed{::'open_kan';'closed_kan'
        value =. concealed{8 16
    else.
        name =. concealed{::'open_triplet';'closed_triplet'
        value =. concealed{2 4
    end.
    value =. value*1+yaochuu {.block
    ( <name,' ',block_notation block),<value
)
fu_breakdown =: 3 : 0
    'form pair triplets wait closed tsumo seat round_wind pinfu' =. y
    if. form-:'chiitoitsu' do.
        items =. ,<'chiitoitsu';25
        (<items),(<25),<25 return.
    end.
    items =. ,<'base';20
    if. closed*.-.tsumo do.
        items =. items,<'closed_ron';10
    end.
    if. tsumo*.-.pinfu do.
        items =. items,<'tsumo';2
    end.
    pair_value =. 2*((pair>:31)+(pair=seat)+pair=round_wind)
    if. pair_value do.
        items =. items,<('pair ',block_notation 2$pair);pair_value
    end.
    for_triplet. triplets do.
        items =. items,<triplet_fu >triplet
    end.
    if. (<wait)e.;:'kanchan penchan tanki' do.
        items =. items,<('wait ',wait);2
    end.
    total =. 0
    for_item. items do.
        total =. total+1{::>item
    end.
    if. (-.closed)*.total=20 do.
        items =. items,<'open_pinfu';10
        total =. total+10
    end.
    fu =. 10*(total+9)intdiv 10
    (<items),(<total),<fu
)
score_limit =: 4 : 0
    'han fu' =. y
    if. (han>:13)*.3{x do.
        5 8000
    elseif. han>:11 do.
        4 6000
    elseif. han>:8 do.
        3 4000
    elseif. han>:6 do.
        2 3000
    else.
        base =. fu*2^han+2
        if. (han=5)+.(base>:2000)+.((4{x)*.base=1920) do.
            1 2000
        else.
            0,base
        end.
    end.
)
round_hundred =: 3 : '100*(y+99)intdiv 100'
payments =: 3 : 0
    'base dealer tsumo' =. y
    if. -.tsumo do.
        ron =. round_hundred base*4+2*dealer
        ron,0,0,ron
    elseif. dealer do.
        other =. round_hundred 2*base
        0,0,other,3*other
    else.
        dealer_payment =. round_hundred 2*base
        other =. round_hundred base
        0,dealer_payment,other,dealer_payment+2*other
    end.
)
