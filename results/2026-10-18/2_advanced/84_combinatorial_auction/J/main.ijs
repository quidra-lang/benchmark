load 'bids_io.ijs'
load 'wdp_solver.ijs'
load 'payments.ijs'
load 'auctions.ijs'
load 'report.ijs'

Formats =: ;:'first_price second_price english dutch all_pay'
Outcomes =: ;:'vcg greedy critical saa'
intdiv =: 4 : '<.(x:x)%x:y'
integer =: 3 : 0
    text =. ,":y
    '-'(I.text='_')}text
)
parse_integer =: 3 : '".y'
join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do.
            text =. text,x
        end.
        text =. text,i{::y
    end.
    text
)
split_char =: 4 : 0
    fields =. 0$a:
    text =. ''
    for_char. y do.
        if. char=x do.
            fields =. fields,<text
            text =. ''
        else.
            text =. text,char
        end.
    end.
    fields,<text
)
records =: 3 : 0
    lines =. <;._2 (1!:1 <'input/',y)
    ' 'split_char&.>lines
)
mask_items =: 3 : 'I.0~:(2^i.ItemCount)17 b.y'
mask_size =: 3 : '#mask_items y'
bundle_reserve =: 3 : '+/(mask_items y){Reserves'
mask_of =: 3 : '+/2^y'
numbers =: 3 : ''' ''join integer&.>y'
names_or_dash =: 3 : 0
    if. #y do.
        ' 'join y
    else.
        ,'-'
    end.
)
bidder_name =: 3 : 0
    if. y=_1 do.
        ,'-'
    else.
        y{::BidderNames
    end.
)
valid_amount =: 3 : 0
    if. (0=#y)+.5<#y do.
        0 return.
    end.
    if. -.*/y e.'0123456789' do.
        0 return.
    end.
    -.((1<#y)*.'0'={.y)
)
bid_error =: 4 : 0
    earlier =. x
    parts =. ':'split_char y
    if. 2~:#parts do.
        (<'malformed bid'),(<0),<0 return.
    end.
    items =. '+'split_char 0{::parts
    amount_text =. 1{::parts
    good =. valid_amount amount_text
    for_item. items do.
        item =. >item
        good =. good*.(0<#item)*.*/item e.'abcdefghijklmnopqrstuvwxyz'
    end.
    if. -.good do.
        (<'malformed bid'),(<0),<0 return.
    end.
    seen =. i.0
    for_name. items do.
        name =. >name
        item =. ItemNames i.<name
        if. item=ItemCount do.
            (<'unknown item ',name),(<0),<0 return.
        elseif. -.item e.Offered do.
            (<'item not offered ',name),(<0),<0 return.
        elseif. item e.seen do.
            (<'duplicate item ',name),(<0),<0 return.
        end.
        seen =. seen,item
    end.
    if. (#items)>parameter 'max_bundle_size' do.
        (<'bundle too large'),(<0),<0 return.
    end.
    amount =. parse_integer amount_text
    if. amount=0 do.
        (<'zero value'),(<0),<0 return.
    end.
    mask =. mask_of seen
    duplicates =. I.mask=2{"1 earlier
    if. #duplicates do.
        number =. 0{({.duplicates){earlier
        (<'duplicate bundle ',integer number),(<0),<0 return.
    end.
    if. (#earlier)>:parameter 'max_bids_per_bidder' do.
        (<'too many bids'),(<0),<0 return.
    end.
    (<''),(<mask),<amount
)
validate_bids =: 3 : 0
    'AuctionName Offered lines' =. y
    OfferedMask =: mask_of Offered
    BidderNames =: 0$a:
    Languages =: 0$a:
    Valid =: 0 5$0
    Eligible =: 0 5$0
    Below =: 0 6$0
    Rejected =: 0$a:
    BidCount =: 0
    ValidCounts =: i.0
    EligibleCounts =: i.0
    seen =. 0$a:
    for_line. lines do.
        'name language strings' =. >line
        error =. ''
        if. (<name)e.seen do.
            error =. 'duplicate bidder'
        elseif. -.(<language)e.'XOR';'OR' do.
            error =. 'bad language ',language
        end.
        seen =. seen,<name
        earlier =. 0 5$0
        bidder =. #BidderNames
        if. 0=#error do.
            BidderNames =: BidderNames,<name
            Languages =: Languages,<language
            ValidCounts =: ValidCounts,0
            EligibleCounts =: EligibleCounts,0
        end.
        for_text. strings do.
            BidCount =: BidCount+1
            if. #error do.
                Rejected =: Rejected,<( <BidCount),(<name),<error
                continue.
            end.
            'reason mask amount' =. earlier bid_error >text
            if. #reason do.
                Rejected =: Rejected,<( <BidCount),(<name),<reason
                continue.
            end.
            bid =. (BidCount,bidder,language-:'XOR')new_bid mask,amount
            earlier =. earlier,bid
            Valid =: Valid,bid
            ValidCounts =: ((bidder{ValidCounts)+1)bidder}ValidCounts
            reserve =. bundle_reserve mask
            if. amount>:reserve do.
                Eligible =: Eligible,bid
                EligibleCounts =: ((bidder{EligibleCounts)+1)bidder}EligibleCounts
            else.
                Below =: Below,bid,reserve
            end.
        end.
    end.
    BidderCount =: #BidderNames
)
allocation =: 3 : 0
    winning =. (/:0{"1 y){y
    owners =. ItemCount$_1
    accepted =. +/3{"1 winning
    for_bid. winning do.
        owners =. (1{bid)(mask_items 2{bid)}owners
    end.
    unsold =. Offered#~_1=Offered{owners
    retained =. +/unsold{Reserves
    (<winning),(<owners),(<unsold),(<accepted),(<retained),<accepted+retained
)
prepare_auction =: 3 : 0
    validate_bids y
    Optimal =: solve Eligible
    OptimalBids =: Eligible#~(0{"1 Eligible)e.1{::Optimal
    Exact =: allocation OptimalBids
    GreedyOrder =: greedy_order Eligible
    Greedy =: allocation greedy_select GreedyOrder
    Critical =: GreedyOrder critical_payments 0{::Greedy
    VcgDetails =: ((<0{::Optimal),<OptimalBids)vcg_payments Eligible
    Values =: BidderCount$0
    GreedyValues =: BidderCount$0
    VcgPaid =: BidderCount$0
    CriticalPaid =: BidderCount$0
    for_bidder. i.BidderCount do.
        value =. +/3{"1 OptimalBids#~bidder=1{"1 OptimalBids
        Values =: value bidder}Values
        greedy_bids =. 0{::Greedy
        own =. greedy_bids#~bidder=1{"1 greedy_bids
        GreedyValues =: (+/3{"1 own)bidder}GreedyValues
        if. #bidder{::VcgDetails do.
            VcgPaid =: (0{::bidder{::VcgDetails)bidder}VcgPaid
        end.
        critical_rows =. Critical#~(0{"1 Critical)e.0{"1 own
        CriticalPaid =: (+/1{"1 critical_rows)bidder}CriticalPaid
    end.
    VcgUtilities =: Values-VcgPaid
    CriticalUtilities =: GreedyValues-CriticalPaid
    VcgRevenue =: +/VcgPaid
    CriticalRevenue =: +/CriticalPaid
)
ascending =: 3 : 0
    increment =. parameter 'saa_increment'
    choices =. 0$a:
    eligibility =. i.0
    for_bidder. i.BidderCount do.
        bids =. Valid#~bidder=1{"1 Valid
        candidate =. ((bidder{::Languages)-:'XOR')candidates bids
        choices =. choices,<candidate
        maximum =. 0
        for_row. candidate do.
            maximum =. maximum>.mask_size 1{row
        end.
        eligibility =. eligibility,maximum
    end.
    prices =. Reserves
    holders =. ItemCount$_1
    bid_counts =. ItemCount$0
    bid_rounds =. ItemCount$0
    last_rounds =. ItemCount$0
    random =. parameter 'seed'
    lines =. <'AUCTION ',AuctionName,' increment ',integer increment
    for_round. 1+i.parameter 'round_cap' do.
        activities =. BidderCount$0
        new =. BidderCount$0
        demand =. 0
        for_bidder. i.BidderCount do.
            held =. mask_of Offered#~bidder=Offered{holders
            asking =. prices+increment*(_1~:holders)*.bidder~:holders
            best =. 0
            demanded =. 0
            for_candidate. bidder{::choices do.
                'number mask value' =. candidate
                if. (mask_size mask 23 b.held)<:bidder{eligibility do.
                    surplus =. value-+/(mask_items mask){asking
                    if. surplus>best do.
                        best =. surplus
                        demanded =. mask
                    end.
                end.
            end.
            activities =. (mask_size demanded 23 b.held)bidder}activities
            fresh =. demanded-held 17 b.demanded
            new =. fresh bidder}new
            demand =. demand+mask_size fresh
        end.
        line =. 'ROUND ',integer round
        if. demand do.
            line =. line,' demand ',integer demand
            for_bidder. I.new~:0 do.
                line =. line,' ',(bidder_name bidder),':',bundle bidder{new
            end.
            lines =. lines,<line
            for_item. Offered do.
                bidders =. I.0~:(2^item)17 b.new
                if. 0=#bidders do.
                    continue.
                end.
                winner =. {.bidders
                if. 1<#bidders do.
                    random =. 2147483647|48271*random
                    winner =. ((#bidders)|random){bidders
                end.
                if. _1~:item{holders do.
                    prices =. ((item{prices)+increment)item}prices
                end.
                holders =. winner item}holders
                bid_counts =. ((item{bid_counts)+#bidders)item}bid_counts
                bid_rounds =. (1+item{bid_rounds)item}bid_rounds
                last_rounds =. round item}last_rounds
            end.
            line =. 'STANDING'
            for_item. Offered do.
                line =. line,' ',(item{::ItemNames),'=',(integer item{prices),'@',bidder_name item{holders
            end.
            lines =. lines,<line
        else.
            lines =. lines,<line,' none'
        end.
        changed =. I.activities<eligibility
        if. #changed do.
            line =. 'ELIGIBILITY'
            for_bidder. changed do.
                eligibility =. (bidder{activities)bidder}eligibility
                line =. line,' ',(bidder_name bidder),'=',integer bidder{eligibility
            end.
            lines =. lines,<line
        end.
        reason =. 'quiet'
        if. demand do.
            reason =. 'cap'
        end.
        if. (demand=0)+.round=parameter 'round_cap' do.
            break.
        end.
    end.
    lines =. lines,<'END rounds ',(integer round),' ',reason
    for_item. Offered do.
        line =. 'ITEM ',item{::ItemNames
        if. _1=item{holders do.
            line =. line,' unsold reserve ',integer item{Reserves
        else.
            line =. line,' price ',(integer item{prices),' holder ',bidder_name item{holders
            line =. line,' bids ',(integer item{bid_counts),' rounds ',integer item{bid_rounds
            line =. line,' last ',integer item{last_rounds
        end.
        lines =. lines,<line
    end.
    paid =. i.0
    utilities =. i.0
    value_total =. 0
    exposure =. 0
    exposed =. 0
    for_bidder. i.BidderCount do.
        won_items =. Offered#~bidder=Offered{holders
        won =. mask_of won_items
        payment =. +/won_items{prices
        value =. (bidder{::choices)value_of won
        utility =. value-payment
        paid =. paid,payment
        utilities =. utilities,utility
        value_total =. value_total+value
        line =. 'BIDDER ',(bidder_name bidder),' won ',(bundle won),' paid ',integer payment
        line =. line,' value ',(integer value),' utility ',(integer utility),' eligibility ',integer bidder{eligibility
        if. utility<0 do.
            line =. line,' exposed'
            exposure =. exposure-utility
            exposed =. exposed+1
        end.
        lines =. lines,<line
    end.
    revenue =. +/paid
    retained =. +/Reserves{~Offered#~_1=Offered{holders
    welfare =. value_total+retained
    line =. 'TOTAL revenue ',(integer revenue),' welfare ',integer welfare
    line =. line,' efficiency ',(fraction (x:welfare)%0{::Optimal),' exposure ',integer exposure
    lines =. lines,<line,' exposed ',integer exposed
    AscendingLines =: AscendingLines,lines
    SaaPaid =: paid
    SaaUtilities =: utilities
    SaaRevenue =: revenue
    SaaRetained =: retained
    SaaWelfare =: welfare
    AscendingTotals =: AscendingTotals+1,round,(reason-:'cap'),exposed,exposure
)
bid_line =: 4 : 0
    'number bidder mask amount xor' =. y
    x,' ',(integer number),' ',(bidder_name bidder),' ',(bundle mask),' ',integer amount
)
wdp_report =: 3 : 0
    line =. 'AUCTION ',AuctionName,' items ',(integer #Offered),' bidders ',integer BidderCount
    line =. line,' bids ',(integer BidCount),' valid ',(integer #Valid),' eligible ',integer #Eligible
    lines =. <line
    for_bidder. i.BidderCount do.
        line =. 'BIDDER ',(bidder_name bidder),' ',(bidder{::Languages),' valid ',integer bidder{ValidCounts
        lines =. lines,<line,' eligible ',integer bidder{EligibleCounts
    end.
    for_rejected. Rejected do.
        'number name reason' =. >rejected
        lines =. lines,<'REJECT ',(integer number),' ',name,' ',reason
    end.
    for_bid. Below do.
        line =. 'BELOW_RESERVE ',(integer 0{bid),' ',(bidder_name 1{bid),' value ',integer 3{bid
        lines =. lines,<line,' reserve ',integer 5{bid
    end.
    for_share. 6{::Optimal do.
        'item value source' =. >share
        line =. 'SHARE ',(item{::ItemNames),' ',(fraction value),' '
        if. source do.
            line =. line,'bid ',integer source
        else.
            line =. line,'reserve'
        end.
        lines =. lines,<line
    end.
    lines =. lines,<'ROOT_BOUND ',fraction 7{::Optimal
    for_improvement. 5{::Optimal do.
        'nodes welfare chosen' =. >improvement
        lines =. lines,<'IMPROVE ',(integer nodes),' welfare ',(integer welfare),' bids ',number_list chosen
    end.
    line =. 'OPTIMAL welfare ',(integer 5{::Exact),' accepted ',integer 3{::Exact
    lines =. lines,<line,' retained ',(integer 4{::Exact),' winners ',integer #0{::Exact
    for_bid. 0{::Exact do.
        lines =. lines,<'WIN'bid_line bid
    end.
    lines =. lines,<'UNSOLD ',names_or_dash (2{::Exact){ItemNames
    line =. 'SEARCH nodes ',(integer 2{::Optimal),' pruned ',integer 3{::Optimal
    lines =. lines,<line,' leaves ',(integer 4{::Optimal),' improvements ',integer #5{::Optimal
    order =. '-'
    if. #GreedyOrder do.
        order =. numbers 0{"1 GreedyOrder
    end.
    lines =. lines,<'GREEDY_ORDER ',order
    line =. 'GREEDY welfare ',(integer 5{::Greedy),' accepted ',integer 3{::Greedy
    line =. line,' retained ',(integer 4{::Greedy),' winners ',integer #0{::Greedy
    lines =. lines,<line,' efficiency ',fraction (x:5{::Greedy)%0{::Optimal
    for_bid. 0{::Greedy do.
        row =. ((0{"1 Critical)i.0{bid){Critical
        rival =. '-'
        if. 2{row do.
            rival =. integer 2{row
        end.
        line =. 'GWIN'bid_line bid
        lines =. lines,<line,' critical ',(integer 1{row),' against ',rival
    end.
    lines =. lines,<'GUNSOLD ',names_or_dash (2{::Greedy){ItemNames
    for_item. Offered do.
        demand =. +/0~:(2^item)17 b.2{"1 Eligible
        line =. 'ITEM ',(item{::ItemNames),' reserve ',(integer item{Reserves),' demand ',integer demand
        line =. line,' optimal ',bidder_name item{1{::Exact
        lines =. lines,<line,' greedy ',bidder_name item{1{::Greedy
    end.
    WdpLines =: WdpLines,lines
)
vcg_report =: 3 : 0
    lines =. <'AUCTION ',AuctionName,' welfare ',integer 0{::Optimal
    for_bidder. i.BidderCount do.
        line =. 'BIDDER ',bidder_name bidder
        details =. bidder{::VcgDetails
        if. 0=#details do.
            lines =. lines,<line,' lost'
            continue.
        end.
        'payment alternative' =. details
        won =. 0{"1 OptimalBids#~bidder=1{"1 OptimalBids
        line =. line,' won ',(number_list won),' value ',integer bidder{Values
        line =. line,' without ',(integer 0{::alternative),' alternative ',number_list 1{::alternative
        lines =. lines,<line,' payment ',(integer payment),' utility ',integer bidder{VcgUtilities
    end.
    line =. 'TOTAL revenue ',(integer VcgRevenue),' pay_as_bid ',integer 3{::Exact
    line =. line,' retained ',(integer 4{::Exact),' seller ',integer VcgRevenue+4{::Exact
    lines =. lines,<line,' bidders ',integer +/VcgUtilities
    for_bidder. i.BidderCount do.
        line =. 'PAYMENTS ',(bidder_name bidder),' vcg ',(integer bidder{VcgPaid),' pay_as_bid ',integer bidder{Values
        line =. line,' greedy ',(integer bidder{GreedyValues),' critical ',integer bidder{CriticalPaid
        lines =. lines,<line,' saa ',integer bidder{SaaPaid
    end.
    for_bidder. i.BidderCount do.
        line =. 'UTILITIES ',(bidder_name bidder),' vcg ',integer bidder{VcgUtilities
        lines =. lines,<line,' critical ',(integer bidder{CriticalUtilities),' saa ',integer bidder{SaaUtilities
    end.
    VcgLines =: VcgLines,lines
)
coalition_text =: 3 : 0
    members =. I.0~:(2^i.BidderCount)17 b.y
    if. #members do.
        '+'join members{BidderNames
    else.
        ,'-'
    end.
)
core_report =: 3 : 0
    lines =. <'AUCTION ',AuctionName,' bidders ',integer BidderCount
    if. BidderCount>parameter 'core_max_bidders' do.
        CoreLines =: CoreLines,lines,<'SKIPPED'
        CoreTotals =: CoreTotals+0 1 0 0 0 0
        i.0 return.
    end.
    CoreTotals =: CoreTotals+1 0 0 0 0 0
    coalitions =. coalition_welfares Eligible
    lines =. lines,<'COALITIONS ',integer #coalitions
    sellers =. (VcgRevenue+4{::Exact),(5{::Greedy),(CriticalRevenue+4{::Greedy),SaaRevenue+SaaRetained
    utilities =. (<VcgUtilities),(<BidderCount$0),(<CriticalUtilities),<SaaUtilities
    for_index. i.4 do.
        name =. index{::Outcomes
        seller =. index{sellers
        utility =. index{::utilities
        lines =. lines,<'OUTCOME ',name,' seller ',(integer seller),' utilities ',numbers utility
        'blocking minimal' =. ((<seller),<utility)blocking_coalitions coalitions
        for_record. minimal do.
            'mask welfare winning payoff deficit' =. >record
            line =. 'BLOCK ',(coalition_text mask),' welfare ',(integer welfare),' payoff ',integer payoff
            lines =. lines,<line,' deficit ',(integer deficit),' bids ',number_list winning
        end.
        if. 0=#blocking do.
            lines =. lines,<'RESULT core'
            position =. index+2
            CoreTotals =: (1+position{CoreTotals)position}CoreTotals
        else.
            best =. 0{::blocking
            for_record. }.blocking do.
                record =. >record
                if. (4{::record)>4{::best do.
                    best =. record
                end.
            end.
            line =. 'RESULT blocked ',(integer #blocking),' minimal ',integer #minimal
            lines =. lines,<line,' max_deficit ',(integer 4{::best),' by ',coalition_text 0{::best
        end.
    end.
    CoreLines =: CoreLines,lines
)
summary_row =: 4 : 0
    'name mechanism' =. x
    SummaryLines =: SummaryLines,<name,'/',mechanism,',',','join fraction&.>y
)
process_auctions =: 3 : 0
    for_name. parameter 'run' do.
        index =. RawNames i.name
        raw =. name,(index{RawOffers),index{RawLines
        prepare_auction raw
        ascending ''
        wdp_report ''
        vcg_report ''
        core_report ''
        counts =. 1,BidCount,(#Valid),(#Eligible),(2{::Optimal),(5{::Greedy)=0{::Optimal
        WdpTotals =: WdpTotals+counts
        revenues =. VcgRevenue,(3{::Exact),(3{::Greedy),CriticalRevenue,SaaRevenue
        VcgTotals =: VcgTotals+revenues
        mechanisms =. ;:'vcg pay_as_bid greedy critical saa'
        welfares =. (0{::Optimal),(0{::Optimal),(5{::Greedy),(5{::Greedy),SaaWelfare
        for_i. i.5 do.
            welfare =. i{welfares
            ((<AuctionName),<i{::mechanisms)summary_row (i{revenues),welfare,(x:welfare)%0{::Optimal
        end.
    end.
)
duplicate_name =: 3 : 0
    seen =. 0$a:
    for_participant. y do.
        name =. 0{::>participant
        if. (<name)e.seen do.
            name return.
        end.
        seen =. seen,<name
    end.
    ''
)
validate_lot =: 3 : 0
    participants =. 3{::y
    if. 0=#participants do.
        'no bidders' return.
    end.
    duplicate =. duplicate_name participants
    if. #duplicate do.
        'duplicate bidder ',duplicate return.
    end.
    for_participant. participants do.
        'name value bid' =. >participant
        if. bid>value do.
            'bid above value ',name return.
        end.
    end.
    ''
)
validate_slots =: 3 : 0
    'kind name arguments participants' =. y
    rates =. i.0x
    for_text. arguments do.
        text =. >text
        parts =. '/'split_char text
        good =. 2=#parts
        if. good do.
            for_part. parts do.
                part =. >part
                if. 0=#part do.
                    good =. 0
                else.
                    good =. good*.('0'~:{.part)*.*/part e.'0123456789'
                end.
            end.
        end.
        if. -.good do.
            (<'bad ctr ',text),<i.0x return.
        end.
        numerator =. parse_integer 0{::parts
        denominator =. parse_integer 1{::parts
        rate =. (x:numerator)%denominator
        if. rate>1 do.
            (<'bad ctr ',text),<i.0x return.
        end.
        if. #rates do.
            if. rate>:{:rates do.
                (<'bad ctr ',text),<i.0x return.
            end.
        end.
        rates =. rates,rate
    end.
    if. 0=#participants do.
        (<'no advertisers'),<i.0x return.
    end.
    duplicate =. duplicate_name participants
    if. #duplicate do.
        (<'duplicate advertiser ',duplicate),<i.0x return.
    end.
    (<''),<rates
)
lot =: 3 : 0
    'kind name arguments participants' =. y
    reserve =. parse_integer 0{::arguments
    count =. #participants
    names =. 0$a:
    values =. i.0
    bids =. i.0
    for_participant. participants do.
        'participant value bid' =. >participant
        names =. names,<participant
        values =. values,value
        bids =. bids,bid
    end.
    eligible =. I.bids>:reserve
    first =. _1
    first_price =. 0
    if. #eligible do.
        first =. eligible{~(eligible{bids)i.>./eligible{bids
        first_price =. first{bids
    end.
    efficient =. values i.>./values
    optimum =. reserve>.efficient{values
    efficient_name =. efficient{::names
    second_price =. 0
    if. (efficient{values)<reserve do.
        efficient =. _1
        efficient_name =. '-'
    else.
        other_values =. ((i.count)~:efficient)#values
        second_price =. reserve>.>./other_values,reserve
    end.
    line =. 'LOT ',name,' reserve ',(integer reserve),' bidders ',integer count
    lines =. <line,' efficient ',efficient_name,' optimum ',integer optimum
    ascending =. english(<values),(<reserve),<parameter 'english_increment'
    descending =. dutch(<bids),(<reserve),(<parameter 'dutch_start'),<parameter 'dutch_decrement'
    winners =. first,efficient,(0{::ascending),(0{descending),first
    prices =. first_price,second_price,(1{::ascending),(1{descending),first_price
    steps =. _1,_1,(2{::ascending),(2{descending),_1
    utilities =. (count,0)$0
    revenues =. i.0
    for_mechanism. i.5 do.
        winner =. mechanism{winners
        price =. mechanism{prices
        utility =. count$0
        revenue =. price
        if. mechanism=4 do.
            revenue =. +/eligible{bids
            utility =. (-eligible{bids)eligible}utility
        end.
        label =. toupper mechanism{::Formats
        if. winner=_1 do.
            welfare =. reserve
            line =. label,' unsold'
        else.
            welfare =. winner{values
            utility =. (welfare-price)winner}utility
            line =. label,' winner ',(winner{::names),' price ',integer price
            line =. line,' utility ',integer winner{utility
        end.
        if. _1~:mechanism{steps do.
            line =. line,' steps ',integer mechanism{steps
        end.
        efficiency =. (x:welfare)%optimum
        line =. line,' revenue ',(integer revenue),' welfare ',integer welfare
        lines =. lines,<line,' efficiency ',fraction efficiency
        if. mechanism=2 do.
            line =. 'ENGLISH_DROPS'
            drops =. 3{::ascending
            for_i. i.count do.
                text =. '-'
                if. _1~:i{drops do.
                    text =. integer i{drops
                end.
                line =. line,' ',(i{::names),'=',text
            end.
            lines =. lines,<line
        end.
        utilities =. utilities,.utility
        revenues =. revenues,revenue
        ((<name),<mechanism{::Formats)summary_row revenue,welfare,efficiency
    end.
    for_i. i.count do.
        lines =. lines,<'UTILITY ',(i{::names),' ',numbers i{utilities
    end.
    ranking =. (\:revenues){Formats
    lines,<'RANKING ',' 'join ranking
)
slots =: 4 : 0
    rates =. x
    'kind name arguments participants' =. y
    count =. #participants
    slots =. #rates
    bids =. i.0
    values =. i.0
    for_participant. participants do.
        bids =. bids,2{::>participant
        values =. values,1{::>participant
    end.
    ranked_bids =. (\:bids){participants
    ranked_values =. (\:values){participants
    lines =. <'SLOTS ',name,' slots ',(integer slots),' advertisers ',integer count
    gsp_revenue =. 0x
    gsp_welfare =. 0x
    vcg_revenue =. 0x
    optimum =. 0x
    for_rank. i.count<.slots do.
        'participant value bid' =. rank{::ranked_bids
        rate =. rank{rates
        price =. ranked_bids gsp_price rank
        payment =. rate*price
        utility =. rate*value-price
        gsp_revenue =. gsp_revenue+payment
        gsp_welfare =. gsp_welfare+rate*value
        optimum =. optimum+rate*1{::rank{::ranked_values
        line =. 'GSP ',(integer rank+1),' ',participant,' ctr ',(fraction rate),' bid ',integer bid
        line =. line,' price ',(fraction price),' payment ',fraction payment
        lines =. lines,<line,' utility ',fraction utility
    end.
    efficiency =. gsp_welfare%optimum
    line =. 'GSP_TOTAL revenue ',(fraction gsp_revenue),' welfare ',fraction gsp_welfare
    lines =. lines,<line,' efficiency ',fraction efficiency
    for_rank. i.count<.slots do.
        'participant value bid' =. rank{::ranked_values
        rate =. rank{rates
        payment =. ((<ranked_values),<rates)slot_vcg_payment rank
        vcg_revenue =. vcg_revenue+payment
        utility =. (rate*value)-payment
        line =. 'VCG ',(integer rank+1),' ',participant,' ctr ',(fraction rate),' value ',integer value
        line =. line,' payment ',(fraction payment),' price ',fraction payment%rate
        lines =. lines,<line,' utility ',fraction utility
    end.
    line =. 'VCG_TOTAL revenue ',(fraction vcg_revenue),' welfare ',fraction optimum
    lines =. lines,<line,' efficiency 1'
    violations =. 0
    for_rank. 1+i.(count<.slots+1)-1 do.
        'participant value bid' =. rank{::ranked_bids
        rate =. 0x
        if. rank<slots do.
            rate =. rank{rates
        end.
        stay =. rate*value-ranked_bids gsp_price rank
        swap =. ((rank-1){rates)*value-bid
        violated =. stay<swap
        violations =. violations+violated
        state =. 'ok'
        if. violated do.
            state =. 'violated'
        end.
        line =. 'ENVY ',(integer rank+1),' ',participant,' stay ',(fraction stay),' swap ',fraction swap
        lines =. lines,<line,' ',state
    end.
    line =. 'ENVY_FREE yes'
    if. violations do.
        line =. 'ENVY_FREE no violations ',integer violations
    end.
    lines =. lines,<line
    deviations =. 0
    for_rank. i.count do.
        'participant value bid' =. rank{::ranked_bids
        rate =. 0x
        if. rank<slots do.
            rate =. rank{rates
        end.
        current =. rate*value-ranked_bids gsp_price rank
        for_target. i.slots do.
            if. target=rank do.
                continue.
            end.
            if. target<rank do.
                price =. 0
                if. target<count do.
                    price =. 2{::target{::ranked_bids
                end.
            else.
                price =. ranked_bids gsp_price target
            end.
            payoff =. (target{rates)*value-price
            if. payoff>current do.
                deviations =. deviations+1
                line =. 'DEVIATE ',participant,' from ',(integer rank+1),' to ',integer target+1
                lines =. lines,<line,' gain ',fraction payoff-current
            end.
        end.
    end.
    line =. 'NASH yes'
    if. deviations do.
        line =. 'NASH no deviations ',integer deviations
    end.
    lines =. lines,<line
    equilibrium =. (violations=0)*.deviations=0
    state =. 'no'
    if. equilibrium do.
        state =. 'yes'
    end.
    lines =. lines,<'EQUILIBRIUM ',state
    GroupTotals =: GroupTotals+0,0,0,(violations=0),(deviations=0),equilibrium
    ((<name),<'gsp')summary_row gsp_revenue,gsp_welfare,efficiency
    ((<name),<'vcg')summary_row vcg_revenue,optimum,1x
    lines
)
process_groups =: 3 : 0
    for_group. Groups do.
        group =. >group
        kind =. 0{::group
        index =. kind-:'slots'
        GroupTotals =: (1+index{GroupTotals)index}GroupTotals
        if. index do.
            'error rates' =. validate_slots group
        else.
            error =. validate_lot group
        end.
        if. #error do.
            SingleLines =: SingleLines,<(toupper kind),' ',(1{::group),' ERROR ',error
            GroupTotals =: (1+2{GroupTotals)2}GroupTotals
        elseif. index do.
            SingleLines =: SingleLines,rates slots group
        else.
            SingleLines =: SingleLines,lot group
        end.
    end.
)
total_line =: 4 : 0
    'prefix labels' =. x
    line =. prefix
    for_i. i.#labels do.
        line =. line,' ',(i{::labels),' ',integer i{y
    end.
    line
)
run =: 3 : 0
    read_inputs ''
    WdpLines =: 0$a:
    VcgLines =: 0$a:
    CoreLines =: 0$a:
    AscendingLines =: 0$a:
    SingleLines =: 0$a:
    SummaryLines =: <'mechanism,revenue,welfare,efficiency'
    WdpTotals =: 6$0
    VcgTotals =: 5$0
    CoreTotals =: 6$0
    AscendingTotals =: 5$0
    GroupTotals =: 6$0
    process_auctions ''
    process_groups ''
    labels =. ;:'auctions bids valid eligible nodes greedy_optimal'
    WdpLines =: WdpLines,<((<'TOTAL'),<labels)total_line WdpTotals
    labels =. ;:'vcg pay_as_bid greedy critical saa'
    VcgLines =: VcgLines,<((<'OVERALL'),<labels)total_line VcgTotals
    labels =. ;:'checked skipped vcg greedy critical saa'
    CoreLines =: CoreLines,<((<'SUMMARY'),<labels)total_line CoreTotals
    labels =. ;:'auctions rounds capped exposed exposure'
    AscendingLines =: AscendingLines,<((<'SUMMARY'),<labels)total_line AscendingTotals
    labels =. ;:'lots slot_groups errors envy_free nash equilibria'
    SingleLines =: SingleLines,<((<'SUMMARY'),<labels)total_line GroupTotals
    try.
        1!:5 <'output'
    catch.
    end.
    'wdp.txt'write_lines WdpLines
    'vcg.txt'write_lines VcgLines
    'core_check.txt'write_lines CoreLines
    'ascending_log.txt'write_lines AscendingLines
    'single_item.txt'write_lines SingleLines
    'summary.csv'write_lines SummaryLines
)
run ''
