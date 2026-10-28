pseudo_header =: 3 : 0
    'source destination protocol size' =. y
    (4 integer_bytes source),(4 integer_bytes destination),0,protocol,2 integer_bytes size
)
dissect_icmp =: 3 : 0
    if. 8>#y do.
        malformed 'icmp: truncated'
    end.
    layer =. new_layer 0
    kind =. {.y
    layer =. layer l_put 'icmp.type';kind
    layer =. layer l_put 'icmp.code';1{y
    layer =. layer l_put 'icmp.checksum';y read_int 2 2
    layer =. layer l_put 'icmp.checksum.status';checksum y
    if. kind e.0 8 do.
        layer =. layer l_put 'icmp.id';y read_int 4 2
        layer =. layer l_put 'icmp.seq';y read_int 6 2
    end.
    (<8}.y)3}layer
)
dissect_udp =: 3 : 0
    'data source destination' =. y
    if. 8>#data do.
        malformed 'udp: truncated'
    end.
    size =. data read_int 4 2
    if. (size<8)+.size>#data do.
        malformed 'udp: bad length ',text size
    end.
    layer =. new_layer 0
    first =. data read_int 0 2
    second =. data read_int 2 2
    check =. data read_int 6 2
    status =. 'none'
    if. check~:0 do.
        status =. checksum (pseudo_header source,destination,17,size),size{.data
    end.
    layer =. layer l_put 'udp.srcport';first
    layer =. layer l_put 'udp.dstport';second
    layer =. layer l_put 'udp.length';size
    layer =. layer l_put 'udp.checksum';check
    layer =. layer l_put 'udp.checksum.status';status
    payload =. 8}.size{.data
    if. 53 e.first,second do.
        layer =. (<'dns')1}layer
        layer =. (<payload)2}layer
    else.
        layer =. (<payload)3}layer
    end.
    layer
)
valid_option_length =: 4 : 0
    select. x
    case. 2 do.
        y=4
    case. 3 do.
        y=3
    case. 4 do.
        y=2
    case. 5 do.
        y e.10 18 26 34
    case. 8 do.
        y=10
    case. do.
        1
    end.
)
parse_options =: 4 : 0
    layer =. x
    index =. 0
    while. index<#y do.
        kind =. index{y
        if. kind=0 do.
            layer l_add 'tcp.option';'EOL' return.
        end.
        if. kind=1 do.
            layer =. layer l_add 'tcp.option';'NOP'
            index =. index+1
            continue.
        end.
        size =. 0
        if. (index+1)<#y do.
            size =. (index+1){y
        end.
        if. (size<2)+.((index+size)>#y)+.-.kind valid_option_length size do.
            layer l_put 'tcp.options.malformed';1 return.
        end.
        body =. (size-2){.(index+2)}.y
        description =. 'kind ',(text kind),' len ',text size
        select. kind
        case. 2 do.
            value =. body read_int 0 2
            layer =. layer l_put 'tcp.options.mss';value
            description =. 'MSS ',text value
        case. 3 do.
            value =. {.body
            layer =. layer l_put 'tcp.options.wscale';value
            description =. 'WS ',text value
        case. 4 do.
            description =. 'SACK_PERM'
        case. 5 do.
            description =. 'SACK'
            for_offset. 8*i.(#body)intdiv 8 do.
                description =. description,' ',(text body read_int offset,4),'-',text body read_int (offset+4),4
            end.
        case. 8 do.
            description =. 'TS ',(text body read_int 0 4),' ',text body read_int 4 4
        end.
        layer =. layer l_add 'tcp.option';description
        index =. index+size
    end.
    layer
)
dissect_tcp =: 3 : 0
    'data source destination' =. y
    if. 20>#data do.
        malformed 'tcp: truncated header'
    end.
    header =. 4*(12{data)intdiv 16
    if. header<20 do.
        malformed 'tcp: bad header length ',text header
    end.
    if. header>#data do.
        malformed 'tcp: truncated header'
    end.
    layer =. new_layer 0
    flags =. 13{data
    layer =. layer l_put 'tcp.srcport';data read_int 0 2
    layer =. layer l_put 'tcp.dstport';data read_int 2 2
    layer =. layer l_put 'tcp.seq_raw';data read_int 4 4
    layer =. layer l_put 'tcp.hdr_len';header
    layer =. layer l_put 'tcp.flags';flags
    names =. 'fin';'syn';'rst';'psh';'ack';'urg'
    bit =. 1
    for_name. names do.
        layer =. layer l_put (<'tcp.flags.',>name),<2|flags intdiv bit
        bit =. bit*2
    end.
    layer =. layer l_put 'tcp.window';data read_int 14 2
    layer =. layer l_put 'tcp.checksum';data read_int 16 2
    covered =. (pseudo_header source,destination,6,#data),data
    layer =. layer l_put 'tcp.checksum.status';checksum covered
    layer =. layer l_put 'tcp.urgent';data read_int 18 2
    layer =. layer l_put 'tcp.len';(#data)-header
    if. 2|flags intdiv 16 do.
        layer =. layer l_put 'tcp.ack_raw';data read_int 8 4
    end.
    layer =. layer parse_options 20}.header{.data
    (<header}.data)3}layer
)
