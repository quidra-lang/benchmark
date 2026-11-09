LF =: 10{a.
Day =: 1
PlanNames =: CustomerNames =: CouponNames =: Regions =: 0$a:
Plans =: Customers =: Coupons =: Subs =: Invoices =: Events =: 0$a:
Taxes =: i.0
PF =: ;:'name price cycle length trial setup perseat mode tiers'
CF =: ;:'name region method balance log'
DF =: ;:'name kind value applications maximum redeemed'
SF =: ;:'customer plan seats state start end trial pause pending cancelend cancelon canceled coupon remaining usage'
IF =: ;:'sub customer day kind items subtotal discount tax total credit due paid refunded outstanding attempts retries'

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
words =: 3 : 0
    parts =. 0$a:
    for_part. y do.
        value =. >part
        if. 2~:3!:0 value do. value =. number value end.
        parts =. parts,<value
    end.
    ' ' join parts
)
write =: 4 : 0
    ((x#' '),(words y),LF) 1!:2 4
    i.0
)
emit =: 0&write
fail =: 3 : 'emit (<''ERROR''),y'
notice =: 3 : '2 write (''day'';Day),y'
floor_ratio =: 4 : '<. (x:x)%x:y'
cents =: 3 : '0".y-.''.'''
padded =: 4 : 0
    t =. number y
    ((0>.x-#t)#'0'),t
)
money =: 3 : 0
    a =. |y
    ((y<0)#'-'),(number a floor_ratio 100),'.',2 padded 100|a
)
percentage =: 3 : '(money y),''%'''
signed_money =: 3 : '((y>0)#''+''),money y'
period =: 3 : '(number 0{y),''-'',number 1{y'
pg =: 4 : '(PF i.<x){::y'
cg =: 4 : '(CF i.<x){::y'
dg =: 4 : '(DF i.<x){::y'
sg =: 4 : '(SF i.<x){::y'
ig =: 4 : '(IF i.<x){::y'
ps =: 4 : 0
    'key value' =. x
    (<value) (PF i.<key)}y
)
cs =: 4 : 0
    'key value' =. x
    (<value) (CF i.<key)}y
)
ds =: 4 : 0
    'key value' =. x
    (<value) (DF i.<key)}y
)
ss =: 4 : 0
    'key value' =. x
    (<value) (SF i.<key)}y
)
is =: 4 : 0
    'key value' =. x
    (<value) (IF i.<key)}y
)
save_sub =: 4 : 'Subs =: (<y) x}Subs'
save_invoice =: 4 : 'Invoices =: (<y) x}Invoices'
fee =: 4 : 0
    p =. x{::Plans
    ('price' pg p)*1>.y*'perseat' pg p
)
tax_rate =: 3 : 0
    k =. Regions i.<y
    if. k=#Regions do. 0 else. k{Taxes end.
)
coupon_error =: 3 : 0
    k =. CouponNames i.<y
    if. k=#Coupons do. 'unknown coupon';y return. end.
    d =. k{::Coupons
    if. ('maximum' dg d)='redeemed' dg d do. 'coupon exhausted';y return. end.
    0$a:
)
redeem =: 3 : 0
    d =. y{::Coupons
    d =. ('redeemed';1+'redeemed' dg d) ds d
    Coupons =: (<d) y}Coupons
    'applications' dg d
)
balance_change =: 3 : 0
    'customer change description' =. y
    if. change=0 do. i.0 return. end.
    c =. customer{::Customers
    balance =. change+'balance' cg c
    log =. ('log' cg c),<Day;description;change;balance
    c =. ('log';<log) cs ('balance';balance) cs c
    Customers =: (<c) customer}Customers
    i.0
)
sub_invoices =: 3 : 0
    indices =. i.0
    for_i. i.#Invoices do.
        if. y='sub' ig i{::Invoices do. indices =. indices,i end.
    end.
    indices
)
open_invoices =: 3 : 0
    indices =. i.0
    for_i. sub_invoices y do.
        if. 0<'outstanding' ig i{::Invoices do. indices =. indices,i end.
    end.
    indices
)
change_state =: 4 : 0
    s =. x{::Subs
    old =. 'state' sg s
    if. old-:'PAST_DUE' do.
        for_i. sub_invoices x do.
            i save_invoice ('retries';i.0) is i{::Invoices
        end.
    end.
    x save_sub ('state';y) ss s
    notice 'sub';(x+1);old;'->';y
    Events =: Events,<Day;x;old;y
    i.0
)
usage_charge =: 4 : 0
    p =. x{::Plans
    tiers =. 'tiers' pg p
    lower =. total =. 0x
    for_i. i.#tiers do.
        'upper unit flat' =. i{tiers
        if. i=(#tiers)-1 do. upper =. y end.
        if. upper=_1 do. upper =. y end.
        if. ('mode' pg p)-:'VOLUME' do.
            if. y<:upper do. (y*unit)+flat return. end.
        else.
            if. y<:lower do. break. end.
            total =. total+(((y<.upper)-lower)*unit)+flat
            lower =. upper
        end.
    end.
    total
)
usage_items =: 3 : 0
    s =. y
    p =. 'plan' sg s
    u =. 'usage' sg s
    if. (0<u)*.0<#'mode' pg p{::Plans do.
        desc =. words 'usage';(p{::PlanNames);u;'units'
        ,<desc;p usage_charge u
    else. 0$a: end.
)
close_usage =: 3 : 0
    s =. y{::Subs
    items =. usage_items s
    if. #items do. y save_sub ('usage';0) ss s end.
    items
)
period_item =: 3 : 0
    'p seats start' =. y
    finish =. start+'length' pg p{::Plans
    desc =. words 'charge';(p{::PlanNames);'seats';seats;period start,finish
    desc;p fee seats
)
opening_items =: 4 : 0
    p =. 'plan' sg x
    items =. ,<period_item p;('seats' sg x);y
    setup =. 'setup' pg p{::Plans
    if. setup>0 do. items =. items,<(words 'setup';p{::PlanNames);setup end.
    items
)
totals =: 4 : 0
    s =. x
    subtotal =. 0x
    for_item. y do. subtotal =. subtotal+1{::>item end.
    discount =. 0x
    coupon =. 'coupon' sg s
    left =. 'remaining' sg s
    if. (coupon>:0)*.(left~:0)*.subtotal>0 do.
        d =. coupon{::Coupons
        if. ('kind' dg d)-:'PERCENT' do.
            discount =. (subtotal*'value' dg d) floor_ratio 10000
        else. discount =. subtotal<.'value' dg d end.
    end.
    c =. ('customer' sg s){::Customers
    tax =. ((subtotal-discount)*tax_rate 'region' cg c) floor_ratio 10000
    total =. (subtotal-discount)+tax
    credit =. total<.'balance' cg c
    subtotal,discount,tax,total,credit,total-credit
)
show_items =: 3 : 0
    for_item. y do.
        'description amount' =. >item
        2 write description;money amount
    end.
    i.0
)
show_totals =: 3 : 0
    'subtotal discount tax total credit due' =. y
    2 write 'subtotal';(money subtotal);'discount';(money discount);'tax';(money tax);'total';money total
    i.0
)
issue =: 3 : 0
    'sub kind items' =. y
    s =. sub{::Subs
    'subtotal discount tax total credit due' =. s totals items
    left =. 'remaining' sg s
    if. (subtotal>0)*.(left>0)*.('coupon' sg s)>:0 do.
        s =. ('remaining';left-1) ss s
        sub save_sub s
    end.
    id =. #Invoices
    customer =. 'customer' sg s
    balance_change customer;(-credit);words 'applied invoice';id+1
    paid =. attempts =. 0x
    outstanding =. due
    result =. 'PAID'
    if. due>0 do.
        if. ('state' sg s)-:'UNPAID' do. result =. 'OPEN'
        else.
            attempts =. 1
            if. ('method' cg customer{::Customers)-:'OK' do. paid =. due
                outstanding =. 0
            else. result =. 'FAILED' end.
        end.
    end.
    invoice =. sub;customer;Day;kind;items;subtotal;discount;tax;total;credit;due;paid;0;outstanding;attempts;i.0
    Invoices =: Invoices,<invoice
    notice 'invoice';(id+1);'sub';(sub+1);kind;'total';(money total);'credit';(money credit);'due';(money due);result
    if. result-:'FAILED' do.
        if. ('state' sg sub{::Subs)-:'ACTIVE' do. sub change_state 'PAST_DUE' end.
        if. ('state' sg sub{::Subs)-:'PAST_DUE' do.
            id save_invoice ('retries';Day+3 5 7) is id{::Invoices
        end.
    end.
    i.0
)
payment_complete =: 3 : 0
    invoice =. y{::Invoices
    y save_invoice ('retries';i.0) is invoice
    sub =. 'sub' ig invoice
    s =. sub{::Subs
    if. (< 'state' sg s)e.;:'PAST_DUE UNPAID' do.
        if. 0=#open_invoices sub do.
            sub save_sub ('cancelon';0) ss s
            sub change_state 'ACTIVE'
        end.
    end.
    i.0
)
cancel_sub =: 3 : 0
    y change_state 'CANCELED'
    s =. y{::Subs
    s =. ('canceled';Day) ss ('pending';i.0) ss ('cancelend';0) ss ('cancelon';0) ss s
    y save_sub s
    items =. close_usage y
    if. #items do. issue y;'final';<items end.
    i.0
)
advance =: 3 : 0
    while. Day<y do.
        Day =: Day+1
        for_sub. i.#Subs do.
            s =. sub{::Subs
            if. (< 'state' sg s)e.;:'PAUSED CANCELED' do. continue. end.
            for_i. sub_invoices sub do.
                invoice =. i{::Invoices
                retry =. 'retries' ig invoice
                if. 0=#retry do. continue. end.
                if. Day~:{.retry do. continue. end.
                attempts =. 1+'attempts' ig invoice
                invoice =. ('retries';}.retry) is ('attempts';attempts) is invoice
                customer =. 'customer' ig invoice
                if. ('method' cg customer{::Customers)-:'OK' do.
                    paid =. ('paid' ig invoice)+'outstanding' ig invoice
                    i save_invoice ('paid';paid) is ('outstanding';0) is invoice
                    notice 'retry';(attempts-1);'invoice';(i+1);'PAID'
                    payment_complete i
                else.
                    i save_invoice invoice
                    notice 'retry';(attempts-1);'invoice';(i+1);'FAILED'
                    if. 1=#retry do.
                        sub change_state 'UNPAID'
                        sub save_sub ('cancelon';Day+14) ss sub{::Subs
                    end.
                end.
            end.
            s =. sub{::Subs
            if. (('state' sg s)-:'UNPAID')*.Day='cancelon' sg s do. cancel_sub sub end.
            s =. sub{::Subs
            if. (('state' sg s)-:'TRIALING')*.Day='trial' sg s do.
                if. 'cancelend' sg s do. cancel_sub sub
                else.
                    sub change_state 'ACTIVE'
                    s =. sub{::Subs
                    finish =. Day+'length' pg ('plan' sg s){::Plans
                    s =. ('start';Day) ss ('end';finish) ss s
                    sub save_sub s
                    issue sub;'first';<s opening_items Day
                end.
            end.
            s =. sub{::Subs
            if. ((<'state' sg s)e.;:'ACTIVE PAST_DUE UNPAID')*.Day='end' sg s do.
                if. 'cancelend' sg s do. cancel_sub sub
                else.
                    items =. close_usage sub
                    s =. sub{::Subs
                    pending =. 'pending' sg s
                    if. #pending do.
                        'p seats' =. pending
                        notice 'sub';(sub+1);(('plan' sg s){::PlanNames);'seats';('seats' sg s);'->';(p{::PlanNames);'seats';seats
                        s =. ('plan';p) ss ('seats';seats) ss ('pending';i.0) ss s
                    end.
                    p =. 'plan' sg s
                    s =. ('start';Day) ss ('end';Day+'length' pg p{::Plans) ss s
                    sub save_sub s
                    items =. items,<period_item p;('seats' sg s);Day
                    issue sub;'renewal';<items
                end.
            end.
        end.
    end.
    i.0
)
show_invoice =: 3 : 0
    inv =. y{::Invoices
    state =. 'PAID'
    if. 'outstanding' ig inv do. state =. 'OPEN' end.
    emit 'INVOICE';(y+1);'sub';(1+'sub' ig inv);(('customer' ig inv){::CustomerNames);'day';('day' ig inv);('kind' ig inv);state
    show_items 'items' ig inv
    show_totals > (IF i.;:'subtotal discount tax total credit due'){inv
    2 write 'credit';(money 'credit' ig inv);'due';(money 'due' ig inv);'paid';(money 'paid' ig inv);'refunded';(money 'refunded' ig inv);'outstanding';money 'outstanding' ig inv
    i.0
)
show_sub =: 3 : 0
    s =. y{::Subs
    state =. 'state' sg s
    emit 'SUB';(y+1);(('customer' sg s){::CustomerNames);(('plan' sg s){::PlanNames);'seats';('seats' sg s);state
    if. state-:'TRIALING' do. 2 write 'trial until';'trial' sg s end.
    if. (<state)e.;:'ACTIVE PAST_DUE UNPAID PAUSED' do. 2 write 'period';period ('start' sg s),'end' sg s end.
    if. state-:'PAUSED' do. 2 write 'paused since';'pause' sg s end.
    pending =. 'pending' sg s
    if. #pending do. 2 write 'pending';(({.pending){::PlanNames);'seats';{:pending end.
    if. 'cancelend' sg s do. 2 write <'cancel at end' end.
    if. 'cancelon' sg s do. 2 write 'cancel on';'cancelon' sg s end.
    if. state-:'CANCELED' do. 2 write 'canceled on';'canceled' sg s end.
    if. ('coupon' sg s)>:0 do.
        left =. 'remaining' sg s
        coupon =. ('coupon' sg s){::CouponNames
        if. left=_1 do. 2 write 'coupon';coupon;'forever'
        elseif. left>0 do. 2 write 'coupon';coupon;'left';left end.
    end.
    if. (-.state-:'CANCELED')*.0<#'mode' pg ('plan' sg s){::Plans do. 2 write 'usage';'usage' sg s end.
    open =. open_invoices y
    if. #open do. 2 write (<'open'),<"0 open+1 end.
    i.0
)
preview =: 3 : 0
    s =. y{::Subs
    trial =. ('state' sg s)-:'TRIALING'
    due =. 'end' sg s
    if. trial do. due =. 'trial' sg s end.
    if. 'cancelend' sg s do.
        kind =. 'final'
        items =. 0$a:
        if. -.trial do. items =. usage_items s end.
    elseif. trial do.
        kind =. 'first'
        items =. s opening_items due
    else.
        kind =. 'renewal'
        items =. usage_items s
        p =. 'plan' sg s
        seats =. 'seats' sg s
        pending =. 'pending' sg s
        if. #pending do. 'p seats' =. pending end.
        items =. items,<period_item p;seats;due
    end.
    emit 'PREVIEW sub';(y+1);'day';due;kind
    if. 0=#items do. 2 write <'(none)' return. end.
    show_items items
    amounts =. s totals items
    show_totals amounts
    2 write 'credit';(money 4{amounts);'due';money 5{amounts
    i.0
)
customer_query =: 4 : 0
    c =. y{::Customers
    name =. y{::CustomerNames
    if. x-:'LEDGER' do.
        emit 'LEDGER';name;'balance';money 'balance' cg c
        log =. 'log' cg c
        if. 0=#log do. 2 write <'(none)' end.
        for_row. log do.
            'day description change balance' =. >row
            2 write 'day';day;description;(signed_money change);'balance';money balance
        end.
    else.
        region =. 'region' cg c
        emit 'STATEMENT';name;'region';region;'tax';(percentage tax_rate region);'method';('method' cg c);'balance';money 'balance' cg c
        for_i. i.#Subs do.
            s =. i{::Subs
            if. y='customer' sg s do. 2 write 'sub';(i+1);(('plan' sg s){::PlanNames);'state' sg s end.
        end.
        outstanding =. 0x
        for_i. i.#Invoices do.
            inv =. i{::Invoices
            if. y~:'customer' ig inv do. continue. end.
            outstanding =. outstanding+'outstanding' ig inv
            2 write 'invoice';(i+1);'day';('day' ig inv);'sub';(1+'sub' ig inv);('kind' ig inv);'total';(money 'total' ig inv);'outstanding';money 'outstanding' ig inv
        end.
        2 write 'outstanding';money outstanding
    end.
    i.0
)
aging_line =: 4 : 0
    2 write x;'0-30';(money 0{y);'31-60';(money 1{y);'61+';(money 2{y);'sum';money +/y
)
summary =: 3 : 0
    select. y
    case. 'MRR' do.
        emit <'MRR'
        count =. total =. 0x
        for_p. /:PlanNames do.
            n =. amount =. 0x
            for_s. Subs do.
                s =. >s
                if. (p='plan' sg s)*.(<'state' sg s)e.;:'ACTIVE PAST_DUE' do.
                    n =. n+1
                    amount =. amount+((p fee 'seats' sg s)*30) floor_ratio 'length' pg p{::Plans
                end.
            end.
            if. n do. 2 write (p{::PlanNames);'subs';n;'mrr';money amount end.
            count =. count+n
            total =. total+amount
        end.
        2 write 'total subs';count;'mrr';money total
    case. 'AGING' do.
        emit 'AGING day';Day
        total =. 3$0x
        for_c. /:CustomerNames do.
            amounts =. 3$0x
            for_inv. Invoices do.
                inv =. >inv
                if. c='customer' ig inv do.
                    age =. Day-'day' ig inv
                    bucket =. (age>30)+age>60
                    amounts =. (('outstanding' ig inv)+bucket{amounts) bucket}amounts
                end.
            end.
            if. +/amounts do. (c{::CustomerNames) aging_line amounts end.
            total =. total+amounts
        end.
        'total' aging_line total
    case. 'DUNNING' do.
        emit <'DUNNING'
        count =. 0
        for_i. i.#Invoices do.
            inv =. i{::Invoices
            retry =. 'retries' ig inv
            if. #retry do.
                count =. count+1
                2 write 'invoice';(i+1);'sub';(1+'sub' ig inv);(('customer' ig inv){::CustomerNames);'outstanding';(money 'outstanding' ig inv);'attempts';('attempts' ig inv);'next';{.retry
            end.
        end.
        if. count=0 do. 2 write <'(none)' end.
    case. 'REVENUE' do.
        sums =. 8$0x
        for_inv. Invoices do.
            sums =. sums+>(IF i.;:'subtotal discount tax total credit paid refunded outstanding'){>inv
        end.
        balances =. 0x
        for_c. Customers do. balances =. balances+'balance' cg >c end.
        emit <'REVENUE'
        2 write 'invoices';(#Invoices);'subtotal';(money 0{sums);'discount';(money 1{sums);'tax';(money 2{sums);'total';money 3{sums
        2 write 'credit';(money 4{sums);'paid';(money 5{sums);'refunded';(money 6{sums);'outstanding';(money 7{sums);'balances';money balances
    end.
    i.0
)
execute =: 3 : 0
    fields =. ' ' split y
    command =. 0{::fields
    args =. }.fields
    select. command
    case. 'PLAN' do.
        'name price cycle' =. 3{.args
        if. (<name)e.PlanNames do. fail 'duplicate plan';name return. end.
        price =. cents price
        length =. ((;:'WEEKLY MONTHLY YEARLY')i.<cycle){7 30 360
        trial =. setup =. perseat =. 0
        mode =. ''
        i =. 3
        while. i<#args do.
            select. i{::args
            case. 'TRIAL' do.
                trial =. 0".(i+1){::args
                i =. i+1
            case. 'SETUP' do.
                setup =. cents (i+1){::args
                i =. i+1
            case. 'PERSEAT' do. perseat =. 1
            case. do. mode =. i{::args
            end.
            i =. i+1
        end.
        Plans =: Plans,<name;price;cycle;length;trial;setup;perseat;mode;0 3$0x
        PlanNames =: PlanNames,<name
        line =. 'PLAN';name;cycle;money price
        if. trial do. line =. line,'trial';trial end.
        if. setup do. line =. line,'setup';money setup end.
        if. perseat do. line =. line,<'perseat' end.
        if. #mode do. line =. line,<tolower mode end.
        emit line
        i.0 return.
    case. 'TIER' do.
        'name limit unit flat' =. args
        p =. PlanNames i.<name
        if. p=#Plans do. fail 'unknown plan';name return. end.
        plan =. p{::Plans
        if. 0=#'mode' pg plan do. fail 'not metered';name return. end.
        upper =. _1
        if. -.limit-:'INF' do. upper =. 0".limit end.
        tiers =. 'tiers' pg plan
        if. #tiers do.
            previous =. 0{{:tiers
            if. (previous=_1)+.(upper~:_1)*.upper<:previous do. fail 'tier order';name return. end.
        end.
        tiers =. tiers,1 3$upper,(cents unit),cents flat
        Plans =: (<('tiers';tiers) ps plan) p}Plans
        emit 'TIER';name;(#tiers);'upto';limit;'unit';unit;'flat';flat
        i.0 return.
    case. 'TAX' do.
        region =. 0{::args
        rate =. 0".1{::args
        i =. Regions i.<region
        if. i=#Regions do.
            Regions =: Regions,<region
            Taxes =: Taxes,rate
        else. Taxes =: rate i}Taxes end.
        emit 'TAX';region;percentage rate
        i.0 return.
    case. 'CUSTOMER' do.
        'name region' =. args
        if. (<name)e.CustomerNames do. fail 'duplicate customer';name return. end.
        CustomerNames =: CustomerNames,<name
        Customers =: Customers,<name;region;'OK';0;<0$a:
        emit 'CUSTOMER';name;'region';region
        i.0 return.
    case. 'COUPON' do.
        'name kind value application' =. 4{.args
        if. (<name)e.CouponNames do. fail 'duplicate coupon';name return. end.
        if. kind-:'PERCENT' do. value =. 0".value
            discount =. 'percent';percentage value
        else. value =. cents value
            discount =. 'amount';money value end.
        applications =. 1
        i =. 4
        use =. <tolower application
        if. application-:'FOREVER' do. applications =. _1
        elseif. application-:'REPEATING' do.
            applications =. 0".4{::args
            use =. use,<applications
            i =. 5
        end.
        maximum =. _1
        suffix =. 0$a:
        if. i<#args do. maximum =. 0".(i+1){::args
            suffix =. 'max';maximum end.
        CouponNames =: CouponNames,<name
        Coupons =: Coupons,<name;kind;value;applications;maximum;0
        emit ('COUPON';name),discount,use,suffix
        i.0 return.
    case. 'DAY' do.
        day =. 0".0{::args
        if. day<:Day do. fail 'invalid day';day return. end.
        emit 'DAY';day
        advance day
        i.0 return.
    case. 'MRR';'AGING';'DUNNING';'REVENUE' do. summary command return.
    case. 'EVENTS' do.
        sub =. _1
        line =. <'EVENTS'
        if. #args do.
            sub =. _1+0".0{::args
            if. (sub<0)+.sub>:#Subs do. fail 'unknown sub';sub+1 return. end.
            line =. line,'sub';sub+1
        end.
        emit line
        count =. 0
        for_event. Events do.
            'day id old new' =. >event
            if. (sub=_1)+.sub=id do.
                2 write 'day';day;'sub';(id+1);old;'->';new
                count =. count+1
            end.
        end.
        if. count=0 do. 2 write <'(none)' end.
        i.0 return.
    end.
    if. (<command)e.;:'PAYMETHOD CREDIT STATEMENT LEDGER SUBSCRIBE' do.
        name =. 0{::args
        customer =. CustomerNames i.<name
        if. customer=#Customers do. fail 'unknown customer';name return. end.
        c =. customer{::Customers
        select. command
        case. 'PAYMETHOD' do.
            method =. 1{::args
            Customers =: (<('method';method) cs c) customer}Customers
            emit 'PAYMETHOD';name;method
        case. 'CREDIT' do.
            amount =. cents 1{::args
            if. amount=0 do. fail <'invalid amount' return. end.
            balance_change customer;amount;'grant'
            emit 'CREDIT';name;'amount';(money amount);'balance';money 'balance' cg customer{::Customers
        case. 'STATEMENT';'LEDGER' do. command customer_query customer
        case. 'SUBSCRIBE' do.
            planname =. 1{::args
            p =. PlanNames i.<planname
            if. p=#Plans do. fail 'unknown plan';planname return. end.
            plan =. p{::Plans
            seats =. 1
            coupon =. _1
            remaining =. 0
            seatarg =. args i.<'SEATS'
            couponarg =. args i.<'COUPON'
            if. seatarg<#args do.
                if. -.'perseat' pg plan do. fail 'not per-seat';planname return. end.
                seats =. 0".(seatarg+1){::args
            end.
            if. seats=0 do. fail <'invalid seats' return. end.
            suffix =. 0$a:
            if. couponarg<#args do.
                couponname =. (couponarg+1){::args
                reason =. coupon_error couponname
                if. #reason do. fail reason return. end.
                coupon =. CouponNames i.<couponname
                remaining =. redeem coupon
                suffix =. 'coupon';couponname
            end.
            sub =. #Subs
            s =. customer;p;seats;'NONE';0;0;0;0;(i.0);0;0;0;coupon;remaining;0
            Subs =: Subs,<s
            emit ('SUBSCRIBE sub';(sub+1);name;planname;'seats';seats),suffix
            trial =. 'trial' pg plan
            if. trial do.
                sub save_sub ('trial';Day+trial) ss s
                sub change_state 'TRIALING'
            else.
                sub save_sub ('start';Day) ss ('end';Day+'length' pg plan) ss s
                sub change_state 'ACTIVE'
                issue sub;'first';<(sub{::Subs) opening_items Day
            end.
        end.
        i.0 return.
    end.
    if. (<command)e.;:'PAY REFUND INVOICE' do.
        id =. _1+0".0{::args
        if. (id<0)+.id>:#Invoices do. fail 'unknown invoice';id+1 return. end.
        inv =. id{::Invoices
        select. command
        case. 'INVOICE' do. show_invoice id
        case. 'PAY' do.
            amount =. 'outstanding' ig inv
            if. amount=0 do. fail 'already paid';id+1 return. end.
            emit 'PAY invoice';(id+1);'amount';money amount
            id save_invoice ('paid';amount+'paid' ig inv) is ('outstanding';0) is inv
            payment_complete id
        case. 'REFUND' do.
            amount =. cents 1{::args
            if. amount=0 do. fail <'invalid amount' return. end.
            available =. ('total' ig inv)-'refunded' ig inv
            if. amount>available do. fail 'refund exceeds';(id+1);money available return. end.
            applied =. amount<.'outstanding' ig inv
            outstanding =. ('outstanding' ig inv)-applied
            inv =. ('refunded';amount+'refunded' ig inv) is ('outstanding';outstanding) is inv
            id save_invoice inv
            customer =. 'customer' ig inv
            balance_change customer;(amount-applied);words 'refund invoice';id+1
            emit 'REFUND invoice';(id+1);'amount';(money amount);'applied';(money applied);'balance';money 'balance' cg customer{::Customers
            if. (applied>0)*.outstanding=0 do. payment_complete id end.
        end.
        i.0 return.
    end.
    sub =. _1+0".0{::args
    if. (sub<0)+.sub>:#Subs do. fail 'unknown sub';sub+1 return. end.
    s =. sub{::Subs
    state =. 'state' sg s
    p =. 'plan' sg s
    plan =. p{::Plans
    planname =. p{::PlanNames
    allowed =. ;:'TRIALING ACTIVE PAST_DUE UNPAID PAUSED CANCELED'
    select. command
    case. 'CHANGE' do. allowed =. ;:'ACTIVE TRIALING'
    case. 'PAUSE' do. allowed =. ,<'ACTIVE'
    case. 'RESUME' do. allowed =. ,<'PAUSED'
    case. 'CANCEL' do.
        allowed =. ;:'TRIALING ACTIVE PAST_DUE UNPAID PAUSED'
        if. (1{::args)-:'END' do. allowed =. ;:'ACTIVE TRIALING' end.
    case. 'USAGE' do. allowed =. ;:'ACTIVE PAST_DUE'
    case. 'APPLY' do. allowed =. ;:'TRIALING ACTIVE PAST_DUE UNPAID PAUSED'
    case. 'PREVIEW' do. allowed =. ;:'TRIALING ACTIVE PAST_DUE UNPAID'
    end.
    if. -.(<state)e.allowed do. fail 'invalid state';(sub+1);state return. end.
    select. command
    case. 'SUB' do. show_sub sub
    case. 'PREVIEW' do. preview sub
    case. 'CHANGE' do.
        oldseats =. seats =. 'seats' sg s
        newp =. p
        if. (1{::args)-:'PLAN' do.
            newname =. 2{::args
            newp =. PlanNames i.<newname
            if. newp=#Plans do. fail 'unknown plan';newname return. end.
            if. -.'perseat' pg newp{::Plans do. seats =. 1 end.
        else.
            if. -.'perseat' pg plan do. fail 'not per-seat';planname return. end.
            seats =. 0".2{::args
            if. seats=0 do. fail <'invalid seats' return. end.
        end.
        if. (p=newp)*.seats=oldseats do. fail 'no change';sub+1 return. end.
        s =. ('pending';i.0) ss s
        sub save_sub s
        head =. 'CHANGE sub';(sub+1);planname;'seats';oldseats;'->';(newp{::PlanNames);'seats';seats
        a =. p fee oldseats
        b =. newp fee seats
        la =. 'length' pg plan
        lb =. 'length' pg newp{::Plans
        if. state-:'TRIALING' do.
            sub save_sub ('plan';newp) ss ('seats';seats) ss s
            emit head,<'now'
        elseif. (b*la)>a*lb do.
            emit head,<'now'
            r =. ('end' sg s)-Day
            items =. close_usage sub
            items =. items,<(words 'unused';planname;'seats';oldseats;r;'days');-((a*r) floor_ratio la)
            items =. items,<(words 'remaining';(newp{::PlanNames);'seats';seats;r;'days');(b*r) floor_ratio lb
            sub save_sub ('plan';newp) ss ('seats';seats) ss sub{::Subs
            issue sub;'upgrade';<items
        else.
            sub save_sub ('pending';newp,seats) ss s
            emit head,'at';'end' sg s
        end.
    case. 'PAUSE' do.
        emit 'PAUSE sub';sub+1
        sub save_sub ('pause';Day) ss s
        sub change_state 'PAUSED'
    case. 'RESUME' do.
        shift =. Day-'pause' sg s
        finish =. shift+'end' sg s
        sub save_sub ('pause';0) ss ('end';finish) ss s
        emit 'RESUME sub';(sub+1);'shift';shift;'period';period ('start' sg s),finish
        sub change_state 'ACTIVE'
    case. 'CANCEL' do.
        if. (1{::args)-:'END' do.
            if. 'cancelend' sg s do. fail 'already canceling';sub+1 return. end.
            sub save_sub ('cancelend';1) ss s
            finish =. 'end' sg s
            if. state-:'TRIALING' do. finish =. 'trial' sg s end.
            emit 'CANCEL sub';(sub+1);'end';finish
        else.
            refund =. 0x
            if. (<state)e.;:'ACTIVE PAUSED' do.
                start =. Day
                if. state-:'PAUSED' do. start =. 'pause' sg s end.
                refund =. ((p fee 'seats' sg s)*(('end' sg s)-start)) floor_ratio 'length' pg plan
            end.
            balance_change ('customer' sg s);refund;words 'cancel sub';sub+1
            emit 'CANCEL sub';(sub+1);'now credit';money refund
            cancel_sub sub
        end.
    case. 'USAGE' do.
        if. 0=#'mode' pg plan do. fail 'not metered';planname return. end.
        units =. 0".1{::args
        if. units=0 do. fail <'invalid units' return. end.
        total =. units+'usage' sg s
        sub save_sub ('usage';total) ss s
        emit 'USAGE sub';(sub+1);'units';units;'total';total
    case. 'APPLY' do.
        name =. 1{::args
        reason =. coupon_error name
        if. #reason do. fail reason return. end.
        coupon =. CouponNames i.<name
        remaining =. redeem coupon
        sub save_sub ('coupon';coupon) ss ('remaining';remaining) ss s
        emit 'APPLY sub';(sub+1);'coupon';name
    end.
    i.0
)
main =: 3 : 0
    lines =. <;._2 (1!:1 3),LF
    for_line. (0".0{::lines){.}.lines do. execute >line end.
    i.0
)
main ''
