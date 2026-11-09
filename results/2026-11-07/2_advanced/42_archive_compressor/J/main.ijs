load 'bitio.ijs'
load 'lzw.ijs'
load 'lz77.ijs'
load 'huffman.ijs'
load 'arith_coder.ijs'
Methods =: ;:'STORE LZW LZ77 LZH ARITH'
Statuses =: ;:'ok repaired checksum error unsupported truncated bad_header'
read_lines =: 3 : '<;._2 (1!:1 <y)'
read_bytes =: 3 : 'x:a.i.1!:1 <y'
words =: 3 : '<;._1 '' '',y'
num =: 3 : 'x:0".y'
text =: 3 : 0
    value =. ":y
    '-'(I.value='_')}value
)
join =: 4 : 0
    result =. ''
    for_index. i.#y do.
        if. index do.
            result =. result,x
        end.
        result =. result,index{::y
    end.
    result
)
integers =: 3 : ''' ''join text&.>y'
ratio =: 4 : 0
    if. y>0 do.
        text (1000*x)intdiv y
    else.
        '-'
    end.
)
method_name =: 3 : 0
    if. y<5 do.
        y{::Methods
    else.
        '#',text y
    end.
)
adler =: 3 : 0
    first =. 1x
    second =. 0x
    for_value. y do.
        first =. 65521|first+value
        second =. 65521|second+first
    end.
    (second*65536)+first
)
modular_power =: 4 : 0
    base =. x
    exponent =. y
    result =. 1x
    while. exponent>0 do.
        if. 2|exponent do.
            result =. 65521|result*base
        end.
        base =. 65521|base*base
        exponent =. exponent intdiv 2
    end.
    result
)
repair_byte =: 3 : 0
    'data stored computed' =. y
    da =. 65521|(65536|stored)-65536|computed
    db =. 65521|(stored intdiv 65536)-computed intdiv 65536
    if. (da>:1)*.da<:255 do.
        delta =. da
    elseif. (da>:65266)*.da<:65520 do.
        delta =. da-65521
    else.
        0$a: return.
    end.
    inverse =. (65521|delta)modular_power 65519
    distance =. 65521|db*inverse
    if. (distance<1)+.distance>#data do.
        0$a: return.
    end.
    position =. (#data)-distance
    before =. position{data
    after =. before+delta
    if. (after<0)+.after>255 do.
        0$a: return.
    end.
    repaired =. after position}data
    if. stored~:adler repaired do.
        0$a: return.
    end.
    (<repaired),<position,before,after
)
fixed_lengths =: 3 : 0
    width =. bits y-1
    shorter =. (2x^width)-y
    width-(i.y)<shorter
)
write_table =: 4 : 0
    writer =. x
    lengths =. y
    symbol =. 0
    while. symbol<#lengths do.
        length =. symbol{lengths
        if. length>0 do.
            writer =. writer write_bits length,4
            symbol =. symbol+1
        else.
            run =. 1
            while. (run<256)*.(symbol+run)<#lengths do.
                if. 0~:(symbol+run){lengths do.
                    break.
                end.
                run =. run+1
            end.
            writer =. writer write_bits 0,4
            writer =. writer write_bits (run-1),8
            symbol =. symbol+run
        end.
    end.
    writer
)
read_table =: 4 : 0
    reader =. x
    count =. y
    lengths =. i.0
    while. (#lengths)<count do.
        'reader length' =. reader read_bits 4,0
        if. reader_failed reader do.
            (<reader),<i.0 return.
        end.
        if. length>0 do.
            lengths =. lengths,length
        else.
            'reader run' =. reader read_bits 8,0
            if. reader_failed reader do.
                (<reader),<i.0 return.
            end.
            run =. run+1
            if. ((#lengths)+run)>count do.
                reader =. (<'bad_table')3}reader
                reader =. (<0)4}reader
                (<reader),<i.0 return.
            end.
            lengths =. lengths,run#0
        end.
    end.
    positive =. lengths#~lengths>0
    valid =. 1
    if. 1=#positive do.
        valid =. 1={.positive
    elseif. 2<:#positive do.
        valid =. 32768=+/2x^15-positive
    end.
    if. -.valid do.
        reader =. (<'bad_table')3}reader
        reader =. (<0)4}reader
    end.
    (<reader),<lengths
)
symbol_table =: 3 : '(<y),(<canonical_codes y),< >./y'
read_symbol =: 4 : 0
    'lengths codes maximum' =. x
    'reader position' =. y
    if. maximum=0 do.
        reader =. (<'bad_code')3}reader
        reader =. (<position)4}reader
        (<reader),<_1 return.
    end.
    code =. 0x
    for_width. 1+i.maximum do.
        'reader next_bit' =. reader read_bits 1,position
        if. reader_failed reader do.
            (<reader),<_1 return.
        end.
        code =. (2*code)+next_bit
        found =. I.(lengths=width)*.codes=code
        if. #found do.
            (<reader),<{.found return.
        end.
    end.
    reader =. (<'bad_code')3}reader
    reader =. (<position)4}reader
    (<reader),<_1
)
encode_lz =: 3 : 0
    'tokens offset_bits length_bits' =. y
    writer =. 0$0
    for_token. tokens do.
        'literal distance length' =. token
        if. literal>:0 do.
            writer =. writer write_bits 0,1
            writer =. writer write_bits literal,8
        else.
            writer =. writer write_bits 1,1
            writer =. writer write_bits (distance-1),offset_bits
            writer =. writer write_bits (length-3),length_bits
        end.
    end.
    finish_bits writer
)
decode_lz =: 3 : 0
    'payload original offset_bits length_bits' =. y
    reader =. new_reader (<payload),<0
    output =. i.0x
    while. (#output)<original do.
        'reader flag' =. reader read_bits 1,#output
        if. reader_failed reader do.
            reader_failure reader return.
        end.
        if. flag=0 do.
            'reader literal' =. reader read_bits 8,#output
            if. reader_failed reader do.
                reader_failure reader return.
            end.
            output =. output,literal
        else.
            'reader distance' =. reader read_bits offset_bits,#output
            'reader length' =. reader read_bits length_bits,#output
            if. reader_failed reader do.
                reader_failure reader return.
            end.
            copied =. copy_match (<output),(<distance+1),(<length+3),<original
            if. decoded_failed copied do.
                copied return.
            end.
            output =. decoded_data copied
        end.
    end.
    decode_ok output
)
write_tokens =: 4 : 0
    'tokens literal_lengths distance_lengths' =. y
    writer =. x
    literal_codes =. canonical_codes literal_lengths
    distance_codes =. canonical_codes distance_lengths
    for_token. tokens do.
        'literal distance length' =. token
        if. literal>:0 do.
            writer =. writer write_bits (literal{literal_codes),literal{literal_lengths
        else.
            symbol =. 256+length-3
            writer =. writer write_bits (symbol{literal_codes),symbol{literal_lengths
            offset =. distance-1
            slot =. bits offset
            writer =. writer write_bits (slot{distance_codes),slot{distance_lengths
            if. slot>:2 do.
                writer =. writer write_bits (offset-2x^slot-1),slot-1
            end.
        end.
    end.
    writer
)
encode_lzh =: 3 : 0
    'tokens offset_bits length_bits maximum' =. y
    literal_count =. 256+2x^length_bits
    distance_count =. offset_bits+1
    literal_frequencies =. literal_count$0
    distance_frequencies =. distance_count$0
    for_token. tokens do.
        'literal distance length' =. token
        symbol =. literal
        if. literal<0 do.
            symbol =. 256+length-3
        end.
        literal_frequencies =. (1+symbol{literal_frequencies)symbol}literal_frequencies
        if. distance>0 do.
            slot =. bits distance-1
            distance_frequencies =. (1+slot{distance_frequencies)slot}distance_frequencies
        end.
    end.
    'literal_lengths literal_halvings' =. maximum limited_lengths literal_frequencies
    'distance_lengths distance_halvings' =. maximum limited_lengths distance_frequencies
    fixed =. (0$0)write_bits 0,1
    fixed =. fixed write_tokens (<tokens),(<fixed_lengths literal_count),<fixed_lengths distance_count
    fixed_bits =. (#fixed)-1
    dynamic =. (0$0)write_bits 1,1
    dynamic =. dynamic write_table literal_lengths
    dynamic =. dynamic write_table distance_lengths
    table_bits =. (#dynamic)-1
    dynamic =. dynamic write_tokens (<tokens),(<literal_lengths),<distance_lengths
    code_bits =. ((#dynamic)-1)-table_bits
    use_fixed =. fixed_bits<:table_bits+code_bits
    stats =. fixed_bits,table_bits,code_bits,(literal_halvings+distance_halvings),(+/literal_lengths>0),(>./literal_lengths),(+/distance_lengths>0),(>./distance_lengths),-.use_fixed
    writer =. dynamic
    if. use_fixed do.
        writer =. fixed
    end.
    (<finish_bits writer),(<stats),<distance_frequencies
)
decode_lzh =: 3 : 0
    'payload original offset_bits length_bits' =. y
    reader =. new_reader (<payload),<0
    literal_count =. 256+2x^length_bits
    distance_count =. offset_bits+1
    'reader mode' =. reader read_bits 1,0
    if. reader_failed reader do.
        reader_failure reader return.
    end.
    if. mode=1 do.
        'reader literal_lengths' =. reader read_table literal_count
        if. reader_failed reader do.
            reader_failure reader return.
        end.
        'reader distance_lengths' =. reader read_table distance_count
        if. reader_failed reader do.
            reader_failure reader return.
        end.
    else.
        literal_lengths =. fixed_lengths literal_count
        distance_lengths =. fixed_lengths distance_count
    end.
    literal_table =. symbol_table literal_lengths
    distance_table =. symbol_table distance_lengths
    output =. i.0x
    while. (#output)<original do.
        'reader symbol' =. literal_table read_symbol (<reader),<#output
        if. reader_failed reader do.
            reader_failure reader return.
        end.
        if. symbol<256 do.
            output =. output,symbol
        else.
            'reader slot' =. distance_table read_symbol (<reader),<#output
            if. reader_failed reader do.
                reader_failure reader return.
            end.
            offset =. slot
            if. slot>:2 do.
                'reader extra' =. reader read_bits (slot-1),#output
                if. reader_failed reader do.
                    reader_failure reader return.
                end.
                offset =. (2x^slot-1)+extra
            end.
            copied =. copy_match (<output),(<offset+1),(<symbol-253),<original
            if. decoded_failed copied do.
                copied return.
            end.
            output =. decoded_data copied
        end.
    end.
    decode_ok output
)
decode_payload =: 3 : 0
    'method payload original offset_bits length_bits' =. y
    select. method
    case. 0 do.
        if. (#payload)<original do.
            'end_of_data'decode_failure #payload
        else.
            decode_ok original{.payload
        end.
    case. 1 do.
        lzw_decode (<payload),<original
    case. 2 do.
        decode_lz (<payload),(<original),(<offset_bits),<length_bits
    case. 3 do.
        decode_lzh (<payload),(<original),(<offset_bits),<length_bits
    case. 4 do.
        arith_decode (<payload),<original
    end.
)
z_name =: 0&{::
z_data =: 1&{::
z_payloads =: 2&{::
z_best =: 3&{::
z_lzw =: 4&{::
z_lz =: 5&{::
z_lzh =: 6&{::
z_slots =: 7&{::
z_arith =: 8&{::
z_payload =: 3 : '(z_best y){::z_payloads y'
encode_file =: 3 : 0
    'name data params' =. y
    'offset_bits length_bits maximum' =. params
    tokens =. lz77_tokenize (<data),(<offset_bits),<length_bits
    'zw_payload zw_stats' =. lzw_encode data
    lz_payload =. encode_lz (<tokens),(<offset_bits),<length_bits
    'zh_payload zh_stats slots' =. encode_lzh (<tokens),(<offset_bits),(<length_bits),<maximum
    'arith_payload arith_stats' =. arith_encode data
    payloads =. (<data),(<zw_payload),(<lz_payload),(<zh_payload),<arith_payload
    sizes =. #&>payloads
    best =. sizes i.<./sizes
    literals =. 0
    matches =. 0
    matched =. 0
    longest =. 0
    farthest =. 0
    for_token. tokens do.
        'literal distance length' =. token
        if. literal>:0 do.
            literals =. literals+1
        else.
            matches =. matches+1
            matched =. matched+length
            longest =. longest>.length
            farthest =. farthest>.distance
        end.
    end.
    lz_stats =. (#tokens),literals,matches,matched,longest,farthest
    (<name),(<data),(<payloads),(<best),(<zw_stats),(<lz_stats),(<zh_stats),(<slots),<arith_stats
)
uint_bytes =: 4 : '(y#256)#:x'
read_uint =: 3 : 0
    'data position count' =. y
    256#.(position+i.count){data
)
hex_value =: 4 : '''0123456789abcdef''{~(y#16)#:x'
build_archive =: 3 : 0
    'encodings params' =. y
    archive =. 84 88 65 82x,(2{.params),(#encodings)uint_bytes 2
    for_box. encodings do.
        encoded =. >box
        name =. z_name encoded
        data =. z_data encoded
        payload =. z_payload encoded
        header =. (#name),(x:a.i.name),z_best encoded
        header =. header,((#data)uint_bytes 4),((#payload)uint_bytes 4),(adler data)uint_bytes 4
        check =. 256|+/header
        archive =. archive,header,check,payload
    end.
    archive
)
e_number =: 0&{::
e_offset =: 1&{::
e_status =: 2&{::
e_valid =: 3&{::
e_name =: 4&{::
e_method =: 5&{::
e_original =: 6&{::
e_compressed =: 7&{::
e_checksum =: 8&{::
e_start =: 9&{::
e_finish =: 10&{::
e_data =: 11&{::
e_computed =: 12&{::
e_failure =: 13&{::
e_failure_position =: 14&{::
e_repair =: 15&{::
new_entry =: 3 : 0
    'number offset' =. y
    (<number),(<offset),(<''),(<0),(<''),(<0),(<0),(<0),(<0),(<0),(<0),(<i.0x),(<0),(<''),(<0),<i.0x
)
a_size =: 0&{::
a_offset_bits =: 1&{::
a_length_bits =: 2&{::
a_declared =: 3&{::
a_entries =: 4&{::
a_intact =: 5&{::
a_reason =: 6&{::
a_stopped =: 7&{::
a_trailing =: 8&{::
parse_archive =: 3 : 0
    archive =. y
    size =. #archive
    entries =. 0$a:
    intact =. 0$a:
    parsed =. (<size),(<0),(<0),(<0),(<entries),(<intact),(<''),(<0),<0
    if. (size<8)+.-.84 88 65 82-:4{.archive do.
        (<'bad_magic')6}parsed return.
    end.
    offset_bits =. 4{archive
    length_bits =. 5{archive
    if. (offset_bits<6)+.(offset_bits>12)+.(length_bits<2)+.length_bits>5 do.
        (<'bad_params')6}parsed return.
    end.
    declared =. read_uint (<archive),(<6),<2
    position =. 8
    stopped =. 0
    trailing =. 0
    for_number. 1+i.declared do.
        entry =. new_entry number,position
        truncated =. position>:size
        if. -.truncated do.
            truncated =. (position+15+position{archive)>size
        end.
        if. truncated do.
            entry =. (<'truncated')2}entry
            entries =. entries,<entry
            stopped =. 1
            break.
        end.
        length =. position{archive
        name_bytes =. ((position+1)+i.length){archive
        cursor =. (position+1)+length
        start =. (position+15)+length
        method =. cursor{archive
        original =. read_uint (<archive),(<cursor+1),<4
        compressed =. read_uint (<archive),(<cursor+5),<4
        checksum =. read_uint (<archive),(<cursor+9),<4
        finish =. start+compressed
        header_indices =. position+i.(start-position)-1
        check =. 256|+/header_indices{archive
        valid =. (length>:1)*.(length<:32)*.(*./name_bytes e.NameBytes)*.check=(start-1){archive
        entry =. (<valid)3}entry
        entry =. (<method)5}entry
        entry =. (<original)6}entry
        entry =. (<compressed)7}entry
        entry =. (<checksum)8}entry
        entry =. (<start)9}entry
        entry =. (<finish)10}entry
        if. -.valid do.
            entry =. (<'bad_header')2}entry
            entries =. entries,<entry
            position =. finish
            if. position>size do.
                stopped =. 1
                break.
            end.
            continue.
        end.
        name =. a.{~name_bytes
        entry =. (<name)4}entry
        if. finish>size do.
            entry =. (<'truncated')2}entry
            entries =. entries,<entry
            stopped =. 1
            break.
        end.
        if. method>:5 do.
            entry =. (<'unsupported')2}entry
        else.
            payload =. (start+i.compressed){archive
            decoded =. decode_payload (<method),(<payload),(<original),(<offset_bits),<length_bits
            if. decoded_failed decoded do.
                entry =. (<'error')2}entry
                entry =. (<decoded_kind decoded)13}entry
                entry =. (<decoded_position decoded)14}entry
            else.
                data =. decoded_data decoded
                computed =. adler data
                entry =. (<data)11}entry
                entry =. (<computed)12}entry
                if. computed=checksum do.
                    entry =. (<'ok')2}entry
                else.
                    repair =. repair_byte (<data),(<checksum),<computed
                    if. #repair do.
                        'repaired record' =. repair
                        entry =. (<'repaired')2}entry
                        entry =. (<repaired)11}entry
                        entry =. (<record)15}entry
                    else.
                        entry =. (<'checksum')2}entry
                    end.
                end.
            end.
        end.
        entries =. entries,<entry
        if. (<e_status entry)e.;:'ok repaired' do.
            intact =. intact,<entry
        end.
        position =. finish
    end.
    if. -.stopped do.
        trailing =. size-position
    end.
    (<size),(<offset_bits),(<length_bits),(<declared),(<entries),(<intact),(<''),(<stopped),<trailing
)
verify =: 3 : 0
    'archive encodings' =. y
    parsed =. parse_archive archive
    entries =. a_entries parsed
    verified =. 0
    for_index. i.#entries do.
        entry =. index{::entries
        if. index<#encodings do.
            if. ('ok'-:e_status entry)*.(e_data entry)-:z_data index{::encodings do.
                verified =. verified+1
            end.
        end.
    end.
    (#entries),verified
)
sizes_report =: 3 : 0
    'encodings params archive examined verified' =. y
    'offset_bits length_bits maximum' =. params
    lines =. <'params offset_bits ',(text offset_bits),' length_bits ',(text length_bits),' window ',(text 2x^offset_bits),' lookahead ',(text (2x^length_bits)+2),' max_code_length ',text maximum
    totals =. 5$0x
    chosen =. 5$0
    original_total =. 0x
    best_total =. 0x
    for_box. encodings do.
        encoded =. >box
        original =. #z_data encoded
        original_total =. original_total+original
        best_total =. best_total+#z_payload encoded
        best =. z_best encoded
        chosen =. (1+best{chosen)best}chosen
        fields =. <'file ',(z_name encoded),' original ',text original
        for_method. i.5 do.
            compressed =. #method{::z_payloads encoded
            totals =. (compressed+method{totals)method}totals
            fields =. fields,<(method{::Methods),' ',(text compressed),' ',compressed ratio original
        end.
        fields =. fields,<'best ',method_name best
        lines =. lines,<' 'join fields
    end.
    fields =. <'total original ',text original_total
    selected =. <'chosen'
    for_method. i.5 do.
        total =. method{totals
        fields =. fields,<(method{::Methods),' ',(text total),' ',total ratio original_total
        selected =. selected,<(method{::Methods),' ',text method{chosen
    end.
    fields =. fields,<'best ',(text best_total),' ',best_total ratio original_total
    lines =. lines,(<' 'join fields),<' 'join selected
    lines =. lines,<'archive bytes ',(text #archive),' entries ',(text #encodings),' ratio ',(#archive)ratio original_total
    lines,<'verify entries ',(text examined),' ok ',text verified
)
analysis_report =: 3 : 0
    lines =. 0$a:
    for_box. y do.
        encoded =. >box
        name =. z_name encoded
        zw =. z_lzw encoded
        z =. z_lz encoded
        zh =. z_lzh encoded
        arithmetic =. z_arith encoded
        mode =. (8{zh){::'fixed';'dynamic'
        lines =. lines,<'lzw ',name,' codes ',(text 0{zw),' clears ',(text 1{zw),' widths ',(integers 2 3 4 5{zw),' longest ',text 6{zw
        lines =. lines,<'lz77 ',name,' tokens ',(text 0{z),' literals ',(text 1{z),' matches ',(text 2{z),' matched ',(text 3{z),' longest ',(text 4{z),' farthest ',text 5{z
        lines =. lines,<'lzh ',name,' mode ',mode,' fixed_bits ',(text 0{zh),' table_bits ',(text 1{zh),' code_bits ',(text 2{zh),' halvings ',(text 3{zh),' litlen_used ',(text 4{zh),' litlen_max ',(text 5{zh),' offset_used ',(text 6{zh),' offset_max ',text 7{zh
        lines =. lines,<'slots ',name,' ',integers z_slots encoded
        lines =. lines,<'arith ',name,' bits ',(text 0{arithmetic),' contexts ',(text 1{arithmetic),' rescales ',text 2{arithmetic
    end.
    lines
)
listing_report =: 3 : 0
    parsed =. y
    if. #a_reason parsed do.
        <'archive bytes ',(text a_size parsed),' error ',a_reason parsed return.
    end.
    lines =. <'archive bytes ',(text a_size parsed),' offset_bits ',(text a_offset_bits parsed),' length_bits ',(text a_length_bits parsed),' entries ',text a_declared parsed
    totals =. 5 3$0x
    listed =. 0
    for_box. a_entries parsed do.
        entry =. >box
        prefix =. 'entry ',(text e_number entry),' offset ',text e_offset entry
        if. -.e_valid entry do.
            suffix =. ' truncated header'
            if. 'bad_header'-:e_status entry do.
                suffix =. ' bad_header'
            end.
            lines =. lines,<prefix,suffix
            continue.
        end.
        listed =. listed+1
        lines =. lines,<prefix,' method ',(method_name e_method entry),' original ',(text e_original entry),' compressed ',(text e_compressed entry),' ratio ',((e_compressed entry)ratio e_original entry),' adler ',((e_checksum entry)hex_value 8),' name ',e_name entry
        method =. e_method entry
        if. method<5 do.
            row =. method{totals
            row =. row+1,(e_original entry),e_compressed entry
            totals =. row method}totals
        end.
    end.
    for_method. i.5 do.
        'count original compressed' =. method{totals
        lines =. lines,<'method ',(method{::Methods),' entries ',(text count),' original ',(text original),' compressed ',(text compressed),' ratio ',compressed ratio original
    end.
    state =. (a_stopped parsed){::'complete';'truncated'
    lines,<'end listed ',(text listed),' of ',(text a_declared parsed),' stop ',state,' trailing ',text a_trailing parsed
)
entry_test_line =: 4 : 0
    archive_size =. x
    entry =. y
    prefix =. 'entry ',(text e_number entry),' offset ',text e_offset entry
    if. -.e_valid entry do.
        status =. 'truncated header'
        if. 'bad_header'-:e_status entry do.
            status =. 'bad_header'
        end.
        prefix,' status ',status return.
    end.
    status =. e_status entry
    line =. prefix,' name ',(e_name entry),' method ',(method_name e_method entry),' status ',status
    select. status
    case. 'repaired' do.
        'position before after' =. e_repair entry
        line =. line,' byte ',(text position),' from ',(text before),' to ',text after
    case. 'checksum' do.
        line =. line,' stored ',((e_checksum entry)hex_value 8),' computed ',(e_computed entry)hex_value 8
    case. 'error' do.
        line =. line,' ',(e_failure entry),' at ',text e_failure_position entry
    case. 'truncated' do.
        line =. line,' payload have ',(text archive_size-e_start entry),' need ',text e_compressed entry
    end.
    line
)
test_report =: 3 : 0
    'parsed encodings salvaged verified' =. y
    if. #a_reason parsed do.
        lines =. <'archive error ',a_reason parsed
    else.
        lines =. 0$a:
        counts =. 7$0
        for_box. a_entries parsed do.
            entry =. >box
            lines =. lines,<(a_size parsed)entry_test_line entry
            status =. Statuses i.<e_status entry
            counts =. (1+status{counts)status}counts
        end.
        fields =. <'summary entries ',(text a_declared parsed),' checked ',text #a_entries parsed
        for_status. i.7 do.
            fields =. fields,<(status{::Statuses),' ',text status{counts
        end.
        fields =. fields,<'missing ',(text (a_declared parsed)-#a_entries parsed),' trailing ',text a_trailing parsed
        lines =. lines,<' 'join fields
    end.
    original =. 0x
    for_index. i.#encodings do.
        encoded =. index{::encodings
        entry =. index{::a_intact parsed
        original =. original+#z_data encoded
        lines =. lines,<'salvage ',(e_name entry),' method ',(method_name z_best encoded),' compressed ',(text #z_payload encoded),' was ',(method_name e_method entry),' ',text e_compressed entry
    end.
    lines,<'salvaged entries ',(text #encodings),' bytes ',(text #salvaged),' original ',(text original),' verified ',text verified
)
text_lines =: 3 : 0
    if. 0=#y do.
        0$a:
    else.
        <;._2 a.{~y
    end.
)
extraction_report =: 3 : 0
    result =. 0$a:
    for_box. y do.
        entry =. >box
        lines =. text_lines e_data entry
        word_count =. 0
        longest =. 0
        for_line. lines do.
            contents =. >line
            nonspace =. contents~:' '
            if. #contents do.
                word_count =. word_count++/nonspace*.-.0,}:nonspace
            end.
            longest =. longest>.#contents
        end.
        result =. result,<'file ',(e_name entry),' bytes ',(text #e_data entry),' lines ',(text #lines),' words ',(text word_count),' longest ',text longest
        result =. result,lines
    end.
    result
)
edit_list =: 3 : 0
    'old new' =. y
    a =. #old
    b =. #new
    below =. (b+1)$0
    decisions =. a$a:
    for_i. |.i.a do.
        current =. (b+1)$0
        deleted =. b$0
        for_j. |.i.b do.
            if. (i{old)-:j{new do.
                current =. (1+(j+1){below)j}current
            elseif. (j{below)>:(j+1){current do.
                current =. (j{below)j}current
                deleted =. 1 j}deleted
            else.
                current =. ((j+1){current)j}current
            end.
        end.
        decisions =. (<finish_bits deleted)i}decisions
        below =. current
    end.
    i =. 0
    j =. 0
    edits =. 0$a:
    removed =. 0
    added =. 0
    while. (i<a)+.j<b do.
        equal =. 0
        if. (i<a)*.j<b do.
            equal =. (i{old)-:j{new
        end.
        if. equal do.
            i =. i+1
            j =. j+1
            continue.
        end.
        deletion =. j=b
        if. (i<a)*.j<b do.
            packed =. i{::decisions
            byte =. (j intdiv 8){packed
            deletion =. 2|byte intdiv 2x^(7-8|j)
        end.
        if. deletion do.
            edits =. edits,<'-',(text i+1),':',i{::old
            i =. i+1
            removed =. removed+1
        else.
            edits =. edits,<'+',(text j+1),':',j{::new
            j =. j+1
            added =. added+1
        end.
    end.
    (<edits),(<removed),<added
)
comparison_report =: 3 : 0
    'entries files' =. y
    names =. 0$a:
    for_file. files do.
        names =. names,<0{::>file
    end.
    seen =. (#files)$0
    result =. 0$a:
    for_box. entries do.
        entry =. >box
        name =. e_name entry
        index =. names i.<name
        if. index=#files do.
            result =. result,<'archive_only ',name
            continue.
        end.
        seen =. 1 index}seen
        original =. 1{::index{::files
        old =. text_lines e_data entry
        new =. text_lines original
        if. (e_data entry)-:original do.
            result =. result,<'same ',name,' lines ',text #old
            continue.
        end.
        first =. 0
        while. first<(#old)<.#new do.
            if. -.(first{old)-:first{new do.
                break.
            end.
            first =. first+1
        end.
        'edits removed added' =. edit_list (<old),<new
        result =. result,<'differs ',name,' first_line ',(text first+1),' archive_lines ',(text #old),' manifest_lines ',(text #new),' removed ',(text removed),' added ',text added
        result =. result,edits
    end.
    for_index. i.#files do.
        if. -.index{seen do.
            result =. result,<'new ',index{::names
        end.
    end.
    result
)
save_lines =: 4 : 0
    contents =. ''
    for_line. y do.
        contents =. contents,(>line),LF
    end.
    contents 1!:2 <'output/',x
)
hex_lines =: 3 : 0
    result =. 0$a:
    for_start. 32*i.>.32%~#y do.
        line =. ''
        for_value. (32<.(#y)-start){.start}.y do.
            line =. line,value hex_value 2
        end.
        result =. result,<line
    end.
    result
)
parse_hex =: 3 : 0
    if. 0=#y do.
        i.0x
    else.
        x:16#. _2]\'0123456789abcdef'i.y
    end.
)
run =: 3 : 0
    NameBytes =: a.i.'abcdefghijklmnopqrstuvwxyz0123456789._-'
    manifest =. read_lines 'input/manifest.txt'
    params =. i.0x
    for_index. i.3 do.
        params =. params,num _1{::words index{::manifest
    end.
    files =. 0$a:
    encodings =. 0$a:
    for_index. 3+i.(#manifest)-3 do.
        name =. 1{::words index{::manifest
        data =. read_bytes 'input/files/',name
        files =. files,<(<name),<data
        encodings =. encodings,<encode_file (<name),(<data),<params
    end.
    created =. build_archive encodings;params
    'examined verified' =. verify (<created),<encodings
    supplied =. parse_hex ;read_lines 'input/archive.hex'
    parsed =. parse_archive supplied
    salvage_params =. params
    if. 0=#a_reason parsed do.
        salvage_params =. (a_offset_bits parsed),(a_length_bits parsed),2{params
    end.
    salvage_encodings =. 0$a:
    for_box. a_intact parsed do.
        entry =. >box
        salvage_encodings =. salvage_encodings,<encode_file (<e_name entry),(<e_data entry),<salvage_params
    end.
    salvaged =. build_archive salvage_encodings;salvage_params
    'salvage_examined salvage_verified' =. verify (<salvaged),<salvage_encodings
    try.
        1!:5 <'output'
    catch.
    end.
    'sizes.txt' save_lines sizes_report (<encodings),(<params),(<created),(<examined),<verified
    'analysis.txt' save_lines analysis_report encodings
    'archive.hex' save_lines hex_lines created
    'listing.txt' save_lines listing_report parsed
    'test_report.txt' save_lines test_report (<parsed),(<salvage_encodings),(<salvaged),<salvage_verified
    'extracted.txt' save_lines extraction_report a_intact parsed
    'compare.txt' save_lines comparison_report (<a_intact parsed),<files
    'salvaged.hex' save_lines hex_lines salvaged
)
run 0
