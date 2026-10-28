split =: 4 : 0
    result =. 0$a:
    start =. 0
    for_position. I.y=x do.
        result =. result,<(position-start){.start}.y
        start =. position+1
    end.
    result,<start}.y
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
num =: 3 : 'x: 0".y'
intdiv =: 4 : '<.(x: x)%x: y'
text =: 3 : 0
    if. 2=3!:0 y do.
        y return.
    end.
    result =. ":y
    '-'(I.result='_')}result
)
line =: 3 : ''' ''join text&.>y'
SQ =: 39{a.
load 'hexdump.ijs'
load 'link_network.ijs'
load 'transport.ijs'
load 'dns_app.ijs'
load 'flows.ijs'
seconds =: 3 : 0
    remainder =. text 1000000|y
    (text y intdiv 1000000),'.',((6-#remainder)#'0'),remainder
)
optional =: 3 : 0
    if. y<0 do.
        '-'
    else.
        text y
    end.
)
notation =: 4 : 0
    select. x
    case. 'hex2' do.
        '0x',2 hexadecimal y
    case. 'hex4' do.
        '0x',4 hexadecimal y
    case. 'ipv4' do.
        ipv4_notation y
    case. 'mac' do.
        mac_notation y
    case. do.
        text y
    end.
)
field_type =: 3 : 0
    index =. FieldNames i.<y
    if. index<#FieldNames do.
        index{::FieldKinds return.
    end.
    index =. AliasNames i.<y
    if. index<#AliasNames do.
        index{::AliasKinds return.
    end.
    if. (<y)e.ProtocolFields do.
        'presence'
    else.
        ''
    end.
)
field_values_of =: 4 : 0
    index =. AliasNames i.<y
    if. index<#AliasNames do.
        (x p_values index{::AliasFirst),x p_values index{::AliasSecond
    else.
        x p_values y
    end.
)
shown =: 4 : '(field_type y)notation x p_value y'
dissect_layer =: 3 : 0
    'packet name payload' =. y
    select. name
    case. 'eth' do.
        dissect_ethernet payload
    case. 'arp' do.
        dissect_arp payload
    case. 'ip' do.
        dissect_ipv4 payload
    case. 'icmp' do.
        dissect_icmp payload
    case. 'udp' do.
        dissect_udp (<payload),(<packet p_value 'ip.src'),<packet p_value 'ip.dst'
    case. 'tcp' do.
        dissect_tcp (<payload),(<packet p_value 'ip.src'),<packet p_value 'ip.dst'
    case. do.
        dissect_dns payload
    end.
)
dissect_packet =: 4 : 0
    packet =. y
    reason =. p_error packet
    if. 0=#reason do.
        name =. 'eth'
        payload =. p_data packet
        while. 1 do.
            packet =. (<(p_layers packet),<name)5}packet
            MalformedReason =: ''
            try.
                layer =. dissect_layer (<packet),(<name),<payload
            catch.
                reason =. MalformedReason
                break.
            end.
            fields =. p_fields packet
            names =. 0{::0{::layer
            values =. 1{::0{::layer
            for_index. i.#names do.
                name_index =. (0{::fields)i.index{names
                current_names =. 0{::fields
                current_values =. 1{::fields
                if. name_index=#current_names do.
                    fields =. (<current_names,index{names),<current_values,index{values
                else.
                    fields =. (<current_names),<((index{values)name_index}current_values)
                end.
            end.
            packet =. (<fields)6}packet
            if. name-:'dns' do.
                packet =. (4{layer)8}packet
            end.
            if. 0=#1{::layer do.
                packet =. (3{layer)7}packet
                break.
            end.
            name =. 1{::layer
            payload =. 2{::layer
        end.
    end.
    if. (0=#reason)*.0<#p_remaining packet do.
        packet =. (<(p_layers packet),<'data')5}packet
        packet =. packet p_put 'data.len';#p_remaining packet
    end.
    packet =. packet p_put 'frame.number';p_number packet
    packet =. packet p_put 'frame.time';(p_time packet)-x
    packet =. packet p_put 'frame.len';p_length packet
    if. #p_layers packet do.
        packet =. packet p_put 'frame.protocols';':'join p_layers packet
    end.
    if. #reason do.
        packet =. packet p_put 'frame.malformed';reason
        packet =. (<i.0)7}packet
    end.
    for_name. ChecksumNames do.
        if. 'bad'-:packet p_value (>name),'.checksum.status' do.
            packet =. packet p_put 'frame.bad_checksum';1
        end.
    end.
    packet
)
mark_text =: 3 : 0
    if. y p_exists 'tcp.analysis.duplicate_ack' do.
        index =. (p_number y)-1
        '[TCP Dup ACK ',(text index{DuplicateOriginal),'#',(text index{DuplicateCount),'] ' return.
    end.
    names =. 'retransmission';'out_of_order';'lost_segment'
    descriptions =. '[TCP Retransmission] ';'[TCP Out-Of-Order] ';'[TCP Previous segment not captured] '
    for_i. i.3 do.
        if. y p_exists 'tcp.analysis.',i{::names do.
            i{::descriptions return.
        end.
    end.
    ''
)
tcp_info =: 3 : 0
    flag_names =. 'FIN';'SYN';'RST';'PSH';'ACK';'URG';'ECE';'CWR'
    flags =. 0$a:
    bit =. 1
    for_name. flag_names do.
        if. 2|(y p_value 'tcp.flags')intdiv bit do.
            flags =. flags,name
        end.
        bit =. bit*2
    end.
    flag_text =. '<None>'
    if. #flags do.
        flag_text =. ', 'join flags
    end.
    result =. (mark_text y),(text y p_value 'tcp.srcport'),' -> ',(text y p_value 'tcp.dstport'),' [',flag_text,'] Seq=',text y p_value 'tcp.seq'
    if. 1=y p_value 'tcp.flags.ack' do.
        result =. result,' Ack=',text y p_value 'tcp.ack'
    end.
    result =. result,' Win=',(text y p_value 'tcp.window.calc'),' Len=',text y p_value 'tcp.len'
    for_option. y p_values 'tcp.option' do.
        words =. ' 'split >option
        select. 0{::words
        case. 'MSS' do.
            result =. result,' MSS=',1{::words
        case. 'WS' do.
            result =. result,' WS=',text power2 num 1{::words
        case. 'SACK_PERM' do.
            result =. result,' SACK_PERM'
        case. 'TS' do.
            result =. result,' TSval=',(1{::words),' TSecr=',2{::words
        end.
    end.
    result
)
basic_info =: 4 : 0
    packet =. y
    if. packet p_exists 'frame.malformed' do.
        packet p_value 'frame.malformed' return.
    end.
    select. x
    case. 'ETH' do.
        'EtherType ',packet shown 'eth.type'
    case. 'ARP' do.
        opcode =. packet p_value 'arp.opcode'
        if. opcode=1 do.
            'Who has ',(packet shown 'arp.dst.ip'),'? Tell ',packet shown 'arp.src.ip'
        elseif. opcode=2 do.
            (packet shown 'arp.src.ip'),' is at ',packet shown 'arp.src.hw'
        else.
            'Opcode ',text opcode
        end.
    case. 'IPv4' do.
        if. -.packet p_exists 'ip.fragment' do.
            'Protocol ',text packet p_value 'ip.proto' return.
        end.
        result =. 'Fragment id=',(packet shown 'ip.id'),' off=',text packet p_value 'ip.frag_offset'
        if. 1=packet p_value 'ip.flags.mf' do.
            result =. result,' MF'
        end.
        result
    case. 'ICMP' do.
        kind =. packet p_value 'icmp.type'
        if. kind e.0 8 do.
            prefix =. 'Echo reply'
            if. kind=8 do.
                prefix =. 'Echo request'
            end.
            prefix,' id=',(text packet p_value 'icmp.id'),' seq=',text packet p_value 'icmp.seq'
        else.
            'Type ',(text kind),' code ',text packet p_value 'icmp.code'
        end.
    case. 'UDP' do.
        (text packet p_value 'udp.srcport'),' -> ',(text packet p_value 'udp.dstport'),' Len=',text (packet p_value 'udp.length')-8
    case. 'TCP' do.
        tcp_info packet
    case. do.
        parts =. (<'Query'),<packet shown 'dns.id'
        if. 1=packet p_value 'dns.flags.response' do.
            parts =. (<'Response')0}parts
        end.
        rcode =. packet p_value 'dns.flags.rcode'
        if. rcode~:0 do.
            parts =. parts,<rcode_name rcode
        end.
        names =. packet p_values 'dns.qry.name'
        kinds =. packet p_values 'dns.qry.type'
        for_index. i.#names do.
            parts =. parts,(<dns_type_name index{::kinds),index{names
        end.
        ' 'join parts,p_answers packet
    end.
)
summary_line =: 3 : 0
    source =. destination =. '-'
    if. y p_exists 'ip.src' do.
        source =. y shown 'ip.src'
        destination =. y shown 'ip.dst'
    elseif. y p_exists 'eth.src' do.
        source =. y shown 'eth.src'
        destination =. y shown 'eth.dst'
    end.
    layers =. (p_layers y)-.<'data'
    protocol =. 'DUMP'
    if. #layers do.
        protocol =. (ProtocolFields i.{:layers){::ProtocolLabels
    end.
    info =. protocol basic_info y
    if. y p_exists 'tcp.options.malformed' do.
        info =. info,' [bad TCP options]'
    end.
    for_index. i.4 do.
        if. 'bad'-:y p_value (index{::ChecksumNames),'.checksum.status' do.
            info =. info,' [bad ',(index{::ChecksumLabels),' checksum]'
        end.
    end.
    line (p_number y);(seconds y p_value 'frame.time');source;'->';destination;protocol;(p_length y);info
)
filter_error =: 3 : 0
    FilterErrorMessage =: y
    13!:8 ]3
)
unexpected =: 3 : 0
    filter_error 'unexpected ',SQ,(1{::y),SQ,' at column ',text 2{::y
)
comparison_operator =: 3 : '(<y)e.''=='';''!='';''<'';''>'';''<='';''>='''
tokenize =: 3 : 0
    tokens =. 0$a:
    index =. 0
    word_characters =. 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:'
    while. index<#y do.
        character =. index{y
        column =. index+1
        pair =. (2<.(#y)-index){.index}.y
        if. character=' ' do.
            index =. index+1 continue.
        end.
        if. (2=#pair)*.((comparison_operator pair)+.(<pair)e.'&&';'||') do.
            kind =. token_text =. pair
            index =. index+2
        elseif. character e.'()!<>' do.
            kind =. token_text =. ,character
            index =. index+1
        elseif. character='"' do.
            last =. index+1
            while. last<#y do.
                if. '"'=last{y do.
                    break.
                end.
                last =. last+1
            end.
            if. last=#y do.
                filter_error 'unterminated string at column ',text column
            end.
            kind =. 'string'
            token_text =. ((1+last)-index){.index}.y
            index =. last+1
        elseif. character e.word_characters do.
            last =. index
            while. last<#y do.
                if. -.(last{y)e.word_characters do.
                    break.
                end.
                last =. last+1
            end.
            token_text =. (last-index){.index}.y
            kind =. 'word'
            if. token_text-:'and' do.
                kind =. '&&'
            elseif. token_text-:'or' do.
                kind =. '||'
            elseif. token_text-:'not' do.
                kind =. '!'
            end.
            index =. last
        else.
            filter_error 'invalid character ',SQ,character,SQ,' at column ',text column
        end.
        tokens =. tokens,<(<kind),(<token_text),<column
    end.
    tokens
)
decimal_digits =: 3 : '(0<#y)*.*./y e.''0123456789'''
hex_any_digits =: 3 : '(0<#y)*.*./y e.''0123456789abcdefABCDEF'''
convert_value =: 4 : 0
    'kind token_text column' =. y
    if. x-:'string' do.
        if. kind-:'string' do.
            (<1),<}.}:token_text
        else.
            (<0),<_1
        end. return.
    end.
    if. -.kind-:'word' do.
        (<0),<_1 return.
    end.
    if. (<x)e.'integer';'hex2';'hex4' do.
        if. ((#token_text)<:15)*.decimal_digits token_text do.
            (<1),<num token_text return.
        end.
        if. ('0x'-:2{.token_text)*.((#token_text)<:14)*.hex_any_digits 2}.token_text do.
            (<1),<hex_value 2}.token_text return.
        end.
        (<0),<_1 return.
    end.
    separator =. ':'
    count =. 6
    if. x-:'ipv4' do.
        separator =. '.'
        count =. 4
    end.
    parts =. separator split token_text
    if. count~:#parts do.
        (<0),<_1 return.
    end.
    value =. 0x
    for_box. parts do.
        part =. >box
        if. x-:'ipv4' do.
            if. ((#part)>3)+.-.decimal_digits part do.
                (<0),<_1 return.
            end.
            byte =. num part
            if. byte>255 do.
                (<0),<_1 return.
            end.
        else.
            if. (2~:#part)+.-.hex_any_digits part do.
                (<0),<_1 return.
            end.
            byte =. hex_value part
        end.
        value =. (value*256)+byte
    end.
    (<1),<value
)
next_kind =: 3 : 0
    if. TokenPosition<#Tokens do.
        0{::TokenPosition{::Tokens
    else.
        ''
    end.
)
take_token =: 3 : 0
    if. TokenPosition>:#Tokens do.
        filter_error 'unexpected end of filter'
    end.
    token =. TokenPosition{::Tokens
    TokenPosition =: TokenPosition+1
    token
)
append_node =: 3 : 0
    index =. #FilterNodes
    FilterNodes =: FilterNodes,<y
    index
)
initialize_schema =: 3 : 0
    FieldNames =: ' 'split 'frame.number frame.time frame.len frame.protocols frame.malformed frame.bad_checksum eth.dst'
    FieldNames =: FieldNames,' 'split 'eth.src eth.type arp.opcode arp.src.hw arp.src.ip arp.dst.hw arp.dst.ip'
    FieldNames =: FieldNames,' 'split 'ip.hdr_len ip.tos ip.len ip.id ip.flags.df ip.flags.mf ip.frag_offset'
    FieldNames =: FieldNames,' 'split 'ip.ttl ip.proto ip.checksum ip.checksum.status ip.src ip.dst ip.fragment'
    FieldNames =: FieldNames,' 'split 'icmp.type icmp.code icmp.checksum icmp.checksum.status icmp.id icmp.seq udp.srcport'
    FieldNames =: FieldNames,' 'split 'udp.dstport udp.length udp.checksum udp.checksum.status tcp.srcport tcp.dstport tcp.stream'
    FieldNames =: FieldNames,' 'split 'tcp.seq tcp.seq_raw tcp.ack tcp.ack_raw tcp.hdr_len tcp.flags tcp.flags.fin'
    FieldNames =: FieldNames,' 'split 'tcp.flags.syn tcp.flags.rst tcp.flags.psh tcp.flags.ack tcp.flags.urg tcp.window tcp.window.calc'
    FieldNames =: FieldNames,' 'split 'tcp.checksum tcp.checksum.status tcp.urgent tcp.option tcp.options.mss tcp.options.wscale tcp.options.malformed'
    FieldNames =: FieldNames,' 'split 'tcp.len tcp.analysis.retransmission tcp.analysis.out_of_order tcp.analysis.lost_segment tcp.analysis.duplicate_ack dns.id dns.flags'
    FieldNames =: FieldNames,' 'split 'dns.flags.response dns.flags.opcode dns.flags.rcode dns.count.queries dns.count.answers dns.count.auth_rr dns.count.add_rr'
    FieldNames =: FieldNames,' 'split 'dns.qry.name dns.qry.type dns.answer dns.authority dns.additional dns.a data.len'
    FieldKinds =: ' 'split 'integer integer integer string string presence mac'
    FieldKinds =: FieldKinds,' 'split 'mac hex4 integer mac ipv4 mac ipv4'
    FieldKinds =: FieldKinds,' 'split 'integer hex2 integer hex4 integer integer integer'
    FieldKinds =: FieldKinds,' 'split 'integer integer hex4 string ipv4 ipv4 presence'
    FieldKinds =: FieldKinds,' 'split 'integer integer hex4 string integer integer integer'
    FieldKinds =: FieldKinds,' 'split 'integer integer hex4 string integer integer integer'
    FieldKinds =: FieldKinds,' 'split 'integer integer integer integer integer hex2 integer'
    FieldKinds =: FieldKinds,' 'split 'integer integer integer integer integer integer integer'
    FieldKinds =: FieldKinds,' 'split 'hex4 string integer string integer integer presence'
    FieldKinds =: FieldKinds,' 'split 'integer presence presence presence presence hex4 hex4'
    FieldKinds =: FieldKinds,' 'split 'integer integer integer integer integer integer integer'
    FieldKinds =: FieldKinds,' 'split 'string integer string string string ipv4 integer'
    AliasNames =: 'eth.addr';'ip.addr';'udp.port';'tcp.port'
    AliasKinds =: 'mac';'ipv4';'integer';'integer'
    AliasFirst =: 'eth.dst';'ip.src';'udp.srcport';'tcp.srcport'
    AliasSecond =: 'eth.src';'ip.dst';'udp.dstport';'tcp.dstport'
    ProtocolFields =: ' 'split 'eth arp ip icmp udp tcp dns data'
    ProtocolLabels =: 'ETH';'ARP';'IPv4';'ICMP';'UDP';'TCP';'DNS';'DATA'
    ChecksumNames =: 'ip';'icmp';'udp';'tcp'
    ChecksumLabels =: 'IPv4';'ICMP';'UDP';'TCP'
    i.0
)
operator_node =: 3 : 0
    'kind left right' =. y
    append_node (<kind),(<left),(<right),(<''),(<''),<_1
)
parse_test =: 3 : 0
    name =. y
    kind =. field_type name
    if. 0=#kind do.
        filter_error 'unknown field ',name
    end.
    if. -.comparison_operator next_kind 0 do.
        append_node (<'exists'),(<_1),(<_1),(<name),(<''),<_1 return.
    end.
    operation =. 0{::take_token 0
    if. (kind-:'presence')+.((kind-:'string')*.-.(<operation)e.'==';'!=') do.
        filter_error 'operator ',operation,' not allowed for ',name
    end.
    token =. take_token 0
    if. -.(0{token)e.'word';'string' do.
        unexpected token
    end.
    'valid value' =. kind convert_value token
    if. -.valid do.
        filter_error 'invalid value ',(1{::token),' for ',name
    end.
    append_node (<'compare'),(<_1),(<_1),(<name),(<operation),<value
)
parse_negation =: 3 : 0
    if. '!' -:next_kind 0 do.
        skipped =. take_token 0
        child =. parse_negation 0
        operator_node (<'not'),(<child),<_1 return.
    end.
    token =. take_token 0
    if. '(' -:0{::token do.
        node =. parse_expression 0
        closing =. take_token 0
        if. -.')'-:0{::closing do.
            unexpected closing
        end.
        node return.
    end.
    if. 'word'-:0{::token do.
        parse_test 1{::token return.
    end.
    unexpected token
)
parse_product =: 3 : 0
    node =. parse_negation 0
    while. '&&'-:next_kind 0 do.
        skipped =. take_token 0
        right =. parse_negation 0
        node =. operator_node (<'and'),(<node),<right
    end.
    node
)
parse_expression =: 3 : 0
    node =. parse_product 0
    while. '||'-:next_kind 0 do.
        skipped =. take_token 0
        right =. parse_product 0
        node =. operator_node (<'or'),(<node),<right
    end.
    node
)
parse_filter =: 3 : 0
    Tokens =: tokenize y
    TokenPosition =: 0
    FilterNodes =: 0$a:
    root =. parse_expression 0
    if. TokenPosition<#Tokens do.
        unexpected TokenPosition{::Tokens
    end.
    (<FilterNodes),<root
)
value_equal =: 4 : 0
    if. 2=3!:0 x do.
        x-:y
    else.
        x=y
    end.
)
compare_value =: 4 : 0
    'operation value' =. y
    select. operation
    case. '==' do.
        x value_equal value
    case. '<' do.
        x<value
    case. '>' do.
        x>value
    case. '<=' do.
        x<:value
    case. do.
        x>:value
    end.
)
evaluate_filter =: 3 : 0
    'nodes index packet' =. y
    'kind left right field operation value' =. index{::nodes
    if. kind-:'and' do.
        if. -.evaluate_filter (<nodes),(<left),<packet do.
            0 return.
        end.
        evaluate_filter (<nodes),(<right),<packet return.
    end.
    if. kind-:'or' do.
        if. evaluate_filter (<nodes),(<left),<packet do.
            1 return.
        end.
        evaluate_filter (<nodes),(<right),<packet return.
    end.
    if. kind-:'not' do.
        -.evaluate_filter (<nodes),(<left),<packet return.
    end.
    if. (kind-:'exists')*.(<field)e.ProtocolFields do.
        (<field)e.p_layers packet return.
    end.
    values =. packet field_values_of field
    if. kind-:'exists' do.
        0<#values return.
    end.
    if. 0=#values do.
        0 return.
    end.
    if. operation-:'!=' do.
        for_candidate. values do.
            if. (>candidate)value_equal value do.
                0 return.
            end.
        end.
        1 return.
    end.
    for_candidate. values do.
        if. (>candidate)compare_value (<operation),<value do.
            1 return.
        end.
    end.
    0
)
detail_lines =: 3 : 0
    number =. y
    if. (number<1)+.number>#Packets do.
        ,<'packet ',(text number),' not found' return.
    end.
    packet =. (number-1){::Packets
    result =. ,<'packet ',text number
    for_box. (<'frame'),p_layers packet do.
        layer =. >box
        result =. result,<layer
        for_index. i.#FieldNames do.
            name =. index{::FieldNames
            kind =. index{::FieldKinds
            if. (layer,'.')-:(1+#layer){.name do.
                for_value. packet p_values name do.
                    shown_value =. ''
                    if. -.kind-:'presence' do.
                        shown_value =. ' = ',kind notation >value
                    end.
                    result =. result,<'  ',name,shown_value
                end.
            end.
        end.
        if. layer-:'data' do.
            result =. result,('  ',])&.>hex_dump p_remaining packet
        end.
    end.
    result
)
dns_transactions =: 3 : 0
    queries =. responses =. pending =. 0$a:
    times =. i.0
    for_box. y do.
        packet =. >box
        if. -.packet p_exists 'dns.id' do.
            continue.
        end.
        if. 0=packet p_value 'dns.flags.response' do.
            queries =. queries,<packet
            pending =. pending,<packet
            continue.
        end.
        responses =. responses,<packet
        for_index. i.#pending do.
            query =. index{::pending
            same =. (query p_value 'dns.id')=packet p_value 'dns.id'
            comparisons =. 4 2$('ip.src';'ip.dst';'udp.srcport';'udp.dstport';'ip.dst';'ip.src';'udp.dstport';'udp.srcport')
            for_pair. comparisons do.
                'first second' =. pair
                same =. same*.(query p_value first)=packet p_value second
            end.
            if. same do.
                times =. times,(p_time packet)-p_time query
                pending =. ((i.#pending)-.index){pending
                break.
            end.
        end.
    end.
    (<queries),(<responses),(<times),<#pending
)
protocol_statistics =: 3 : 0
    'queries responses times unanswered' =. y
    result =. (<line 'packets';#Packets),(<line 'bytes';+/p_length&>Packets),<line 'duration';seconds (p_time >{:Packets)-p_time >{.Packets
    result =. result,<'hierarchy'
    names =. 'eth';'arp';'ip';'icmp';'udp';'dns';'tcp'
    indents =. 0 2 2 4 4 6 4
    for_index. i.7 do.
        name =. index{::names
        count =. bytes =. 0
        for_box. Packets do.
            packet =. >box
            if. (<name)e.p_layers packet do.
                count =. count+1
                bytes =. bytes+p_length packet
            end.
        end.
        result =. result,<((index{indents)#' '),line name;count;bytes
    end.
    result =. result,<'checksums'
    for_name_box. ChecksumNames do.
        name =. >name_box
        good =. bad =. unchecked =. 0
        for_box. Packets do.
            status =. (>box)p_value name,'.checksum.status'
            good =. good+status-:'good'
            bad =. bad+status-:'bad'
            unchecked =. unchecked+status-:'none'
        end.
        value =. line name;'good';good;'bad';bad
        if. name-:'udp' do.
            value =. value,' none ',text unchecked
        end.
        result =. result,<value
    end.
    bad_dump =. +/0<#&>p_error&.>Packets
    result =. result,(<'malformed'),<line 'dump';bad_dump
    for_name_box. }:ProtocolFields do.
        name =. >name_box
        count =. 0
        for_box. Packets do.
            packet =. >box
            if. 0=#p_error packet do.
                if. packet p_exists 'frame.malformed' do.
                    count =. count+name-:>{:p_layers packet
                end.
            end.
        end.
        result =. result,<line name;count
    end.
    result =. result,<'tcp analysis'
    for_mark_box. MarkNames do.
        mark =. >mark_box
        count =. 0
        for_box. Packets do.
            count =. count+(>box)p_exists 'tcp.analysis.',mark
        end.
        result =. result,<line mark;count
    end.
    result =. result,(<'dns'),(<line 'queries';#queries),(<line 'responses';#responses),(<line 'transactions';#times),<line 'unanswered';unanswered
    if. #times do.
        result =. result,<line 'response_time';'min';(seconds <./times);'max';seconds >./times
    else.
        result =. result,<'response_time -'
    end.
    rcodes =. 16$0
    for_box. responses do.
        code =. (>box)p_value 'dns.flags.rcode'
        rcodes =. (>:(code{rcodes))code}rcodes
    end.
    for_code. I.rcodes>0 do.
        result =. result,<line 'rcode';(rcode_name code);code{rcodes
    end.
    names =. 0$a:
    counts =. i.0
    for_box. queries do.
        for_name. (>box)p_values 'dns.qry.name' do.
            index =. names i.name
            if. index=#names do.
                names =. names,name
                counts =. counts,0
            end.
            counts =. (>:(index{counts))index}counts
        end.
    end.
    result =. result,<'names'
    ordered =. /:names
    ordered =. ordered /:-ordered{counts
    for_index. ordered do.
        result =. result,<line (index{::names);index{counts
    end.
    result
)
endpoint_text =: 3 : 0
    result =. ipv4_notation {.y
    if. ({:y)>:0 do.
        result =. result,':',text {:y
    end.
    result
)
conversation_lines =: 3 : 0
    result =. ,<'type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b,bytes_a_to_b,packets_b_to_a,bytes_b_to_a,start,duration'
    for_box. build_conversations Packets do.
        row =. >box
        fields =. (<cv_kind row),(<endpoint_text cv_source row),(<endpoint_text cv_destination row),(<text cv_packets row),(<text cv_bytes row),(<text cv_ap row),(<text cv_ab row),(<text cv_bp row),(<text cv_bb row),(<seconds (cv_start row)-BaseTime),<seconds (cv_finish row)-cv_start row
        result =. result,<','join fields
    end.
    result
)
endpoint_lines =: 3 : 0
    result =. ,<'address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes'
    for_row. build_endpoints Packets do.
        'address tx_packets tx_bytes rx_packets rx_bytes' =. row
        fields =. (<ipv4_notation address),(<text tx_packets+rx_packets),(<text tx_bytes+rx_bytes),(<text tx_packets),(<text tx_bytes),(<text rx_packets),<text rx_bytes
        result =. result,<','join fields
    end.
    result
)
side_line =: 3 : 0
    result =. line (sd_name y);'packets';(sd_packets y);'payload';sd_payload y
    for_index. i.4 do.
        result =. result,' ',line (index{::MarkNames);index{sd_marks y
    end.
    result
)
stream_lines =: 3 : 0
    stream =. y
    client =. st_client_side stream
    server =. st_server_side stream
    rtt =. '-'
    if. ((st_syn stream)>:0)*.(st_ack stream)>:0 do.
        rtt =. seconds (p_time ((st_ack stream)-1){::Packets)-p_time ((st_syn stream)-1){::Packets
    end.
    history =. 0$a:
    for_change. st_history stream do.
        history =. history,<line >change
    end.
    result =. ,<line 'stream';(st_number stream);(endpoint_text st_client stream);'->';endpoint_text st_server stream
    result =. result,<line 'packets';(st_packets stream);'bytes';(st_bytes stream);'start';(seconds (st_start stream)-BaseTime);'duration';seconds (st_finish stream)-st_start stream
    result =. result,<'states ',(', 'join history)
    result =. result,<line 'handshake';'syn';(optional st_syn stream);'syn_ack';(optional st_syn_ack stream);'ack';(optional st_ack stream);'rtt';rtt
    result =. result,<line 'options';'client';'mss';(optional sd_mss client);'wscale';(optional sd_wscale client);'server';'mss';(optional sd_mss server);'wscale';optional sd_wscale server
    result =. result,(<side_line client),<side_line server
    for_event. st_events stream do.
        'number side mark start size' =. >event
        result =. result,<line 'event';number;side;mark;'seq';start;'len';size
    end.
    result
)
write_lines =: 4 : 0
    data =. ''
    for_value. y do.
        data =. data,(>value),LF
    end.
    data 1!:2 <'output/',x
)
run =: 3 : 0
    initialize_schema 0
    Packets =: read_capture 'input/capture.txt'
    BaseTime =: p_time 0{::Packets
    init_tracker #Packets
    for_index. i.#Packets do.
        packet =. BaseTime dissect_packet index{::Packets
        if. packet p_exists 'tcp.srcport' do.
            packet =. track_packet packet
        end.
        Packets =: (<packet)index}Packets
    end.
    summaries =. summary_line&.>Packets
    summary_output =. summaries
    detail_output =. 0$a:
    detail_count =. 0
    for_box. read_lines 'input/filters.txt' do.
        request =. >box
        if. 'FILTER '-:7{.request do.
            expression =. 7}.request
            summary_output =. summary_output,(<''),<'filter ',expression
            FilterErrorMessage =: ''
            try.
                'nodes root' =. parse_filter expression
            catch.
                summary_output =. summary_output,<'error: ',FilterErrorMessage
                continue.
            end.
            count =. 0
            for_index. i.#Packets do.
                if. evaluate_filter (<nodes),(<root),index{Packets do.
                    summary_output =. summary_output,index{summaries
                    count =. count+1
                end.
            end.
            summary_output =. summary_output,<line 'matched';count;'of';#Packets
        elseif. 'DETAIL '-:7{.request do.
            number =. num 7}.request
            if. detail_count do.
                detail_output =. detail_output,<''
            end.
            detail_output =. detail_output,detail_lines number
            detail_count =. detail_count+1
        end.
    end.
    streams_output =. 0$a:
    for_index. i.#Streams do.
        if. index do.
            streams_output =. streams_output,<''
        end.
        streams_output =. streams_output,stream_lines index{::Streams
    end.
    try. 1!:5 <'output' catch. end.
    'summary.txt'write_lines summary_output
    'details.txt'write_lines detail_output
    'conversations.csv'write_lines conversation_lines 0
    'endpoints.csv'write_lines endpoint_lines 0
    'protocol_stats.txt'write_lines protocol_statistics dns_transactions Packets
    'tcp_streams.txt'write_lines streams_output
)
run 0
