LF =: 10{a.
SETTING_NAMES =: ;: 'STATE SUPP SSRATE MEDRATE ADDMED UIRATE MATCH MATCHMAX GARNCAP SSBASE ADDBASE UIBASE RETIRECAP ALLOWANCE NIGHT'
Settings =: 500 2200 620 145 90 270 5000 600 2500 16860000 20000000 700000 2300000 15000 100x
TaxTable =: 0 2$0x
CommissionTable =: 0 2$0x
Holidays =: i.0
Closed =: 0
EmployeeIds =: i.0
Employees =: 0$a:
Ledger =: 0$a:
WEEKDAYS =: ;: 'Mon Tue Wed Thu Fri Sat Sun'
EMPLOYEE_FIELDS =: ;: 'id department kind base active retirement_rate health allowances extra orders bonus balance shifts pto leave sales ytd periods'
STUB_FIELDS =: ;: 'reg ot dbl night pto accrued salary leave deduction sales commission earnings bonus gross retirement health federal supplemental state social_security medicare garnishment net employer_ss employer_med unemployment match employer federal_wages ss_wages med_wages ui_wages garn_balance pto_balance'

split =: 4 : 0
    <;._1 x,y
)

join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i>0 do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)

number =: 3 : 0
    ,'0' 8!:2 y
)

write =: 4 : 0
    parts =. 0$a:
    for_item. y do.
        value =. >item
        if. 2=3!:0 value do.
            parts =. parts,<value
        else.
            parts =. parts,<number value
        end.
    end.
    ((x#' '),(' ' join parts),LF) 1!:2 4
    i.0
)
emit =: 0&write

fail =: 3 : 0
    emit (<'ERROR'),y
    i.0
)

floor_ratio =: 4 : 0
    <. (x:x) % x:y
)

cents =: 3 : 0
    parts =. '.' split y
    (100x*0".0{::parts)+0".1{::parts
)

padded =: 4 : 0
    text =. number y
    ((0>.x-#text)#'0'),text
)

money =: 3 : 0
    (number y floor_ratio 100),'.',2 padded 100|y
)

rate_text =: 3 : 0
    (money y),'%'
)

duration =: 3 : 0
    (number y floor_ratio 60),':',2 padded 60|y
)

clock_text =: 3 : 0
    (2 padded y floor_ratio 60),':',2 padded 60|y
)

clock_value =: 3 : 0
    (60*0".2{.y)+0".3}.y
)

valid_clock =: 3 : 0
    ((0".2{.y)<24) *. (0".3}.y)<60
)

period_of =: 3 : 0
    1+(y-1) floor_ratio 14
)

weekday =: 3 : 0
    (7|y-1){::WEEKDAYS
)

setting =: 3 : 0
    (SETTING_NAMES i.<y){Settings
)

setting_text =: 4 : 0
    if. x<9 do. rate_text y else. money y end.
)

employee_get =: 4 : 0
    (EMPLOYEE_FIELDS i.<x){::y
)

employee_set =: 4 : 0
    'name value' =. x
    (<value) (EMPLOYEE_FIELDS i.<name)}y
)

stub_get =: 4 : 0
    (STUB_FIELDS i.<x){y
)

stub_set =: 4 : 0
    'name value' =. x
    value (STUB_FIELDS i.<name)}y
)

new_employee =: 3 : 0
    'id department kind base' =. y
    id;department;kind;base;1;0;0;0;0;(0 2$0x);0;0;(0 3$0);(0 2$0);(i.0);(26$0x);(34$0x);0
)

employment =: 3 : 0
    if. 'active' employee_get y do. 'active' else. 'terminated' end.
)

day_error =: 3 : 0
    if. (y<1)+.y>364 do.
        'invalid day';y return.
    end.
    period =. period_of y
    if. period<:Closed do.
        'period closed';period return.
    end.
    0$a:
)

progressive =: 4 : 0
    table =. /:~x
    total =. 0x
    for_i. i.#table do.
        'bound rate' =. i{table
        if. bound>:y do. break. end.
        upper =. y
        if. (i+1)<#table do. upper =. upper<.0{(i+1){table end.
        total =. total+rate*(upper-bound)
    end.
    total floor_ratio 10000
)

shifts_on =: 4 : 0
    shifts =. 'shifts' employee_get x
    /:~ shifts #~ y=0{"1 shifts
)

