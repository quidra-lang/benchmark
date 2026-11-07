LF =: 10{a.
STAGES =: ;:'RETAILER WHOLESALER DISTRIBUTOR FACTORY'
POLICY_NAMES =: ;:'FIXED PASS BASESTOCK MINMAX MOVAVG SMOOTH STERMAN'
MODES =: ;:'ORDERS INV BACK NET'
Initial =: 0 6$0
InitialPolicies =: SnapshotNames =: Snapshots =: 0$a:
BaseDemand =: i.0
split =: 4 : '<;._1 x,y'
number =: 3 : 0
    ,'0' 8!:2 y
)
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
strings =: 3 : 0
    parts =. 0$a:
    for_part. y do.
        value =. >part
        if. 2~:3!:0 value do. value =. number value end.
        parts =. parts,<value
    end.
    parts
)
emit =: 3 : 0
    ((' ' join strings y),LF) 1!:2 4
    i.0
)
fail =: 3 : 'emit (<''ERROR''),y'
floor_ratio =: 4 : '<.(x:x)%x:y'
ceil_ratio =: 4 : '>.(x:x)%x:y'
padded =: 4 : 0
    text =. number y
    ((0>.x-#text)#'0'),text
)
money =: 3 : '(number y floor_ratio 100),''.'',2 padded 100|y'
decimal =: 4 : 0
    'p q' =. y
    scale =. 10x^x
    value =. (p*scale) floor_ratio q
    (number value floor_ratio scale),'.',x padded scale|value
)
ratio =: 3 : 0
    if. 0=1{y do. 'n/a' else. 4 decimal y end.
)
fill_rate =: 3 : 0
    'ontime ordered' =. y
    if. ordered=0 do. 'n/a' else. (2 decimal (100*ontime),ordered),'%' end.
)
span =: 3 : '(number 0{y),''-'',number 1{y'
pipeline =: 3 : ''','' join strings <"0 y'
aligned =: 4 : 0
    parts =. strings y
    for_i. i.#parts do.
        text =. i{::parts
        parts =. (<((0>.(i{x)-#text)#' '),text) i}parts
    end.
    ' ' join parts
)
policy_error =: 3 : 0
    name =. 0{::y
    p =. POLICY_NAMES i.<name
    if. p=#POLICY_NAMES do. 'unknown policy';name return. end.
    count =. p{1 0 1 2 2 2 4
    if. count~:<:#y do. name;'needs';count;'parameters' return. end.
    values =. i.0
    for_token. }.y do. values =. values,0".(>token)-.'.' end.
    valid =. 1
    select. name
    case. 'FIXED' do. valid =. ({.values)<:1000
    case. 'BASESTOCK' do. valid =. ({.values)<:10000
    case. 'MINMAX' do. valid =. ((0{values)<1{values)*.(1{values)<:10000
    case. 'MOVAVG' do. valid =. ((0{values)>:1)*.((0{values)<:52)*.(1{values)<:10000
    case. 'SMOOTH' do. valid =. ((0{values)>:1)*.((0{values)<:10)*.(1{values)<:10000
    case. 'STERMAN' do. valid =. (*./(3{.values)<:100)*.(3{values)<:10000
    end.
    if. -.valid do. 'invalid parameter for';name return. end.
    0$a:
)
parse_policy =: 3 : 0
    values =. i.0
    for_token. }.y do. values =. values,0".(>token)-.'.' end.
    (0{::y);values;' ' join y
)
initialize =: 3 : 0
    Week =: 0
    Inventory =: 0{"1 Initial
    Backlog =: 4$0
    Shipping =: Pending =: 0$a:
    for_row. Initial do.
        'inventory quantity shipping orders holding backlog' =. row
        Shipping =: Shipping,<shipping$quantity
        Pending =: Pending,<orders$quantity
    end.
    Policies =: InitialPolicies
    Expected =: 100*1{"1 Initial
    Holding =: 4{"1 Initial
    Penalty =: 5{"1 Initial
    Lots =: 4$1
    Capacities =: 4$_1
    PlantBack =: 0
    PlantCapacity =: _1
    Visible =: 0
    Demand =: BaseDemand
    Records =: 4$<0 11$0
    PlantRecords =: 0 3$0
    i.0
)
snapshot =: 3 : 0
    Week;Inventory;Backlog;Shipping;Pending;Policies;Expected;Holding;Penalty;Lots;Capacities;PlantBack;PlantCapacity;Visible;Demand;Records;PlantRecords
)
restore =: 3 : 0
    'Week Inventory Backlog Shipping Pending Policies Expected Holding Penalty Lots Capacities PlantBack PlantCapacity Visible Demand Records PlantRecords' =: y
    i.0
)
supply =: 3 : 0
    result =. (}.Backlog),PlantBack
    for_s. i.4 do.
        value =. (s{result)+(+/s{::Shipping)++/s{::Pending
        result =. value s}result
    end.
    result
)
set_policy =: 4 : 0
    Policies =: (<y) x}Policies
    if. (0{::y)-:'STERMAN' do.
        signal =. x{1{"1 Initial
        if. Week>0 do.
            if. Visible do. signal =. (Week-1){Demand
            else. signal =. 1{{:x{::Records end.
        end.
        Expected =: (100*signal) x}Expected
    end.
    i.0
)
policy_order =: 4 : 0
    'stage line position incoming' =. x
    'name parameters text' =. y
    signal =. stage{incoming
    if. Visible do. signal =. Week{Demand end.
    select. name
    case. 'FIXED' do. {.parameters
    case. 'PASS' do. stage{incoming
    case. 'BASESTOCK' do. 0>.({.parameters)-position
    case. 'MINMAX' do.
        if. position<:0{parameters do. (1{parameters)-position else. 0 end.
    case. 'MOVAVG' do.
        'k target' =. parameters
        signals =. (1{"1 stage{::Records),stage{incoming
        if. Visible do. signals =. (Week+1){.Demand end.
        count =. k<.Week+1
        forecast =. (+/(-count){.signals) floor_ratio count
        delay =. +/2 3{stage{Initial
        0>.(target+forecast*delay)-position
    case. 'SMOOTH' do.
        'k target' =. parameters
        0>.signal+(target-position) floor_ratio k
    case. 'STERMAN' do.
        'theta alpha beta target' =. parameters
        forecast =. ((100*theta*signal)+((100-theta)*stage{Expected)) floor_ratio 100
        Expected =: forecast stage}Expected
        net =. (stage{Inventory)-stage{Backlog
        correction =. (100*(target-net))-beta*line
        0>.((100*forecast)+alpha*correction) floor_ratio 10000
    end.
)
simulate_week =: 3 : 0
    received =. incoming =. i.0
    for_s. i.4 do.
        pipe =. s{::Shipping
        received =. received,{.pipe
        Shipping =: (<}.pipe) s}Shipping
        pipe =. s{::Pending
        incoming =. incoming,{.pipe
        Pending =: (<}.pipe) s}Pending
    end.
    plant_incoming =. {:incoming
    incoming =. (Week{Demand),}:incoming
    Inventory =: Inventory+received
    old_back =. Backlog
    requested =. Backlog+incoming
    shipped =. Inventory<.requested
    for_s. I.Capacities>:0 do. shipped =. ((s{shipped)<.s{Capacities) s}shipped end.
    Inventory =: Inventory-shipped
    Backlog =: requested-shipped
    ontime =. incoming<.0>.shipped-old_back
    for_s. i.3 do. Shipping =: (<(s{::Shipping),(s+1){shipped) s}Shipping end.
    requested =. PlantBack+plant_incoming
    made =. requested
    if. PlantCapacity>:0 do. made =. made<.PlantCapacity end.
    PlantBack =: requested-made
    Shipping =: (<(3{::Shipping),made) 3}Shipping
    lines =. supply ''
    positions =. (Inventory+lines)-Backlog
    orders =. i.0
    for_s. i.4 do.
        quantity =. (s;(s{lines);(s{positions);incoming) policy_order s{::Policies
        quantity =. (s{Lots)*quantity ceil_ratio s{Lots
        orders =. orders,quantity
        Pending =: (<(s{::Pending),quantity) s}Pending
    end.
    hc =. Holding*Inventory
    bc =. Penalty*Backlog
    costs =. hc+bc
    for_s. i.4 do.
        row =. (s{received),(s{incoming),(s{shipped),(s{old_back),(s{ontime),(s{Inventory),(s{Backlog),(s{orders),(s{hc),(s{bc),s{costs
        Records =: (<(s{::Records),row) s}Records
        if. y do.
            if. ((s{old_back)=0)*.(s{Backlog)>0 do. emit 'STOCKOUT';(s{::STAGES);'week';(Week+1);'backlog';s{Backlog
            elseif. ((s{old_back)>0)*.(s{Backlog)=0 do. emit 'RECOVER';(s{::STAGES);'week';Week+1 end.
        end.
    end.
    PlantRecords =: PlantRecords,1 3$plant_incoming,made,PlantBack
    Week =: Week+1
    +/costs
)
variation =: 3 : '((#y)*+/*:y)-*:+/y'
cost_totals =: 3 : 0
    totals =. 0 3$0
    for_record. Records do. totals =. totals,+/8 9 10{"1 >record end.
    totals
)
trial =: 3 : 0
    saved =. snapshot ''
    hold =. Holding
    penalty =. Penalty
    lots =. Lots
    caps =. Capacities
    plantcap =. PlantCapacity
    visible =. Visible
    demand =. Demand
    initialize ''
    Holding =: hold
    Penalty =: penalty
    Lots =: lots
    Capacities =: caps
    PlantCapacity =: plantcap
    Visible =: visible
    Demand =: demand
    Policies =: y
    while. Week<#Demand do. simulate_week 0 end.
    costs =. 2{"1 cost_totals ''
    retail =. 0{::Records
    fill =. fill_rate (+/4{"1 retail),+/1{"1 retail
    bull =. ratio (variation 7{"1 3{::Records),variation Demand
    restore saved
    costs;fill;bull
)
range_error =: 4 : 0
    if. 0=#y do. 0$a: return. end.
    'start finish' =. 0".>y
    if. (start<1)+.(start>finish)+.finish>x do. 'bad range';start;finish
    else. 0$a: end.
)
range_values =: 4 : 0
    if. #y do. 0".>y else. 1,x end.
)
values =: 4 : 0
    select. x
    case. 'ORDERS' do. 7{"1 y
    case. 'INV' do. 5{"1 y
    case. 'BACK' do. 6{"1 y
    case. 'NET' do. (5{"1 y)-6{"1 y
    end.
)
capacity_text =: 3 : 0
    if. y=_1 do. 'OFF' else. number y end.
)
status =: 3 : 0
    emit 'STATUS week';Week;'of';#Demand
    lines =. supply ''
    positions =. (Inventory+lines)-Backlog
    for_s. i.4 do.
        policy =. s{::Policies
        line =. (s{::STAGES);'inv';(s{Inventory);'back';(s{Backlog);'transit';(pipeline s{::Shipping);'pending';(pipeline s{::Pending);'supply';(s{lines);'position';(s{positions);'policy';2{::policy
        if. (0{::policy)-:'STERMAN' do. line =. line,'expect';money s{Expected end.
        emit line
    end.
    emit 'PLANT back';PlantBack
)
settings =: 3 : 0
    emit <'SETTINGS'
    for_s. i.4 do.
        'shipping orders' =. 2 3{s{Initial
        emit (s{::STAGES);'holding';(s{Holding);'backlog';(s{Penalty);'batch';(s{Lots);'capacity';(capacity_text s{Capacities);'delays';shipping;orders
    end.
    emit 'PLANT capacity';capacity_text PlantCapacity
    emit 'VISIBILITY';Visible{::;:'OFF ON'
)
show_week =: 3 : 0
    emit 'WEEK';y;'demand';(y-1){Demand
    for_s. i.4 do.
        row =. (y-1){s{::Records
        emit (s{::STAGES);'recv';(0{row);'in';(1{row);'ship';(2{row);'inv';(5{row);'back';(6{row);'order';(7{row);'cost';money 10{row
    end.
    row =. (y-1){PlantRecords
    emit 'PLANT in';(0{row);'made';(1{row);'back';2{row
)
show_costs =: 3 : 0
    emit 'COSTS week';Week
    costs =. cost_totals ''
    labels =. STAGES,<'TOTAL'
    costs =. costs,+/costs
    for_s. i.5 do.
        'holding backlog total' =. s{costs
        emit (s{::labels);'holding';(money holding);'backlog';(money backlog);'total';money total
    end.
)
show_balance =: 3 : 0
    emit 'BALANCE week';Week
    for_s. i.4 do.
        record =. s{::Records
        emit (s{::STAGES);'start';(0{s{Initial);'received';(+/0{"1 record);'shipped';(+/2{"1 record);'end';(s{Inventory);'owed';s{Backlog
    end.
    initial =. +/(0{"1 Initial)+(1{"1 Initial)*2{"1 Initial
    transit =. 0
    for_pipe. Shipping do. transit =. transit++/>pipe end.
    emit 'SYSTEM initial';initial;'produced';(+/1{"1 PlantRecords);'delivered';(+/2{"1 0{::Records);'stock';(+/Inventory);'transit';transit
)
show_summary =: 3 : 0
    emit 'SUMMARY weeks';span 1,Week
    for_s. i.4 do.
        record =. s{::Records
        orders =. 7{"1 record
        emit (s{::STAGES);'avg_inv';(2 decimal (+/5{"1 record),Week);'avg_back';(2 decimal (+/6{"1 record),Week);'orders';(+/orders);'min';(<./orders);'max';(>./orders);'zero_weeks';+/orders=0
    end.
)
show_fill =: 3 : 0
    emit 'FILLRATE weeks';span 1,Week
    for_s. i.4 do.
        record =. s{::Records
        ontime =. +/4{"1 record
        ordered =. +/1{"1 record
        stockout =. +/(6{"1 record)>0
        service =. (2 decimal (100*(Week-stockout)),Week),'%'
        emit (s{::STAGES);'fill';(fill_rate ontime,ordered);'ontime';ontime;'ordered';ordered;'stockout_weeks';stockout;'service';service
    end.
)
show_bullwhip =: 3 : 0
    demand =. Week{.Demand
    dv =. variation demand
    previous =. dv
    emit 'BULLWHIP weeks';(span 1,Week);'demand mean';(4 decimal (+/demand),Week);'var';4 decimal dv,*:Week
    for_s. i.4 do.
        orders =. 7{"1 s{::Records
        v =. variation orders
        emit (s{::STAGES);'mean';(4 decimal (+/orders),Week);'var';(4 decimal v,*:Week);'ratio';(ratio v,dv);'step';ratio v,previous
        previous =. v
    end.
)
show_peaks =: 3 : 0
    emit 'PEAKS weeks';span 1,Week
    for_s. i.4 do.
        record =. s{::Records
        inv =. 5{"1 record
        back =. 6{"1 record
        maxinv =. >./inv
        maxback =. >./back
        iw =. bw =. '-'
        if. maxinv do. iw =. number 1+inv i.maxinv end.
        if. maxback do. bw =. number 1+back i.maxback end.
        best =. run =. start =. beststart =. 0
        for_i. i.Week do.
            if. i{back do.
                if. run=0 do. start =. i+1 end.
                run =. run+1
                if. run>best do. best =. run
                    beststart =. start end.
            else. run =. 0 end.
        end.
        longest =. '0'
        if. best do. longest =. (number best),' weeks ',span beststart,(beststart+best)-1 end.
        emit (s{::STAGES);'max_inv';maxinv;'week';iw;'max_back';maxback;'week';bw;'longest_stockout';longest
    end.
)
leadtime =: 3 : 0
    record =. y{::Records
    delay =. +/2 3{y{Initial
    initial =. delay*1{y{Initial
    receipts =. (+/\0{"1 record)-initial
    orders =. 7{"1 record
    cumulative =. +/\orders
    leads =. i.0
    for_t. I.orders>0 do.
        matches =. I.((i.Week)>t)*.receipts>:t{cumulative
        if. #matches do. leads =. leads,({.matches)-t end.
    end.
    count =. +/orders>0
    line =. 'LEADTIME';(y{::STAGES);'nominal';delay;'orders';count;'completed';(#leads);'open';count-#leads
    if. #leads do. line =. line,'min';(<./leads);'avg';(2 decimal (+/leads),#leads);'max';>./leads
    else. line =. line,<'min - avg - max -' end.
    emit line
)
execute =: 3 : 0
    fields =. ' ' split y
    command =. 0{::fields
    args =. }.fields
    select. command
    case. 'DEMAND';'GENERATE' do.
        if. command-:'DEMAND' do. demand =. 0".>args
        else.
            'weeks base spread seed' =. 0".>4{.args
            changes =. _3[\4}.args
            for_change. changes do.
                week =. 0".1{::change
                if. (week<1)+.week>weeks do. fail 'week';week;'outside horizon' return. end.
            end.
            levels =. weeks$base
            for_change. changes do.
                kind =. 0{::change
                week =. 0".1{::change
                amount =. 0".2{::change
                times =. 1+i.weeks
                select. kind
                case. 'STEP' do. levels =. levels+amount*times>:week
                case. 'PULSE' do. levels =. levels+amount*times=week
                case. 'RAMP' do. levels =. levels+amount*0>.(times-week)+1
                end.
            end.
            negative =. I.levels<0
            if. #negative do. fail 'negative level at week';1+{.negative return. end.
            demand =. i.0
            for_level. levels do.
                seed =. 2147483647|48271x*seed
                demand =. demand,level+spread|seed
            end.
        end.
        BaseDemand =: demand
        initialize ''
        emit 'DEMAND weeks';(#Demand);'total';(+/Demand);'min';(<./Demand);'max';>./Demand
    case. 'RUN' do.
        if. Week=#Demand do. fail 'horizon reached at week';#Demand return. end.
        start =. Week+1
        count =. (0".0{::args)<.(#Demand)-Week
        total =. 0
        for_i. i.count do. total =. total+simulate_week 1 end.
        demand =. count{.(start-1)}.Demand
        emit 'RUN';(span start,Week);'demand';(+/demand);'cost';money total
        if. Week=#Demand do. emit 'HORIZON';Week end.
    case. 'RESET' do. initialize ''
        emit 'RESET week';0
    case. 'SAVE' do.
        name =. 0{::args
        index =. SnapshotNames i.<name
        state =. snapshot ''
        if. index=#Snapshots do.
            SnapshotNames =: SnapshotNames,<name
            Snapshots =: Snapshots,<state
        else. Snapshots =: (<state) index}Snapshots end.
        emit 'SAVE';name;'week';Week
    case. 'LOAD' do.
        name =. 0{::args
        index =. SnapshotNames i.<name
        if. index=#Snapshots do. fail 'no snapshot';name return. end.
        restore index{::Snapshots
        emit 'LOAD';name;'week';Week
    case. 'SET';'BATCH';'CAPACITY';'COST' do.
        name =. 0{::args
        stage =. STAGES i.<name
        special =. ((command-:'SET')*.name-:'ALL')+.((command-:'CAPACITY')*.name-:'PLANT')
        if. (stage=4)*.-.special do. fail 'unknown stage';name return. end.
        select. command
        case. 'SET' do.
            reason =. policy_error }.args
            if. #reason do. fail reason return. end.
            policy =. parse_policy }.args
            stages =. ,stage
            if. name-:'ALL' do. stages =. i.4 end.
            for_s. stages do. s set_policy policy end.
            emit 'SET';name;2{::policy
        case. 'BATCH' do.
            lot =. 0".1{::args
            if. (lot<1)+.lot>100 do. fail 'invalid batch size';lot return. end.
            Lots =: lot stage}Lots
            emit 'BATCH';name;lot
        case. 'CAPACITY' do.
            token =. 1{::args
            capacity =. _1
            if. -.token-:'OFF' do. capacity =. 0".token end.
            if. capacity>10000 do. fail 'invalid capacity';token return. end.
            if. name-:'PLANT' do. PlantCapacity =: capacity
            else. Capacities =: capacity stage}Capacities end.
            emit 'CAPACITY';name;token
        case. 'COST' do.
            'hold penalty' =. 0".>}.args
            if. (hold>1000)+.penalty>1000 do. fail <'invalid cost' return. end.
            Holding =: hold stage}Holding
            Penalty =: penalty stage}Penalty
            emit 'COST';name;'holding';hold;'backlog';penalty
        end.
    case. 'VISIBILITY' do.
        mode =. 0{::args
        if. -.(<mode)e.;:'ON OFF' do. fail 'unknown visibility';mode return. end.
        Visible =: mode-:'ON'
        emit 'VISIBILITY';mode
    case. 'SHOCK' do.
        'week demand' =. 0".>args
        if. (week<1)+.week>#Demand do. fail 'week';week;'outside horizon' return. end.
        if. week<:Week do. fail 'week';week;'already simulated' return. end.
        old =. (week-1){Demand
        Demand =: demand (week-1)}Demand
        emit 'SHOCK week';week;old;'->';demand
    case. 'STATUS' do. status ''
    case. 'SETTINGS' do. settings ''
    case. 'COSTS' do. show_costs ''
    case. 'BALANCE' do. show_balance ''
    case. 'DEMANDS';'CHAIN' do.
        limit =. #Demand
        if. command-:'CHAIN' do.
            if. Week=0 do. fail <'no weeks simulated' return. end.
            limit =. Week
        end.
        reason =. limit range_error args
        if. #reason do. fail reason return. end.
        'start finish' =. limit range_values args
        indices =. (start-1)+i.1+finish-start
        if. command-:'DEMANDS' do.
            demand =. indices{Demand
            emit 'DEMANDS';(span start,finish);'total';(+/demand);'min';(<./demand);'max';>./demand
            emit <"0 demand
        else.
            emit 'CHAIN';span start,finish
            widths =. 4 6 11 11 11 11
            emit <widths aligned ('week';'demand'),STAGES
            for_i. indices do.
                line =. (i+1);i{Demand
                for_record. Records do. line =. line,<7{i{>record end.
                emit <widths aligned line
            end.
        end.
    case. 'WEEK';'SUMMARY';'FILLRATE';'BULLWHIP';'PEAKS' do.
        if. Week=0 do. fail <'no weeks simulated' return. end.
        select. command
        case. 'WEEK' do.
            week =. 0".0{::args
            if. (week<1)+.week>Week do. fail 'bad week';week return. end.
            show_week week
        case. 'SUMMARY' do. show_summary ''
        case. 'FILLRATE' do. show_fill ''
        case. 'BULLWHIP' do. show_bullwhip ''
        case. 'PEAKS' do. show_peaks ''
        end.
    case. 'TABLE';'LEADTIME';'PLOT';'HISTOGRAM' do.
        name =. 0{::args
        stage =. STAGES i.<name
        if. stage=4 do. fail 'unknown stage';name return. end.
        if. (<command)e.;:'PLOT HISTOGRAM' do.
            mode =. 1{::args
            if. -.(<mode)e.MODES do. fail 'unknown mode';mode return. end.
            if. command-:'HISTOGRAM' do.
                width =. 0".2{::args
                if. (width<1)+.width>100 do. fail 'invalid width';width return. end.
            end.
        end.
        if. Week=0 do. fail <'no weeks simulated' return. end.
        record =. stage{::Records
        select. command
        case. 'LEADTIME' do. leadtime stage
        case. 'HISTOGRAM' do.
            bins =. (mode values record) floor_ratio width
            emit 'HISTOGRAM';name;mode;'width';width;'weeks';span 1,Week
            for_bin. (<./bins)+i.1+(>./bins)-<./bins do.
                count =. +/bin=bins
                lower =. bin*width
                label =. (number lower),'..',number (lower+width)-1
                line =. label;count
                if. count do. line =. line,<count#'*' end.
                emit line
            end.
        case. 'TABLE';'PLOT' do.
            offset =. 1
            if. command-:'PLOT' do. offset =. 2 end.
            limits =. offset}.args
            reason =. Week range_error limits
            if. #reason do. fail reason return. end.
            'start finish' =. Week range_values limits
            indices =. (start-1)+i.1+finish-start
            if. command-:'TABLE' do.
                emit 'TABLE';name;span start,finish
                emit <'week     in   ship   recv    inv   back  order      cost'
                for_i. indices do.
                    row =. i{record
                    line =. (<i+1),(<"0 (1 2 0 5 6 7){row),<money 10{row
                    emit <4 6 6 6 6 6 6 9 aligned line
                end.
            else.
                vals =. indices{mode values record
                maximum =. >./vals
                if. mode-:'NET' do.
                    emit 'PLOT';name;mode;(span start,finish);'min';(<./vals);'max';maximum
                    scale =. >./|vals
                else.
                    emit 'PLOT';name;mode;(span start,finish);'max';maximum
                    scale =. maximum
                end.
                for_j. i.#indices do.
                    value =. j{vals
                    weektext =. 3 aligned <1+j{indices
                    n =. 0
                    if. mode-:'NET' do.
                        if. scale do. n =. (25*|value) floor_ratio scale end.
                        if. value<0 do. bar =. ((25-n)#' '),(n#'-'),'|'
                        else. bar =. (25#' '),'|',n#'+' end.
                        emit <weektext,' ',bar,' ',number value
                    else.
                        if. scale do. n =. (50*value) floor_ratio scale end.
                        emit <weektext,' |',(n#'#'),' ',number value
                    end.
                end.
            end.
        end.
    case. 'COMPARE' do.
        chunks =. 0$a:
        current =. 0$a:
        for_token. args do.
            if. token-:<'/' do. chunks =. chunks,<current
                current =. 0$a:
            else. current =. current,token end.
        end.
        chunks =. chunks,<current
        policies =. 0$a:
        for_chunk. chunks do.
            reason =. policy_error >chunk
            if. #reason do. fail reason return. end.
            policies =. policies,<parse_policy >chunk
        end.
        results =. 0$a:
        costs =. i.0
        for_policy. policies do.
            result =. trial 4$policy
            results =. results,<result
            costs =. costs,+/0{::result
        end.
        emit 'COMPARE';(#policies);'weeks';#Demand
        order =. /:costs
        for_rank. i.#order do.
            i =. rank{order
            'stagecosts fill bull' =. i{::results
            emit (rank+1);(2{::i{::policies);'total';(money i{costs);'fill';fill;'bullwhip';bull
        end.
    case. 'OPTIMIZE' do.
        name =. 0{::args
        stage =. STAGES i.<name
        if. (stage=4)*.-.name-:'ALL' do. fail 'unknown stage';name return. end.
        'low high' =. 0".>}.args
        if. low>high do. fail 'bad range';low;high return. end.
        if. (high-low)>200 do. fail <'range too large' return. end.
        bestcost =. _
        best =. low
        besttotal =. 0
        for_target. low+i.1+high-low do.
            policy =. parse_policy 'BASESTOCK';number target
            policies =. Policies
            if. name-:'ALL' do. policies =. 4$<policy
            else. policies =. (<policy) stage}policies end.
            result =. trial policies
            costs =. 0{::result
            total =. +/costs
            cost =. total
            if. stage<4 do. cost =. stage{costs end.
            if. cost<bestcost do. bestcost =. cost
                best =. target
                besttotal =. total end.
        end.
        emit 'OPTIMIZE';name;'BASESTOCK';best;'cost';(money bestcost);'total';money besttotal
    case. do. fail 'unknown command';command
    end.
    i.0
)
main =: 3 : 0
    lines =. <;._2 (1!:1 3),LF
    for_line. 4{.lines do.
        fields =. ' ' split >line
        Initial =: Initial,1 6$0".>6{.}.fields
        InitialPolicies =: InitialPolicies,<parse_policy 7}.fields
    end.
    for_line. 4}.lines do.
        if. (>line)-:'END' do. break. end.
        execute >line
    end.
    i.0
)
main ''
