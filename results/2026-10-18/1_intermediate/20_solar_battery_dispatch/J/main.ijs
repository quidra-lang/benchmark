LF =: 10{a.
ITEMS =: ;:'CAPACITY INITIAL CHARGE DISCHARGE CEFF DEFF RESERVE COST EXPORT FEEDIN FIXED DEMAND PVSCALE'
MINIMUM =: 1 0 1 1 1 1 0 0 0 0 0 0 0
MAXIMUM =: 100000 100 20000 20000 100 100 100 100000 100000 10000 100000 100000 300
STRATEGIES =: ;:'SELF TOU PEAKSHAVE BACKUP EXPORTPEAK'
COMMANDS =: ;:'RUN SET PRICE RESET CONFIG NOBATTERY COMPARE SIZE SWEEP OUTAGE DIFF HOURLY DAILY BILL SAVINGS BYPERIOD DAYTYPE PEAKS PROFILE FLOWS SELFSUFF CYCLES USAGE HISTOGRAM CHART END'
RECORD_FIELDS =: ;:'load pv period charge discharge drawn soc import export curtailed shortfall loss pv_load pv_battery pv_grid pv_curtail battery_load battery_grid grid_load grid_battery import_cost export_income'
RESULT_FIELDS =: ;:'strategy settings prices rows start reserve bill peak demand'
FLOW_FIELDS =: ;:'pv_load pv_battery pv_grid pv_curtail battery_load battery_grid grid_load grid_battery'
FLOW_NAMES =: ;:'PV>LOAD PV>BATTERY PV>GRID PV>CURTAIL BATTERY>LOAD BATTERY>GRID GRID>LOAD GRID>BATTERY'
Current =: 0$a:
split =: 4 : '<;._1 x,y'
floor_ratio =: 4 : '<.(x:x)%x:y'
ceil_ratio =: 4 : '-((-x) floor_ratio y)'
number =: 3 : 0
    ,'0' 8!:2 y
)
integer =: 3 : 0
    if. '-'={.y do. -0".}.y else. 0".y end.
)
numbers =: 3 : '>integer each y'
padded =: 4 : 0
    s =. number y
    ((0>.x-#s)#'0'),s
)
money =: 3 : 0
    value =. |y
    ((y<0)#'-'),(number value floor_ratio 100),'.',2 padded 100|value
)
percentage =: 4 : 0
    if. y=0 do. '0.00' else. money (10000*x) floor_ratio y end.
)
words =: 3 : 0
    result =. ''
    for_i. i.#y do.
        value =. i{::y
        if. 2~:3!:0 value do. value =. number value end.
        if. i do. result =. result,' ' end.
        result =. result,value
    end.
    result
)
emit =: 3 : '(y,LF) 1!:2 4'
say =: 3 : 'emit words y'
fail =: 3 : 'emit ''ERROR '',y'
align =: 4 : '((0>.x-#y)#'' ''),y'
table =: 4 : 0
    line =. ''
    for_i. i.#y do.
        value =. i{::y
        if. 2~:3!:0 value do. value =. number value end.
        line =. line,(i{x) align value
    end.
    emit line
)
bar =: 3 : '''|'',(y#''#''),((20-y)#''.''),''|'''
setting =: 4 : '(ITEMS i.<x){y'
get =: 4 : '(RESULT_FIELDS i.<x){::y'
column =: 4 : '(RECORD_FIELDS i.<x){"1 y'
columns =: 4 : '(RECORD_FIELDS i.x){"1 y'
total =: 4 : '+/x column y'
net =: 3 : '(''import_cost'' total y)-''export_income'' total y'
day_indices =: 3 : '(24*(y-1))+i.24'
day_name =: 3 : 0
    if. y e.Holidays do. 'HOL' else. (7|y-1){::;:'MON TUE WED THU FRI SAT SUN' end.
)
notation =: 3 : 0
    result =. ({.y){::STRATEGIES
    if. ({.y)e.1 2 3 do. result =. result,' ',number {:y end.
    result
)
sufficiency =: 3 : 0
    rows =. 'rows' get y
    load =. 'load' total rows
    (0>.load-'import' total rows) percentage load
)
parse_strategies =: 3 : 0
    result =. 0 2$0
    i =. 0
    while. i<#y do.
        name =. i{::y
        kind =. STRATEGIES i.<name
        if. kind=#STRATEGIES do. ('unknown strategy ',name);result return. end.
        i =. i+1
        parameter =. 0
        if. kind e.1 2 3 do.
            if. i=#y do. ('missing parameter for ',name);result return. end.
            parameter =. integer i{::y
            i =. i+1
            low =. kind=1
            high =. 100+99900*kind=2
            if. (parameter<low)+.parameter>high do. ('invalid parameter for ',name);result return. end.
        end.
        result =. result,kind,parameter
    end.
    '';result
)
valid_range =: 4 : 0
    'low high step' =. y
    if. (low<x{MINIMUM)+.(high>x{MAXIMUM)+.(high<low)+.step<1 do. 0 return. end.
    (1+(high-low) floor_ratio step)<:20
)
check =: 4 : 0
    strategies =. 0 2$0
    wrong =. 'wrong number of arguments';strategies
    select. x
    case. 0;6 do.
        'error strategies' =. parse_strategies y
        if. #error do. error;strategies return. end.
        if. (x=0)*.(#strategies)~:1 do. wrong return. end.
        if. 0=#strategies do. wrong return. end.
    case. 1;2 do.
        if. 2~:#y do. wrong return. end.
        name =. 0{::y
        value =. integer 1{::y
        if. x=1 do.
            item =. ITEMS i.<name
            if. item=#ITEMS do. ('unknown parameter ',name);strategies return. end.
            low =. item{MINIMUM
            high =. item{MAXIMUM
        else.
            if. -. (<name)e.PeriodNames do. ('unknown period ',name);strategies return. end.
            low =. 0
            high =. 10000
        end.
        if. (value<low)+.value>high do. ('invalid value for ',name);strategies return. end.
    case. 7 do.
        if. 3~:#y do. wrong return. end.
        if. -.0 valid_range numbers y do. 'invalid range';strategies return. end.
    case. 8 do.
        if. 5>#y do. wrong return. end.
        item =. ITEMS i.0{y
        if. item=#ITEMS do. ('unknown parameter ',0{::y);strategies return. end.
        if. -.item valid_range numbers 3{.}.y do. 'invalid range';strategies return. end.
        'error strategies' =. parse_strategies 4}.y
        if. #error do. error;strategies return. end.
        if. 1~:#strategies do. wrong return. end.
    case. 9 do.
        if. 3~:#y do. wrong return. end.
        'day first last' =. numbers y
        if. (day<1)+.day>Days do. 'invalid day';strategies return. end.
        if. (first<0)+.(last<first)+.last>23 do. 'invalid hours';strategies return. end.
    case. 10 do.
        if. 2>#y do. wrong return. end.
        day =. integer 0{::y
        if. (day<1)+.day>Days do. 'invalid day';strategies return. end.
        'error strategies' =. parse_strategies }.y
        if. #error do. error;strategies return. end.
        if. 1~:#strategies do. wrong return. end.
    case. 11;24 do.
        if. 1~:#y do. wrong return. end.
        day =. integer 0{::y
        if. (day<1)+.day>Days do. 'invalid day';strategies return. end.
    case. 17 do.
        if. 1~:#y do. wrong return. end.
        if. 1>integer 0{::y do. 'invalid count';strategies return. end.
    case. do. if. #y do. wrong return. end.
    end.
    if. (x>:9)*.(x<25)*.0=#Current do. 'no run';strategies return. end.
    '';strategies
)
simulate =: 3 : 0
    'strategy settings prices outage' =. y
    'kind parameter' =. strategy
    'capacity initial charge_max discharge_max ceff deff reserve_pct cost export_max feedin fixed demand_price pvscale' =. settings
    if. kind=3 do. reserve_pct =. reserve_pct>.parameter end.
    reserve =. (capacity*reserve_pct) floor_ratio 100
    start =. (capacity*initial) floor_ratio 100
    soc =. start
    lo =. prices i.<./prices
    hi =. prices i.>./prices
    arbitrage =. (kind=4)*.feedin>lo{prices
    generation =. (BasePV*pvscale) floor_ratio 100
    rows =. 0 22$0
    for_i. i.#Load do.
        load =. i{Load
        pv =. i{generation
        period =. i{HourPeriods
        hour =. 24|i
        day =. 1+i floor_ratio 24
        interrupted =. (day=0{outage)*.(hour>:1{outage)*.hour<:2{outage
        direct =. load<.pv
        surplus =. pv-direct
        deficit =. load-direct
        pv_charge =. <./surplus,charge_max,(100*(capacity-soc)) ceil_ratio ceff
        pv_stored =. (pv_charge*ceff) floor_ratio 100
        soc =. soc+pv_stored
        surplus =. surplus-pv_charge
        target =. deficit
        lower =. reserve
        if. interrupted do. lower =. 0
        elseif. kind=1 do. target =. deficit*period=hi
        elseif. kind=2 do. target =. 0>.deficit-parameter
        elseif. (kind=4)*.arbitrage*.(period=lo)*.period~:hi do. target =. 0
        end.
        load_draw =. <./((100*target) ceil_ratio deff),discharge_max,0>.soc-lower
        battery_load =. (load_draw*deff) floor_ratio 100
        soc =. soc-load_draw
        deficit =. deficit-battery_load
        grid_charge =. grid_stored =. export_draw =. battery_grid =. 0
        if. interrupted do.
            grid_load =. pv_grid =. 0
            shortfall =. deficit
            curtailed =. surplus
        else.
            grid_load =. deficit
            shortfall =. 0
            pv_grid =. surplus<.export_max
            curtailed =. surplus-pv_grid
            headroom =. charge_max-pv_charge
            target =. _1
            if. (kind=1)*.(period=lo)*.period~:hi do.
                target =. (capacity*parameter) floor_ratio 100
            elseif. (kind=2)*.period=lo do.
                target =. capacity
                headroom =. headroom<.0>.parameter-grid_load
            elseif. (kind=3)*.period=lo do. target =. reserve
            elseif. (kind=4)*.arbitrage*.(period=lo)*.period~:hi do. target =. capacity
            end.
            if. target>:0 do.
                grid_charge =. headroom<.(100*0>.target-soc) ceil_ratio ceff
                grid_stored =. (grid_charge*ceff) floor_ratio 100
                soc =. soc+grid_stored
            end.
            if. (kind=4)*.arbitrage*.(period=hi)*.pv_charge=0 do.
                export_draw =. <./((100*(export_max-pv_grid)) ceil_ratio deff),(discharge_max-load_draw),0>.soc-reserve
                battery_grid =. (export_draw*deff) floor_ratio 100
                soc =. soc-export_draw
            end.
        end.
        charge =. pv_charge+grid_charge
        discharge =. battery_load+battery_grid
        drawn =. load_draw+export_draw
        imported =. grid_load+grid_charge
        exported =. pv_grid+battery_grid
        loss =. (pv_charge-pv_stored)+(grid_charge-grid_stored)+(load_draw-battery_load)+(export_draw-battery_grid)
        import_cost =. (imported*period{prices) floor_ratio 100000
        export_income =. (exported*feedin) floor_ratio 100000
        rows =. rows,load,pv,period,charge,discharge,drawn,soc,imported,exported,curtailed,shortfall,loss,direct,pv_charge,pv_grid,curtailed,battery_load,battery_grid,grid_load,grid_charge,import_cost,export_income
    end.
    peak =. >./'import' column rows
    demand =. (peak*demand_price) floor_ratio 1000
    bill =. (net rows)+fixed+demand
    NB. Each result retains the inputs used to calculate its records.
    strategy;settings;prices;rows;start;reserve;bill;peak;demand
)
baseline =: 3 : 0
    'settings prices' =. y
    simulate 0 0;(0,}.settings);prices;0 _1 _1
)
run_current =: 3 : 'simulate y;Settings;Prices;0 _1 _1'
report_run =: 3 : 0
    rows =. 'rows' get y
    say 'RUN';(notation 'strategy' get y);'bill';(money 'bill' get y);'import';('import' total rows);'export';('export' total rows);'soc';'soc' column {:rows
)
configuration =: 3 : 0
    say 'BATTERY';'capacity';(0{Settings);'initial';(1{Settings);'charge';(2{Settings);'discharge';(3{Settings);'ceff';(4{Settings);'deff';(5{Settings);'reserve';(6{Settings);'cost';7{Settings
    say 'GRID';'export';(8{Settings);'feedin';(9{Settings);'fixed';(10{Settings);'demand';11{Settings
    say 'SOLAR';'pvscale';12{Settings
    fields =. <'TARIFF'
    for_i. i.#Prices do. fields =. fields,(i{PeriodNames),<i{Prices end.
    fields =. fields,'cheapest';((Prices i.<./Prices){::PeriodNames);'peak';(Prices i.>./Prices){::PeriodNames
    say fields
)
compare =: 3 : 0
    base =. baseline Settings;Prices
    bill =. 'bill' get base
    results =. 0$a:
    bills =. 0$0
    for_strategy. y do.
        result =. run_current strategy
        results =. results,<result
        bills =. bills,'bill' get result
    end.
    say 'COMPARE';'baseline';money bill
    rank =. 0
    for_i. /:bills do.
        rank =. rank+1
        result =. i{::results
        amount =. 'bill' get result
        say ((number rank),'.');(notation 'strategy' get result);'bill';(money amount);'saving';(money bill-amount);'sufficiency';(sufficiency result),'%'
    end.
)
size =: 3 : 0
    'low high step' =. y
    base =. 'bill' get baseline Settings;Prices
    best =. _1
    best_cost =. 0
    best_saving =. 1
    for_capacity. low+step*i.1+(high-low) floor_ratio step do.
        settings =. capacity 0}Settings
        result =. simulate 0 0;settings;Prices;0 _1 _1
        bill =. 'bill' get result
        saving =. base-bill
        cost =. (capacity*'COST' setting Settings) floor_ratio 1000
        payback =. 'never'
        if. saving>0 do.
            w =. (10*cost) floor_ratio saving
            payback =. (number w floor_ratio 10),'.',number 10|w
            if. (best=_1)+.((x:cost)*best_saving)<(x:best_cost)*saving do.
                best =. capacity
                best_cost =. cost
                best_saving =. saving
            end.
        end.
        say 'SIZE';capacity;'bill';(money bill);'saving';(money saving);'cost';(money cost);'payback';payback
    end.
    if. best=_1 do. emit 'BEST none' else. say 'BEST';best end.
)
sweep =: 3 : 0
    'item low high step strategy' =. y
    best =. low
    best_bill =. _
    for_value. low+step*i.1+(high-low) floor_ratio step do.
        settings =. value item}Settings
        result =. simulate strategy;settings;Prices;0 _1 _1
        base =. 'bill' get baseline settings;Prices
        bill =. 'bill' get result
        if. bill<best_bill do.
            best =. value
            best_bill =. bill
        end.
        say 'SWEEP';(item{::ITEMS);value;'bill';(money bill);'saving';(money base-bill);'sufficiency';(sufficiency result),'%'
    end.
    say 'BEST';best
)
outage_report =: 3 : 0
    'day first last' =. y
    result =. simulate ('strategy' get Current);('settings' get Current);('prices' get Current);y
    rows =. 'rows' get result
    index =. first+24*(day-1)
    before =. 'start' get result
    if. index do. before =. 'soc' column (index-1){rows end.
    say 'OUTAGE';'day';day;'hours';((number first),'-',number last);'strategy';(notation 'strategy' get result);'soc';before
    emit 'hour   load     pv  disch    soc  short   curt'
    selected =. (index+i.1+last-first){rows
    values =. (;:'load pv discharge soc shortfall curtailed') columns selected
    for_i. i.#selected do. (4,6#7) table (<first+i),<"0 i{values end.
    load =. 'load' total selected
    unserved =. 'shortfall' total selected
    served =. '100.00'
    if. load do. served =. (load-unserved) percentage load end.
    say 'TOTAL';'load';load;'unserved';unserved;'served';(served,'%');'bill';money 'bill' get result
)
diff_report =: 3 : 0
    'day strategy' =. y
    result =. simulate strategy;('settings' get Current);('prices' get Current);0 _1 _1
    indices =. day_indices day
    left =. indices{'rows' get Current
    right =. indices{'rows' get result
    say 'DIFF';'day';day;(day_name day);(notation 'strategy' get Current);'vs';notation strategy
    emit 'hour   imp1   imp2   exp1   exp2   soc1   soc2'
    for_hour. i.24 do.
        a =. hour{left
        b =. hour{right
        (4,6#7) table hour;('import' column a);('import' column b);('export' column a);('export' column b);('soc' column a);'soc' column b
    end.
    cost1 =. net left
    cost2 =. net right
    say 'TOTAL';'cost1';(money cost1);'cost2';(money cost2);'difference';money cost2-cost1
)
hourly =: 3 : 0
    rows =. (day_indices y){'rows' get Current
    say 'HOURLY';'day';y;(day_name y);'strategy';notation 'strategy' get Current
    emit 'hour   load     pv charge  disch    soc import export   curt'
    fields =. ;:'load pv charge discharge soc import export curtailed'
    values =. fields columns rows
    for_hour. i.24 do. (4,8#7) table (<hour),<"0 hour{values end.
    sums =. (<'sum'),<"0 +/values
    sums =. (<'' ) 5}sums
    (4,8#7) table sums
)
daily =: 3 : 0
    rows =. 'rows' get Current
    say 'DAILY';'strategy';notation 'strategy' get Current
    emit 'day name    load      pv  import  export    curt     soc      cost'
    for_day. 1+i.Days do.
        selected =. (day_indices day){rows
        sums =. +/(;:'load pv import export curtailed') columns selected
        fields =. day;(day_name day)
        fields =. fields,(<"0 sums),('soc' column {:selected);money net selected
        (3 5,(6#8),10) table fields
    end.
    say 'TOTAL';'load';('load' total rows);'pv';('pv' total rows);'import';('import' total rows);'export';('export' total rows);'curtailed';('curtailed' total rows);'cost';money net rows
)
period_costs =: 3 : 0
    rows =. 'rows' get y
    result =. 0$0
    for_i. i.#PeriodNames do.
        selected =. (I.i='period' column rows){rows
        result =. result,'import_cost' total selected
    end.
    result
)
bill_report =: 3 : 0
    rows =. 'rows' get Current
    say 'BILL';'strategy';(notation 'strategy' get Current);'days';Days
    for_i. i.#PeriodNames do.
        selected =. (I.i='period' column rows){rows
        say 'IMPORT';(i{::PeriodNames);('import' total selected);'Wh';money 'import_cost' total selected
    end.
    say 'EXPORT';('export' total rows);'Wh';money -'export_income' total rows
    say 'FIXED';money 'FIXED' setting 'settings' get Current
    say 'DEMAND';('peak' get Current);'Wh';money 'demand' get Current
    say 'TOTAL';money 'bill' get Current
)
savings =: 3 : 0
    base =. baseline ('settings' get Current);'prices' get Current
    left =. (period_costs base),(-'export_income' total 'rows' get base),('demand' get base),'bill' get base
    right =. (period_costs Current),(-'export_income' total 'rows' get Current),('demand' get Current),'bill' get Current
    names =. PeriodNames,;:'EXPORT DEMAND TOTAL'
    say 'SAVINGS';'strategy';notation 'strategy' get Current
    for_i. i.#names do.
        a =. i{left
        b =. i{right
        say (i{::names);(money a);'->';(money b);'saving';money a-b
    end.
)
byperiod =: 3 : 0
    rows =. 'rows' get Current
    say 'BYPERIOD';'strategy';notation 'strategy' get Current
    for_i. i.#PeriodNames do.
        selected =. (I.i='period' column rows){rows
        say (i{::PeriodNames);'hours';(#selected);'load';('load' total selected);'pv';('pv' total selected);'charge';('charge' total selected);'discharge';('discharge' total selected);'import';('import' total selected);'export';'export' total selected
    end.
)
daytype =: 3 : 0
    rows =. 'rows' get Current
    say 'DAYTYPE';'strategy';notation 'strategy' get Current
    for_type. i.2 do.
        days =. 1+I.Weekend=type
        indices =. ,(24*(days-1))+/i.24
        selected =. indices{rows
        count =. #days
        averages =. (+/(;:'load pv import export') columns selected) floor_ratio count
        cost =. net selected
        cost =. (*cost)*(|cost) floor_ratio count
        say (type{::;:'WEEKDAY WEEKEND');'days';count;'load';(0{averages);'pv';(1{averages);'import';(2{averages);'export';(3{averages);'cost';money cost
    end.
)
peaks =: 3 : 0
    rows =. 'rows' get Current
    imports =. 'import' column rows
    indices =. I.imports>0
    indices =. (y<.#indices){.indices /: -indices{imports
    say 'PEAKS';'strategy';notation 'strategy' get Current
    if. 0=#indices do. emit 'none' return. end.
    for_rank. i.#indices do.
        index =. rank{indices
        row =. index{rows
        say ((number rank+1),'.');'day';(1+index floor_ratio 24);'hour';(24|index);(('period' column row){::PeriodNames);'import';('import' column row);'load';('load' column row);'soc';'soc' column row
    end.
)
profile =: 3 : 0
    rows =. 'rows' get Current
    say 'PROFILE';'strategy';(notation 'strategy' get Current);'days';Days
    emit 'hour   load     pv import export    soc'
    for_hour. i.24 do.
        selected =. (hour+24*i.Days){rows
        averages =. (+/(;:'load pv import export soc') columns selected) floor_ratio Days
        (4,5#7) table (<hour),<"0 averages
    end.
)
flows =: 3 : 0
    rows =. 'rows' get Current
    sums =. +/FLOW_FIELDS columns rows
    say 'FLOWS';'strategy';notation 'strategy' get Current
    for_i. i.8 do. say (i{::FLOW_NAMES);i{sums end.
    say 'LOSSES';'loss' total rows
    say 'STORED';('soc' column {:rows)-'start' get Current
)
selfsuff =: 3 : 0
    rows =. 'rows' get Current
    consumed =. ('pv_load' total rows)+'pv_battery' total rows
    consumption =. consumed percentage 'pv' total rows
    say 'SELFSUFF';'sufficiency';((sufficiency Current),'%');'consumption';consumption,'%'
)
cycles =: 3 : 0
    rows =. 'rows' get Current
    capacity =. 'CAPACITY' setting 'settings' get Current
    drawn =. 'drawn' total rows
    divisor =. drawn+.capacity
    fraction =. (number drawn floor_ratio divisor),'/',number capacity floor_ratio divisor
    w =. (1000*drawn) floor_ratio capacity
    decimal =. (number w floor_ratio 1000),'.',3 padded 1000|w
    say 'CYCLES';fraction;decimal;'drawn';drawn;'losses';'loss' total rows
)
usage =: 3 : 0
    rows =. 'rows' get Current
    capacity =. 'CAPACITY' setting 'settings' get Current
    reserve =. 'reserve' get Current
    charge =. 'charge' column rows
    drawn =. 'drawn' column rows
    soc =. 'soc' column rows
    low =. soc<:reserve
    longest =. run =. first =. 0
    for_i. i.#low do.
        if. i{low do. run =. run+1 else. run =. 0 end.
        if. run>longest do.
            longest =. run
            first =. 1+i-run
        end.
    end.
    fields =. 'USAGE';'charging';(+/charge>0);'discharging';(+/drawn>0);'idle';(+/(charge=0)*.drawn=0);'full';(+/soc=capacity);'low';(+/low);'longest';longest
    if. longest do. fields =. fields,'from';'day';(1+first floor_ratio 24);'hour';24|first end.
    say fields
)
histogram =: 3 : 0
    rows =. 'rows' get Current
    capacity =. 'CAPACITY' setting 'settings' get Current
    bands =. 9<.(10*'soc' column rows) floor_ratio capacity
    say 'HISTOGRAM';'strategy';notation 'strategy' get Current
    for_i. i.10 do.
        count =. +/bands=i
        width =. (20*count) floor_ratio #rows
        emit (3 align number 10*i),'% ',(bar width),' ',number count
    end.
)
chart =: 3 : 0
    rows =. (day_indices y){'rows' get Current
    capacity =. 'CAPACITY' setting 'settings' get Current
    say 'CHART';'day';y;(day_name y);'strategy';notation 'strategy' get Current
    for_hour. i.24 do.
        soc =. 'soc' column hour{rows
        width =. (20*soc) floor_ratio capacity
        emit (2 align number hour),' ',(bar width),' ',(soc percentage capacity),'%'
    end.
)
execute =: 3 : 0
    tokens =. ' ' split y
    name =. 0{::tokens
    command =. COMMANDS i.<name
    if. command=#COMMANDS do. fail 'unknown command ',name return. end.
    args =. }.tokens
    'error strategies' =. command check args
    if. #error do. fail error return. end.
    select. command
    case. 0 do.
        Current =: run_current {.strategies
        report_run Current
    case. 1 do.
        item =. ITEMS i.0{args
        value =. integer 1{::args
        old =. item{Settings
        Settings =: value item}Settings
        say 'SET';(item{::ITEMS);old;'->';value
    case. 2 do.
        period =. PeriodNames i.0{args
        value =. integer 1{::args
        old =. period{Prices
        Prices =: value period}Prices
        say 'PRICE';(period{::PeriodNames);old;'->';value;'cheapest';((Prices i.<./Prices){::PeriodNames);'peak';(Prices i.>./Prices){::PeriodNames
    case. 3 do.
        Settings =: InitialSettings
        Prices =: InitialPrices
        emit 'RESET'
    case. 4 do. configuration ''
    case. 5 do.
        result =. baseline Settings;Prices
        rows =. 'rows' get result
        say 'NOBATTERY';'bill';(money 'bill' get result);'import';('import' total rows);'export';('export' total rows);'curtailed';('curtailed' total rows);'peak';'peak' get result
    case. 6 do. compare strategies
    case. 7 do. size numbers args
    case. 8 do.
        'low high step' =. numbers 3{.}.args
        sweep (ITEMS i.0{args);low;high;step;{.strategies
    case. 9 do. outage_report numbers args
    case. 10 do. diff_report (integer 0{::args);{.strategies
    case. 11 do. hourly integer 0{::args
    case. 12 do. daily ''
    case. 13 do. bill_report ''
    case. 14 do. savings ''
    case. 15 do. byperiod ''
    case. 16 do. daytype ''
    case. 17 do. peaks integer 0{::args
    case. 18 do. profile ''
    case. 19 do. flows ''
    case. 20 do. selfsuff ''
    case. 21 do. cycles ''
    case. 22 do. usage ''
    case. 23 do. histogram ''
    case. 24 do. chart integer 0{::args
    end.
    i.0
)
next_line =: 3 : 0
    line =. InputPosition{::InputLines
    InputPosition =: InputPosition+1
    ' ' split line
)
read_division =: 3 : 0
    mapping =. 24$0
    pairs =. }.y
    for_i. 2*i.-:#pairs do.
        first =. integer i{::pairs
        last =. 24
        if. (i+2)<#pairs do. last =. integer (i+2){::pairs end.
        period =. PeriodNames i.(i+1){pairs
        mapping =. period (first+i.last-first)}mapping
    end.
    mapping
)
main =: 3 : 0
    InputLines =: <;._2 (1!:1 3),LF
    InputPosition =: 0
    Settings =: numbers }.next_line ''
    Settings =: Settings,(numbers }.next_line ''),100
    count =. integer 1{::next_line ''
    PeriodNames =: 0$a:
    Prices =: 0$0
    for_i. i.count do.
        line =. next_line ''
        PeriodNames =: PeriodNames,{.line
        Prices =: Prices,integer 1{::line
    end.
    weekday =. read_division next_line ''
    weekend =. read_division next_line ''
    divisions =. weekday,:weekend
    count =. integer 1{::next_line ''
    profile_names =. 0$a:
    profiles =. 0 24$0
    for_i. i.count do.
        line =. next_line ''
        profile_names =. profile_names,<(0{::line),' ',1{::line
        profiles =. profiles,numbers 2}.line
    end.
    Days =: integer 1{::next_line ''
    Load =: BasePV =: 0$0
    for_day. i.Days do.
        'load_profile load_pct pv_profile pv_pct' =. next_line ''
        load =. (profile_names i.<'LOAD ',load_profile){profiles
        pv =. (profile_names i.<'PV ',pv_profile){profiles
        Load =: Load,(load*integer load_pct) floor_ratio 100
        BasePV =: BasePV,(pv*integer pv_pct) floor_ratio 100
    end.
    Holidays =: numbers 2}.next_line ''
    Weekend =: ((7|i.Days)>:5)+.(1+i.Days)e.Holidays
    HourPeriods =: ,Weekend{divisions
    count =. integer 1{::next_line ''
    for_i. i.count do.
        'day hour load pv' =. numbers next_line ''
        index =. hour+24*(day-1)
        Load =: load index}Load
        BasePV =: pv index}BasePV
    end.
    InitialSettings =: Settings
    InitialPrices =: Prices
    while. InputPosition<#InputLines do.
        line =. InputPosition{::InputLines
        InputPosition =: InputPosition+1
        if. 'END'-:0{::' ' split line do. break. end.
        execute line
    end.
    i.0
)
main ''
