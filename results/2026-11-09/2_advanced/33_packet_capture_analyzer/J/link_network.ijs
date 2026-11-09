malformed =: 3 : 0
    MalformedReason =: y
    13!:8 ]3
)
new_layer =: 3 : 0
    (<new_fields 0),(<''),(<i.0),(<i.0),<0$a:
)
read_int =: 4 : 0
    'offset size' =. y
    result =. 0x
    for_index. offset+i.size do.
        result =. (256*result)+index{x
    end.
    result
)
integer_bytes =: 4 : 0
    result =. x$0
    value =. y
    for_offset. i.x do.
        result =. (256|value)((x-1)-offset)}result
        value =. value intdiv 256
    end.
    result
)
checksum =: 3 : 0
    values =. y
    if. 2|#values do.
        values =. values,0
    end.
    sum =. 0x
    for_index. 2*i.(#values)intdiv 2 do.
        sum =. sum+((256*index{values)+(index+1){values)
    end.
    while. sum>65535 do.
        sum =. (65536|sum)+sum intdiv 65536
    end.
    if. sum=65535 do.
        'good'
    else.
        'bad'
    end.
)
mac_notation =: 3 : 0
    parts =. 0$a:
    for_byte. 6 integer_bytes y do.
        parts =. parts,<2 hexadecimal byte
    end.
    ':'join parts
)
ipv4_notation =: 3 : '''.''join text&.>4 integer_bytes y'
dissect_ethernet =: 3 : 0
    if. 14>#y do.
        malformed 'eth: truncated'
    end.
    layer =. new_layer 0
    kind =. y read_int 12 2
    layer =. layer l_put 'eth.dst';y read_int 0 6
    layer =. layer l_put 'eth.src';y read_int 6 6
    layer =. layer l_put 'eth.type';kind
    if. kind e.2054 2048 do.
        next_layer =. 'ip'
        if. kind=2054 do.
            next_layer =. 'arp'
        end.
        layer =. (<next_layer)1}layer
        layer =. (<14}.y)2}layer
    else.
        layer =. (<14}.y)3}layer
    end.
    layer
)
dissect_arp =: 3 : 0
    if. 28>#y do.
        malformed 'arp: truncated'
    end.
    if. ((y read_int 0 2)~:1)+.((y read_int 2 2)~:2048)+.((4{y)~:6)+.(5{y)~:4 do.
        malformed 'arp: unsupported format'
    end.
    layer =. new_layer 0
    names =. 'opcode';'src.hw';'src.ip';'dst.hw';'dst.ip'
    positions =. 5 2$6 2 8 6 14 4 18 6 24 4
    for_index. i.5 do.
        layer =. layer l_put (<'arp.',index{::names),<y read_int index{positions
    end.
    layer
)
dissect_ipv4 =: 3 : 0
    available =. #y
    if. available<20 do.
        malformed 'ip: truncated header'
    end.
    version =. ({.y)intdiv 16
    if. version~:4 do.
        malformed 'ip: bad version ',text version
    end.
    header =. 4*16|{.y
    if. header<20 do.
        malformed 'ip: bad header length ',text header
    end.
    if. available<header do.
        malformed 'ip: truncated header'
    end.
    total =. y read_int 2 2
    if. total<header do.
        malformed 'ip: bad total length ',text total
    end.
    if. total>available do.
        malformed 'ip: truncated (total length ',(text total),', available ',(text available),')'
    end.
    layer =. new_layer 0
    flags =. y read_int 6 2
    protocol =. 9{y
    layer =. layer l_put 'ip.hdr_len';header
    layer =. layer l_put 'ip.tos';1{y
    layer =. layer l_put 'ip.len';total
    layer =. layer l_put 'ip.id';y read_int 4 2
    layer =. layer l_put 'ip.flags.df';2|flags intdiv 16384
    layer =. layer l_put 'ip.flags.mf';2|flags intdiv 8192
    layer =. layer l_put 'ip.frag_offset';8*8192|flags
    layer =. layer l_put 'ip.ttl';8{y
    layer =. layer l_put 'ip.proto';protocol
    layer =. layer l_put 'ip.checksum';y read_int 10 2
    layer =. layer l_put 'ip.checksum.status';checksum header{.y
    layer =. layer l_put 'ip.src';y read_int 12 4
    layer =. layer l_put 'ip.dst';y read_int 16 4
    payload =. header}.total{.y
    if. ((2|flags intdiv 8192)=1)+.0~:8192|flags do.
        layer =. layer l_put 'ip.fragment';1
        layer =. (<payload)3}layer
    elseif. protocol e.1 17 6 do.
        next_layer =. (1 17 6 i.protocol){::'icmp';'udp';'tcp'
        layer =. (<next_layer)1}layer
        layer =. (<payload)2}layer
    else.
        layer =. (<payload)3}layer
    end.
    layer
)
