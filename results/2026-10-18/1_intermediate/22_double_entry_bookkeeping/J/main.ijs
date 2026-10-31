LF =: 10{a.
Codes =: Types =: Names =: 0$a:
Active =: i.0
IDs =: Categories =: Memos =: 0$a:
Days =: Starts =: Counts =: ReversedBy =: Reverses =: i.0
Amounts =: 0$0x
LineEntries =: LineAccounts =: LineSides =: i.0
LineAmounts =: 0$0x
LinePartners =: 0$a:
TemplateNames =: TemplateMemos =: TemplateLines =: 0$a:
Uses =: i.0
DraftKind =: DraftKey =: DraftDate =: DraftMemo =: ''
DraftLines =: 0 4$a:
CloseDays =: CloseEntries =: i.0
CloseCounter =: DepCounter =: InterestCounter =: WriteoffCounter =: 0
Error =: ''

split =: 4 : '<;._1 x,y'
number =: 3 : ',''0'' 8!:2 y'
padded =: 4 : 0
    text =. number y
    ((0>.x-#text)#'0'),text
)
money =: 3 : 0
    magnitude =. |y
    sign =. ''
    if. y<0 do. sign =. '-' end.
    sign,(number <.magnitude%100x),'.',2 padded 100x|magnitude
)
cents =: 3 : 0
    'whole fraction' =. '.' split y
    (100x*x:0".whole)+x:0".fraction
)
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
words =: 3 : 0
    fields =. 0$a:
    for_part. y do.
        part =. >part
        if. 2~:3!:0 part do. part =. number part end.
        fields =. fields,<part
    end.
    ' ' join fields
)
emit =: 3 : '(y,LF) 1!:2 4'
say =: 3 : 'emit words y'
indent =: 4 : 'emit (x#'' ''),y'
fail =: 3 : 0
    Error =: y
    throw.
)
prefix =: 4 : 'x-:(#x){.y'
trunc_div =: 4 : '(*x)*<.(|x)%y'
leap =: 3 : '(0=4|y)*.(0~:100|y)+.0=400|y'
month_days =: 4 : '((y-1){31 28 31 30 31 30 31 31 30 31 30 31)+(y=2)*leap x'
day_number =: 3 : 0
    'year month day' =. y
    prior =. year-1
    result =. 365*prior
    result =. result+<.prior%4x
    result =. result-<.prior%100x
    result =. result+<.prior%400x
    for_m. 1+i.month-1 do. result =. result+year month_days m end.
    result+day-730120
)
date_parts =: 3 : 0
    year =. 2000
    remaining =. y
    while. remaining>:365+leap year do.
        remaining =. remaining-365+leap year
        year =. year+1
    end.
    month =. 1
    while. remaining>:year month_days month do.
        remaining =. remaining-year month_days month
        month =. month+1
    end.
    year,month,remaining+1
)
date_text =: 3 : 0
    'year month day' =. date_parts y
    (4 padded year),'-',(2 padded month),'-',2 padded day
)
parse_date =: 3 : 0
    parts =. >0".each '-' split y
    'year month day' =. parts
    if. (year<2000)+.(year>2099)+.(month<1)+.month>12 do. fail 'invalid date ',y end.
    if. (day<1)+.day>year month_days month do. fail 'invalid date ',y end.
    day_number parts
)
date_range =: 3 : 0
    first =. parse_date 0{::y
    last =. parse_date 1{::y
    if. first>last do. fail 'invalid range ',' ' join y end.
    first,last
)
add_months =: 4 : 0
    'year month day' =. date_parts y
    total =. (month-1)+x
    year =. year+<.total%12x
    month =. 1+12|total
    day_number year,month,day<.year month_days month
)
closed_text =: 3 : 0
    if. #CloseDays do. date_text {:CloseDays else. 'none' end.
)
check_open_date =: 3 : 0
    if. #CloseDays do.
        if. y<:{:CloseDays do. fail 'period closed ',date_text y end.
    end.
)
account =: 3 : 0
    index =. Codes i.<y
    if. index=#Codes do. fail 'unknown account ',y end.
    index
)
typed_account =: 4 : 0
    index =. account y
    if. -.x-:index{::Types do. fail 'wrong type ',y,' ',x end.
    index
)
active_check =: 3 : 0
    for_index. y do.
        if. -.index{Active do. fail 'inactive account ',index{::Codes end.
    end.
)
entry =: 3 : 0
    index =. IDs i.<y
    if. index=#IDs do. fail 'unknown entry ',y end.
    index
)
template =: 3 : 0
    index =. TemplateNames i.<y
    if. index=#TemplateNames do. fail 'unknown template ',y end.
    index
)
normal =: 3 : '_1+2*(y{Types)e.;:''ASSET EXPENSE'''
type_class =: 3 : 0
    if. y-:'CONTRA_ASSET' do. 'ASSET' else. y end.
)
ancestors =: 3 : 0
    code =. y{::Codes
    result =. i.0
    for_index. i.#Codes do.
        if. (index~:y)*.(index{::Codes) prefix code do. result =. result,index end.
    end.
    result
)
parent_code =: 3 : 0
    indices =. ancestors y
    if. 0=#indices do. 'none' return. end.
    lengths =. #&>indices{Codes
    (indices{~lengths i.>./lengths){::Codes
)
top_account =: 3 : 0
    indices =. ancestors y
    if. 0=#indices do. y return. end.
    lengths =. #&>indices{Codes
    indices{~lengths i.<./lengths
)
line_sums =: 3 : 0
    sides =. >0{"1 y
    amounts =. >2{"1 y
    (+/amounts#~sides=0),+/amounts#~sides=1
)
line_indices =: 3 : '(y{Starts)+i.y{Counts'
lines_of =: 3 : 0
    selected =. line_indices y
    (<"0 selected{LineSides),.((selected{LineAccounts){Codes),.(<"0 selected{LineAmounts),.selected{LinePartners
)
post =: 3 : 0
    'id day category memo lines' =. y
    index =. #IDs
    Starts =: Starts,#LineAmounts
    Counts =: Counts,#lines
    IDs =: IDs,<id
    Days =: Days,day
    Categories =: Categories,<category
    Memos =: Memos,<memo
    ReversedBy =: ReversedBy,_1
    Reverses =: Reverses,_1
    Amounts =: Amounts,{.line_sums lines
    LineEntries =: LineEntries,(#lines)#index
    LineAccounts =: LineAccounts,Codes i.1{"1 lines
    LineSides =: LineSides,>0{"1 lines
    LineAmounts =: LineAmounts,>2{"1 lines
    LinePartners =: LinePartners,3{"1 lines
    index
)
reverse_entry =: 4 : 0
    lines =. lines_of x
    lines =. (<"0 1->0{"1 lines),.1}."1 lines
    index =. post y,<lines
    ReversedBy =: index x}ReversedBy
    Reverses =: x index}Reverses
    index
)
make_line =: 3 : '1 4$y'
post_text =: 3 : 0
    words 'POST';(y{::IDs);(date_text y{Days);'lines';(y{Counts);'amount';money y{Amounts
)
totals =: 3 : 0
    'first last operating' =. y
    chosen =. (Days>:first)*.Days<:last
    if. operating do. chosen =. chosen*.-.Categories e.;:'closing reopen' end.
    selected =. I.LineEntries{chosen
    values =. (2*#Codes)#0x
    if. #selected do.
        keys =. (2*selected{LineAccounts)+selected{LineSides
        values =. (keys +//.selected{LineAmounts) (~.keys)}values
    end.
    ((#Codes),2)$values
)
differences =: 3 : '(0{"1 y)-1{"1 y'
balances =: 3 : '(normal i.#Codes)*differences y'
current_balances =: 3 : 'balances totals 0 36600 0'
daily_sum =: 4 : 0
    'first last' =. y
    dates =. LineEntries{Days
    selected =. I.(LineAccounts=x)*.dates<:last
    signed =. (normal x)*(1-2*selected{LineSides)*selected{LineAmounts
    +/signed*1+last-first>.selected{dates
)
posting_entries =: 3 : '/:Days,.i.#IDs'
partners =: 4 : 0
    selected =. (LineAccounts=x)*.((LineEntries{Days)<:y)*.-.(<'')=LinePartners
    /:~~.selected#LinePartners
)
open_items =: 3 : 0
    'acc partner day' =. y
    dates =. LineEntries{Days
    selected =. I.(LineAccounts=acc)*.(dates<:day)*.(<partner)=LinePartners
    selected =. (/: (selected{dates),.selected){selected
    entries =. i.0
    originals =. remaining =. 0$0x
    unapplied =. 0x
    head =. 0
    for_index. selected do.
        signed =. (normal acc)*(1-2*index{LineSides)*index{LineAmounts
        if. signed>0 do.
            used =. signed<.unapplied
            unapplied =. unapplied-used
            if. signed>used do.
                entries =. entries,index{LineEntries
                originals =. originals,signed
                remaining =. remaining,signed-used
            end.
        else.
            need =. -signed
            while. (need>0)*.head<#entries do.
                used =. need<.head{remaining
                remaining =. ((head{remaining)-used) head}remaining
                need =. need-used
                if. 0=head{remaining do. head =. head+1 end.
            end.
            unapplied =. unapplied+need
        end.
    end.
    (<head}.entries),(<head}.originals),(<head}.remaining),<unapplied
)
section =: 3 : 0
    'heading kinds sign differences extra show_extra' =. y
    selected =. I.Types e.kinds
    selected =. (/:selected{Codes){selected
    values =. sign*differences
    result =. extra++/selected{values
    2 indent heading,' ',money result
    roots =. i.0
    if. #selected do. roots =. top_account"0 selected end.
    groups =. ~.roots
    groups =. (/:groups{Codes){groups
    for_root. groups do.
        members =. selected#~roots=root
        if. -. +./0~:members{values do. continue. end.
        4 indent words (root{::Codes);(root{::Names);money +/members{values
        for_index. members#~0~:members{values do.
            6 indent words (index{::Codes);(index{::Names);money index{values
        end.
    end.
    if. show_extra do. 4 indent 'current earnings ',money extra end.
    result
)
aging_text =: 4 : 0
    'a b c d unapplied' =. y
    words x;'0-30';(money a);'31-60';(money b);'61-90';(money c);'91+';(money d);'unapplied';(money unapplied);'balance';money (a+b+c+d)-unapplied
)
command =: 3 : 0
    tokens =. ' ' split y
    op =. 0{::tokens
    select. op
    case. 'ACCOUNT' do.
        'code kind name' =. 1}.tokens
        if. (<code)e.Codes do. fail 'duplicate account ',code end.
        for_index. /:Codes do.
            other =. index{::Codes
            if. (code prefix other)+.other prefix code do.
                if. -. (type_class kind)-:type_class index{::Types do. fail 'class mismatch ',code,' ',other end.
            end.
        end.
        Codes =: Codes,<code
        Types =: Types,<kind
        Names =: Names,<name
        Active =: Active,1
        say 'ACCOUNT';code;kind;name;'parent';parent_code <:#Codes
    case. 'DEACTIVATE' do.
        acc =. account 1{::tokens
        if. -.acc{Active do. fail 'already inactive ',acc{::Codes end.
        balance =. acc{current_balances''
        if. balance~:0 do. fail 'nonzero balance ',(acc{::Codes),' ',money balance end.
        Active =: 0 acc}Active
        say 'DEACTIVATE';(acc{::Codes);acc{::Names
    case. 'JOURNAL';'TEMPLATE' do.
        if. #DraftKind do. say 'DISCARD';DraftKey;'lines';#DraftLines end.
        DraftKey =: 1{::tokens
        DraftLines =: 0 4$a:
        if. op-:'JOURNAL' do.
            DraftKind =: 'journal'
            DraftDate =: 2{::tokens
            DraftMemo =: 3{::tokens
        else.
            DraftKind =: 'template'
            DraftDate =: ''
            DraftMemo =: 2{::tokens
        end.
    case. 'DR';'CR' do.
        if. 0=#DraftKind do. fail 'no open entry' end.
        partner =. ''
        if. 4=#tokens do. partner =. 3{::tokens end.
        DraftLines =: DraftLines,make_line (op-:'CR');(1{::tokens);(cents 2{::tokens);partner
    case. 'DRAFT' do.
        if. 0=#DraftKind do. fail 'no open entry' end.
        'debit credit' =. line_sums DraftLines
        say 'DRAFT';DraftKind;DraftKey;'lines';(#DraftLines);'debit';(money debit);'credit';(money credit);'difference';money debit-credit
    case. 'POST' do.
        if. 0=#DraftKind do. fail 'no open entry' end.
        kind =. DraftKind
        key =. DraftKey
        date =. DraftDate
        memo =. DraftMemo
        lines =. DraftLines
        DraftKind =: ''
        DraftLines =: 0 4$a:
        if. kind-:'journal' do.
            if. (<key)e.IDs do. fail 'duplicate entry ',key end.
            day =. parse_date date
            check_open_date day
        else.
            if. (<key)e.TemplateNames do. fail 'duplicate template ',key end.
        end.
        if. 2>#lines do. fail 'too few lines ',key end.
        for_line. lines do.
            'side code amount partner' =. line
            acc =. account code
            if. kind-:'journal' do. active_check ,acc end.
            if. amount=0 do. fail 'zero amount ',code end.
        end.
        'debit credit' =. line_sums lines
        if. debit~:credit do. fail words 'unbalanced';key;'debit';(money debit);'credit';money credit end.
        if. kind-:'journal' do.
            index =. post (<key),(<day),(<kind),(<memo),<lines
            emit post_text index
        else.
            TemplateNames =: TemplateNames,<key
            TemplateMemos =: TemplateMemos,<memo
            TemplateLines =: TemplateLines,<lines
            Uses =: Uses,0
            say 'TEMPLATE';key;'lines';(#lines);'amount';money debit
        end.
    case. 'REVERSE' do.
        index =. entry 1{::tokens
        if. (index{Categories)e.;:'reversal closing reopen' do. fail 'cannot reverse ',index{::IDs end.
        if. _1~:index{ReversedBy do. fail 'already reversed ',index{::IDs end.
        day =. parse_date 2{::tokens
        if. day<index{Days do. fail words 'reverse before entry';(index{::IDs);date_text index{Days end.
        check_open_date day
        active_check (line_indices index){LineAccounts
        id =. (index{::IDs),'-R'
        created =. index reverse_entry id;day;'reversal';index{::Memos
        say 'REVERSE';(index{::IDs);'entry';id;(date_text day);'amount';money created{Amounts
    case. 'RECUR' do.
        index =. template 1{::tokens
        day =. parse_date 2{::tokens
        count =. 0".3{::tokens
        if. count=0 do. fail 'invalid count' end.
        check_open_date day
        lines =. index{::TemplateLines
        active_check Codes i.1{"1 lines
        say 'RECUR';(index{::TemplateNames);'count';count
        for_offset. i.count do.
            Uses =: (1+index{Uses) index}Uses
            id =. (index{::TemplateNames),'-',number index{Uses
            posted_day =. offset add_months day
            created =. post (<id),(<posted_day),(<'recurring'),(index{TemplateMemos),<lines
            2 indent post_text created
        end.
    case. 'DEPRECIATE' do.
        day =. parse_date 1{::tokens
        check_open_date day
        asset =. 'ASSET' typed_account 2{::tokens
        contra =. 'CONTRA_ASSET' typed_account 3{::tokens
        expense =. 'EXPENSE' typed_account 4{::tokens
        active_check contra,expense
        life =. 0".5{::tokens
        values =. balances totals 0,day,0
        cost =. asset{values
        accumulated =. contra{values
        amount =. 0x
        if. cost>0 do. amount =. (<.cost%life)<.cost-accumulated end.
        if. amount<:0 do. fail 'nothing to depreciate ',asset{::Codes end.
        DepCounter =: DepCounter+1
        id =. 'DEP-',number DepCounter
        lines =. (make_line 0;(expense{::Codes);amount;''),make_line 1;(contra{::Codes);amount;''
        post (<id),(<day),(<'depreciation'),(<'depreciation'),<lines
        say 'DEPRECIATE';(asset{::Codes);'entry';id;(date_text day);'amount';(money amount);'accumulated';(money accumulated+amount);'book';money cost-accumulated+amount
    case. 'INTEREST' do.
        acc =. account 1{::tokens
        kind =. acc{::Types
        if. -.(<kind)e.;:'ASSET LIABILITY' do. fail 'not interest bearing ',acc{::Codes end.
        required =. 'EXPENSE'
        if. kind-:'ASSET' do. required =. 'REVENUE' end.
        offset =. required typed_account 2{::tokens
        'first last' =. date_range 3 4{tokens
        check_open_date last
        active_check acc,offset
        rate =. x:0".5{::tokens
        sum =. acc daily_sum first,last
        amount =. (sum*rate) trunc_div 3650000x
        if. amount<:0 do. fail 'no interest ',acc{::Codes end.
        InterestCounter =: InterestCounter+1
        id =. 'INT-',number InterestCounter
        sides =. acc,offset
        if. kind-:'LIABILITY' do. sides =. |.sides end.
        lines =. (make_line 0;(({.sides){::Codes);amount;''),make_line 1;(({:sides){::Codes);amount;''
        post (<id),(<last),(<'interest'),(<'interest'),<lines
        days =. 1+last-first
        say 'INTEREST';(acc{::Codes);'entry';id;(date_text last);'days';days;'average';(money sum trunc_div days);'amount';money amount
    case. 'WRITEOFF' do.
        day =. parse_date 1{::tokens
        check_open_date day
        acc =. 'ASSET' typed_account 2{::tokens
        expense =. 'EXPENSE' typed_account 3{::tokens
        active_check acc,expense
        age_limit =. 0".4{::tokens
        targets =. 0$a:
        amounts =. 0$0x
        for_partner. acc partners day do.
            'entries originals remaining unapplied' =. open_items acc;(>partner);day
            amount =. +/remaining#~(day-entries{Days)>age_limit
            if. amount>0 do.
                targets =. targets,partner
                amounts =. amounts,amount
            end.
        end.
        total =. +/amounts
        if. total=0 do. fail 'nothing to write off ',acc{::Codes end.
        WriteoffCounter =: WriteoffCounter+1
        id =. 'WO-',number WriteoffCounter
        lines =. make_line 0;(expense{::Codes);total;''
        for_i. i.#targets do. lines =. lines,make_line 1;(acc{::Codes);(i{amounts);i{::targets end.
        post (<id),(<day),(<'writeoff'),(<'writeoff'),<lines
        say 'WRITEOFF';(acc{::Codes);'entry';id;(date_text day);'partners';(#targets);'amount';money total
        for_i. i.#targets do. 2 indent words (i{::targets);money i{amounts end.
    case. 'CLOSE' do.
        day =. parse_date 1{::tokens
        check_open_date day
        equity =. 'EQUITY' typed_account 2{::tokens
        active_check ,equity
        values =. differences totals 0,day,0
        selected =. I.(Types e.;:'REVENUE EXPENSE')*.values~:0
        selected =. (/:selected{Codes){selected
        active_check selected
        lines =. 0 4$a:
        for_index. selected do.
            value =. index{values
            lines =. lines,make_line (value>0);(index{::Codes);(|value);''
        end.
        income =. -+/selected{values
        if. income~:0 do. lines =. lines,make_line (income>0);(equity{::Codes);(|income);'' end.
        CloseCounter =: CloseCounter+1
        created =. _1
        if. #lines do.
            id =. 'CLOSE-',number CloseCounter
            created =. post (<id),(<day),(<'closing'),(<'closing'),<lines
            say 'CLOSE';(date_text day);'entry';id;'lines';(#lines);'net income';money income
        else. say 'CLOSE';(date_text day);'no entry' end.
        CloseDays =: CloseDays,day
        CloseEntries =: CloseEntries,created
    case. 'REOPEN' do.
        if. 0=#CloseDays do. fail 'nothing to reopen' end.
        index =. {:CloseEntries
        day =. {:CloseDays
        detail =. 'no entry'
        if. index>:0 do.
            active_check (line_indices index){LineAccounts
            id =. (index{::IDs),'-R'
            index reverse_entry id;day;'reopen';'reopen'
            detail =. 'entry ',id
        end.
        CloseDays =: }:CloseDays
        CloseEntries =: }:CloseEntries
        say 'REOPEN';(date_text day);detail;'closed';closed_text''
    case. 'LEDGER' do.
        acc =. account 1{::tokens
        'first last' =. date_range 2 3{tokens
        values =. balances totals 0,(first-1),0
        running =. acc{values
        debit =. credit =. 0x
        sum =. acc daily_sum first,last
        say 'LEDGER';(acc{::Codes);(acc{::Names);(date_text first);date_text last
        2 indent 'opening ',money running
        for_index. posting_entries'' do.
            day =. index{Days
            if. (day<first)+.day>last do. continue. end.
            for_line. line_indices index do.
                if. acc~:line{LineAccounts do. continue. end.
                side =. line{LineSides
                amount =. line{LineAmounts
                running =. running+(normal acc)*(1-2*side)*amount
                if. side=0 do. debit =. debit+amount else. credit =. credit+amount end.
                2 indent words (date_text day);(index{::IDs);(side{::'DR';'CR');(money amount);'balance';(money running);index{::Memos
            end.
        end.
        days =. 1+last-first
        2 indent words 'ending';(money running);'debits';(money debit);'credits';(money credit);'days';days;'average';money sum trunc_div days
    case. 'ACTIVITY' do.
        acc =. account 1{::tokens
        year =. 0".2{::tokens
        say 'ACTIVITY';(acc{::Codes);(acc{::Names);year
        annual =. 0x 0x
        for_month. 1+i.12 do.
            first =. day_number year,month,1
            last =. first+(year month_days month)-1
            sums =. acc{totals first,last,0
            annual =. annual+sums
            balance =. acc{balances totals 0,last,0
            2 indent words ((4 padded year),'-',2 padded month);'debit';(money {.sums);'credit';(money {:sums);'balance';money balance
        end.
        2 indent words 'total debit';(money {.annual);'credit';money {:annual
    case. 'TRIAL' do.
        day =. parse_date 1{::tokens
        values =. differences totals 0,day,0
        say 'TRIAL';date_text day
        for_index. /:Codes do.
            amount =. index{values
            if. amount=0 do. continue. end.
            side =. (amount<0){::'debit';'credit'
            2 indent words (index{::Codes);(index{::Names);side;money |amount
        end.
        2 indent words 'total debit';(money +/0>.values);'credit';money -+/0<.values
    case. 'INCOME' do.
        'first last' =. date_range 1 2{tokens
        values =. differences totals first,last,1
        say 'INCOME';(date_text first);date_text last
        revenue =. section (<'REVENUE'),(<,<'REVENUE'),(<_1),(<values),(<0),<0
        expense =. section (<'EXPENSE'),(<,<'EXPENSE'),(<1),(<values),(<0),<0
        2 indent 'NET INCOME ',money revenue-expense
    case. 'BALANCE' do.
        day =. parse_date 1{::tokens
        values =. differences totals 0,day,0
        earnings =. -+/values#~Types e.;:'REVENUE EXPENSE'
        say 'BALANCE';date_text day
        assets =. section (<'ASSETS'),(<;:'ASSET CONTRA_ASSET'),(<1),(<values),(<0),<0
        liabilities =. section (<'LIABILITIES'),(<,<'LIABILITY'),(<_1),(<values),(<0),<0
        equity =. section (<'EQUITY'),(<,<'EQUITY'),(<_1),(<values),(<earnings),<1
        if. assets=liabilities+equity do. 2 indent 'check ok'
        else. 2 indent 'check mismatch ',money assets-liabilities+equity end.
    case. 'ROLLUP' do.
        code =. 1{::tokens
        day =. parse_date 2{::tokens
        selected =. i.0
        for_index. /:Codes do.
            if. code prefix index{::Codes do. selected =. selected,index end.
        end.
        say 'ROLLUP';code;date_text day
        if. 0=#selected do. 2 indent '(none)' return. end.
        sums =. totals 0,day,0
        values =. differences sums
        for_index. selected do.
            descendants =. i.0
            depth =. 0
            for_other. selected do.
                if. (index{::Codes) prefix other{::Codes do. descendants =. descendants,other end.
                if. (other~:index)*.(other{::Codes) prefix index{::Codes do. depth =. depth+1 end.
            end.
            sign =. normal index
            (2*1+depth) indent words (index{::Codes);(index{::Names);'own';(money sign*index{values);'total';money sign*+/descendants{values
        end.
        'debit credit' =. +/selected{sums
        2 indent words 'postings debit';(money debit);'credit';money credit
    case. 'AGING';'ITEMS' do.
        acc =. account 1{::tokens
        day =. parse_date _1{::tokens
        if. op-:'ITEMS' do.
            partner =. 2{::tokens
            say 'ITEMS';(acc{::Codes);(acc{::Names);partner;date_text day
            'entries originals remaining unapplied' =. open_items acc;partner;day
            for_i. i.#entries do.
                index =. i{entries
                2 indent words (date_text index{Days);(index{::IDs);'amount';(money i{originals);'open';(money i{remaining);'age';day-index{Days
            end.
            2 indent words 'unapplied';(money unapplied);'balance';money (+/remaining)-unapplied
        else.
            say 'AGING';(acc{::Codes);(acc{::Names);date_text day
            total =. 5#0x
            for_partner. acc partners day do.
                'entries originals remaining unapplied' =. open_items acc;(>partner);day
                if. (0=#entries)*.unapplied=0 do. continue. end.
                ages =. day-entries{Days
                bins =. +/"1 (ages>/30 60 90)
                values =. 4#0x
                for_bin. i.4 do. values =. (+/remaining#~bins=bin) bin}values end.
                values =. values,unapplied
                total =. total+values
                2 indent (>partner) aging_text values
            end.
            2 indent 'total' aging_text total
        end.
    case. 'ENTRY' do.
        index =. entry 1{::tokens
        say 'ENTRY';(index{::IDs);(date_text index{Days);(index{::Categories);index{::Memos
        for_line. line_indices index do.
            acc =. line{LineAccounts
            text =. words ((line{LineSides){::'DR';'CR');(acc{::Codes);(acc{::Names);money line{LineAmounts
            partner =. line{::LinePartners
            if. #partner do. text =. text,' ',partner end.
            2 indent text
        end.
        2 indent 'total ',money index{Amounts
        if. (index{Reverses)>:0 do. 2 indent 'reverses ',(index{Reverses){::IDs end.
        if. (index{ReversedBy)>:0 do. 2 indent 'reversed by ',(index{ReversedBy){::IDs end.
    case. 'DAYBOOK' do.
        'first last' =. date_range 1 2{tokens
        say 'DAYBOOK';(date_text first);date_text last
        count =. 0
        amount =. 0x
        for_index. posting_entries'' do.
            day =. index{Days
            if. (day<first)+.day>last do. continue. end.
            count =. count+1
            amount =. amount+index{Amounts
            2 indent words (date_text day);(index{::IDs);(index{::Categories);(money index{Amounts);index{::Memos
        end.
        2 indent words 'total entries';count;'amount';money amount
    case. 'ACCOUNTS' do.
        emit 'ACCOUNTS'
        if. 0=#Codes do. 2 indent '(none)' end.
        values =. current_balances''
        for_index. /:Codes do.
            status =. (index{Active){::'inactive';'active'
            2 indent words (index{::Codes);(index{::Types);(index{::Names);'parent';(parent_code index);'balance';(money index{values);status
        end.
    case. 'TEMPLATES' do.
        emit 'TEMPLATES'
        if. 0=#TemplateNames do. 2 indent '(none)' end.
        for_index. /:TemplateNames do.
            lines =. index{::TemplateLines
            2 indent words (index{::TemplateNames);(index{::TemplateMemos);'lines';(#lines);'amount';(money {.line_sums lines);'used';index{Uses
        end.
    case. 'STATUS' do.
        open =. 'none'
        if. #DraftKind do. open =. DraftKey end.
        say 'STATUS';'accounts';(#Codes);'inactive';(+/-.Active);'entries';(#IDs);'templates';(#TemplateNames);'closed';(closed_text'');'open';open
    end.
)
main =: 3 : 0
    lines =. <;._2 (1!:1 3),LF
    count =. 0".0{::lines
    for_i. 1+i.count do.
        try. command i{::lines
        catcht. emit 'ERROR ',Error end.
    end.
)
main''
