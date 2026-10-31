ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
div =: 4 : '_1 x:<.(x:x)%x:y'
real =: 3 : '1.0*y'
num =: 3 : '10#.Digits i.y'
signed_num =: 3 : 0
    if. '-'={.y do. -num }.y else. num y end.
)
number =: 3 : 0
    value =. y
    if. value<0 do. '-',number -value return. end.
    text =. ''
    while. value>0 do.
        text =. ((10|value){Digits),text
        value =. value div 10
    end.
    if. #text do. text else. '0' end.
)
pad2 =: 3 : '_2{.''00'',number y'
split =: 4 : 0
    parts =. 0$a:
    while. 1 do.
        position =. y i.x
        parts =. parts,<position{.y
        if. position=#y do. parts return. end.
        y =. (position+1)}.y
    end.
)
join =: 4 : 0
    text =. ''
    for_index. i.#y do.
        if. index do. text =. text,x end.
        text =. text,index{::y
    end.
    text
)
read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
empty_table =: 3 : '0 2$a:'
table_keys =: 3 : '0{"1 y'
has_key =: 4 : '(<x)e.table_keys y'
get_key =: 4 : '((table_keys y)i.<x){::1{"1 y'
put_key =: 4 : 0
    'key value' =. x
    position =. (table_keys y)i.<key
    if. position<#y do. (<value) (<position,1)}y
    else. y,1 2$(<key),<value end.
)
record =: 4 : '('' '' split x),.y'
round_half_up =: 4 : '((2*x)+y) div 2*y'
hundredths =: 3 : 0
    if. y<0 do. '-',hundredths -y return. end.
    (number y div 100),'.',pad2 100|y
)
decimals =: 4 : 0
    negative =. y<!.0 0
    if. negative do. y =. -y end.
    scale =. 1
    for_i. i.x do. scale =. scale*10 end.
    rounded =. <.!.0 (y*scale)+0.5
    whole =. rounded div scale
    fraction =. rounded-whole*scale
    text =. (number whole),'.',(-x){.(x#'0'),number fraction
    if. negative*.rounded~:0 do. '-',text else. text end.
)
percent =: 3 : '4 decimals y*100.0'
amount =: 3 : '2 decimals y%100.0'
thousandths =: 3 : 'num y#~y~:''.'''
load SourceDirectory,'dates_calendar.ijs'
load SourceDirectory,'daycount.ijs'
load SourceDirectory,'schedule.ijs'
load SourceDirectory,'pricing.ijs'
load SourceDirectory,'curve.ijs'

BondTypes =: ' ' split 'FIXED ZERO AMORT FRN'
Frequencies =: 1 2 4 12
BucketNames =: ' ' split '0-1Y 1-3Y 3-5Y 5-10Y 10Y+'
bad =: 3 : 0
    InputError =: y
    empty_table ''
)
read_rows =: 3 : 0
    lines =. }.read_lines y
    rows =. 0$a:
    for_index. i.#lines do. rows =. rows,<(<index+2),<',' split index{::lines end.
    rows
)
read_params =: 3 : 0
    ScenarioRows =: Limits =: 0$a:
    lines =. read_lines 'params.txt'
    for_index. i.#lines do.
        words =. ' ' split index{::lines
        select. 0{::words
        case. 'valuation_date' do. ValuationDate =: parse_date 1{::words
        case. 'settlement_days' do. SettlementDays =: num 1{::words
        case. 'scenario' do. ScenarioRows =: ScenarioRows,<( <index+1),(1{words),<signed_num&>2}.words
        case. 'limit' do. Limits =: Limits,<}.words
        end.
    end.
    i.0
)
parse_pillar =: 4 : 0
    text =. 0{::y
    if. (<text)e.x do. bad 'duplicate pillar' return. end.
    if. -.valid_date text do. bad 'invalid date' return. end.
    maturity =. parse_date text
    if. maturity<:Settlement do. bad 'pillar not after settlement' return. end.
    frequency =. num 2{::y
    if. -.frequency e.Frequencies do. bad 'invalid frequency' return. end.
    maturity,(num 1{::y),frequency
)
validate_scenarios =: 3 : 0
    seen =. scenarios =. 0$a:
    for_box. ScenarioRows do.
        'line name shifts' =. >box
        reason =. ''
        if. (<name)e.seen do. reason =. 'duplicate scenario'
        elseif. (#shifts)~:#Pillars do. reason =. 'wrong number of shifts' end.
        if. #reason do. Errors =: Errors,<'params.txt:',(number line),': ',name,': ',reason
        else. scenarios =. scenarios,<(<name),<BasisPoint*real shifts end.
        seen =. seen,<name
    end.
    scenarios
)
parse_options =: 4 : 0
    kind =. x
    eom =. longstub =. 0
    lag =. cap =. floor =. _1
    sinks =. calls =. seen =. 0$a:
    allowed =. ' ' split 'EOM LONG'
    select. kind
    case. 'FIXED' do. allowed =. allowed,<'CALL'
    case. 'AMORT' do. allowed =. allowed,<'SINK'
    case. 'FRN' do. allowed =. allowed,' ' split 'LAG CAP FLOOR'
    end.
    items =. 0$a:
    if. -.y-:'-' do. items =. ';' split y end.
    for_box. items do.
        parts =. '=' split >box
        key =. 0{::parts
        if. (-.(<key)e.allowed)+.((<key)e.seen)*.-.(<key)e.' ' split 'SINK CALL' do. bad 'invalid option' return. end.
        seen =. seen,<key
        value =. ''
        if. 1<#parts do. value =. 1{::parts end.
        select. key
        case. 'EOM' do. eom =. 1
        case. 'LONG' do. longstub =. 1
        case. 'LAG' do. lag =. num value
        case. 'CAP' do. cap =. num value
        case. 'FLOOR' do. floor =. num value
        case. 'SINK';'CALL' do.
            pair =. ':' split value
            if. key-:'SINK' do. sinks =. sinks,<(0{pair),<num 1{::pair
            else. calls =. calls,<(0{pair),<thousandths 1{::pair end.
        end.
    end.
    if. kind-:'FRN' do.
        maximum =. cap
        if. cap=_1 do. maximum =. 1200 end.
        if. (-.lag e.>:i.5)+.(maximum>1200)+.floor>maximum do. bad 'invalid option' return. end.
    end.
    'eom longstub lag cap floor sinks calls' record (<eom),(<longstub),(<lag),(<cap),(<floor),(<sinks),<calls
)
schedule_days =: 4 : 0
    'items schedule' =. y
    days =. 0$0
    inner =. }:}.schedule
    for_box. items do.
        text =. 0{::>box
        if. -.valid_date text do. bad x
        0$0 return. end.
        day =. parse_date text
        invalid =. -.day e.inner
        if. #days do. invalid =. invalid+.day<:{:days end.
        if. invalid do. bad x
        0$0 return. end.
        days =. days,day
    end.
    days
)
build_periods =: 3 : 0
    schedule =. 'schedule' get_key y
    options =. 'options' get_key y
    kind =. 'kind' get_key y
    convention =. 'bdc' get_key y
    opening =. 'face' get_key y
    sinks =. 'sinks' get_key y
    periods =. 0$a:
    count =. (#schedule)-1
    for_index. i.count do.
        start =. index{schedule
        finish =. (index+1){schedule
        'numerator denominator' =. ('daycount' get_key y) year_fraction start,finish
        rate =. 'coupon' get_key y
        if. kind-:'ZERO' do. rate =. 0
        elseif. kind-:'FRN' do.
            reset =. (('lag' get_key options),_1) business_days convention adjust_date start
            eligible =. I.FixingDays<:reset
            if. 0=#eligible do. bad 'missing fixing'
            0$a: return. end.
            rate =. rate+({:eligible){FixingRates
            floor =. 'floor' get_key options
            cap =. 'cap' get_key options
            if. floor~:_1 do. rate =. rate>.floor end.
            if. cap~:_1 do. rate =. rate<.cap end.
        end.
        principal =. 0
        key =. number finish
        if. index=count-1 do. principal =. opening
        elseif. key has_key sinks do. principal =. key get_key sinks end.
        coupon =. (opening*rate*numerator) round_half_up 10000*denominator
        values =. (<index+1),(<start),(<finish),(<convention adjust_date finish),(<numerator),(<denominator),(<rate),(<opening),(<coupon),(<principal),<coupon+principal
        periods =. periods,<'number start end payment numerator denominator rate opening coupon principal cash_flow' record values
        opening =. opening-principal
    end.
    periods
)
parse_bond =: 4 : 0
    'code kind issuetext maturitytext coupontext frequencytext daycount bdc facetext optiontext' =. y
    if. (<code)e.x do. bad 'duplicate id' return. end.
    if. -.(<kind)e.BondTypes do. bad 'unknown type' return. end.
    if. (-.valid_date issuetext)+.-.valid_date maturitytext do. bad 'invalid date' return. end.
    issue =. parse_date issuetext
    maturity =. parse_date maturitytext
    if. maturity<:issue do. bad 'maturity not after issue' return. end.
    frequency =. num frequencytext
    if. -.frequency e.Frequencies do. bad 'invalid frequency' return. end.
    if. -.(<daycount)e.DayCounts do. bad 'unknown day count' return. end.
    if. -.(<bdc)e.BusinessDayRules do. bad 'unknown business day rule' return. end.
    face =. num facetext
    if. (0~:100000|face)+.face>10000000 do. bad 'invalid face' return. end.
    coupon =. num coupontext
    if. (coupon>1200)+.(kind-:'ZERO')*.coupon~:0 do. bad 'invalid coupon' return. end.
    options =. kind parse_options optiontext
    if. #InputError do. empty_table '' return. end.
    schedule =. coupon_schedule issue,maturity,frequency,('eom' get_key options),'longstub' get_key options
    sinkitems =. 'sinks' get_key options
    sinkdays =. 'invalid sinking fund' schedule_days (<sinkitems),<schedule
    if. #InputError do. empty_table '' return. end.
    amounts =. 0$0
    for_box. sinkitems do. amounts =. amounts,1{::>box end.
    if. (0 e.amounts)+.(kind-:'AMORT')*.((0=+/amounts)+.face<:+/amounts) do. bad 'invalid sinking fund' return. end.
    sinks =. empty_table ''
    for_index. i.#sinkdays do. sinks =. ((<number index{sinkdays),<index{amounts) put_key sinks end.
    callitems =. 'calls' get_key options
    calldays =. 'invalid call schedule' schedule_days (<callitems),<schedule
    if. #InputError do. empty_table '' return. end.
    calls =. 0$a:
    for_index. i.#callitems do.
        price =. 1{::index{::callitems
        if. (price<100000)+.price>110000 do. bad 'invalid call schedule' return. end.
        calls =. calls,<(index{calldays),price
    end.
    values =. (<code),(<kind),(<issue),(<maturity),(<coupon),(<frequency),(<daycount),(<bdc),(<face),(<options),(<schedule),(<sinks),<calls
    bond =. 'code kind issue maturity coupon frequency daycount bdc face options schedule sinks calls' record values
    periods =. build_periods bond
    if. #InputError do. empty_table '' return. end.
    ((<'periods'),<periods) put_key bond
)
make_valuation =: 4 : 0
    bond =. x
    clean =. y
    periods =. 'periods' get_key bond
    index =. 0
    while. ('end' get_key index{::periods)<:Settlement do. index =. index+1 end.
    remaining =. index}.periods
    current =. 0{::remaining
    outstanding =. 'opening' get_key current
    convention =. 'daycount' get_key bond
    frequency =. 'frequency' get_key bond
    'numerator denominator' =. convention year_fraction ('start' get_key current),Settlement
    accrued =. ((real 'rate' get_key current)*numerator)%(100.0*denominator)
    accruedamount =. (outstanding*('rate' get_key current)*numerator) round_half_up 10000*denominator
    cleanamount =. (outstanding*clean) round_half_up 100000
    cashflows =. 0$a:
    flows =. 0 2$0
    allcash =. 0$0
    for_box. remaining do.
        period =. >box
        cash =. 'cash_flow' get_key period
        allcash =. allcash,cash
        if. cash>0 do.
            cashflows =. cashflows,box
            flows =. flows,(('payment' get_key period)-Settlement),cash
        end.
    end.
    'numerator denominator' =. convention year_fraction Settlement,'end' get_key current
    fraction =. ((real frequency)*numerator)%real denominator
    pricer =. (<allcash),(<fraction),(<frequency),<outstanding
    values =. (<bond),(<clean),(<outstanding),(<remaining),(<cashflows),(<flows),(<accrued),(<accruedamount),(<cleanamount),(<cleanamount+accruedamount),(<(clean%1000.0)+accrued),(<pricer),(<('payment' get_key 0{::cashflows)),<'maturity' get_key bond
    'bond clean outstanding remaining cash_flows flows accrued accrued_amount clean_amount unit_value target pricer next_payment workout' record values
)
parse_price =: 4 : 0
    'code price' =. y
    if. -.code has_key Bonds do. bad 'unknown bond' return. end.
    if. (<code)e.x do. bad 'duplicate price' return. end.
    bond =. code get_key Bonds
    if. (Settlement<'issue' get_key bond)+.Settlement>:'maturity' get_key bond do. bad 'not outstanding' return. end.
    value =. bond make_valuation thousandths price
    pricer =. 'pricer' get_key value
    target =. 'target' get_key value
    if. (-.(pricer dirty_price 0.0)>!.0 target)+.-.target>!.0 pricer dirty_price 1.0 do. bad 'yield out of range' return. end.
    value
)
parse_holding =: 3 : 0
    'portfolio code facetext booktext' =. y
    if. -.code has_key Bonds do. bad 'unknown bond' return. end.
    if. -.code has_key Valuations do. bad 'no price' return. end.
    face =. num facetext
    unitface =. 'face' get_key code get_key Bonds
    if. 0~:unitface|face do. bad 'invalid face' return. end.
    units =. face div unitface
    outstanding =. 'outstanding' get_key code get_key Valuations
    book =. (units*outstanding*thousandths booktext) round_half_up 100000
    'portfolio code units book' record (<portfolio),(<code),(<units),<book
)
validate_rows =: 4 : 0
    file =. x
    seen =. valid =. 0$a:
    for_box. y do.
        'line fields' =. >box
        keyindex =. file-:'holdings.csv'
        key =. keyindex{::fields
        InputError =: ''
        select. file
        case. 'curve_quotes.csv' do. value =. seen parse_pillar fields
        case. 'bonds.csv' do. value =. seen parse_bond fields
        case. 'prices.csv' do. value =. seen parse_price fields
        case. 'holdings.csv' do. value =. parse_holding fields
        end.
        if. #InputError do. Errors =: Errors,<file,':',(number line),': ',key,': ',InputError
        else. valid =. valid,<value end.
        seen =. seen,<key
    end.
    valid
)
analyze_valuation =: 3 : 0
    value =. y
    bond =. 'bond' get_key value
    pricer =. 'pricer' get_key value
    target =. 'target' get_key value
    ytm =. pricer yield_to_maturity target
    risk =. pricer yield_risk ytm
    ytw =. ytm
    workout =. 'maturity' get_key bond
    for_box. 'calls' get_key bond do.
        'day price' =. >box
        if. day<:Settlement do. continue. end.
        coupons =. 0$0
        for_periodbox. 'remaining' get_key value do.
            period =. >periodbox
            coupons =. coupons,'coupon' get_key period
            if. day='end' get_key period do.
                redemption =. (('opening' get_key period)*price) round_half_up 100000
                coupons =. (}:coupons),redemption+{:coupons
                break.
            end.
        end.
        callpricer =. (<coupons) 0}pricer
        rate =. callpricer yield_to_maturity target
        if. rate<!.0 ytw do. ytw =. rate
        workout =. day end.
    end.
    periods =. 'cash_flows' get_key value
    flows =. 'flows' get_key value
    principalday =. 0
    for_index. i.#periods do.
        principalday =. principalday+('principal' get_key index{::periods)*(<index,0){flows
    end.
    wal =. (real principalday)%(365.0*'outstanding' get_key value)
    curveclean =. ((100.0*ZeroCurve curve_value (<flows),<0.0)%real 'outstanding' get_key value)-'accrued' get_key value
    spread =. ZeroCurve z_spread (<flows),<'unit_value' get_key value
    updates =. 'ytm risk ytw workout wal curve_clean zspread' record (<ytm),(<risk),(<ytw),(<workout),(<wal),(<curveclean),<spread
    for_row. updates do. value =. row put_key value end.
    value
)
position_value =: 3 : '(''units'' get_key y)*''unit_value'' get_key ''valuation'' get_key y'
position_face =: 3 : '(''units'' get_key y)*''face'' get_key ''bond'' get_key ''valuation'' get_key y'
position_outstanding =: 3 : '(''units'' get_key y)*''outstanding'' get_key ''valuation'' get_key y'
position_gain =: 3 : '((''units'' get_key y)*''clean_amount'' get_key ''valuation'' get_key y)-''book'' get_key y'
position_dv01 =: 3 : 0
    value =. 'valuation' get_key y
    ((3{'risk' get_key value)*('units' get_key y)*'outstanding' get_key value)%10000.0
)
position_pv =: 4 : 0
    value =. 'valuation' get_key x
    ('units' get_key x)*y curve_value (<'flows' get_key value),<'zspread' get_key value
)
build_portfolios =: 3 : 0
    names =. codes =. 0$a:
    for_box. y do. names =. names,<'portfolio' get_key >box end.
    portfolios =. 0$a:
    for_namebox. /:~~.names do.
        name =. >namebox
        codes =. 0$a:
        for_box. y do.
            holding =. >box
            if. name-:'portfolio' get_key holding do. codes =. codes,<'code' get_key holding end.
        end.
        positions =. 0$a:
        for_codebox. /:~~.codes do.
            code =. >codebox
            units =. book =. 0
            for_box. y do.
                holding =. >box
                if. (name-:'portfolio' get_key holding)*.code-:'code' get_key holding do.
                    units =. units+'units' get_key holding
                    book =. book+'book' get_key holding
                end.
            end.
            position =. 'portfolio code units book valuation' record (<name),(<code),(<units),(<book),<code get_key Valuations
            positions =. positions,<position
        end.
        portfolios =. portfolios,<'name positions' record (<name),<positions
    end.
    portfolios
)
portfolio_value =: 4 : 0
    total =. 0.0
    for_box. 'positions' get_key x do. total =. total+(>box) position_pv y end.
    total
)
analyze_portfolio =: 3 : 0
    portfolio =. y
    positions =. 'positions' get_key portfolio
    totalvalue =. 0
    ytm =. modified =. convexity =. spread =. dv01 =. 0.0
    flows =. 0 2$0
    ladder =. empty_table ''
    basevalues =. 0$0.0
    basevalue =. 0.0
    for_box. positions do.
        position =. >box
        value =. 'valuation' get_key position
        units =. 'units' get_key position
        market =. position_value position
        totalvalue =. totalvalue+market
        ytm =. ytm+(real market)*'ytm' get_key value
        modified =. modified+(real market)*1{'risk' get_key value
        convexity =. convexity+(real market)*2{'risk' get_key value
        spread =. spread+(real market)*'zspread' get_key value
        dv01 =. dv01+position_dv01 position
        for_row. 'flows' get_key value do. flows =. flows,({.row),units*{:row end.
        for_periodbox. 'cash_flows' get_key value do.
            period =. >periodbox
            year =. number {.civil_date 'payment' get_key period
            totals =. 0 0
            if. year has_key ladder do. totals =. year get_key ladder end.
            totals =. totals+units*('coupon' get_key period),'principal' get_key period
            ladder =. ((<year),<totals) put_key ladder
        end.
        pv =. position position_pv ZeroCurve
        basevalues =. basevalues,pv
        basevalue =. basevalue+pv
    end.
    ytm =. ytm%real totalvalue
    modified =. modified%real totalvalue
    convexity =. convexity%real totalvalue
    spread =. spread%real totalvalue
    PortfolioFlows =: flows
    trial =. 3 : '(flat_curve y) curve_value (<PortfolioFlows),<0.0'
    cashyield =. trial bisection 0.0 1.0,real totalvalue
    durations =. 0$0.0
    count =. #1{::ZeroCurve
    for_index. i.count+1 do.
        shifts =. count$0.0
        if. index=0 do. shifts =. count$BasisPoint
        else. shifts =. BasisPoint (index-1)}shifts end.
        down =. portfolio portfolio_value ZeroCurve shift_curve -shifts
        up =. portfolio portfolio_value ZeroCurve shift_curve shifts
        durations =. durations,(down-up)%(2.0*BasisPoint*basevalue)
    end.
    ladder =. (/:table_keys ladder){ladder
    results =. 0$a:
    scenarios =. (<(<'BASE'),<count$0.0),Scenarios
    for_box. scenarios do.
        'name shifts' =. >box
        shifted =. ZeroCurve shift_curve shifts
        values =. 0$0.0
        total =. 0.0
        for_positionbox. positions do.
            pv =. (>positionbox) position_pv shifted
            values =. values,pv
            total =. total+pv
        end.
        result =. 'name values pnls total pnl' record (<name),(<values),(<values-basevalues),(<total),<total-basevalue
        results =. results,<result
    end.
    values =. (<totalvalue),(<ytm),(<modified),(<convexity),(<spread),(<dv01),(<cashyield),(<basevalues),(<basevalue),(<{.durations),(<}.durations),(<ladder),<results
    updates =. 'total_value ytm modified convexity zspread dv01 cash_yield base_values base_value effective key_rates ladder results' record values
    for_row. updates do. portfolio =. row put_key portfolio end.
    portfolio
)
portfolio_income =: 3 : 0
    total =. 0
    for_box. 'positions' get_key y do.
        position =. >box
        value =. 'valuation' get_key position
        periods =. 'cash_flows' get_key value
        flows =. 'flows' get_key value
        for_index. i.#periods do.
            if. ((<index,0){flows)<:365 do.
                total =. total+('units' get_key position)*'coupon' get_key index{::periods
            end.
        end.
    end.
    total
)
bucket_index =: 3 : '+/y>:365 1095 1825 3650'
group_line =: 4 : 0
    'label name members' =. y
    value =. 0
    duration =. dv01 =. 0.0
    total =. real 'total_value' get_key x
    for_box. members do.
        position =. >box
        market =. position_value position
        value =. value+market
        duration =. duration+(real market)*1{'risk' get_key 'valuation' get_key position
        dv01 =. dv01+position_dv01 position
    end.
    text =. label,' ',name,' positions ',(number #members),' value ',hundredths value
    text =. text,' weight ',(4 decimals (100.0*real value)%total),' duration ',4 decimals duration%total
    text,' dv01 ',2 decimals dv01
)
portfolio_lines =: 3 : 0
    portfolio =. y
    positions =. 'positions' get_key portfolio
    totalvalue =. 'total_value' get_key portfolio
    lines =. <'portfolio ','name' get_key portfolio
    totalface =. totaloutstanding =. totalbook =. totalgain =. 0
    for_box. positions do.
        position =. >box
        value =. 'valuation' get_key position
        market =. position_value position
        face =. position_face position
        outstanding =. position_outstanding position
        book =. 'book' get_key position
        gain =. position_gain position
        totalface =. totalface+face
        totaloutstanding =. totaloutstanding+outstanding
        totalbook =. totalbook+book
        totalgain =. totalgain+gain
        text =. 'position ',('code' get_key position),' face ',(hundredths face),' outstanding ',hundredths outstanding
        text =. text,' clean ',(6 decimals ('clean' get_key value)%1000.0),' value ',hundredths market
        text =. text,' weight ',(4 decimals (100.0*real market)%real totalvalue),' book ',(hundredths book),' gain ',hundredths gain
        text =. text,' ytm ',(percent 'ytm' get_key value),' modified ',(4 decimals 1{'risk' get_key value),' dv01 ',2 decimals position_dv01 position
        lines =. lines,<text
    end.
    text =. 'total positions ',(number #positions),' face ',(hundredths totalface),' outstanding ',hundredths totaloutstanding
    text =. text,' value ',(hundredths totalvalue),' book ',(hundredths totalbook),' gain ',hundredths totalgain
    lines =. lines,<text,' income ',hundredths portfolio_income portfolio
    text =. 'risk ytm ',(percent 'ytm' get_key portfolio),' yield ',percent 'cash_yield' get_key portfolio
    text =. text,' modified ',(4 decimals 'modified' get_key portfolio),' convexity ',4 decimals 'convexity' get_key portfolio
    text =. text,' zspread ',(percent 'zspread' get_key portfolio),' dv01 ',2 decimals 'dv01' get_key portfolio
    lines =. lines,<text
    rates =. 4&decimals&.><"0 'key_rates' get_key portfolio
    lines =. lines,<'curve effective ',(4 decimals 'effective' get_key portfolio),' krd ',' ' join rates
    for_kindbox. BondTypes do.
        kind =. >kindbox
        members =. 0$a:
        for_box. positions do.
            if. kind-:'kind' get_key 'bond' get_key 'valuation' get_key >box do. members =. members,box end.
        end.
        lines =. lines,<portfolio group_line (<'type'),(<kind),<members
    end.
    for_index. i.5 do.
        members =. 0$a:
        for_box. positions do.
            maturity =. 'maturity' get_key 'bond' get_key 'valuation' get_key >box
            if. index=bucket_index maturity-Settlement do. members =. members,box end.
        end.
        lines =. lines,<portfolio group_line (<'bucket'),(index{BucketNames),<members
    end.
    totalcoupon =. totalprincipal =. 0
    for_row. 'ladder' get_key portfolio do.
        'year totals' =. row
        'coupon principal' =. totals
        text =. 'ladder ',year,' coupon ',(hundredths coupon),' principal ',(hundredths principal),' total ',hundredths coupon+principal
        lines =. lines,<text
        totalcoupon =. totalcoupon+coupon
        totalprincipal =. totalprincipal+principal
    end.
    lines =. lines,<'ladder total coupon ',(hundredths totalcoupon),' principal ',(hundredths totalprincipal),' total ',hundredths totalcoupon+totalprincipal
    results =. }.'results' get_key portfolio
    if. #results do.
        worst =. 0{::results
        for_box. }.results do.
            if. ('pnl' get_key >box)<!.0 'pnl' get_key worst do. worst =. >box end.
        end.
        pnls =. 'pnls' get_key worst
        order =. /:pnls,.i.#positions
        order =. (3<.#order){.order
        text =. 'stress worst ',('name' get_key worst),' pnl ',(amount 'pnl' get_key worst),' losers'
        for_index. order do. text =. text,' ',('code' get_key index{::positions),' ',amount index{pnls end.
        lines =. lines,<text
    end.
    lines
)
scenario_lines =: 3 : 0
    name =. 'name' get_key y
    positions =. 'positions' get_key y
    lines =. 0$a:
    for_box. 'results' get_key y do.
        result =. >box
        scenario =. 'name' get_key result
        values =. 'values' get_key result
        pnls =. 'pnls' get_key result
        for_index. i.#positions do.
            lines =. lines,<name,',',scenario,',',('code' get_key index{::positions),',',(amount index{values),',',amount index{pnls
        end.
        lines =. lines,<name,',',scenario,',*,',(amount 'total' get_key result),',',amount 'pnl' get_key result
    end.
    lines
)
check_limit =: 4 : 0
    portfolio =. x
    words =. y
    kind =. 0{::words
    positions =. 'positions' get_key portfolio
    totalvalue =. 'total_value' get_key portfolio
    select. kind
    case. 'position_weight' do.
        values =. 0$0
        for_box. positions do. values =. values,position_value >box end.
        index =. values i.>./values
        limit =. num 1{::words
        value =. index{values
        text =. ('code' get_key index{::positions),' ',(4 decimals (100.0*real value)%real totalvalue),' limit ',hundredths limit
        breach =. (10000*value)>limit*totalvalue
    case. 'type_weight' do.
        kindname =. 1{::words
        limit =. num 2{::words
        value =. 0
        for_box. positions do.
            if. kindname-:'kind' get_key 'bond' get_key 'valuation' get_key >box do. value =. value+position_value >box end.
        end.
        text =. kindname,' ',(4 decimals (100.0*real value)%real totalvalue),' limit ',hundredths limit
        breach =. (10000*value)>limit*totalvalue
    case. 'max_maturity' do.
        years =. num 1{::words
        count =. 0
        for_box. positions do.
            maturity =. 'maturity' get_key 'bond' get_key 'valuation' get_key >box
            count =. count+(maturity-Settlement)>365*years
        end.
        text =. (number years),'Y positions ',number count
        breach =. count>0
    case. 'min_yield' do.
        limit =. num 1{::words
        rate =. 'ytm' get_key portfolio
        text =. (percent rate),' limit ',hundredths limit
        breach =. (rate*10000.0)<!.0 real limit
    case. 'duration' do.
        low =. num 1{::words
        high =. num 2{::words
        duration =. 'modified' get_key portfolio
        text =. (4 decimals duration),' range ',(hundredths low),' ',hundredths high
        breach =. (duration<!.0 low%100.0)+.duration>!.0 high%100.0
    case. 'dv01' do.
        limit =. num 1{::words
        value =. 'dv01' get_key portfolio
        text =. (2 decimals value),' limit ',hundredths limit
        breach =. (value*100.0)>!.0 real limit
    end.
    (<text),<breach
)
compliance_lines =: 3 : 0
    lines =. 0$a:
    breaches =. 0
    name =. 'name' get_key y
    for_box. Limits do.
        words =. >box
        'text breach' =. y check_limit words
        breaches =. breaches+breach
        result =. breach{::'PASS';'BREACH'
        lines =. lines,<name,' ',(0{::words),' ',text,' ',result
    end.
    lines,<name,' breaches ',number breaches
)
cashflow_lines =: 3 : 0
    lines =. <'bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal'
    for_codebox. /:~table_keys Bonds do.
        code =. >codebox
        for_box. 'periods' get_key code get_key Bonds do.
            period =. >box
            if. ('cash_flow' get_key period)<1 do. continue. end.
            parts =. (<code),<number 'number' get_key period
            parts =. parts,(<format_date 'start' get_key period),(<format_date 'end' get_key period),<format_date 'payment' get_key period
            fraction =. (real 'numerator' get_key period)%real 'denominator' get_key period
            parts =. parts,(<6 decimals fraction),(<number 'rate' get_key period),(<number 'opening' get_key period),(<number 'coupon' get_key period),<number 'principal' get_key period
            lines =. lines,<',' join parts
        end.
    end.
    lines
)
analytics_lines =: 3 : 0
    lines =. <'bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,macaulay,modified,convexity,dv01,curve_clean,zspread'
    for_codebox. /:~table_keys Valuations do.
        code =. >codebox
        value =. code get_key Valuations
        risk =. 'risk' get_key value
        parts =. (<code),(<6 decimals ('clean' get_key value)%1000.0),(<6 decimals 'accrued' get_key value),<6 decimals 'target' get_key value
        parts =. parts,(<percent 'ytm' get_key value),(<percent 'ytw' get_key value),(<format_date 'workout' get_key value),<format_date 'next_payment' get_key value
        parts =. parts,(<4 decimals 'wal' get_key value),(<4 decimals 0{risk),(<4 decimals 1{risk),<4 decimals 2{risk
        parts =. parts,(<6 decimals 3{risk),(<6 decimals 'curve_clean' get_key value),<percent 'zspread' get_key value
        lines =. lines,<',' join parts
    end.
    lines
)
curve_lines =: 3 : 0
    lines =. <'valuation ',(format_date ValuationDate),' settlement ',format_date Settlement
    'days rates' =. ZeroCurve
    previous =. 0
    for_index. i.#Pillars do.
        'maturity coupon frequency' =. index{::Pillars
        day =. index{days
        text =. 'pillar ',(format_date maturity),' days ',(number day),' frequency ',(number frequency),' par ',hundredths coupon
        text =. text,' zero ',(percent index{rates),' df ',6 decimals ZeroCurve discount_factor day,0.0
        text =. text,' forward ',percent ZeroCurve forward_rate previous,day
        lines =. lines,<text
        previous =. day
    end.
    for_year. >:i.({:days) div 365 do.
        day =. 365*year
        text =. 'grid ',(number year),'Y days ',(number day),' zero ',percent ZeroCurve zero_rate day
        text =. text,' df ',(6 decimals ZeroCurve discount_factor day,0.0),' forward ',percent ZeroCurve forward_rate (day-365),day
        lines =. lines,<text
    end.
    lines
)
write_lines =: 4 : 0
    text =. ''
    for_box. y do. text =. text,(>box),LF end.
    text 1!:2 <'output/',x
    i.0
)
main =: 3 : 0
    read_params ''
    Holidays =: parse_date&>read_lines 'calendar.txt'
    FixingDays =: FixingRates =: 0$0
    for_box. read_rows 'fixings.csv' do.
        fields =. 1{::>box
        FixingDays =: FixingDays,parse_date 0{::fields
        FixingRates =: FixingRates,num 1{::fields
    end.
    Settlement =: (SettlementDays,1) business_days ValuationDate
    Errors =: 0$a:
    Pillars =: 'curve_quotes.csv' validate_rows read_rows 'curve_quotes.csv'
    dates =. 0$0
    for_box. Pillars do. dates =. dates,{.>box end.
    Pillars =: (/:dates){Pillars
    Scenarios =: validate_scenarios ''
    validbonds =. 'bonds.csv' validate_rows read_rows 'bonds.csv'
    Bonds =: empty_table ''
    for_box. validbonds do.
        bond =. >box
        Bonds =: ((<'code' get_key bond),<bond) put_key Bonds
    end.
    validprices =. 'prices.csv' validate_rows read_rows 'prices.csv'
    Valuations =: empty_table ''
    for_box. validprices do.
        value =. >box
        code =. 'code' get_key 'bond' get_key value
        Valuations =: ((<code),<value) put_key Valuations
    end.
    holdings =. 'holdings.csv' validate_rows read_rows 'holdings.csv'
    ZeroCurve =: bootstrap Pillars
    for_codebox. table_keys Valuations do.
        code =. >codebox
        Valuations =: ((<code),<analyze_valuation code get_key Valuations) put_key Valuations
    end.
    portfolios =. build_portfolios holdings
    report =. compliance =. 0$a:
    scenarios =. <'portfolio,scenario,bond,value,pnl'
    for_box. portfolios do.
        portfolio =. analyze_portfolio >box
        report =. report,portfolio_lines portfolio
        scenarios =. scenarios,scenario_lines portfolio
        compliance =. compliance,compliance_lines portfolio
    end.
    1!:5 <'output'
    'errors.txt' write_lines Errors
    'cashflows.csv' write_lines cashflow_lines ''
    'analytics.csv' write_lines analytics_lines ''
    'curve.txt' write_lines curve_lines ''
    'portfolio.txt' write_lines report
    'scenarios.csv' write_lines scenarios
    'compliance.txt' write_lines compliance
    i.0
)
main ''
