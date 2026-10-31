load 'schema_io.ijs'
load 'bitstream.ijs'
load 'encoding.ijs'
load 'query.ijs'

intdiv =: 4 : '<.(x:x)%x:y'
integer =: 3 : 0
    text =. ":y
    '-'(I.text='_')}text
)
parse_integer =: 3 : 0
    text =. '_'(I.y='-')}y
    ".text
)
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do.
            result =. result,x
        end.
        result =. result,i{::y
    end.
    result
)
hexadecimal =: 3 : ',''0123456789abcdef''{~(2#16)#:y'
hex32 =: 3 : '''0123456789abcdef''{~(8#16)#:y'
order_values =: 4 : 0
    present =. I.-.is_null&>y
    nulls =. (i.#y)-.present
    if. x do.
        (present{~\:present{y),nulls
    else.
        nulls,present{~/:present{y
    end.
)
compare =: 4 : 0
    if. 2=3!:0 x do.
        if. x-:y do.
            0
        elseif. 0={./:(<x),<y do.
            _1
        else.
            1
        end.
    else.
        *x-y
    end.
)
statistics =: 3 : 0
    values =. y#~-.is_null&>y
    if. 0=#values do.
        0$a: return.
    end.
    ordered =. /:values
    (({.ordered){values),({:ordered){values
)
statistics_text =: 4 : 0
    if. 0=#y do.
        'stats none'
    else.
        'min ',(x value_text 0{::y),' max ',x value_text 1{::y
    end.
)
method_list =: 3 : ''',''join y{Methods'
column_line =: 3 : 0
    nullable =. (y{FileNullable){::'REQUIRED';'NULLABLE'
    'column ',(integer y),' ',(y{::FileNames),' ',((y{FileTypes){::Types),' ',nullable
)
build_page =: 4 : 0
    'kind nullable page_kind method dictionary' =. x
    values =. y
    if. page_kind=1 do.
        body =. ((<kind),(<0),<0$a:)encode_values values
        nulls =. 0
        bounds =. 0$a:
    else.
        present =. values#~-.is_null&>values
        nulls =. (#values)-#present
        bounds =. statistics values
        body =. i.0
        if. nullable do.
            levels =. 1 hybrid_encode -.is_null&>values
            body =. (write_integer #levels),levels
        end.
        body =. body,((<kind),(<method),<dictionary)encode_values present
    end.
    header =. page_kind,method,(uleb #values),(uleb nulls),uleb #body
    header =. header,(write_integer adler32 body),kind encode_statistics bounds
    header,body
)
build_chunk =: 4 : 0
    'kind nullable method' =. x
    values =. y
    pages =. 0$a:
    start =. 0
    while. start<#values do.
        pages =. pages,< (PageSize<.(#values)-start){.start}.values
        start =. start+PageSize
    end.
    dictionary =. 0$a:
    dictionary_pages =. 0
    if. method=1 do.
        for_page. pages do.
            proposed =. dictionary
            for_value. >page do.
                if. -.is_null >value do.
                    if. -.value e.proposed do.
                        proposed =. proposed,value
                    end.
                end.
            end.
            bytes =. ((<kind),(<0),<0$a:)encode_values proposed
            if. DictionaryLimit<#bytes do.
                break.
            end.
            dictionary =. proposed
            dictionary_pages =. dictionary_pages+1
        end.
        if. 0=#dictionary do.
            dictionary_pages =. 0
        end.
    end.
    data =. i.0
    if. dictionary_pages do.
        descriptor =. (<kind),(<nullable),(<1),(<0),<dictionary
        data =. descriptor build_page dictionary
    end.
    methods =. i.0
    for_i. i.#pages do.
        selected =. method
        if. method=1 do.
            selected =. i<dictionary_pages
        end.
        descriptor =. (<kind),(<nullable),(<0),(<selected),<dictionary
        data =. data,descriptor build_page i{::pages
        methods =. methods,selected
    end.
    fallback =. 0
    if. method=1 do.
        fallback =. (#pages)-dictionary_pages
    end.
    methods =. /:~~.methods
    nulls =. +/is_null&>values
    bounds =. statistics values
    (<data),(<methods),(<dictionary_pages>0),(<#pages),(<nulls),(<bounds),<fallback
)
build_file =: 3 : 0
    data =. a.i.'MPTC'
    groups =. 0$a:
    EncodingReport =: ,<'row_group,column,encoding,bytes,fallback_pages,chosen'
    first =. 0
    while. first<#Rows do.
        group_number =. #groups
        count =. RowGroupSize<.(#Rows)-first
        rows =. count{.first}.Rows
        chunks =. 0$a:
        for_column. i.#SchemaNames do.
            kind =. column{SchemaTypes
            nullable =. column{SchemaNullable
            values =. column{"1 rows
            methods =. kind{::Candidates
            candidates =. 0$a:
            sizes =. i.0
            for_method. methods do.
                chunk =. (kind,nullable,method)build_chunk values
                candidates =. candidates,<chunk
                sizes =. sizes,#0{::chunk
            end.
            requested =. column{::RequestedEncodings
            if. requested-:'AUTO' do.
                choice =. sizes i.<./sizes
            else.
                chosen_method =. Methods i.<requested
                choice =. methods i.chosen_method
                if. chosen_method=1 do.
                    if. -.2{::choice{::candidates do.
                        choice =. methods i.0
                    end.
                end.
            end.
            for_i. i.#methods do.
                method =. i{methods
                candidate =. i{::candidates
                selected =. (i=choice){::'no';'yes'
                fields =. (<integer group_number),(column{SchemaNames),(method{Methods)
                fields =. fields,(<integer i{sizes),(<integer 6{::candidate),<selected
                EncodingReport =: EncodingReport,<','join fields
            end.
            'bytes used has_dictionary pages nulls bounds fallback' =. choice{::candidates
            offset =. #data
            data =. data,bytes
            chunk =. (<offset),(<#bytes),(<used),(<has_dictionary),(<pages),(<nulls),<bounds
            chunks =. chunks,<chunk
        end.
        groups =. groups,<( <count),<chunks
        first =. first+count
    end.
    footer =. (uleb 1),uleb #SchemaNames
    for_column. i.#SchemaNames do.
        name =. column{::SchemaNames
        footer =. footer,(uleb #name),(a.i.name),(column{SchemaTypes),column{SchemaNullable
    end.
    footer =. footer,(uleb #Rows),uleb #groups
    for_group. groups do.
        'count chunks' =. >group
        footer =. footer,uleb count
        for_column. i.#chunks do.
            'offset size used has_dictionary pages nulls bounds' =. column{::chunks
            footer =. footer,(uleb offset),(uleb size),(uleb #used),used
            footer =. footer,has_dictionary,(uleb pages),(uleb nulls),(column{SchemaTypes)encode_statistics bounds
        end.
    end.
    data,footer,(write_integer #footer),a.i.'MPTC'
)
parse_file =: 3 : 0
    data =. y
    reader_begin data
    ReadPosition =: (#data)-8
    footer_size =. read_integer 0
    footer_offset =. ((#data)-8)-footer_size
    ReadPosition =: footer_offset
    version =. read_uleb ''
    count =. read_uleb ''
    names =. 0$a:
    types =. i.0
    nullable =. i.0
    for_i. i.count do.
        length =. read_uleb ''
        names =. names,<a.{~read_bytes length
        types =. types,read_byte ''
        nullable =. nullable,read_byte ''
    end.
    row_count =. read_uleb ''
    group_count =. read_uleb ''
    groups =. 0$a:
    first =. 0
    for_g. i.group_count do.
        rows =. read_uleb ''
        chunks =. 0$a:
        for_column. i.count do.
            offset =. read_uleb ''
            size =. read_uleb ''
            method_count =. read_uleb ''
            methods =. read_bytes method_count
            has_dictionary =. read_byte ''
            pages =. read_uleb ''
            nulls =. read_uleb ''
            bounds =. decode_statistics column{types
            chunk =. (<offset),(<size),(<methods),(<has_dictionary),(<pages),(<nulls),<bounds
            chunks =. chunks,<chunk
        end.
        groups =. groups,<( <rows),(<first),<chunks
        first =. first+rows
    end.
    for_g. i.#groups do.
        'rows first chunks' =. g{::groups
        for_column. i.count do.
            chunk =. column{::chunks
            offset =. 0{::chunk
            size =. 1{::chunk
            ReadPosition =: offset
            pages =. 0$a:
            while. ReadPosition<offset+size do.
                start =. ReadPosition
                page_kind =. read_byte ''
                method =. read_byte ''
                values =. read_uleb ''
                nulls =. read_uleb ''
                body_size =. read_uleb ''
                checksum =. read_integer 0
                bounds =. decode_statistics column{types
                header_size =. ReadPosition-start
                page =. (<start),(<page_kind),(<method),(<values),(<nulls),(<body_size),(<checksum)
                page =. page,(<bounds),(<header_size),(<ReadPosition),<header_size+body_size
                pages =. pages,<page
                ReadPosition =: ReadPosition+body_size
            end.
            dictionary_page =. 0$a:
            if. 3{::chunk do.
                dictionary_page =. 0{::pages
                pages =. }.pages
            end.
            chunk =. chunk,(<dictionary_page),<pages
            chunks =. (<chunk)column}chunks
        end.
        groups =. (<(<rows),(<first),<chunks)g}groups
    end.
    (<data),(<version),(<names),(<types),(<nullable),(<row_count),(<groups),(<footer_offset),<footer_size
)
use_file =: 3 : 0
    'FileData FileVersion FileNames FileTypes FileNullable FileRows FileGroups FooterOffset FooterSize' =: y
)
page_body =: 3 : '(5{::y){.(9{::y)}.FileData'
decode_dictionary =: 4 : 0
    reader_begin page_body y
    ((x{FileTypes),0,3{::y)decode_values 0$a:
)
decode_page =: 4 : 0
    'page dictionary' =. y
    reader_begin page_body page
    count =. 3{::page
    if. x{FileNullable do.
        length =. read_integer 0
        finish =. ReadPosition+length
        levels =. 1 hybrid_decode count
        ReadPosition =: finish
    else.
        levels =. count$1
    end.
    present =. +/levels=1
    values =. ((x{FileTypes),(2{::page),present)decode_values dictionary
    result =. count$<Null
    values (I.levels=1)}result
)

condition_leaves =: 3 : 0
    if. 0=#y do.
        0$a: return.
    end.
    operation =. 0{::y
    if. operation-:'NOT' do.
        condition_leaves 1{::y
    elseif. (<operation)e.;:'AND OR' do.
        (condition_leaves 1{::y),condition_leaves 2{::y
    else.
        ,<y
    end.
)
convert_condition =: 3 : 0
    if. 0=#y do.
        y return.
    end.
    operation =. 0{::y
    if. operation-:'NOT' do.
        (<operation),<convert_condition 1{::y
    elseif. (<operation)e.;:'AND OR' do.
        (<operation),(<convert_condition 1{::y),<convert_condition 2{::y
    else.
        column =. FileNames i.1{y
        values =. 0$a:
        for_literal. 2{::y do.
            'kind value' =. >literal
            if. 3=column{FileTypes do.
                value =. day_number value
            end.
            values =. values,<value
        end.
        (<operation),(<column),<values
    end.
)
item_header =: 4 : 0
    if. x-:'COLUMN' do.
        y
    elseif. x-:'COUNT_DISTINCT' do.
        'COUNT(DISTINCT ',y,')'
    else.
        x,'(',y,')'
    end.
)
check_query =: 3 : 0
    'items condition group order descending limit' =. y
    if. items-:,<'*' do.
        items =. 0$a:
        for_name. FileNames do.
            items =. items,<(<'COLUMN'),name
        end.
    end.
    leaves =. condition_leaves condition
    names =. 0$a:
    for_item. items do.
        name =. 1{::>item
        if. -.name-:'*' do.
            names =. names,<name
        end.
    end.
    condition_names =. 0$a:
    for_leaf. leaves do.
        name =. 1{::>leaf
        names =. names,<name
        condition_names =. condition_names,<name
    end.
    if. #group do.
        names =. names,<group
    end.
    if. #order do.
        names =. names,<order
    end.
    if. -. *./names e.FileNames do.
        'unknown_column' return.
    end.
    for_leaf. leaves do.
        leaf =. >leaf
        column =. FileNames i.1{leaf
        expected =. column{FileTypes
        if. expected=3 do.
            expected =. 1
        end.
        for_literal. 2{::leaf do.
            if. expected~:0{::>literal do.
                'type_mismatch' return.
            end.
        end.
    end.
    aggregate =. 0<#group
    for_item. items do.
        'operation name' =. >item
        aggregate =. aggregate+.-.operation-:'COLUMN'
        if. (<operation)e.;:'SUM AVG' do.
            column =. FileNames i.<name
            if. 0~:column{FileTypes do.
                'bad_aggregate' return.
            end.
        end.
    end.
    if. aggregate do.
        for_item. items do.
            'operation name' =. >item
            if. (operation-:'COLUMN')*.-.name-:group do.
                'not_grouped' return.
            end.
        end.
        if. #order do.
            'bad_order' return.
        end.
    end.
    PlanItems =: 0$a:
    PlanHeaders =: 0$a:
    for_item. items do.
        'operation name' =. >item
        column =. _1
        if. -.name-:'*' do.
            column =. FileNames i.<name
        end.
        PlanItems =: PlanItems,<operation;column
        PlanHeaders =: PlanHeaders,<operation item_header name
    end.
    PlanCondition =: convert_condition condition
    PlanGroup =: _1
    PlanOrder =: _1
    if. #group do.
        PlanGroup =: FileNames i.<group
    end.
    if. #order do.
        PlanOrder =: FileNames i.<order
    end.
    PlanDescending =: descending
    PlanLimit =: limit
    PlanAggregate =: aggregate
    PlanNeeded =: /:~~.FileNames i.names
    PlanConditionColumns =: /:~~.FileNames i.condition_names
    ''
)
logical_not =: 3 : 0
    if. y=2 do.
        2
    else.
        -.y
    end.
)
logical_pair =: 4 : 0
    if. x-:'AND' do.
        if. 0 e.y do.
            0
        elseif. 2 e.y do.
            2
        else.
            1
        end.
    else.
        if. 1 e.y do.
            1
        elseif. 2 e.y do.
            2
        else.
            0
        end.
    end.
)
compare_value =: 4 : 0
    'value literals' =. y
    null =. is_null value
    if. x-:'IS_NULL' do.
        null return.
    elseif. x-:'IS_NOT_NULL' do.
        -.null return.
    elseif. null do.
        2 return.
    end.
    if. x-:'BETWEEN' do.
        ((value compare 0{::literals)>:0)*.(value compare 1{::literals)<:0 return.
    elseif. x-:'IN' do.
        for_literal. literals do.
            if. 0=value compare >literal do.
                1 return.
            end.
        end.
        0 return.
    end.
    difference =. value compare 0{::literals
    select. x
    case. '=' do. difference=0
    case. '<>' do. difference~:0
    case. '<' do. difference<0
    case. '<=' do. difference<:0
    case. '>' do. difference>0
    case. '>=' do. difference>:0
    end.
)
evaluate =: 4 : 0
    if. 0=#x do.
        1 return.
    end.
    operation =. 0{::x
    if. operation-:'NOT' do.
        logical_not (1{::x)evaluate y
    elseif. (<operation)e.;:'AND OR' do.
        first =. (1{::x)evaluate y
        second =. (2{::x)evaluate y
        operation logical_pair first,second
    else.
        value =. (1{::x){::y
        operation compare_value (<value),<2{::x
    end.
)
range_possibilities =: 4 : 0
    'low high literals' =. y
    if. x-:'BETWEEN' do.
        first =. 0{::literals
        last =. 1{::literals
        can_true =. ((low compare last)<:0)*.((high compare first)>:0)*.(first compare last)<:0
        can_false =. ((low compare first)<0)+.(high compare last)>0
        can_true,can_false return.
    elseif. x-:'IN' do.
        can_true =. 0
        contains =. 0
        for_literal. literals do.
            value =. >literal
            can_true =. can_true+.((low compare value)<:0)*.(high compare value)>:0
            contains =. contains+.0=low compare value
        end.
        can_false =. -.((0=low compare high)*.contains)
        can_true,can_false return.
    end.
    value =. 0{::literals
    lower =. low compare value
    upper =. high compare value
    between =. (lower<:0)*.upper>:0
    equal =. (lower=0)*.upper=0
    select. x
    case. '=' do. between,-.equal
    case. '<>' do. (-.equal),between
    case. '<' do. (lower<0),upper>:0
    case. '<=' do. (lower<:0),upper>0
    case. '>' do. (upper>0),lower<:0
    case. '>=' do. (upper>:0),lower<0
    end.
)
zone_values =: 4 : 0
    operation =. 0{::y
    if. operation-:'NOT' do.
        ~.logical_not"0 x zone_values 1{::y return.
    elseif. (<operation)e.;:'AND OR' do.
        first =. x zone_values 1{::y
        second =. x zone_values 2{::y
        result =. i.0
        for_a. first do.
            for_b. second do.
                result =. result,operation logical_pair a,b
            end.
        end.
        ~.result return.
    end.
    'bounds nulls count' =. (1{::y){::x
    values =. i.0
    if. (<operation)e.;:'IS_NULL IS_NOT_NULL' do.
        if. nulls>0 do.
            values =. values,operation-:'IS_NULL'
        end.
        if. nulls<count do.
            values =. values,operation-:'IS_NOT_NULL'
        end.
        ~.values return.
    end.
    if. nulls>0 do.
        values =. ,2
    end.
    if. #bounds do.
        'can_true can_false' =. operation range_possibilities bounds,<2{::y
        if. can_true do.
            values =. values,1
        end.
        if. can_false do.
            values =. values,0
        end.
    end.
    values
)

cell_equal =: 4 : 0
    if. (is_null x)+.is_null y do.
        (is_null x)*.is_null y
    else.
        0=x compare y
    end.
)
page_description =: 4 : 0
    'group column number' =. x
    page =. y
    label =. integer number
    if. number=_1 do.
        label =. 'dict'
    end.
    line =. 'page ',(integer group),' ',(column{::FileNames),' ',label,' offset ',integer 0{::page
    line =. line,' header ',(integer 8{::page),' body ',(integer 5{::page),' checksum ',hex32 6{::page
    if. number=_1 do.
        line,' entries ',integer 3{::page
    else.
        line =. line,' encoding ',((2{::page){::Methods),' values ',(integer 3{::page),' nulls ',integer 4{::page
        line,' ',(column{FileTypes)statistics_text 7{::page
    end.
)
verify_and_describe =: 3 : 0
    line =. 'file bytes ',(integer #FileData),' footer_offset ',(integer FooterOffset),' footer_bytes ',integer FooterSize
    lines =. ,<line
    line =. 'table version ',(integer FileVersion),' rows ',(integer FileRows),' columns ',integer #FileNames
    lines =. lines,<line,' row_groups ',integer #FileGroups
    lines =. lines,column_line&.>i.#FileNames
    summaries =. ((#FileNames),3)$0
    summary_methods =. (#FileNames)$<i.0
    cells =. 0
    nulls =. 0
    mismatches =. 0
    checksum_errors =. 0
    for_g. i.#FileGroups do.
        'count first chunks' =. g{::FileGroups
        size =. 0
        for_chunk. chunks do.
            size =. size+1{::>chunk
        end.
        line =. 'row_group ',(integer g),' rows ',(integer count),' first_row ',(integer first),' bytes ',integer size
        lines =. lines,<line
        for_column. i.#FileNames do.
            chunk =. column{::chunks
            'offset size methods has_dictionary page_count chunk_nulls bounds dictionary_page pages' =. chunk
            present =. has_dictionary{::'no';'yes'
            line =. 'chunk ',(integer g),' ',(column{::FileNames),' offset ',(integer offset),' size ',integer size
            line =. line,' encodings ',(method_list methods),' dictionary ',present,' pages ',(integer page_count),' nulls ',integer chunk_nulls
            lines =. lines,<line,' ',(column{FileTypes)statistics_text bounds
            summaries =. ((column{summaries)+size,page_count,has_dictionary)column}summaries
            summary_methods =. (<~.(column{::summary_methods),methods)column}summary_methods
            dictionary =. 0$a:
            if. has_dictionary do.
                checksum_errors =. checksum_errors+(6{::dictionary_page)~:adler32 page_body dictionary_page
                dictionary =. column decode_dictionary dictionary_page
                lines =. lines,<(g,column,_1)page_description dictionary_page
            end.
            row =. first
            for_number. i.#pages do.
                page =. number{::pages
                checksum_errors =. checksum_errors+(6{::page)~:adler32 page_body page
                lines =. lines,<(g,column,number)page_description page
                values =. column decode_page(<page),<dictionary
                for_value. values do.
                    value =. >value
                    cells =. cells+1
                    nulls =. nulls+is_null value
                    expected =. >(<row,column){Rows
                    mismatches =. mismatches+-.value cell_equal expected
                    row =. row+1
                end.
            end.
        end.
    end.
    for_column. i.#FileNames do.
        'bytes pages dictionaries' =. column{summaries
        methods =. /:~column{::summary_methods
        line =. 'summary ',(column{::FileNames),' bytes ',(integer bytes),' data_pages ',integer pages
        lines =. lines,<line,' dictionary_pages ',(integer dictionaries),' encodings ',method_list methods
    end.
    status =. ((mismatches+checksum_errors)=0){::'failed';'ok'
    line =. 'roundtrip ',status,' cells ',(integer cells),' nulls ',(integer nulls),' mismatches ',integer mismatches
    lines,<line,' checksum_errors ',integer checksum_errors
)
ScanNames =: ;:'row_groups_read row_groups_skipped pages_read pages_skipped pages_unneeded dictionary_pages_read bytes_read rows_scanned rows_matched'
counts_text =: 3 : 0
    parts =. 0$a:
    for_i. i.#ScanNames do.
        parts =. parts,<(i{::ScanNames),' ',integer i{y
    end.
    ' 'join parts
)
read_scan_page =: 3 : 0
    'group column page_number' =. y
    chunks =. 2{::group{::FileGroups
    chunk =. column{::chunks
    page =. page_number{::8{::chunk
    dictionary =. 0$a:
    if. 1=2{::page do.
        index =. column+(#FileNames)*group
        if. -.index{DictionariesRead do.
            dictionary_page =. 7{::chunk
            dictionary =. column decode_dictionary dictionary_page
            Dictionaries =: (<dictionary)index}Dictionaries
            DictionariesRead =: 1 index}DictionariesRead
            ScanCounts =: (1+5{ScanCounts)5}ScanCounts
            ScanCounts =: ((6{ScanCounts)+10{::dictionary_page)6}ScanCounts
        end.
        dictionary =. index{::Dictionaries
    end.
    ScanCounts =: (1+2{ScanCounts)2}ScanCounts
    ScanCounts =: ((6{ScanCounts)+10{::page)6}ScanCounts
    column decode_page(<page),<dictionary
)
scan =: 3 : 0
    columns =. #FileNames
    ScanCounts =: 9$0
    Dictionaries =: (columns*#FileGroups)$<0$a:
    DictionariesRead =: (columns*#FileGroups)$0
    records =. 0$a:
    matched =. (0,columns)$a:
    remaining =. PlanNeeded-.PlanConditionColumns
    for_g. i.#FileGroups do.
        'count first chunks' =. g{::FileGroups
        zones =. columns$<0$a:
        for_column. PlanConditionColumns do.
            chunk =. column{::chunks
            zone =. (6 5{chunk),<count
            zones =. (<zone)column}zones
        end.
        if. #PlanCondition do.
            if. -.1 e.zones zone_values PlanCondition do.
                ScanCounts =: (1+1{ScanCounts)1}ScanCounts
                records =. records,<''
                continue.
            end.
        end.
        ScanCounts =: (1+0{ScanCounts)0}ScanCounts
        if. 0=#PlanNeeded do.
            ScanCounts =: ((7{ScanCounts)+count)7}ScanCounts
            matched =. matched,(count,columns)$<Null
            records =. records,<'-'
            continue.
        end.
        page_count =. 4{::0{::chunks
        record =. ''
        for_p. i.page_count do.
            zones =. columns$<0$a:
            for_column. PlanConditionColumns do.
                chunk =. column{::chunks
                page =. p{::8{::chunk
                zone =. 7 4 3{page
                zones =. (<zone)column}zones
            end.
            if. #PlanCondition do.
                if. -.1 e.zones zone_values PlanCondition do.
                    ScanCounts =: ((3{ScanCounts)+#PlanNeeded)3}ScanCounts
                    record =. record,'s'
                    continue.
                end.
            end.
            page =. p{::8{::0{::chunks
            count =. 3{::page
            ScanCounts =: ((7{ScanCounts)+count)7}ScanCounts
            rows =. (count,columns)$<Null
            for_column. PlanConditionColumns do.
                values =. read_scan_page g,column,p
                for_row. i.count do.
                    rows =. (row{values)(<row,column)}rows
                end.
            end.
            selected =. i.0
            for_row. i.count do.
                if. 1=PlanCondition evaluate row{rows do.
                    selected =. selected,row
                end.
            end.
            if. (0=#selected)*.0<#remaining do.
                ScanCounts =: ((4{ScanCounts)+#remaining)4}ScanCounts
                record =. record,'u'
                continue.
            end.
            for_column. remaining do.
                values =. read_scan_page g,column,p
                for_row. i.count do.
                    rows =. (row{values)(<row,column)}rows
                end.
            end.
            matched =. matched,selected{rows
            record =. record,'r'
        end.
        records =. records,<record
    end.
    ScanCounts =: (#matched)8}ScanCounts
    (<matched),<records
)
aggregate_item =: 4 : 0
    'operation column key' =. x
    rows =. y
    if. operation-:'COLUMN' do.
        (column{FileTypes)value_text key return.
    elseif. (operation-:'COUNT')*.column=_1 do.
        integer #rows return.
    end.
    values =. column{"1 rows
    values =. values#~-.is_null&>values
    if. operation-:'COUNT' do.
        integer #values return.
    elseif. operation-:'COUNT_DISTINCT' do.
        integer #~.values return.
    elseif. 0=#values do.
        'NULL' return.
    end.
    if. operation-:'SUM' do.
        integer +/>values return.
    elseif. operation-:'AVG' do.
        total =. +/>values
        count =. #values
        factor =. total+.count
        numerator =. total intdiv factor
        denominator =. count intdiv factor
        if. denominator=1 do.
            integer numerator
        else.
            (integer numerator),'/',integer denominator
        end.
        return.
    end.
    sorted =. (/:values){values
    if. operation-:'MIN' do.
        value =. 0{::sorted
    else.
        value =. _1{::sorted
    end.
    (column{FileTypes)value_text value
)
build_result =: 3 : 0
    matched =. y
    output =. 0$a:
    if. -.PlanAggregate do.
        kind =. 'rows'
        arranged =. matched
        if. PlanOrder~:_1 do.
            order =. PlanDescending order_values PlanOrder{"1 matched
            arranged =. order{matched
        end.
        for_row. arranged do.
            fields =. 0$a:
            for_item. PlanItems do.
                'operation column' =. >item
                fields =. fields,<(column{FileTypes)value_text column{::row
            end.
            output =. output,<','join fields
        end.
    else.
        if. PlanGroup=_1 do.
            kind =. 'aggregate'
            groups =. ,<matched
            keys =. ,<Null
        else.
            kind =. 'grouped'
            key_values =. PlanGroup{"1 matched
            keys =. ~.key_values
            keys =. (0 order_values keys){keys
            groups =. 0$a:
            for_key. keys do.
                indices =. i.0
                for_i. i.#matched do.
                    if. (>key)cell_equal i{::key_values do.
                        indices =. indices,i
                    end.
                end.
                groups =. groups,<indices{matched
            end.
        end.
        for_g. i.#groups do.
            key =. g{::keys
            rows =. g{::groups
            fields =. 0$a:
            for_item. PlanItems do.
                'operation column' =. >item
                descriptor =. (<operation),(<column),<key
                fields =. fields,<descriptor aggregate_item rows
            end.
            output =. output,<','join fields
        end.
    end.
    if. PlanLimit do.
        output =. (PlanLimit<.#output){.output
    end.
    (<kind),(<#matched),<output
)
execute_queries =: 3 : 0
    results =. 0$a:
    statistic_lines =. 0$a:
    totals =. 9$0
    errors =. 0
    checks_ok =. 0
    for_number. 1+i.#Queries do.
        error =. check_query parse_query (number-1){::Queries
        if. #error do.
            line =. 'query ',(integer number),' error ',error
            results =. results,<line
            statistic_lines =. statistic_lines,<line
            errors =. errors+1
            continue.
        end.
        'matched records' =. scan ''
        result =. build_result matched
        selected =. i.0
        for_i. i.#Rows do.
            if. 1=PlanCondition evaluate i{Rows do.
                selected =. selected,i
            end.
        end.
        reference =. build_result selected{Rows
        check =. 'mismatch'
        if. result-:reference do.
            check =. 'ok'
            checks_ok =. checks_ok+1
        end.
        'kind count output' =. result
        line =. 'query ',(integer number),' ',kind,' matched ',(integer count),' output ',integer #output
        results =. results,(<line),(<'columns ',','join PlanHeaders),output
        needed =. '-'
        if. #PlanNeeded do.
            needed =. ','join PlanNeeded{FileNames
        end.
        line =. 'query ',(integer number),' columns ',needed,' ',(counts_text ScanCounts),' check ',check
        statistic_lines =. statistic_lines,<line
        for_g. i.#records do.
            record =. g{::records
            detail =. 'skipped'
            if. #record do.
                detail =. 'pages ',record
            end.
            statistic_lines =. statistic_lines,<'query ',(integer number),' row_group ',(integer g),' ',detail
        end.
        totals =. totals+ScanCounts
    end.
    line =. 'total queries ',(integer #Queries),' errors ',(integer errors),' ',counts_text totals
    statistic_lines =. statistic_lines,<line,' checks_ok ',integer checks_ok
    (<results),<statistic_lines
)

recover =: 3 : 0
    use_file parse_file y
    columns =. #FileNames
    recovered_rows =. (FileRows,columns)$<UnknownCell
    line =. 'file bytes ',(integer #FileData),' rows ',(integer FileRows),' columns ',integer columns
    lines =. (<line,' row_groups ',integer #FileGroups),column_line&.>i.columns
    pages_examined =. 0
    damaged_count =. 0
    lost_pages =. 0
    lost_cells =. 0
    for_g. i.#FileGroups do.
        'count first chunks' =. g{::FileGroups
        for_column. i.columns do.
            chunk =. column{::chunks
            dictionary =. 0$a:
            dictionary_damaged =. 0
            pages =. 8{::chunk
            numbers =. i.#pages
            if. 3{::chunk do.
                pages =. (7{chunk),pages
                numbers =. _1,numbers
            end.
            row_number =. first
            for_i. i.#pages do.
                page =. i{::pages
                number =. i{numbers
                pages_examined =. pages_examined+1
                checksum =. adler32 page_body page
                damaged =. checksum~:6{::page
                label =. integer number
                if. number=_1 do.
                    label =. 'dict'
                end.
                if. damaged do.
                    damaged_count =. damaged_count+1
                    line =. 'damaged ',(integer g),' ',(column{::FileNames),' ',label,' offset ',integer 0{::page
                    lines =. lines,<line,' stored ',(hex32 6{::page),' computed ',hex32 checksum
                end.
                if. number=_1 do.
                    dictionary_damaged =. damaged
                    if. -.damaged do.
                        dictionary =. column decode_dictionary page
                    end.
                    continue.
                end.
                reason =. ''
                if. damaged do.
                    reason =. 'checksum'
                elseif. ((2{::page)=1)*.dictionary_damaged do.
                    reason =. 'dictionary'
                end.
                if. #reason do.
                    lost_pages =. lost_pages+1
                    lost_cells =. lost_cells+3{::page
                    line =. 'lost ',(integer g),' ',(column{::FileNames),' ',label,' rows ',integer 3{::page
                    lines =. lines,<line,' reason ',reason
                else.
                    values =. column decode_page(<page),<dictionary
                    for_offset. i.#values do.
                        position =. <(row_number+offset),column
                        recovered_rows =. (offset{values)position}recovered_rows
                    end.
                end.
                row_number =. row_number+3{::page
            end.
        end.
    end.
    line =. 'summary pages ',(integer pages_examined),' damaged ',(integer damaged_count),' lost_pages ',integer lost_pages
    line =. line,' lost_cells ',(integer lost_cells),' recovered_cells ',integer (FileRows*columns)-lost_cells
    lines =. lines,<line
    recovered =. ,<','join FileNames
    for_row. recovered_rows do.
        fields =. 0$a:
        for_column. i.columns do.
            value =. column{::row
            if. 32=3!:0 value do.
                text =. '?'
            elseif. is_null value do.
                text =. ''
            else.
                text =. (column{FileTypes)value_text value
            end.
            fields =. fields,<text
        end.
        recovered =. recovered,<','join fields
    end.
    (<lines),<recovered
)
run =: 3 : 0
    read_inputs ''
    data =. build_file ''
    use_file parse_file data
    metadata =. verify_and_describe ''
    'results query_statistics' =. execute_queries ''
    'recovery recovered' =. recover DamagedBytes
    hex_lines =. 0$a:
    start =. 0
    while. start<#data do.
        hex_lines =. hex_lines,<hexadecimal (32<.(#data)-start){.start}.data
        start =. start+32
    end.
    try.
        1!:5 <'output'
    catch.
    end.
    'file.hex'write_lines hex_lines
    'metadata.txt'write_lines metadata
    'encoding_report.csv'write_lines EncodingReport
    'query_results.txt'write_lines results
    'query_stats.txt'write_lines query_statistics
    'recovery.txt'write_lines recovery
    'recovered.csv'write_lines recovered
)
run ''
