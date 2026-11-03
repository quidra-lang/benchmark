LF =: 10{a.
STATIONS =: ;:'GRILL FRY COLD BAR'
COURSES =: ;:'DRINK STARTER MAIN DESSERT'
CHECK_FIELDS =: ;:'party size table server since paid discount closed'
ORDER_FIELDS =: ;:'check seat item quantity station prep unit course state comp fire ready started'
Time =: HappyRate =: HappyEnd =: 0
Tables =: 0 3$0
Servers =: Checks =: Orders =: Waiting =: MenuNames =: 0$a:
ServerStats =: 0 3$0
Menu =: 0 6$0
Queues =: 4$<i.0
Up =: 4$1
StationStats =: 4 4$0
Covers =: Parties =: ClosedCount =: StaySum =: Tips =: CompCount =: CompValue =: Voids =: 0
Sales =: 4$0
Financial =: 5$0
Payments =: 2$0
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
emit =: 3 : 0
    parts =. 0$a:
    for_part. y do.
        value =. >part
        if. 2~:3!:0 value do. value =. number value end.
        parts =. parts,<value
    end.
    ((' ' join parts),LF) 1!:2 4
    i.0
)
fail =: 3 : 'emit (<''ERROR''),y'
floor_ratio =: 4 : '<.(x:x)%x:y'
cents =: 3 : '0".y-.''.'''
padded =: 4 : 0
    text =. number y
    ((0>.x-#text)#'0'),text
)
money =: 3 : '(number y floor_ratio 100),''.'',2 padded 100|y'
clock =: 3 : '(2 padded (660+y) floor_ratio 60),'':'',2 padded 60|660+y'
percent =: 3 : '(number y),''%'''
order_number =: 3 : '''#'',number y+1'
quantity_text =: 3 : '''x'',number y'
rounded =: 4 : '((x*y)+50) floor_ratio 100'
cg =: 4 : '(CHECK_FIELDS i.<x){::y'
og =: 4 : '(ORDER_FIELDS i.<x){::y'
cs =: 4 : 0
    'key value' =. x
    (<value) (CHECK_FIELDS i.<key)}y
)
os =: 4 : 0
    'key value' =. x
    (<value) (ORDER_FIELDS i.<key)}y
)
save_check =: 4 : 'Checks =: (<y) x}Checks'
save_order =: 4 : 'Orders =: (<y) x}Orders'
table_number =: 3 : '0{y{Tables'
table_error =: 3 : 0
    t =. (0{"1 Tables)i.y
    if. t=#Tables do. 'unknown table';y return. end.
    if. _1=2{t{Tables do. 'table';y;'is free' return. end.
    0$a:
)
check_lines =: 3 : 0
    indices =. i.0
    for_i. i.#Orders do.
        if. y='check' og i{::Orders do. indices =. indices,i end.
    end.
    indices
)
active_lines =: 3 : 0
    indices =. i.0
    for_i. check_lines y do.
        if. -.('state' og i{::Orders)-:'VOID' do. indices =. indices,i end.
    end.
    indices
)
unserved =: 3 : 0
    count =. 0
    for_i. active_lines y do.
        count =. count+-.('state' og i{::Orders)-:'SERVED'
    end.
    count
)
line_amount =: 3 : 0
    if. #'comp' og y do. 0 else. ('unit' og y)*'quantity' og y end.
)
check_amounts =: 3 : 0
    c =. y{::Checks
    subtotal =. 0
    for_i. active_lines y do. subtotal =. subtotal+line_amount i{::Orders end.
    discount =. ('discount' cg c) rounded subtotal
    after =. subtotal-discount
    service =. 0
    if. ('size' cg c)>:6 do. service =. 18 rounded after end.
    tax =. 8 rounded after
    total =. after+service+tax
    subtotal,discount,service,tax,total,total-'paid' cg c
)
server_loads =: 3 : 0
    loads =. (#Servers)$0
    for_check. Checks do.
        c =. >check
        if. -.'closed' cg c do.
            s =. 'server' cg c
            loads =. (1+s{loads) s}loads
        end.
    end.
    loads
)
select_table =: 3 : 0
    fitting =. I.((2{"1 Tables)=_1)*.(1{"1 Tables)>:y
    if. 0=#fitting do. _1 return. end.
    keys =. (fitting{1{"1 Tables),.fitting{0{"1 Tables
    ({./:keys){fitting
)
seat_party =: 3 : 0
    'party size table' =. y
    loads =. server_loads ''
    server =. loads i.<./loads
    check =. #Checks
    Checks =: Checks,<party;size;table;server;Time;0;0;0
    Tables =: ((2{.table{Tables),check) table}Tables
    stats =. server{ServerStats
    stats =. (1+0{stats) 0}stats
    ServerStats =: stats server}ServerStats
    Covers =: Covers+size
    Parties =: Parties+1
    check
)
seat_waiting =: 3 : 0
    remaining =. 0$a:
    for_party. Waiting do.
        'name size joined' =. >party
        table =. select_table size
        if. table=_1 do. remaining =. remaining,party
        else.
            check =. seat_party name;size;table
            server =. 'server' cg check{::Checks
            emit 'SEATED';name;size;'table';(table_number table);'server';(server{::Servers);'waited';Time-joined
        end.
    end.
    Waiting =: remaining
    i.0
)
close_check =: 3 : 0
    c =. y{::Checks
    amounts =. check_amounts y
    for_i. active_lines y do.
        order =. i{::Orders
        course =. 'course' og order
        Sales =: ((course{Sales)+line_amount order) course}Sales
    end.
    Financial =: Financial+5{.amounts
    server =. 'server' cg c
    stats =. server{ServerStats
    stats =. ((1{stats)+4{amounts) 1}stats
    ServerStats =: stats server}ServerStats
    stayed =. Time-'since' cg c
    StaySum =: StaySum+stayed
    ClosedCount =: ClosedCount+1
    y save_check ('closed';1) cs c
    table =. 'table' cg c
    Tables =: ((2{.table{Tables),_1) table}Tables
    emit 'FREE table';(table_number table);('party' cg c);'stayed';stayed
    seat_waiting ''
    i.0
)
cooking =: 3 : 0
    indices =. i.0
    for_i. i.#Orders do.
        order =. i{::Orders
        if. (y='station' og order)*.('state' og order)-:'COOKING' do. indices =. indices,i end.
    end.
    indices
)
cook_start =: 4 : 0
    if. -.x{Up do. i.0 return. end.
    queue =. x{::Queues
    count =. #cooking x
    capacity =. x{1 1 1 2
    while. (#queue)*.count<capacity do.
        i =. {.queue
        queue =. }.queue
        order =. i{::Orders
        order =. ('state';'COOKING') os ('started';1) os ('ready';y+'prep' og order) os order
        i save_order order
        count =. count+1
    end.
    Queues =: (<queue) x}Queues
    i.0
)
tick =: 3 : 0
    target =. Time+y
    emit 'TICK';clock target
    while. 1 do.
        ready =. i.0
        for_s. i.4 do.
            for_i. cooking s do. ready =. ready,'ready' og i{::Orders end.
        end.
        if. 0=#ready do. break. end.
        next =. <./ready
        if. next>target do. break. end.
        for_s. i.4 do.
            for_i. cooking s do.
                order =. i{::Orders
                if. next~:'ready' og order do. continue. end.
                i save_order ('state';'READY') os order
                ticket =. next-'fire' og order
                stats =. s{StationStats
                stats =. (1+0{stats),(ticket+1{stats),((2{stats)>.ticket),3{stats
                StationStats =: stats s}StationStats
                c =. ('check' og order){::Checks
                emit 'READY';(clock next);(s{::STATIONS);(order_number i);(('item' og order){::MenuNames);(quantity_text 'quantity' og order);'table';(table_number 'table' cg c);'seat';'seat' og order
            end.
        end.
        for_s. i.4 do. s cook_start next end.
    end.
    Time =: target
    i.0
)
number_list =: 3 : 0
    if. 0=#y do. '-' return. end.
    parts =. 0$a:
    for_i. y do. parts =. parts,<order_number i end.
    ' ' join parts
)
modification_error =: 3 : 0
    order =. y{::Orders
    label =. order_number y
    if. ('state' og order)-:'VOID' do. label;'is void' return. end.
    c =. ('check' og order){::Checks
    if. 'closed' cg c do. label;'is on a closed check' return. end.
    if. 'paid' cg c do. 'check for table';(table_number 'table' cg c);'is locked' return. end.
    0$a:
)
seat_subtotals =: 3 : 0
    seats =. i.0
    for_i. active_lines y do. seats =. seats,'seat' og i{::Orders end.
    seats =. /:~ ~.seats
    amounts =. (#seats)$0
    for_i. active_lines y do.
        order =. i{::Orders
        index =. seats i.'seat' og order
        amounts =. ((index{amounts)+line_amount order) index}amounts
    end.
    seats;amounts
)
allocate =: 4 : 0
    allocations =. (x*y) floor_ratio 100
    left =. (x rounded +/y)-+/allocations
    winners =. left{.\:100|x*y
    (1+winners{allocations) winners}allocations
)
bill =: 3 : 0
    c =. y{::Checks
    'subtotal discount service tax total due' =. check_amounts y
    emit 'BILL table';(table_number 'table' cg c);('party' cg c);'guests';'size' cg c
    'seats amounts' =. seat_subtotals y
    for_j. i.#seats do.
        seat =. j{seats
        emit 'SEAT';seat;money j{amounts
        for_i. active_lines y do.
            order =. i{::Orders
            if. seat~:'seat' og order do. continue. end.
            line =. (order_number i);(('item' og order){::MenuNames);(quantity_text 'quantity' og order);money line_amount order
            if. #'comp' og order do. line =. line,'COMP';'comp' og order end.
            emit line
        end.
    end.
    emit 'SUBTOTAL';money subtotal
    if. 'discount' cg c do. emit 'DISCOUNT';(percent 'discount' cg c);money discount end.
    if. ('size' cg c)>:6 do. emit 'SERVICE';money service end.
    emit 'TAX';money tax
    emit 'TOTAL';money total
    if. 'paid' cg c do. emit 'PAID';money 'paid' cg c
        emit 'DUE';money due end.
    i.0
)
show_status =: 3 : 0
    c =. y{::Checks
    emit 'STATUS table';(table_number 'table' cg c);('party' cg c);'guests';('size' cg c);'since';clock 'since' cg c
    for_i. check_lines y do.
        order =. i{::Orders
        state =. 'state' og order
        line =. (order_number i);'seat';('seat' og order);(('item' og order){::MenuNames);(quantity_text 'quantity' og order);(('course' og order){::COURSES);state
        if. state-:'COOKING' do. line =. line,'until';clock 'ready' og order end.
        if. #'comp' og order do. line =. line,'COMP';'comp' og order end.
        emit line
    end.
    i.0
)
show_kitchen =: 3 : 0
    emit 'KITCHEN';clock Time
    for_s. i.4 do.
        indices =. cooking s
        ready =. i.0
        for_i. indices do. ready =. ready,'ready' og i{::Orders end.
        parts =. 0$a:
        for_i. (/:ready){indices do.
            parts =. parts,<(order_number i),'@',clock 'ready' og i{::Orders
        end.
        text =. '-'
        if. #parts do. text =. ' ' join parts end.
        state =. (s{Up){::;:'down up'
        emit (s{::STATIONS);state;'cooking';text;'queue';number_list s{::Queues
    end.
    i.0
)
show_floor =: 3 : 0
    free =. +/(2{"1 Tables)=_1
    emit 'FLOOR';(clock Time);'free';free;'seated';((#Tables)-free);'waiting';#Waiting
    for_t. /:0{"1 Tables do.
        'table seats check' =. t{Tables
        line =. 'table';table;'seats';seats
        if. check=_1 do. line =. line,<'free'
        else.
            c =. check{::Checks
            line =. line,('party' cg c);'guests';('size' cg c);'server';(('server' cg c){::Servers);'since';(clock 'since' cg c);'items';(#active_lines check);'total';money 4{check_amounts check
            if. 'paid' cg c do. line =. line,'paid';money 'paid' cg c end.
        end.
        emit line
    end.
    for_i. i.#Waiting do.
        'name size joined' =. i{::Waiting
        emit 'WAITING';(i+1);name;size;'since';clock joined
    end.
    i.0
)
show_report =: 3 : 0
    emit 'REPORT';clock Time
    emit 'COVERS';Covers;'parties';Parties
    average =. '-'
    if. ClosedCount do. average =. number StaySum floor_ratio ClosedCount end.
    emit 'TURNS';ClosedCount;'avg_stay';average
    emit 'SALES DRINK';(money 0{Sales);'STARTER';(money 1{Sales);'MAIN';(money 2{Sales);'DESSERT';money 3{Sales
    emit 'TOTALS subtotal';(money 0{Financial);'discount';(money 1{Financial);'service';(money 2{Financial);'tax';(money 3{Financial);'total';money 4{Financial
    emit 'PAYMENTS cash';(money 0{Payments);'card';(money 1{Payments);'tips';money Tips
    emit 'COMPS';CompCount;(money CompValue);'VOIDS';Voids
    candidates =. (/:MenuNames)#~0<(5{"1 Menu){~/:MenuNames
    candidates =. (\:candidates{5{"1 Menu){candidates
    for_rank. i.3<.#candidates do.
        i =. rank{candidates
        emit 'TOP';(rank+1);(i{::MenuNames);5{i{Menu
    end.
    for_s. i.4 do.
        'count total maximum remakes' =. s{StationStats
        avgtext =. maxtext =. '-'
        if. count do. avgtext =. number total floor_ratio count
            maxtext =. number maximum end.
        emit (s{::STATIONS);'tickets';count;'avg';avgtext;'max';maxtext;'remakes';remakes
    end.
    loads =. server_loads ''
    for_s. i.#Servers do.
        'parties sales tips' =. s{ServerStats
        emit 'SERVER';(s{::Servers);'tables';(s{loads);'parties';parties;'sales';(money sales);'tips';money tips
    end.
    i.0
)
execute =: 3 : 0
    fields =. ' ' split y
    command =. 0{::fields
    args =. }.fields
    select. command
    case. 'TABLE' do.
        'table seats' =. 0".>args
        if. table e.0{"1 Tables do. fail 'table';table;'already exists' return. end.
        Tables =: Tables,1 3$table,seats,_1
        emit 'TABLE';table;'seats';seats
        seat_waiting ''
        i.0 return.
    case. 'STAFF' do.
        name =. 0{::args
        if. (<name)e.Servers do. fail name;'is already on duty' return. end.
        Servers =: Servers,<name
        ServerStats =: ServerStats,0 0 0
        emit 'STAFF';name
        i.0 return.
    case. 'SEAT' do.
        name =. 0{::args
        size =. 0".1{::args
        for_c. Checks do.
            c =. >c
            if. (-.'closed' cg c)*.name-:'party' cg c do.
                fail name;'is already seated at table';table_number 'table' cg c return.
            end.
        end.
        for_party. Waiting do.
            if. name-:0{::>party do. fail name;'is already waiting' return. end.
        end.
        if. -. +./(1{"1 Tables)>:size do. fail 'no table for party of';size return. end.
        if. 0=#Servers do. fail <'no server on duty' return. end.
        table =. select_table size
        if. table=_1 do.
            Waiting =: Waiting,<name;size;Time
            emit 'WAIT';name;size;'position';#Waiting
        else.
            check =. seat_party name;size;table
            server =. 'server' cg check{::Checks
            emit 'SEAT';name;size;'table';(table_number table);'server';server{::Servers
        end.
        i.0 return.
    case. 'CANCEL' do.
        name =. 0{::args
        index =. _1
        for_i. i.#Waiting do.
            if. name-:0{::i{::Waiting do. index =. i
                break. end.
        end.
        if. index=_1 do. fail name;'is not waiting' return. end.
        'party size joined' =. index{::Waiting
        Waiting =: ((i.#Waiting)-.index){Waiting
        emit 'CANCEL';name;size;'waited';Time-joined
        i.0 return.
    case. 'MOVE' do.
        'from to' =. 0".>args
        source =. (0{"1 Tables)i.from
        target =. (0{"1 Tables)i.to
        if. source=#Tables do. fail 'unknown table';from return. end.
        if. target=#Tables do. fail 'unknown table';to return. end.
        check =. 2{source{Tables
        if. check=_1 do. fail 'table';from;'is free' return. end.
        if. _1~:2{target{Tables do. fail 'table';to;'is occupied' return. end.
        c =. check{::Checks
        if. (1{target{Tables)<'size' cg c do. fail 'table';to;'is too small for';'party' cg c return. end.
        Tables =: ((2{.source{Tables),_1) source}Tables
        Tables =: ((2{.target{Tables),check) target}Tables
        check save_check ('table';target) cs c
        emit 'MOVE';('party' cg c);'table';from;'->';to
        seat_waiting ''
        i.0 return.
    case. 'MENU' do.
        'name station prep price course' =. args
        s =. STATIONS i.<station
        c =. COURSES i.<course
        if. s=4 do. fail 'unknown station';station return. end.
        if. c=4 do. fail 'unknown course';course return. end.
        index =. MenuNames i.<name
        row =. s,(0".prep),(cents price),c
        action =. 'UPDATE'
        if. index=#Menu do.
            MenuNames =: MenuNames,<name
            Menu =: Menu,1 6$row,_1,0
            action =. 'ADD'
        else. Menu =: (row,4}.index{Menu) index}Menu end.
        emit 'MENU';action;name;station;prep;price;course
        i.0 return.
    case. 'STOCK' do.
        name =. 0{::args
        index =. MenuNames i.<name
        if. index=#Menu do. fail 'unknown item';name return. end.
        stock =. 0".1{::args
        Menu =: (stock 4}index{Menu) index}Menu
        emit 'STOCK';name;stock
        i.0 return.
    case. 'HAPPY' do.
        'rate duration' =. 0".>args
        HappyRate =: rate
        HappyEnd =: Time+duration
        emit 'HAPPY';(percent HappyRate);'until';clock HappyEnd
        i.0 return.
    case. 'ITEMS' do.
        emit 'ITEMS';#Menu
        names =. /:MenuNames
        order =. (/:names{3{"1 Menu){names
        for_i. order do.
            'station prep price course stock served' =. i{Menu
            text =. '-'
            if. stock>:0 do. text =. number stock end.
            emit (course{::COURSES);(i{::MenuNames);(station{::STATIONS);prep;(money price);text
        end.
        i.0 return.
    case. 'TICK' do. tick 0".0{::args return.
    case. 'STATION' do.
        'station operation' =. args
        s =. STATIONS i.<station
        if. s=4 do. fail 'unknown station';station return. end.
        if. operation-:'DOWN' do.
            if. -.s{Up do. fail 'station';station;'is already down' return. end.
            Up =: 0 s}Up
        else.
            if. s{Up do. fail 'station';station;'is not down' return. end.
            Up =: 1 s}Up
            s cook_start Time
        end.
        emit 'STATION';station;operation
        i.0 return.
    case. 'KITCHEN' do. show_kitchen '' return.
    case. 'FLOOR' do. show_floor '' return.
    case. 'REPORT' do. show_report '' return.
    end.
    if. (<command)e.;:'RUSH REMAKE VOID COMP TRANSFER' do.
        id =. _1+0".0{::args
        if. (id<0)+.id>:#Orders do. fail 'unknown line';id+1 return. end.
        order =. id{::Orders
        label =. order_number id
        state =. 'state' og order
        check =. 'check' og order
        c =. check{::Checks
        item =. 'item' og order
        name =. item{::MenuNames
        station =. 'station' og order
        select. command
        case. 'RUSH' do.
            if. -.state-:'QUEUED' do. fail label;'is not queued' return. end.
            Queues =: (<id,(station{::Queues)-.id) station}Queues
            emit 'RUSH';label;station{::STATIONS
        case. 'REMAKE' do.
            if. 'closed' cg c do. fail label;'is on a closed check' return. end.
            if. -.(<state)e.;:'READY SERVED' do. fail label;'is not ready or served' return. end.
            id save_order ('state';'QUEUED') os ('fire';Time) os order
            Queues =: (<id,station{::Queues) station}Queues
            stats =. station{StationStats
            StationStats =: ((1+3{stats) 3}stats) station}StationStats
            emit 'REMAKE';label;name;station{::STATIONS
            station cook_start Time
        case. 'VOID' do.
            if. state-:'VOID' do. fail label;'is already void' return. end.
            if. 'started' og order do. fail label;'has already started' return. end.
            if. state-:'QUEUED' do. Queues =: (<(station{::Queues)-.id) station}Queues end.
            id save_order ('state';'VOID') os order
            row =. item{Menu
            if. (4{row)>:0 do. Menu =: ((('quantity' og order)+4{row) 4}row) item}Menu end.
            Voids =: Voids+1
            emit 'VOID';label;name;quantity_text 'quantity' og order
        case. 'COMP';'TRANSFER' do.
            reason =. modification_error id
            if. #reason do. fail reason return. end.
            if. command-:'COMP' do.
                if. #'comp' og order do. fail label;'is already comped' return. end.
                amount =. line_amount order
                reason =. 1{::args
                CompCount =: CompCount+1
                CompValue =: CompValue+amount
                id save_order ('comp';reason) os order
                emit 'COMP';label;name;(money amount);reason
            else.
                seat =. 0".1{::args
                table =. table_number 'table' cg c
                if. seat>'size' cg c do. fail 'seat';seat;'out of range for table';table return. end.
                old =. 'seat' og order
                if. old=seat do. fail label;'is already on seat';seat return. end.
                id save_order ('seat';seat) os order
                emit 'TRANSFER';label;'seat';old;'->';seat
            end.
        end.
        i.0 return.
    end.
    table =. 0".0{::args
    reason =. table_error table
    if. #reason do. fail reason return. end.
    t =. (0{"1 Tables)i.table
    check =. 2{t{Tables
    c =. check{::Checks
    select. command
    case. 'ORDER';'DISCOUNT' do.
        if. 'paid' cg c do. fail 'check for table';table;'is locked' return. end.
        if. command-:'DISCOUNT' do.
            rate =. 0".1{::args
            check save_check ('discount';rate) cs c
            emit 'DISCOUNT table';table;percent rate
        else.
            seat =. 0".1{::args
            if. seat>'size' cg c do. fail 'seat';seat;'out of range for table';table return. end.
            name =. 2{::args
            item =. MenuNames i.<name
            if. item=#Menu do. fail 'unknown item';name return. end.
            quantity =. 0".3{::args
            'station prep price course stock served' =. item{Menu
            if. (stock>:0)*.stock<quantity do. fail 'only';stock;name;'left' return. end.
            happy =. (course=0)*.Time<HappyEnd
            if. happy do. price =. price-HappyRate rounded price end.
            id =. #Orders
            order =. check;seat;item;quantity;station;prep;price;course;'ORDERED';'';0;0;0
            Orders =: Orders,<order
            line =. 'ORDER';(order_number id);'table';table;'seat';seat;name;(quantity_text quantity);money quantity*price
            if. happy do. line =. line,<'HAPPY' end.
            emit line
            if. stock>:0 do.
                stock =. stock-quantity
                Menu =: (stock 4}item{Menu) item}Menu
                if. stock=0 do. emit 'SOLDOUT';name end.
            end.
        end.
    case. 'FIRE' do.
        course =. 1{::args
        index =. COURSES i.<course
        if. index=4 do. fail 'unknown course';course return. end.
        candidates =. i.0
        earlier =. i.0
        for_i. check_lines check do.
            order =. i{::Orders
            if. -.('state' og order)-:'ORDERED' do. continue. end.
            cindex =. 'course' og order
            if. cindex=index do. candidates =. candidates,i end.
            if. (cindex>:1)*.cindex<index do. earlier =. earlier,cindex end.
        end.
        if. 0=#candidates do. fail 'nothing to fire for';course;'at table';table return. end.
        if. #earlier do. fail 'fire';((<./earlier){::COURSES);'first' return. end.
        for_i. candidates do.
            order =. i{::Orders
            station =. 'station' og order
            i save_order ('state';'QUEUED') os ('fire';Time) os order
            Queues =: (<(station{::Queues),i) station}Queues
        end.
        emit 'FIRE table';table;course;number_list candidates
        for_s. i.4 do. s cook_start Time end.
    case. 'SERVE' do.
        candidates =. i.0
        for_i. check_lines check do.
            if. ('state' og i{::Orders)-:'READY' do. candidates =. candidates,i end.
        end.
        if. 0=#candidates do. fail 'nothing ready for table';table return. end.
        for_i. candidates do.
            order =. i{::Orders
            i save_order ('state';'SERVED') os order
            item =. 'item' og order
            row =. item{Menu
            Menu =: ((('quantity' og order)+5{row) 5}row) item}Menu
        end.
        emit 'SERVE table';table;number_list candidates
    case. 'BILL' do. bill check
    case. 'STATUS' do. show_status check
    case. 'SPLIT' do.
        amounts =. check_amounts check
        due =. 5{amounts
        if. due=0 do. fail 'nothing to split for table';table return. end.
        if. (1{::args)-:'EVEN' do.
            count =. 0".2{::args
            if. count>'size' cg c do. fail 'cannot split table';table;count;'ways' return. end.
            emit 'SPLIT table';table;'EVEN';count;'due';money due
            for_i. i.count do. emit 'PAYER';(i+1);money (due floor_ratio count)+i<count|due end.
        else.
            if. 'paid' cg c do. fail 'table';table;'has payments' return. end.
            'seats subtotals' =. seat_subtotals check
            discounts =. ('discount' cg c) allocate subtotals
            after =. subtotals-discounts
            services =. (#seats)$0
            if. ('size' cg c)>:6 do. services =. 18 allocate after end.
            taxes =. 8 allocate after
            totals =. after+services+taxes
            emit 'SPLIT table';table;'BYSEAT total';money 4{amounts
            for_i. i.#seats do.
                emit 'SEAT';(i{seats);'subtotal';(money i{subtotals);'discount';(money i{discounts);'service';(money i{services);'tax';(money i{taxes);'total';money i{totals
            end.
        end.
    case. 'PAY';'CLOSE' do.
        if. command-:'PAY' do.
            method =. 1{::args
            index =. (;:'CASH CARD')i.<method
            if. index=2 do. fail 'unknown method';method return. end.
        end.
        count =. unserved check
        if. count do. fail 'table';table;'has';count;'unserved items' return. end.
        due =. 5{check_amounts check
        if. command-:'CLOSE' do.
            if. due do. fail 'table';table;'still owes';money due return. end.
            close_check check
        else.
            if. due=0 do. fail 'nothing to pay for table';table return. end.
            amount =. cents 2{::args
            applied =. due<.amount
            check save_check ('paid';applied+'paid' cg c) cs c
            Payments =: (applied+index{Payments) index}Payments
            if. amount<due do.
                emit 'PAY table';table;method;(money amount);'remaining';money due-amount
            else.
                change =. amount-due
                label =. 'change'
                if. index=1 do.
                    label =. 'tip'
                    Tips =: Tips+change
                    server =. 'server' cg c
                    stats =. server{ServerStats
                    ServerStats =: ((change+2{stats) 2}stats) server}ServerStats
                end.
                emit 'PAY table';table;method;(money amount);label;money change
                close_check check
            end.
        end.
    end.
    i.0
)
main =: 3 : 0
    lines =. <;._2 (1!:1 3),LF
    for_line. (0".0{::lines){.}.lines do. execute >line end.
    i.0
)
main ''
