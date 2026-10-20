NB. Field values are boxed sequences; singular fields contain zero or one value.
LF =: 10{a.
Quote =: 34{a.
Slash =: 92{a.
Digits =: '0123456789'
Letters =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
Hex =: '0123456789abcdef'
Base64 =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
IntegerTypes =: ;:'uint32 uint64 sint32 sint64 fixed32 sfixed32 fixed64'
EnumNames =: Enums =: MessageNames =: Messages =: 0$a:
Error =: ''
split =: 4 : '<;._1 x,y'
number =: 3 : ',''0'' 8!:2 y'
integer =: 3 : 'if. ''-''={.y do. -x:0".}.y else. x:0".y end.'
emit =: 3 : 'Output =: Output,<y'
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
fail =: 3 : 0
    Error =: y
    throw.
)
wire_error =: 4 : 'fail x,'' at byte '',number y'
literal_error =: 4 : 'fail x,'' at column '',number y'
hex_digits =: 3 : 'if. #y do. ,Hex{~16 16#:y else. '''' end.'
hex_text =: 3 : 'if. #y do. hex_digits y else. ''-'' end.'
byte_text =: 3 : '''<'',(hex_digits y),''>'''
valid_hex =: 3 : '(y-:''-'')+.((0<#y)*.(0=2|#y)*.*./y e.Hex)'
unhex =: 3 : 'if. (0=#y)+.y-:''-'' do. i.0 else. 16#._2]\Hex i.y end.'
is_message =: 3 : '(<y)e.MessageNames'
is_enum =: 3 : '(<y)e.EnumNames'
wire_type =: 3 : 0
    if. (<y)e.;:'fixed32 sfixed32' do. 5
    elseif. y-:'fixed64' do. 1
    elseif. ((<y)e.;:'string bytes')+.is_message y do. 2
    else. 0 end.
)
bounds =: 3 : 0
    select. y
    case. 'uint32';'fixed32' do. 0x 4294967295x
    case. 'uint64';'fixed64' do. 0x 9007199254740991x
    case. 'sint32';'sfixed32' do. _2147483648x 2147483647x
    case. 'sint64' do. _4503599627370496x 4503599627370495x
    end.
)
in_range =: 4 : 0
    'lo hi' =. bounds x
    (lo<:y)*.y<:hi
)
zigzag =: 3 : 'if. y<0 do. <:-2*y else. 2*y end.'
unzigzag =: 3 : 'if. 2|y do. ->.y%2 else. <.y%2 end.'
varint =: 3 : 0
    result =. i.0
    while. y>:128 do.
        result =. result,128+128|y
        y =. <.y%128
    end.
    result,y
)
base64 =: 3 : 0
    result =. ''
    for_i. i.>. (#y)%3 do.
        part =. (3*i)}.y
        count =. 3<.#part
        codes =. 64 64 64 64#:256#.3{.part
        result =. result,((count+1){.Base64{~codes),(3-count)#'='
    end.
    result
)
quote_bytes =: 4 : 0
    result =. ,Quote
    for_byte. y do.
        select. byte
        case. 34;92 do. result =. result,Slash,byte{a.
        case. 10 do. result =. result,Slash,'n'
        case. 9 do. result =. result,Slash,'t'
        case. do.
            if. (byte>:32)*.byte<127 do. result =. result,byte{a.
            else.
                prefix =. 'x'
                if. x do. prefix =. 'u00' end.
                result =. result,Slash,prefix,hex_digits ,byte
            end.
        end.
    end.
    result,Quote
)
camel =: 3 : 0
    result =. ''
    upper =. 0
    for_c. y do.
        if. c='_' do. upper =. 1 continue. end.
        if. upper*.c e.'abcdefghijklmnopqrstuvwxyz' do. c =. (32-~a.i.c){a. end.
        result =. result,c
        upper =. 0
    end.
    result
)

read_schema =: 3 : 0
    while. 1 do.
        line =. 1!:1[3
        if. line-:'END SCHEMA' do. break. end.
        words =. ' ' split line
        kind =. 0{::words
        name =. 1{::words
        enum =. kind-:'ENUM'
        table =. (0,2+5*-.enum)$a:
        while. 1 do.
            line =. 1!:1[3
            if. line-:'END' do. break. end.
            words =. ' ' split line
            if. enum do.
                table =. table,((1{words),<integer 2{::words)
            else.
                required =. repeated =. packed =. 0
                group =. ''
                if. 4<#words do.
                    modifier =. 4{::words
                    required =. modifier-:'REQUIRED'
                    repeated =. modifier-:'REPEATED'
                    packed =. repeated*.6=#words
                    if. modifier-:'ONEOF' do. group =. 5{::words end.
                end.
                row =. (integer 1{::words);(2{::words);(3{::words);required;repeated;packed;<group
                table =. table,row
            end.
        end.
        if. enum do.
            EnumNames =: EnumNames,<name
            Enums =: Enums,<(/:>1{"1 table){table
        else.
            MessageNames =: MessageNames,<name
            Messages =: Messages,<(/:>0{"1 table){table
        end.
    end.
)
empty_message =: 3 : 0
    values =. (#y{::Messages)#<0$a:
    (<values),<0 3$a:
)
render_value =: 4 : 0
    'type json' =. x
    if. is_message type do. render_message (MessageNames i.<type);y;<json
    elseif. type-:'string' do. json quote_bytes y
    elseif. type-:'bytes' do.
        if. json do. Quote,(base64 y),Quote else. byte_text y end.
    elseif. type-:'bool' do. y{::'false';'true'
    elseif. is_enum type do.
        table =. (EnumNames i.<type){::Enums
        text =. 0{::((>1{"1 table)i.y){table
        if. json do. Quote,text,Quote else. text end.
    else.
        text =. number y
        if. json*.(<type)e.;:'uint64 sint64 fixed64' do. Quote,text,Quote else. text end.
    end.
)
render_sequence =: 4 : 0
    separator =. ', '
    if. 1{::x do. separator =. ',' end.
    parts =. 0$a:
    for_value. y do. parts =. parts,<x render_value >value end.
    '[',(separator join parts),']'
)
render_message =: 3 : 0
    'type message json' =. y
    fields =. type{::Messages
    values =. 0{::message
    parts =. 0$a:
    for_i. i.#fields do.
        sequence =. i{::values
        if. 0=#sequence do. continue. end.
        field =. i{fields
        name =. 2{::field
        context =. (1{::field);json
        if. 4{::field do. text =. context render_sequence sequence
        else. text =. context render_value 0{::sequence end.
        if. json do. parts =. parts,<Quote,(camel name),Quote,':',text
        else. parts =. parts,<name,': ',text end.
    end.
    separator =. ', '
    if. json do. separator =. ',' end.
    '{',(separator join parts),'}'
)
encode_value =: 4 : 0
    wire =. wire_type x
    if. wire=0 do.
        if. (<x)e.;:'sint32 sint64' do. y =. zigzag y end.
        varint y
    elseif. wire e.1 5 do.
        width =. 4+4*wire=1
        |.(width#256)#: (256x^width)|y
    else.
        if. is_message x do. y =. encode_message (MessageNames i.<x);<y end.
        (varint #y),y
    end.
)
encode_field =: 4 : 0
    'number type name required repeated packed group' =. x
    if. 0=#y do. i.0 return. end.
    result =. i.0
    if. packed do.
        for_value. y do. result =. result,type encode_value >value end.
        (varint 2+8*number),(varint #result),result
    else.
        tag =. varint (wire_type type)+8*number
        for_value. y do. result =. result,tag,type encode_value >value end.
        result
    end.
)
encode_message =: 3 : 0
    'type message' =. y
    fields =. type{::Messages
    'values unknown' =. message
    result =. i.0
    for_i. i.#fields do. result =. result,(i{fields) encode_field i{::values end.
    for_record. unknown do.
        'number wire raw' =. record
        result =. result,varint wire+8*number
        if. wire=0 do. result =. result,varint raw
        elseif. wire=2 do. result =. result,(varint #raw),raw
        else. result =. result,raw end.
    end.
    result
)

replace_field =: 4 : 0
    'type index incoming' =. x
    fields =. type{::Messages
    values =. 0{::y
    group =. 6{::index{fields
    if. (#group)*.0<#incoming do.
        for_i. (I.(6{"1 fields)=<group)-.index do.
            values =. (<0$a:) i}values
        end.
    end.
    values =. (<incoming) index}values
    (<values),1{y
)
apply_field =: 4 : 0
    'type index incoming' =. x
    field =. index{type{::Messages
    previous =. index{::0{::y
    child =. 1{::field
    if. 4{::field do.
        incoming =. previous,incoming
    elseif. (is_message child)*.(0<#previous)*.0<#incoming do.
        incoming =. ,<merge_messages (MessageNames i.<child);(0{::previous);<0{::incoming
    end.
    (type;index;<incoming) replace_field y
)
merge_messages =: 3 : 0
    'type first second' =. y
    values =. 0{::second
    for_i. i.#values do.
        incoming =. i{::values
        if. #incoming do. first =. (type;i;<incoming) apply_field first end.
    end.
    ({.first),<(1{::first),1{::second
)
check_required =: 3 : 0
    'type message prefix' =. y
    fields =. type{::Messages
    values =. 0{::message
    for_i. i.#fields do.
        field =. i{fields
        sequence =. i{::values
        path =. prefix,2{::field
        if. (3{::field)*.0=#sequence do. fail 'missing required field ',path end.
        child =. 1{::field
        if. is_message child do.
            for_j. i.#sequence do.
                next =. path
                if. 4{::field do. next =. next,'[',(number j),']' end.
                check_required (MessageNames i.<child);(j{::sequence);<next,'.'
            end.
        end.
    end.
    i.0
)
read_varint =: 3 : 0
    start =. Position
    value =. 0x
    factor =. 1x
    for_i. i.8 do.
        if. Position>:y do. 'truncated varint' wire_error start end.
        byte =. Position{Data
        Position =: >:Position
        value =. value+factor*128|byte
        if. byte<128 do.
            if. value>:9007199254740992x do. 'varint too large' wire_error start end.
            value return.
        end.
        if. i=7 do. 'varint too long' wire_error start end.
        factor =. 128*factor
    end.
)
read_raw =: 4 : 0
    if. x=0 do. read_varint y return. end.
    start =. Position
    if. x=2 do.
        count =. read_varint y
        if. (Position+count)>y do. 'length past end' wire_error start end.
    else.
        count =. 4+4*x=1
        if. count>y-Position do.
            ('truncated ',(x=1){::'i32';'i64') wire_error start
        end.
    end.
    result =. count{.Position}.Data
    Position =: Position+count
    result
)
convert_value =: 4 : 0
    'type offset start finish depth' =. x
    if. (<type)e.IntegerTypes do.
        if. (wire_type type)e.1 5 do. y =. 256x#.|.y end.
        if. (<type)e.;:'sint32 sint64' do. y =. unzigzag y end.
        if. (type-:'sfixed32')*.y>:2147483648x do. y =. y-4294967296x end.
        if. -.type in_range y do. 'value out of range' wire_error offset end.
        y
    elseif. type-:'bool' do.
        if. -.y e.0 1 do. 'value out of range' wire_error offset end.
        y
    elseif. is_enum type do.
        table =. (EnumNames i.<type){::Enums
        if. -.y e.>1{"1 table do. 'unknown enum number' wire_error offset end.
        y
    elseif. type-:'string' do.
        bad =. I.y>:128
        if. #bad do. 'invalid string' wire_error start+{.bad end.
        y
    elseif. type-:'bytes' do. y
    else.
        Position =: start
        read_message (MessageNames i.<type);finish;<depth
    end.
)
wire_name =: 3 : '(0 1 2 5 i.y){::''varint'';''i64'';''len'';''i32'''
raw_text =: 4 : 'if. x=0 do. number y else. byte_text y end.'
read_message =: 3 : 0
    'type finish depth' =. y
    message =. empty_message type
    fields =. type{::Messages
    numbers =. >0{"1 fields
    while. Position<finish do.
        offset =. Position
        tag =. read_varint finish
        num =. <.tag%8
        wire =. 8|tag
        if. num=0 do. 'invalid field number' wire_error offset end.
        if. -.wire e.0 1 2 5 do. 'invalid wire type' wire_error offset end.
        index =. numbers i.num
        known =. index<#fields
        packed =. 0
        name =. '?'
        if. known do.
            field =. index{fields
            child =. 1{::field
            name =. 2{::field
            expected =. wire_type child
            packed =. (4{::field)*.(expected~:2)*.wire=2
            if. (-.packed)*.wire~:expected do. 'wire type mismatch' wire_error offset end.
        end.
        value_offset =. Position
        raw =. wire read_raw finish
        after =. Position
        start =. after-#raw
        head =. ((2*depth)#' '),(number offset),' ',(number num),' ',name,' ',wire_name wire
        if. wire=2 do. head =. head,' ',number #raw end.
        if. -.known do.
            if. Explain do. emit head,' ',wire raw_text raw
            else.
                unknown =. (1{::message),num;wire;<raw
                message =. ({.message),<unknown
            end.
            continue.
        end.
        if. packed do.
            Position =: start
            incoming =. 0$a:
            while. Position<after do.
                at =. Position
                element =. expected read_raw after
                incoming =. incoming,<(child;at;at;after;<depth+1) convert_value element
            end.
            if. Explain do.
                head =. head,' packed'
                for_value. incoming do. head =. head,' ',(child;0) render_value >value end.
                emit head
            end.
        else.
            if. Explain*.is_message child do. emit head end.
            value =. (child;value_offset;start;after;<depth+1) convert_value raw
            incoming =. ,<value
            if. Explain*.-.is_message child do. emit head,' ',(child;0) render_value value end.
        end.
        if. -.Explain do. message =. (type;index;<incoming) apply_field message end.
    end.
    message
)
decode =: 4 : 0
    Data =: y
    Position =: 0
    Explain =: 0
    message =. read_message x;(#Data);<0
    check_required x;message;<''
    message
)

tokenize =: 3 : 0
    Tokens =: 0 3$a:
    i =. 0
    while. i<#y do.
        c =. i{y
        if. c=' ' do. i =. >:i continue. end.
        column =. >:i
        if. c e.'{}[]:,' do.
            kind =. ,c
            value =. ''
            i =. >:i
        elseif. c=Quote do.
            kind =. 'string'
            value =. i.0
            i =. >:i
            closed =. 0
            while. i<#y do.
                c =. i{y
                i =. >:i
                if. c=Quote do. closed =. 1 break. end.
                if. c=Slash do.
                    if. i=#y do. 'syntax error' literal_error column end.
                    c =. i{y
                    i =. >:i
                    if. c e.Quote,Slash do. byte =. a.i.c
                    elseif. c='n' do. byte =. 10
                    elseif. c='t' do. byte =. 9
                    elseif. c='x' do.
                        digits =. 2{.i}.y
                        if. ((i+2)>#y)+.-.*./digits e.Hex do. 'syntax error' literal_error column end.
                        byte =. 16#.Hex i.digits
                        if. byte>:128 do. 'syntax error' literal_error column end.
                        i =. i+2
                    else. 'syntax error' literal_error column end.
                else. byte =. a.i.c end.
                value =. value,byte
            end.
            if. -.closed do. 'syntax error' literal_error column end.
        elseif. c='<' do.
            kind =. 'bytes'
            tail =. (i+1)}.y
            finish =. tail i.'>'
            if. finish=#tail do. 'syntax error' literal_error column end.
            digits =. finish{.tail
            if. (2|#digits)+.-.*./digits e.Hex do. 'syntax error' literal_error column end.
            value =. unhex digits
            i =. i+finish+2
        elseif. c e.'-',Digits do.
            kind =. 'integer'
            start =. i
            if. c='-' do. i =. >:i end.
            first =. i
            while. i<#y do.
                if. -.(i{y)e.Digits do. break. end.
                i =. >:i
            end.
            if. i=first do. 'syntax error' literal_error column end.
            value =. integer (i-start){.start}.y
        elseif. c e.Letters,'_' do.
            kind =. 'name'
            start =. i
            while. i<#y do.
                if. -.(i{y)e.Letters,Digits,'_' do. break. end.
                i =. >:i
            end.
            value =. (i-start){.start}.y
        else. 'syntax error' literal_error column end.
        Tokens =: Tokens,kind;value;<column
    end.
    Tokens =: Tokens,'end';'';<1+#y
    TokenAt =: 0
)
peek =: 3 : '0{::TokenAt{Tokens'
token_value =: 3 : '1{::TokenAt{Tokens'
column =: 3 : '2{::TokenAt{Tokens'
advance =: 3 : 'TokenAt =: >:TokenAt'
expect =: 3 : 0
    if. -.y-:peek '' do. 'syntax error' literal_error column '' end.
    advance ''
)
shape =: 3 : 0
    kind =. peek ''
    if. (<kind)e.'}';']';':';',';'end' do. ''
    elseif. kind-:'name' do.
        if. (<token_value '')e.;:'true false' do. 'boolean' else. 'name' end.
    else. kind end.
)
parse_element =: 3 : 0
    type =. y
    actual =. shape ''
    if. 0=#actual do. 'syntax error' literal_error column '' end.
    if. (<type)e.IntegerTypes do. wanted =. 'integer'
    elseif. type-:'bool' do. wanted =. 'boolean'
    elseif. is_enum type do. wanted =. 'name'
    elseif. is_message type do. wanted =. '{'
    else. wanted =. type end.
    if. -.wanted-:actual do. 'type mismatch' literal_error column '' end.
    if. wanted-:'{' do. parse_message MessageNames i.<type return. end.
    value =. token_value ''
    at =. column ''
    advance ''
    if. wanted-:'integer' do.
        if. -.type in_range value do. 'out of range' literal_error at end.
    elseif. wanted-:'boolean' do. value =. value-:'true'
    elseif. wanted-:'name' do.
        table =. (EnumNames i.<type){::Enums
        index =. (0{"1 table)i.<value
        if. index=#table do. 'unknown enum value' literal_error at end.
        value =. 1{::index{table
    end.
    value
)
parse_field =: 3 : 0
    field =. y
    if. -.4{::field do. ,<parse_element 1{::field return. end.
    actual =. shape ''
    if. 0=#actual do. 'syntax error' literal_error column '' end.
    if. -.actual-:'[' do. 'type mismatch' literal_error column '' end.
    advance ''
    sequence =. 0$a:
    if. -.']'-:peek '' do.
        while. 1 do.
            sequence =. sequence,<parse_element 1{::field
            if. -.','-:peek '' do. break. end.
            advance ''
        end.
    end.
    expect ']'
    sequence
)
parse_message =: 3 : 0
    type =. y
    fields =. type{::Messages
    message =. empty_message type
    values =. 0{::message
    seen =. (#fields)#0
    expect '{'
    if. -.'}'-:peek '' do.
        while. 1 do.
            if. -.'name'-:peek '' do. 'syntax error' literal_error column '' end.
            name =. token_value ''
            index =. (2{"1 fields)i.<name
            if. index=#fields do. 'unknown field' literal_error column '' end.
            if. index{seen do. 'duplicate field' literal_error column '' end.
            field =. index{fields
            group =. 6{::field
            if. #group do.
                if. +./seen*.(6{"1 fields)=<group do. 'oneof conflict' literal_error column '' end.
            end.
            seen =. 1 index}seen
            advance ''
            expect ':'
            sequence =. parse_field field
            values =. (<sequence) index}values
            if. -.','-:peek '' do. break. end.
            advance ''
        end.
    end.
    closing =. column ''
    expect '}'
    missing =. I.(>3{"1 fields)*.-.seen
    if. #missing do. ('missing required field ',2{::{.missing{fields) literal_error closing end.
    (<values),1{message
)
parse_literal =: 4 : 0
    tokenize y
    result =. parse_message x
    if. -.'end'-:peek '' do. 'syntax error' literal_error column '' end.
    result
)

parse_path =: 4 : 0
    type =. x
    if. (0=#y)+.({.y)='.' do. fail 'invalid path' end.
    if. (({:y)='.')+.+./'..' E.y do. fail 'invalid path' end.
    segments =. '.' split y
    path =. 0 2$0
    for_i. i.#segments do.
        segment =. i{::segments
        bracket =. segment i.'['
        index =. _1
        name =. bracket{.segment
        if. bracket<#segment do.
            if. ']'~:{:segment do. fail 'invalid path' end.
            digits =. }: (bracket+1)}.segment
            if. (0=#digits)+.(6<#digits)+.-.*./digits e.Digits do. fail 'invalid path' end.
            index =. 0".digits
        end.
        fields =. type{::Messages
        at =. (2{"1 fields)i.<name
        if. at=#fields do. fail 'invalid path' end.
        field =. at{fields
        if. (index>:0)*.-.4{::field do. fail 'invalid path' end.
        path =. path,at,index
        if. i<((#segments)-1) do.
            child =. 1{::field
            if. (-.is_message child)+.((4{::field)*.index<0) do. fail 'invalid path' end.
            type =. MessageNames i.<child
        end.
    end.
    path
)
path_field =: 4 : 0
    type =. x
    for_segment. y do.
        field =. ({.segment){type{::Messages
        type =. MessageNames i.<1{::field
    end.
    field
)
get_path =: 3 : 0
    'type message path' =. y
    'at index' =. {.path
    field =. at{type{::Messages
    sequence =. at{::0{::message
    if. index>:0 do.
        if. index>:#sequence do. 0$a: return. end.
        sequence =. ,index{sequence
    end.
    if. (1=#path)+.0=#sequence do. sequence return. end.
    get_path (MessageNames i.<1{::field);(0{::sequence);<}.path
)
change_path =: 3 : 0
    'type message path patch incoming' =. y
    'at index' =. {.path
    field =. at{type{::Messages
    sequence =. at{::0{::message
    if. 1=#path do.
        if. index<0 do.
            if. patch do. sequence =. incoming else. sequence =. 0$a: end.
        elseif. index>:#sequence do.
            if. patch do. fail 'index out of range' end.
        elseif. patch do. sequence =. ({.incoming) index}sequence
        else. sequence =. (index~:i.#sequence)#sequence end.
    else.
        child =. MessageNames i.<1{::field
        if. index<0 do.
            index =. 0
            if. 0=#sequence do.
                if. -.patch do. message return. end.
                sequence =. ,<empty_message child
            end.
        elseif. index>:#sequence do.
            if. patch do. fail 'index out of range' else. message return. end.
        end.
        value =. change_path child;(index{::sequence);(}.path);patch;<incoming
        sequence =. (<value) index}sequence
    end.
    (type;at;<sequence) replace_field message
)
text_contents =: 3 : 0
    'type message depth' =. y
    fields =. type{::Messages
    'values unknown' =. message
    indent =. (2*depth)#' '
    for_i. i.#fields do.
        field =. i{fields
        name =. 2{::field
        child =. 1{::field
        for_value. i{::values do.
            if. is_message child do.
                emit indent,name,' {'
                text_contents (MessageNames i.<child);(>value);<depth+1
                emit indent,'}'
            else. emit indent,name,': ',(child;0) render_value >value end.
        end.
    end.
    for_record. unknown do.
        'num wire raw' =. record
        emit indent,(number num),': ',(wire_name wire),' ',wire raw_text raw
    end.
)
text_message =: 4 : 0
    emit (x{::MessageNames),' {'
    text_contents x;y;<1
    emit '}'
)
schema_fields =: 3 : 0
    chain =. y
    fields =. ({:chain){::Messages
    for_field. fields do.
        'num type name required repeated packed group' =. field
        kind =. ''
        if. required do. kind =. 'required '
        elseif. packed do. kind =. 'repeated packed '
        elseif. repeated do. kind =. 'repeated '
        elseif. #group do. kind =. 'oneof ',group,' ' end.
        text =. ((2*#chain)#' '),(number num),' ',name,': ',kind,type
        if. is_enum type do.
            parts =. 0$a:
            for_pair. (EnumNames i.<type){::Enums do.
                parts =. parts,<(0{::pair),'=',number 1{::pair
            end.
            text =. text,' (',(', ' join parts),')'
        end.
        child =. MessageNames i.<type
        if. child e.chain do. text =. text,' (recursive)' end.
        emit text
        if. (child<#Messages)*.-.child e.chain do. schema_fields chain,child end.
    end.
)
differences =: 3 : 0
    'type first second prefix' =. y
    fields =. type{::Messages
    for_i. i.#fields do.
        field =. i{fields
        child =. 1{::field
        a =. i{::0{::first
        b =. i{::0{::second
        for_j. i.(#a)>.#b do.
            path =. prefix,2{::field
            if. 4{::field do. path =. path,'[',(number j),']' end.
            both =. (j<#a)*.j<#b
            if. both*.is_message child do.
                differences (MessageNames i.<child);(j{::a);(j{::b);<path,'.'
            else.
                same =. 0
                if. both do. same =. (j{a)-:j{b end.
                if. -.same do.
                    left =. right =. '(none)'
                    if. j<#a do. left =. (child;0) render_value j{::a end.
                    if. j<#b do. right =. (child;0) render_value j{::b end.
                    emit path,': ',left,' -> ',right
                end.
            end.
        end.
    end.
)

Commands =: ;:'VARINT ZIGZAG SCHEMA ENCODE SIZE DECODE LITERAL JSON CANON EXPLAIN GET PATCH CLEAR MERGE DIFF'
valid_number =: 3 : 0
    if. '-'={.y do. y =. }.y end.
    (0<#y)*.(18>:#y)*.*./y e.Digits
)
execute =: 3 : 0
    Output =: 0$a:
    words =. ' ' split y
    command =. 0{::words
    if. -.(<command)e.Commands do. fail 'unknown command' end.
    count =. #words
    if. (<command)e.;:'ENCODE SIZE' do. valid =. count>:3
    elseif. command-:'PATCH' do. valid =. count>:5
    elseif. (<command)e.;:'VARINT ZIGZAG SCHEMA' do. valid =. count=2
    elseif. (<command)e.;:'GET CLEAR MERGE DIFF' do. valid =. count=4
    else. valid =. count=3 end.
    if. -.valid do. fail 'wrong number of arguments' end.
    if. (<command)e.;:'VARINT ZIGZAG' do.
        argument =. 1{::words
        if. -.valid_number argument do. fail 'invalid number' end.
        value =. integer argument
        type =. 'uint64'
        if. command-:'ZIGZAG' do. type =. 'sint64' end.
        if. -.type in_range value do. fail 'invalid number' end.
        prefix =. ''
        if. command-:'ZIGZAG' do.
            value =. zigzag value
            prefix =. (number value),' '
        end.
        emit prefix,hex_text varint value
        Output return.
    end.
    type =. MessageNames i.1{words
    if. type=#MessageNames do. fail 'unknown message type' end.
    if. -. (<command)e.;:'SCHEMA ENCODE SIZE' do.
        if. -.valid_hex 2{::words do. fail 'invalid hex' end.
        if. (<command)e.;:'MERGE DIFF' do.
            if. -.valid_hex 3{::words do. fail 'invalid hex' end.
        end.
        bytes =. unhex 2{::words
    end.
    if. (<command)e.;:'GET PATCH CLEAR' do. path =. type parse_path 3{::words end.
    select. command
    case. 'SCHEMA' do.
        emit type{::MessageNames
        schema_fields ,type
    case. 'ENCODE';'SIZE' do.
        literal =. (1+1{I.y=' ')}.y
        message =. type parse_literal literal
        encoded =. encode_message type;<message
        if. command-:'ENCODE' do. emit hex_text encoded
        else.
            text =. number #encoded
            fields =. type{::Messages
            values =. 0{::message
            for_i. i.#fields do.
                if. #i{::values do.
                    text =. text,' ',(2{::i{fields),'=',number #(i{fields) encode_field i{::values
                end.
            end.
            emit text
        end.
    case. 'EXPLAIN' do.
        Data =: bytes
        Position =: 0
        Explain =: 1
        read_message type;(#Data);<0
        if. 0=#bytes do. emit '(empty)' end.
    case. 'MERGE' do. type text_message type decode bytes,unhex 3{::words
    case. 'DIFF' do.
        try. first =. type decode bytes
        catcht. fail Error,' in first' end.
        try. second =. type decode unhex 3{::words
        catcht. fail Error,' in second' end.
        differences type;first;second;<''
        if. 0=#Output do. emit 'SAME' end.
    case. do.
        message =. type decode bytes
        select. command
        case. 'DECODE' do. type text_message message
        case. 'LITERAL' do. emit render_message type;message;<0
        case. 'JSON' do. emit render_message type;message;<1
        case. 'CANON' do. emit hex_text encode_message type;<message
        case. 'GET' do.
            field =. type path_field path
            sequence =. get_path type;message;<path
            if. (4{::field)*.0>{:{:path do.
                emit ((1{::field);0) render_sequence sequence
            elseif. #sequence do. emit ((1{::field);0) render_value 0{::sequence
            else. emit '(none)' end.
        case. 'PATCH';'CLEAR' do.
            patch =. command-:'PATCH'
            incoming =. 0$a:
            if. patch do.
                tokenize (1+3{I.y=' ')}.y
                field =. type path_field path
                if. (4{::field)*.0>{:{:path do. incoming =. parse_field field
                else. incoming =. ,<parse_element 1{::field end.
                if. -.'end'-:peek '' do. 'syntax error' literal_error column '' end.
            end.
            message =. change_path type;message;path;patch;<incoming
            check_required type;message;<''
            emit hex_text encode_message type;<message
        end.
    end.
    Output
)
main =: 3 : 0
    read_schema ''
    count =. 0".1!:1[3
    for_i. i.count do.
        line =. 1!:1[3
        try. lines =. execute line
        catcht. lines =. <'ERROR ',Error end.
        for_text. lines do. ((>text),LF) 1!:2[4 end.
    end.
)
main ''
2!:55[0
