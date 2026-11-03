dns_type_name =: 3 : 0
    kinds =. 1 2 5 6 12 15 16 28
    names =. 'A';'NS';'CNAME';'SOA';'PTR';'MX';'TXT';'AAAA'
    index =. kinds i.y
    if. index<#kinds do.
        index{::names
    else.
        'TYPE',text y
    end.
)
rcode_name =: 3 : 0
    names =. 'NoError';'FormErr';'ServFail';'NXDomain';'NotImp';'Refused'
    if. y<#names do.
        y{::names
    else.
        'RCODE',text y
    end.
)
dns_label_text =: 3 : 0
    result =. ''
    for_byte. y do.
        if. (byte>:33)*.(byte<:126)*.-.byte e.46 92 do.
            result =. result,byte{a.
        else.
            value =. text byte
            result =. result,'\',((3-#value)#'0'),value
        end.
    end.
    result
)
ipv6_notation =: 3 : 0
    groups =. i.0
    for_offset. 2*i.8 do.
        groups =. groups,y read_int offset,2
    end.
    best_start =. _1
    best_length =. 1
    index =. 0
    while. index<8 do.
        if. 0~:index{groups do.
            index =. index+1 continue.
        end.
        last =. index
        while. last<8 do.
            if. 0~:last{groups do.
                break.
            end.
            last =. last+1
        end.
        if. (last-index)>best_length do.
            best_start =. index
            best_length =. last-index
        end.
        index =. last
    end.
    texts =. 0$a:
    for_group. groups do.
        texts =. texts,<1 hexadecimal group
    end.
    if. best_start<0 do.
        ':'join texts return.
    end.
    (':'join best_start{.texts),'::',':'join (best_start+best_length)}.texts
)
dns_chunk =: 4 : 0
    if. (x+y)>#DNSMessage do.
        malformed 'dns: truncated'
    end.
    y{.x}.DNSMessage
)
dns_integer =: 4 : '(x dns_chunk y)read_int 0,y'
dns_name =: 3 : 0
    cursor =. y
    labels =. 0$a:
    pointers =. 0
    after =. _1
    while. 1 do.
        size =. cursor dns_integer 1
        if. size=0 do.
            if. after<0 do.
                after =. cursor+1
            end.
            break.
        elseif. size>:192 do.
            low =. (cursor+1)dns_integer 1
            if. after<0 do.
                after =. cursor+2
            end.
            pointers =. pointers+1
            if. pointers>16 do.
                malformed 'dns: compression loop'
            end.
            cursor =. (256*size-192)+low
            if. cursor>:#DNSMessage do.
                malformed 'dns: pointer out of range'
            end.
        elseif. size>:64 do.
            malformed 'dns: bad label type'
        else.
            labels =. labels,<dns_label_text (cursor+1)dns_chunk size
            cursor =. cursor+size+1
        end.
    end.
    notation =. '<root>'
    if. #labels do.
        notation =. '.'join labels
    end.
    (<notation),<after
)
dns_rdata =: 3 : 0
    'kind start size' =. y
    if. kind=1 do.
        (<ipv4_notation start dns_integer 4),<start+4 return.
    end.
    if. kind=28 do.
        (<ipv6_notation start dns_chunk 16),<start+16 return.
    end.
    if. kind e.2 5 12 do.
        dns_name start return.
    end.
    if. kind=15 do.
        preference =. start dns_integer 2
        'name after' =. dns_name start+2
        (<(text preference),' ',name),<after return.
    end.
    if. kind=6 do.
        'primary position' =. dns_name start
        'mailbox position' =. dns_name position
        parts =. (<primary),<mailbox
        for_i. i.5 do.
            parts =. parts,<text position dns_integer 4
            position =. position+4
        end.
        (<' 'join parts),<position return.
    end.
    (<(text size),' bytes'),<start+size
)
dns_record =: 4 : 0
    layer =. x
    'position section' =. y
    'name after' =. dns_name position
    fixed =. after dns_chunk 10
    kind =. fixed read_int 0 2
    class =. fixed read_int 2 2
    ttl =. fixed read_int 4 4
    size =. fixed read_int 8 2
    start =. after+10
    checked =. start dns_chunk size
    'body finish' =. dns_rdata kind,start,size
    if. finish~:start+size do.
        malformed 'dns: bad rdata length'
    end.
    class_name =. 'IN'
    if. class~:1 do.
        class_name =. 'CLASS',text class
    end.
    value =. name,' ',(dns_type_name kind),' ',class_name,' ',(text ttl),' ',body
    layer =. layer l_add (<section),<value
    if. section-:'dns.answer' do.
        layer =. (<(4{::layer),<(dns_type_name kind),' ',body)4}layer
        if. kind=1 do.
            layer =. layer l_add 'dns.a';start dns_integer 4
        end.
    end.
    (<start+size),<layer
)
dissect_dns =: 3 : 0
    DNSMessage =: y
    header =. 0 dns_chunk 12
    layer =. new_layer 0
    flags =. header read_int 2 2
    layer =. layer l_put 'dns.id';header read_int 0 2
    layer =. layer l_put 'dns.flags';flags
    layer =. layer l_put 'dns.flags.response';2|flags intdiv 32768
    layer =. layer l_put 'dns.flags.opcode';16|flags intdiv 2048
    layer =. layer l_put 'dns.flags.rcode';16|flags
    names =. 'queries';'answers';'auth_rr';'add_rr'
    counts =. i.0
    for_index. i.4 do.
        count =. header read_int (4+2*index),2
        counts =. counts,count
        layer =. layer l_put (<'dns.count.',index{::names),<count
    end.
    position =. 12
    for_i. i.{.counts do.
        'name position' =. dns_name position
        tail =. position dns_chunk 4
        layer =. layer l_add 'dns.qry.name';name
        layer =. layer l_add 'dns.qry.type';tail read_int 0 2
        position =. position+4
    end.
    sections =. 'dns.answer';'dns.authority';'dns.additional'
    for_index. i.3 do.
        for_i. i.(index+1){counts do.
            'position layer' =. layer dns_record (<position),index{sections
        end.
    end.
    layer
)
