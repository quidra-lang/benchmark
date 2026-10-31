read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
read_params =: 3 : 0
    fields =. 0$a:
    for_line. read_lines 'params.txt' do. fields =. fields,<}. ' ' split >line end.
    ReferenceDay =: num 0{::0{::fields
    SnapshotDay =: num 0{::1{::fields
    OutcomeDays =: num 0{::2{::fields
    'KMin KMax' =: num&>3{::fields
    Methods =: 4{::fields
    Restarts =: num 0{::5{::fields
    MaxIterations =: num 0{::6{::fields
    Seed =: num 0{::7{::fields
    Subsamples =: num 0{::8{::fields
    SubsamplePercent =: num 0{::9{::fields
    OutlierSD =: decimal 0{::10{::fields
    OverdueFactor =: num 0{::11{::fields
    OrderBins =: num&>12{::fields
    TopCategories =: num 0{::13{::fields
    TopCustomers =: num 0{::14{::fields
    PeriodDays =: num 0{::15{::fields
    Periods =: num 0{::16{::fields
    i.0
)
read_transactions =: 3 : 0
    ValidRows =: 0$a:
    FileCustomers =: 0$a:
    seen =. 0$a:
    lines =. }.read_lines 'transactions.csv'
    RowCount =: #lines
    Duplicates =: FreeRows =: 0
    for_box. lines do.
        line =. >box
        fields =. ',' split line
        FileCustomers =: FileCustomers,0{fields
        amount =. signed_num 4{::fields
        if. (<line)e.seen do. Duplicates =: Duplicates+1
        elseif. amount=0 do. FreeRows =: FreeRows+1
        else.
            row =. (0{fields),(<num 1{::fields),(2{fields),(3{fields),<amount
            ValidRows =: ValidRows,<row
        end.
        seen =. seen,<line
    end.
    FileCustomers =: ascii_sort ~.FileCustomers
    i.0
)
group_orders =: 3 : 0
    'first last' =. y
    ids =. orders =. 0$a:
    for_index. i.#ValidRows do.
        row =. index{::ValidRows
        day =. 1{::row
        if. (day<first)+.day>last do. continue. end.
        id =. 2{::row
        position =. ids i.<id
        if. position=#ids do.
            ids =. ids,<id
            orders =. orders,<(<id),(0{row),(<day),(<0),<0$0
        end.
        order =. position{::orders
        order =. (<day<.2{::order) 2}order
        order =. (<(3{::order)+4{::row) 3}order
        order =. (<(4{::order),index) 4}order
        orders =. (<order) position}orders
    end.
    orders
)
orders_by_customer =: 3 : 0
    table =. empty_table ''
    for_box. y do.
        order =. >box
        id =. 1{::order
        group =. 0$a:
        if. id has_key table do. group =. id get_key table end.
        group =. group,<order
        table =. ((<id),<group) put_key table
    end.
    table
)
