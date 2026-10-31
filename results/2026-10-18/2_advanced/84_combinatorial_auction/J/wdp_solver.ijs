lex_less =: 4 : 0
    count =. (#x)<.#y
    differences =. I.(count{.x)~:count{.y
    if. #differences do.
        position =. {.differences
        (position{x)<position{y
    else.
        (#x)<#y
    end.
)
shares =: 4 : 0
    result =. 0$a:
    for_item. x do.
        share =. x:item{Reserves
        source =. 0
        for_bid. y do.
            if. (2^item)17 b.2{bid do.
                candidate =. (x:3{bid)%mask_size 2{bid
                if. candidate>share do.
                    share =. candidate
                    source =. 0{bid
                end.
            end.
        end.
        result =. result,<( <item),(<share),<source
    end.
    result
)
search_visit =: 3 : 0
    'decided used welfare chosen' =. y
    SearchNodes =: SearchNodes+1
    if. decided=OfferedMask do.
        SearchLeaves =: SearchLeaves+1
        numbers =. /:~chosen
        if. (SearchWelfare=_1)+.(welfare>SearchWelfare)+.((welfare=SearchWelfare)*.numbers lex_less SearchNumbers) do.
            SearchWelfare =: welfare
            SearchNumbers =: numbers
            SearchImprovements =: SearchImprovements,<( <SearchNodes),(<welfare),<numbers
        end.
        i.0 return.
    end.
    available =. 0 5$0
    for_bid. SearchBids do.
        if. decided 17 b.2{bid do.
            continue.
        end.
        if. (4{bid)*.0~:used 17 b.2^1{bid do.
            continue.
        end.
        available =. available,bid
    end.
    remaining =. Offered#~0=(2^Offered)17 b.decided
    upper =. x:welfare
    for_share. remaining shares available do.
        upper =. upper+1{::>share
    end.
    if. (SearchWelfare~:_1)*.upper<SearchWelfare do.
        SearchPruned =: SearchPruned+1
        i.0 return.
    end.
    first =. {.remaining
    for_bid. available do.
        if. (2^first)17 b.2{bid do.
            next_used =. used
            if. 4{bid do.
                next_used =. used 23 b.2^1{bid
            end.
            state =. (<decided 23 b.2{bid),(<next_used),(<welfare+3{bid),<chosen,0{bid
            search_visit state
        end.
    end.
    state =. (<decided 23 b.2^first),(<used),(<welfare+first{Reserves),<chosen
    search_visit state
)
solve =: 3 : 0
    SearchBids =: y
    SearchNodes =: 0
    SearchPruned =: 0
    SearchLeaves =: 0
    SearchWelfare =: _1
    SearchNumbers =: i.0
    SearchImprovements =: 0$a:
    root_shares =. Offered shares y
    root_bound =. 0x
    for_share. root_shares do.
        root_bound =. root_bound+1{::>share
    end.
    search_visit(<0),(<0),(<0),<i.0
    result =. (<SearchWelfare),(<SearchNumbers),(<SearchNodes),(<SearchPruned),(<SearchLeaves)
    result,(<SearchImprovements),(<root_shares),<root_bound
)
greedy_order =: 3 : 0
    order =. 0 5$0
    for_bid. y do.
        position =. #order
        for_index. i.#order do.
            other =. index{order
            left =. (*:3{bid)*mask_size 2{other
            right =. (*:3{other)*mask_size 2{bid
            if. (left>right)+.((left=right)*.(0{bid)<0{other) do.
                position =. index
                break.
            end.
        end.
        order =. (position{.order),(,:bid),position}.order
    end.
    order
)
greedy_select =: 3 : 0
    occupied =. 0
    used =. 0
    chosen =. 0 5$0
    for_bid. y do.
        if. occupied 17 b.2{bid do.
            continue.
        end.
        if. (4{bid)*.0~:used 17 b.2^1{bid do.
            continue.
        end.
        chosen =. chosen,bid
        occupied =. occupied 23 b.2{bid
        if. 4{bid do.
            used =. used 23 b.2^1{bid
        end.
    end.
    chosen
)
