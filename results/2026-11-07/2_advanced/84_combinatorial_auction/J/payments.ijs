critical_payments =: 4 : 0
    result =. 0 3$0
    for_bid. y do.
        selected =. greedy_select x#~(0{bid)~:0{"1 x
        rival =. 0
        payment =. bundle_reserve 2{bid
        for_other. selected do.
            overlap =. 0~:(2{bid)17 b.2{other
            same =. (4{bid)*.(1{bid)=1{other
            if. overlap+.same do.
                rival =. 0{other
                threshold =. (*:3{other)*mask_size 2{bid
                size =. mask_size 2{other
                wins_tie =. (0{bid)<0{other
                low =. 1
                high =. 1
                while. -.(((*:high)*size)>threshold)+.((((*:high)*size)=threshold)*.wins_tie) do.
                    high =. high*2
                end.
                while. low<high do.
                    middle =. (low+high)intdiv 2
                    value =. (*:middle)*size
                    if. (value>threshold)+.((value=threshold)*.wins_tie) do.
                        high =. middle
                    else.
                        low =. middle+1
                    end.
                end.
                payment =. payment>.low
                break.
            end.
        end.
        result =. result,(0{bid),payment,rival
    end.
    result
)
vcg_payments =: 4 : 0
    'welfare winning' =. x
    result =. BidderCount$<0$a:
    for_bidder. i.BidderCount do.
        won =. winning#~bidder=1{"1 winning
        if. #won do.
            alternative =. solve y#~bidder~:1{"1 y
            value =. +/3{"1 won
            payment =. (0{::alternative)-(welfare-value)
            result =. (<(<payment),<alternative)bidder}result
        end.
    end.
    result
)
coalition_welfares =: 3 : 0
    masks =. i.2^BidderCount
    keys =. 0$a:
    for_mask. masks do.
        members =. I.0~:(2^i.BidderCount)17 b.mask
        keys =. keys,<(#members),members
    end.
    masks =. (/:keys){masks
    result =. 0$a:
    for_mask. masks do.
        bids =. y#~0~:(2^1{"1 y)17 b.mask
        search =. solve bids
        result =. result,<( <mask),(<0{::search),<1{::search
    end.
    result
)
blocking_coalitions =: 4 : 0
    'seller utilities' =. x
    blocking =. 0$a:
    minimal =. 0$a:
    for_coalition. y do.
        'mask welfare numbers' =. >coalition
        members =. I.0~:(2^i.BidderCount)17 b.mask
        payoff =. seller++/members{utilities
        if. welfare>payoff do.
            is_minimal =. 1
            for_previous. blocking do.
                previous_mask =. 0{::>previous
                if. previous_mask=previous_mask 17 b.mask do.
                    is_minimal =. 0
                    break.
                end.
            end.
            record =. (<mask),(<welfare),(<numbers),(<payoff),<welfare-payoff
            blocking =. blocking,<record
            if. is_minimal do.
                minimal =. minimal,<record
            end.
        end.
    end.
    (<blocking),<minimal
)
gsp_price =: 4 : 0
    if. (y+1)<#x do.
        2{::(y+1){::x
    else.
        0
    end.
)
slot_vcg_payment =: 4 : 0
    'ranking rates' =. x
    payment =. 0x
    count =. (#ranking)<.1+#rates
    for_following. (y+1)+i.count-(y+1) do.
        next =. 0x
        if. following<#rates do.
            next =. following{rates
        end.
        value =. 1{::following{::ranking
        payment =. payment+value*((following-1){rates)-next
    end.
    payment
)