pto_on =: 4 : 0
    pto =. 'pto' employee_get x
    +/(1{"1 pto) #~ y=0{"1 pto
)

daily =: 4 : 0
    shifts =. x shifts_on y
    starts =. 1{"1 shifts
    ends =. 2{"1 shifts
    worked =. +/ends-starts
    night =. +/ (0>.((ends<.360)-starts)) + (0>.(ends-(starts>.1320)))
    pto =. x pto_on y
    if. (0=7|y)+.y e.Holidays do.
        regular =. 0
        overtime =. 0
        double =. worked
    else.
        regular =. 480<.worked
        overtime =. 240<.0>.worked-480
        double =. 0>.worked-720
    end.
    worked,regular,overtime,double,night,pto
)

weekly =: 4 : 0
    result =. 5$0
    for_day. ((7*y)-6)+i.7 do.
        result =. result+}.x daily day
    end.
    extra =. 0>.(0{result)-2400
    result =. ((0{result)-extra) 0}result
    result =. ((1{result)+extra) 1}result
    result,extra
)

period_hours =: 4 : 0
    (5{.x weekly ((2*y)-1))+5{.x weekly 2*y
)

hours_fields =: 3 : 0
    'reg';(duration 0{y);'ot';(duration 1{y);'dbl';(duration 2{y);'night';(duration 3{y);'pto';duration 4{y
)

show_hours =: 4 : 0
    employee =. x
    period =. y
    id =. 'id' employee_get employee
    emit 'HOURS';id;'period';period
    shown =. 0
    for_day. ((14*period)-13)+i.14 do.
        shifts =. employee shifts_on day
        pto =. employee pto_on day
        if. (0=#shifts)*.pto=0 do. continue. end.
        shown =. shown+1
        parts =. 'day';day;weekday day
        if. day e.Holidays do. parts =. parts,<'holiday' end.
        for_shift. shifts do.
            'serial begin end' =. shift
            parts =. parts,< (clock_text begin),'-',clock_text end
        end.
        breakdown =. employee daily day
        parts =. parts,(<'total'),(<duration {.breakdown),hours_fields }.breakdown
        2 write parts
    end.
    if. shown=0 do. 2 write <'(none)' end.
    for_week. ((2*period)-1)+i.2 do.
        breakdown =. employee weekly week
        parts =. (<'week'),(<week),(hours_fields 5{.breakdown),(<'weekly-ot'),<duration 5{breakdown
        2 write parts
    end.
    2 write (<'total'),hours_fields employee period_hours period
    i.0
)

calculate =: 4 : 0
    employee =. x
    period =. y
    kind =. 'kind' employee_get employee
    active =. 'active' employee_get employee
    base =. 'base' employee_get employee
    annual =. 'ytd' employee_get employee
    orders =. 'orders' employee_get employee
    old_balance =. 'balance' employee_get employee
    stub =. 34$0x
    earnings =. 0x
    select. kind
        case. 'HOURLY' do.
            hours =. employee period_hours period
            stub =. hours (i.5)}stub
            'regular overtime double night pto' =. hours
            weighted =. (2*(regular+pto))+(3*overtime)+4*double
            earnings =. ((weighted*base)+(2*night*setting 'NIGHT')) floor_ratio 120
        case. 'SALARIED' do.
            salary =. 0x
            leave_count =. 0
            deduction =. 0x
            if. active do.
                salary =. base floor_ratio 26
                leave =. 'leave' employee_get employee
                leave_count =. +/ ((period_of leave)=period) *. -.leave e.Holidays
                deduction =. leave_count*(base floor_ratio 260)
            end.
            earnings =. salary-deduction
            stub =. (salary,leave_count,deduction) (6 7 8)}stub
        case. 'COMMISSION' do.
            sales =. (period-1){'sales' employee_get employee
            commission =. CommissionTable progressive sales
            earnings =. commission+active*base
            stub =. (sales,commission) (9 10)}stub
    end.
    bonus =. 'bonus' employee_get employee
    gross =. earnings+bonus
    stub =. (earnings,bonus,gross) (11 12 13)}stub
    if. gross=0 do. stub;orders return. end.

    remaining =. gross
    rate =. 'retirement_rate' employee_get employee
    room =. 0>.(setting 'RETIRECAP')-'retirement' stub_get annual
    retirement =. remaining <. room <. (gross*rate) floor_ratio 10000
    remaining =. remaining-retirement
    health =. remaining<.'health' employee_get employee
    remaining =. remaining-health
    wages =. remaining
    base_wages =. 0>.earnings-(retirement+health)
    allowances =. 'allowances' employee_get employee
    taxable =. 0>.base_wages-allowances*setting 'ALLOWANCE'
    federal =. remaining<.(TaxTable progressive taxable)+'extra' employee_get employee
    remaining =. remaining-federal
    supplemental =. remaining<.((wages-base_wages)*setting 'SUPP') floor_ratio 10000
    remaining =. remaining-supplemental
    state =. remaining<.(wages*setting 'STATE') floor_ratio 10000
    remaining =. remaining-state
    medicare_wages =. gross-health
    ss_wages =. medicare_wages<.0>.(setting 'SSBASE')-'ss_wages' stub_get annual
    extra_wages =. 0>.medicare_wages<.(('med_wages' stub_get annual)+medicare_wages)-setting 'ADDBASE'
    employer_ss =. (ss_wages*setting 'SSRATE') floor_ratio 10000
    social_security =. remaining<.employer_ss
    remaining =. remaining-social_security
    employer_med =. (medicare_wages*setting 'MEDRATE') floor_ratio 10000
    additional_med =. (extra_wages*setting 'ADDMED') floor_ratio 10000
    medicare =. remaining<.employer_med+additional_med
    remaining =. remaining-medicare

    cap =. (remaining*setting 'GARNCAP') floor_ratio 10000
    garnishment =. 0x
    revised_orders =. orders
    for_i. i.#orders do.
        'order_rate balance' =. i{orders
        amount =. balance <. (cap-garnishment) <. (remaining*order_rate) floor_ratio 10000
        revised_orders =. (order_rate,balance-amount) i}revised_orders
        garnishment =. garnishment+amount
    end.
    net =. remaining-garnishment
    unemployment_wages =. medicare_wages<.0>.(setting 'UIBASE')-'ui_wages' stub_get annual
    unemployment =. (unemployment_wages*setting 'UIRATE') floor_ratio 10000
    eligible =. retirement<.(gross*setting 'MATCHMAX') floor_ratio 10000
    matching =. (eligible*setting 'MATCH') floor_ratio 10000
    employer =. employer_ss+employer_med+unemployment+matching
    accrued =. 0
    if. kind-:'HOURLY' do.
        accrued =. (960-old_balance)<.(+/3{.hours) floor_ratio 20
    end.
    stub =. accrued 5}stub
    deductions =. retirement,health,federal,supplemental,state,social_security,medicare,garnishment,net
    stub =. deductions (14+i.9)}stub
    contributions =. employer_ss,employer_med,unemployment,matching,employer
    stub =. contributions (23+i.5)}stub
    stub =. (wages,ss_wages,medicare_wages,unemployment_wages) (28+i.4)}stub
    stub =. ((+/1{"1 revised_orders),(old_balance+accrued)) (32 33)}stub
    stub;revised_orders
)

stub_block =: 4 : 0
    'kind values' =. y
    select. kind
        case. 'HOURLY' do.
            x write (<'hours'),hours_fields 5{.values
            x write 'pto';'accrued';(duration 'accrued' stub_get values);'balance';duration 'pto_balance' stub_get values
        case. 'SALARIED' do.
            x write 'salary';(money 'salary' stub_get values);'leave';('leave' stub_get values);'deduction';money 'deduction' stub_get values
        case. 'COMMISSION' do.
            x write 'sales';(money 'sales' stub_get values);'commission';money 'commission' stub_get values
    end.
    for_field. ;:'earnings bonus gross retirement health federal supplemental state social_security medicare' do.
        name =. >field
        label =. name
        if. name-:'social_security' do. label =. 'social-security' end.
        x write label;money name stub_get values
    end.
    x write 'garnishment';(money 'garnishment' stub_get values);'balance';money 'garn_balance' stub_get values
    x write 'net';money 'net' stub_get values
    x write 'employer';'social-security';(money 'employer_ss' stub_get values);'medicare';(money 'employer_med' stub_get values);'unemployment';(money 'unemployment' stub_get values);'match';money 'match' stub_get values
    i.0
)

show_stub =: 3 : 0
    'id department kind period values' =. y
    2 write 'STUB';id;department;kind;'period';period
    4 stub_block kind;values
    i.0
)

ledger_sum =: 3 : 0
    total =. 34$0x
    for_entry. y do.
        total =. total+3{::>entry
    end.
    total
)

report_line =: 4 : 0
    entries =. y
    values =. ledger_sum entries
    pretax =. ('retirement' stub_get values)+'health' stub_get values
    taxes =. +/(STUB_FIELDS i.;:'federal supplemental state social_security medicare'){values
    2 write x;'stubs';(#entries);'gross';(money 'gross' stub_get values);'pretax';(money pretax);'taxes';(money taxes);'garnishment';(money 'garnishment' stub_get values);'net';(money 'net' stub_get values);'employer';money 'employer' stub_get values
    i.0
)

run_payroll =: 3 : 0
    period =. y
    if. (period~:Closed+1)+.period>26 do.
        fail 'invalid period';period
        i.0 return.
    end.
    Closed =: period
    span =. (number (14*period)-13),'-',number 14*period
    emit 'RUN';period;'days';span
    paid =. 0
    skipped =. 0
    total =. 34$0x
    for_index. /:EmployeeIds do.
        employee =. index{::Employees
        'stub orders' =. employee calculate period
        if. 0='gross' stub_get stub do.
            skipped =. skipped+'active' employee_get employee
            continue.
        end.
        id =. 'id' employee_get employee
        department =. 'department' employee_get employee
        kind =. 'kind' employee_get employee
        show_stub id;department;kind;period;stub
        Ledger =: Ledger,<id;department;period;stub
        employee =. ('bonus';0) employee_set employee
        employee =. ('balance';'pto_balance' stub_get stub) employee_set employee
        employee =. ('orders';orders) employee_set employee
        annual =. ('ytd' employee_get employee)+stub
        annual =. 0 (32 33)}annual
        employee =. ('ytd';annual) employee_set employee
        employee =. ('periods';1+'periods' employee_get employee) employee_set employee
        Employees =: (<employee) index}Employees
        total =. total+stub
        paid =. paid+1
    end.
    gross =. 'gross' stub_get total
    net =. 'net' stub_get total
    2 write 'TOTAL';'paid';paid;'skipped';skipped;'gross';(money gross);'deductions';(money gross-net);'net';(money net);'employer';money 'employer' stub_get total
    i.0
)

show_journal =: 3 : 0
    if. (y<1)+.y>Closed do.
        fail 'no run';y
        i.0 return.
    end.
    entries =. 0$a:
    for_entry. Ledger do.
        if. y=2{::>entry do. entries =. entries,entry end.
    end.
    values =. ledger_sum entries
    emit 'JOURNAL';y;'stubs';#entries
    employer_tax =. +/(STUB_FIELDS i.;:'employer_ss employer_med unemployment'){values
    matching =. 'match' stub_get values
    debits =. ('gross' stub_get values),employer_tax,matching
    credits =. (('retirement' stub_get values)+matching),('health' stub_get values)
    credits =. credits,(('federal' stub_get values)+'supplemental' stub_get values),('state' stub_get values)
    fica =. +/(STUB_FIELDS i.;:'social_security medicare employer_ss employer_med'){values
    credits =. credits,fica,('unemployment' stub_get values),('garnishment' stub_get values),'net' stub_get values
    debit_names =. ;:'wages employer-tax retirement-match'
    credit_names =. ;:'retirement health federal state fica unemployment garnishment net-pay'
    for_i. i.#debits do. 2 write 'debit';(i{::debit_names);money i{debits end.
    for_i. i.#credits do. 2 write 'credit';(i{::credit_names);money i{credits end.
    2 write 'total';'debit';(money +/debits);'credit';money +/credits
    i.0
)

show_report =: 3 : 0
    emit 'REPORT';'period';Closed
    departments =. 0$a:
    for_entry. Ledger do. departments =. departments,1{>entry end.
    for_department. /:~ ~.departments do.
        entries =. 0$a:
        for_entry. Ledger do.
            if. department-:1{>entry do. entries =. entries,entry end.
        end.
        (>department) report_line entries
    end.
    'total' report_line Ledger
    i.0
)

show_top =: 3 : 0
    emit 'TOP';y
    candidates =. i.0
    keys =. 0 2$0x
    for_index. i.#Employees do.
        employee =. index{::Employees
        if. 0='periods' employee_get employee do. continue. end.
        candidates =. candidates,index
        gross =. 'gross' stub_get 'ytd' employee_get employee
        keys =. keys,1 2$(-gross),'id' employee_get employee
    end.
    if. 0=#candidates do.
        2 write <'(none)'
        i.0 return.
    end.
    indices =. (y<.#candidates){.(/:keys){candidates
    for_rank. i.#indices do.
        employee =. (rank{indices){::Employees
        annual =. 'ytd' employee_get employee
        2 write (rank+1);('id' employee_get employee);('department' employee_get employee);'gross';(money 'gross' stub_get annual);'net';money 'net' stub_get annual
    end.
    i.0
)

show_employees =: 3 : 0
    emit <'EMPLOYEES'
    if. 0=#Employees do.
        2 write <'(none)'
        i.0 return.
    end.
    for_index. /:EmployeeIds do.
        employee =. index{::Employees
        2 write ('id' employee_get employee);('department' employee_get employee);('kind' employee_get employee);(money 'base' employee_get employee);(employment employee);'retirement';(rate_text 'retirement_rate' employee_get employee);'health';(money 'health' employee_get employee);'allowances';('allowances' employee_get employee);'extra';(money 'extra' employee_get employee);'bonus';money 'bonus' employee_get employee
        orders =. 'orders' employee_get employee
        for_i. i.#orders do.
            'rate balance' =. i{orders
            4 write 'garnish';(i+1);(rate_text rate);'balance';money balance
        end.
    end.
    i.0
)

show_config =: 3 : 0
    emit <'CONFIG'
    for_i. i.#SETTING_NAMES do.
        2 write (i{::SETTING_NAMES);i setting_text i{Settings
    end.
    for_row. /:~TaxTable do.
        'bound rate' =. row
        2 write 'bracket';(money bound);rate_text rate
    end.
    for_row. /:~CommissionTable do.
        'bound rate' =. row
        2 write 'tier';(money bound);rate_text rate
    end.
    i.0
)

execute =: 3 : 0
    fields =. ' ' split y
    command =. 0{::fields
    args =. }.fields
    select. command
        case. 'SET' do.
            name =. 0{::args
            index =. SETTING_NAMES i.<name
            if. index=#SETTING_NAMES do. fail 'unknown setting';name
                i.0 return.
            end.
            value =. cents 1{::args
            if. (index<9)*.value>10000 do. fail 'invalid rate';1{::args
                i.0 return.
            end.
            old =. index{Settings
            Settings =: value index}Settings
            emit 'SET';name;(index setting_text old);'->';index setting_text value
            i.0 return.

        case. 'BRACKET';'TIER' do.
            bound =. cents 0{::args
            rate =. cents 1{::args
            if. rate>10000 do. fail 'invalid rate';1{::args
                i.0 return.
            end.
            table =. TaxTable
            if. command-:'TIER' do. table =. CommissionTable end.
            index =. (0{"1 table)i.bound
            action =. 'replaced'
            if. index=#table do.
                table =. table,1 2$bound,rate
                action =. 'added'
            else.
                table =. (bound,rate) index}table
            end.
            if. command-:'BRACKET' do. TaxTable =: /:~table
            else. CommissionTable =: /:~table end.
            emit command;(money bound);(rate_text rate);action
            i.0 return.

        case. 'EMP' do.
            id =. 0".0{::args
            if. id e.EmployeeIds do. fail 'duplicate employee';0{::args
                i.0 return.
            end.
            base =. cents 3{::args
            if. base=0 do. fail <'invalid amount'
                i.0 return.
            end.
            department =. 1{::args
            kind =. 2{::args
            employee =. new_employee id;department;kind;base
            EmployeeIds =: EmployeeIds,id
            Employees =: Employees,<employee
            emit 'EMP';id;department;kind;money base
            i.0 return.

        case. 'HOLIDAY' do.
            day =. 0".0{::args
            reason =. day_error day
            if. #reason do. fail reason
                i.0 return.
            end.
            if. day e.Holidays do. fail 'duplicate holiday';day
                i.0 return.
            end.
            Holidays =: Holidays,day
            emit 'HOLIDAY';day;weekday day
            i.0 return.

        case. 'RUN' do. run_payroll 0".0{::args
            i.0 return.
        case. 'JOURNAL' do. show_journal 0".0{::args
            i.0 return.
        case. 'REPORT' do. show_report ''
            i.0 return.
        case. 'TOP' do. show_top 0".0{::args
            i.0 return.
        case. 'EMPLOYEES' do. show_employees ''
            i.0 return.
        case. 'CONFIG' do. show_config ''
            i.0 return.
    end.

    id =. 0".0{::args
    index =. EmployeeIds i.id
    if. index=#EmployeeIds do. fail 'unknown employee';id
        i.0 return.
    end.
    employee =. index{::Employees
    read_only =. (<command)e.;:'HOURS PREVIEW REPRINT YTD'
    if. (-.read_only)*.-.'active' employee_get employee do.
        fail 'terminated employee';id
        i.0 return.
    end.
    kind =. 'kind' employee_get employee
    if. (<command)e.;:'TIME UNTIME PTO HOURS' do.
        if. -.kind-:'HOURLY' do. fail 'not hourly';id
            i.0 return.
        end.
    elseif. command-:'LEAVE' do.
        if. -.kind-:'SALARIED' do. fail 'not salaried';id
            i.0 return.
        end.
    elseif. command-:'SALES' do.
        if. -.kind-:'COMMISSION' do. fail 'not commission';id
            i.0 return.
        end.
    end.
    if. (<command)e.;:'TIME UNTIME PTO LEAVE SALES' do.
        day =. 0".1{::args
        reason =. day_error day
        if. #reason do. fail reason
            i.0 return.
        end.
    end.

    select. command
        case. 'RATE' do.
            value =. cents 1{::args
            if. value=0 do. fail <'invalid amount'
                i.0 return.
            end.
            old =. 'base' employee_get employee
            employee =. ('base';value) employee_set employee
            emit 'RATE';id;(money old);'->';money value

        case. 'DEPT' do.
            department =. 1{::args
            old =. 'department' employee_get employee
            if. department-:old do. fail 'same department';department
                i.0 return.
            end.
            employee =. ('department';department) employee_set employee
            emit 'DEPT';id;old;'->';department

        case. 'BENEFIT' do.
            rate =. cents 1{::args
            if. rate>10000 do. fail 'invalid rate';1{::args
                i.0 return.
            end.
            health =. cents 2{::args
            employee =. ('retirement_rate';rate) employee_set employee
            employee =. ('health';health) employee_set employee
            emit 'BENEFIT';id;'retirement';(rate_text rate);'health';money health

        case. 'W4' do.
            allowances =. 0".1{::args
            extra =. cents 2{::args
            employee =. ('allowances';allowances) employee_set employee
            employee =. ('extra';extra) employee_set employee
            emit 'W4';id;'allowances';allowances;'extra';money extra

        case. 'GARNISH' do.
            rate =. cents 1{::args
            if. rate>10000 do. fail 'invalid rate';1{::args
                i.0 return.
            end.
            value =. cents 2{::args
            if. value=0 do. fail <'invalid amount'
                i.0 return.
            end.
            orders =. 'orders' employee_get employee
            orders =. orders,1 2$rate,value
            employee =. ('orders';orders) employee_set employee
            emit 'GARNISH';id;'order';(#orders);(rate_text rate);'balance';money value

        case. 'TERM' do.
            employee =. ('active';0) employee_set employee
            emit 'TERM';id

        case. 'TIME';'UNTIME' do.
            begin_text =. 2{::args
            if. -.valid_clock begin_text do. fail 'invalid time';begin_text
                i.0 return.
            end.
            begin =. clock_value begin_text
            shifts =. 'shifts' employee_get employee
            today =. employee shifts_on day
            if. command-:'TIME' do.
                end_text =. 3{::args
                if. -.valid_clock end_text do. fail 'invalid time';end_text
                    i.0 return.
                end.
                end =. clock_value end_text
                label =. begin_text,'-',end_text
                if. begin>:end do. fail 'invalid shift';label
                    i.0 return.
                end.
                overlaps =. today #~ (begin<2{"1 today) *. (1{"1 today)<end
                if. #overlaps do.
                    'serial old_begin old_end' =. 0{overlaps
                    fail 'overlapping shift';(clock_text old_begin),'-',clock_text old_end
                    i.0 return.
                end.
                worked =. +/(2{"1 today)-1{"1 today
                if. (worked+end-begin)>960 do. fail 'daily limit';id;day
                    i.0 return.
                end.
                shifts =. /:~shifts,1 3$day,begin,end
                employee =. ('shifts';shifts) employee_set employee
                emit 'TIME';id;'day';day;label;duration end-begin
            else.
                mask =. (day=0{"1 shifts) *. begin=1{"1 shifts
                if. -. +./mask do. fail 'no shift';id;day;begin_text
                    i.0 return.
                end.
                removed =. {.mask#shifts
                label =. (clock_text 1{removed),'-',clock_text 2{removed
                employee =. ('shifts';(-.mask)#shifts) employee_set employee
                emit 'UNTIME';id;'day';day;label
            end.

        case. 'PTO' do.
            text =. 2{::args
            length =. clock_value text
            if. ((0".3}.text)>59)+.(length<1)+.length>480 do.
                fail 'invalid duration';text
                i.0 return.
            end.
            pto =. 'pto' employee_get employee
            if. day e.0{"1 pto do. fail 'duplicate pto';id;day
                i.0 return.
            end.
            balance =. 'balance' employee_get employee
            if. length>balance do. fail 'insufficient pto';id;duration balance
                i.0 return.
            end.
            employee =. ('pto';pto,1 2$day,length) employee_set employee
            employee =. ('balance';balance-length) employee_set employee
            emit 'PTO';id;'day';day;(duration length);'balance';duration balance-length

        case. 'LEAVE' do.
            if. ((7|day)e.0 6)+.day e.Holidays do. fail 'not workday';day
                i.0 return.
            end.
            leave =. 'leave' employee_get employee
            if. day e.leave do. fail 'duplicate leave';id;day
                i.0 return.
            end.
            employee =. ('leave';leave,day) employee_set employee
            emit 'LEAVE';id;'day';day;weekday day

        case. 'SALES' do.
            amount =. cents 2{::args
            if. amount=0 do. fail <'invalid amount'
                i.0 return.
            end.
            period =. period_of day
            sales =. 'sales' employee_get employee
            total =. amount+(period-1){sales
            sales =. total (period-1)}sales
            employee =. ('sales';sales) employee_set employee
            emit 'SALES';id;'day';day;(money amount);'period';period;'total';money total

        case. 'BONUS' do.
            amount =. cents 1{::args
            if. amount=0 do. fail <'invalid amount'
                i.0 return.
            end.
            pending =. amount+'bonus' employee_get employee
            employee =. ('bonus';pending) employee_set employee
            emit 'BONUS';id;(money amount);'pending';money pending

        case. 'HOURS' do.
            period =. 0".1{::args
            if. (period<1)+.period>26 do. fail 'invalid period';period
                i.0 return.
            end.
            employee show_hours period
            i.0 return.

        case. 'PREVIEW' do.
            period =. Closed+1
            emit 'PREVIEW';id;'period';period
            'stub orders' =. employee calculate period
            if. 0='gross' stub_get stub do. 2 write <'no pay'
            else. show_stub id;('department' employee_get employee);kind;period;stub end.
            i.0 return.

        case. 'REPRINT' do.
            period =. 0".1{::args
            if. (period<1)+.period>26 do. fail 'invalid period';period
                i.0 return.
            end.
            found =. 0$a:
            for_entry. Ledger do.
                item =. >entry
                if. (id=0{::item)*.period=2{::item do. found =. item
                    break.
                end.
            end.
            if. 0=#found do. fail 'no stub';id;period
                i.0 return.
            end.
            emit 'REPRINT';id;period
            show_stub id;(1{::found);kind;period;3{::found
            i.0 return.

        case. 'YTD' do.
            values =. 'ytd' employee_get employee
            orders =. 'orders' employee_get employee
            values =. ('garn_balance';+/1{"1 orders) stub_set values
            values =. ('pto_balance';'balance' employee_get employee) stub_set values
            emit 'YTD';id;('department' employee_get employee);kind;(employment employee);'periods';'periods' employee_get employee
            2 stub_block kind;values
            2 write 'wages';'federal';(money 'federal_wages' stub_get values);'social-security';(money 'ss_wages' stub_get values);'medicare';(money 'med_wages' stub_get values);'unemployment';money 'ui_wages' stub_get values
            room =. 0>.(setting 'RETIRECAP')-'retirement' stub_get values
            2 write 'retirement-room';(money room);'pending-bonus';money 'bonus' employee_get employee
            i.0 return.
    end.
    Employees =: (<employee) index}Employees
    i.0
)

main =: 3 : 0
    lines =. <;._2 (1!:1 3),LF
    count =. 0".0{::lines
    for_line. count{.}.lines do. execute >line end.
    i.0
)

main ''
