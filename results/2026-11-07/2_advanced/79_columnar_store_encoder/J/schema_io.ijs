Types =: ;:'INT STRING BOOL DATE'
Null =: i.0
UnknownCell =: <'?'
is_null =: 3 : '(0=#y)*.2~:3!:0 y'
leap_year =: 3 : '(0=4|y)*.((0~:100|y)+.0=400|y)'
days_before_year =: 3 : 0
    previous =. y-1
    (365*previous)+(previous intdiv 4)+(previous intdiv 400)-previous intdiv 100
)
month_lengths =: 3 : '31,(28+leap_year y),31 30 31 30 31 31 30 31 30 31'
day_number =: 3 : 0
    year =. ".4{.y
    month =. ".2{.5}.y
    day =. ".2{.8}.y
    (days_before_year year)+(+/ (month-1){.month_lengths year)+day-719163
)
date_text =: 3 : 0
    ordinal =. y+719162
    year =. 1950
    while. ordinal>:days_before_year year+1 do.
        year =. year+1
    end.
    remaining =. ordinal-days_before_year year
    months =. month_lengths year
    month =. 0
    while. remaining>:month{months do.
        remaining =. remaining-month{months
        month =. month+1
    end.
    (integer year),'-',(_2{.'00',integer month+1),'-',_2{.'00',integer remaining+1
)
parse_value =: 4 : 0
    if. 0=#y do.
        Null return.
    end.
    select. x
    case. 0 do. parse_integer y
    case. 1 do. y
    case. 2 do. y-:'true'
    case. 3 do. day_number y
    end.
)
value_text =: 4 : 0
    if. is_null y do.
        'NULL' return.
    end.
    select. x
    case. 0 do. integer y
    case. 1 do. y
    case. 2 do. y{::'false';'true'
    case. 3 do. date_text y
    end.
)
read_lines =: 3 : '<;._2 (1!:1 <y)'
split_words =: 3 : '<;._1 '' '',y'
split_csv =: 3 : '<;._1 '','',y'
read_inputs =: 3 : 0
    SchemaNames =: 0$a:
    SchemaTypes =: i.0
    SchemaNullable =: i.0
    for_line. read_lines 'input/schema.txt' do.
        'name kind nullable' =. split_words >line
        SchemaNames =: SchemaNames,<name
        SchemaTypes =: SchemaTypes,Types i.<kind
        SchemaNullable =: SchemaNullable,nullable-:'NULLABLE'
    end.
    columns =. #SchemaNames
    Rows =: (0,columns)$a:
    lines =. }.read_lines 'input/table.csv'
    for_line. lines do.
        fields =. split_csv >line
        row =. 0$a:
        for_i. i.columns do.
            row =. row,<(i{SchemaTypes)parse_value i{::fields
        end.
        Rows =: Rows,row
    end.
    RequestedEncodings =: 0$a:
    for_line. read_lines 'input/options.txt' do.
        fields =. split_words >line
        select. 0{::fields
        case. 'row_group_size' do. RowGroupSize =: ".1{::fields
        case. 'page_size' do. PageSize =: ".1{::fields
        case. 'dictionary_limit' do. DictionaryLimit =: ".1{::fields
        case. 'encoding' do. RequestedEncodings =: RequestedEncodings,2{fields
        end.
    end.
    Queries =: read_lines 'input/queries.txt'
    hex =. ;read_lines 'input/damaged.hex'
    DamagedBytes =: 16#.((2 intdiv~#hex),2)$'0123456789abcdef'i.hex
)
write_lines =: 4 : 0
    text =. ''
    if. #y do.
        text =. (LF join y),LF
    end.
    text 1!:2 <'output/',x
)
