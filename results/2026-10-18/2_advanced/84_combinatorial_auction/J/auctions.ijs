candidates =: 4 : 0
    result =. 0 3$0
    for_number. 1+i.<:2^#y do.
        selected =. I.0~:(2^i.#y)17 b.number
        if. x*.1~:#selected do.
            continue.
        end.
        bundle =. 0
        value =. 0
        good =. 1
        for_index. selected do.
            bid =. index{y
            if. bundle 17 b.2{bid do.
                good =. 0
                break.
            end.
            bundle =. bundle 23 b.2{bid
            value =. value+3{bid
        end.
        if. good do.
            result =. result,number,bundle,value
        end.
    end.
    result
)
value_of =: 4 : 0
    value =. 0
    for_candidate. x do.
        bundle =. 1{candidate
        if. bundle=bundle 17 b.y do.
            value =. value>.2{candidate
        end.
    end.
    value
)
english =: 3 : 0
    'values reserve increment' =. y
    price =. reserve
    paid =. 0
    steps =. 0
    remaining =. I.values>:price
    winner =. _1
    while. 1<#remaining do.
        previous =. remaining
        price =. price+increment
        steps =. steps+1
        remaining =. I.values>:price
        if. 0=#remaining do.
            winner =. {.previous
            paid =. price-increment
            break.
        end.
    end.
    if. #remaining do.
        winner =. {.remaining
        paid =. price
    end.
    drops =. (#values)$_1
    for_index. i.#values do.
        value =. index{values
        drop =. reserve
        if. value>:reserve do.
            drop =. reserve+increment*1+(value-reserve)intdiv increment
        end.
        if. drop<:price do.
            drops =. drop index}drops
        end.
    end.
    (<winner),(<paid),(<steps),<drops
)
dutch =: 3 : 0
    'bids reserve price decrement' =. y
    steps =. 0
    while. price>:reserve do.
        eligible =. I.bids>:price
        if. #eligible do.
            winner =. eligible{~(eligible{bids)i.>./eligible{bids
            winner,price,steps return.
        end.
        price =. price-decrement
        steps =. steps+1
    end.
    _1,0,steps
)
