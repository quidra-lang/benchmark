const DNS_TYPE_NAMES = Dict(1=>"A",2=>"NS",5=>"CNAME",6=>"SOA",12=>"PTR",15=>"MX",16=>"TXT",28=>"AAAA")
const RCODE_NAMES = ("NoError","FormErr","ServFail","NXDomain","NotImp","Refused")
type_name(type) = get(DNS_TYPE_NAMES,type,"TYPE$type")
class_name(class) = class == 1 ? "IN" : "CLASS$class"
rcode_name(code) = code < length(RCODE_NAMES) ? RCODE_NAMES[code+1] : "RCODE$code"
function dns_chunk(message,position,size)
    position+size > length(message) && throw(Malformed("dns: truncated"))
    message[(position+1):(position+size)]
end
dns_byte(message,position) = Int(only(dns_chunk(message,position,1)))
dns_integer(message,position,size) = read_integer(dns_chunk(message,position,size),0,size)
function dns_label(label)
    join(33 <= byte <= 126 && !(byte in (
        46,
        92
    )) ? string(Char(byte)) : "\\$(lpad(string(Int(byte)),3,'0'))" for byte in label)
end
function dns_name(message,position)
    labels = String[]
    pointers = 0
    after = nothing
    while true
        size = dns_byte(message,position)
        if size == 0
            isnothing(after) && (after=position+1)
            break
        elseif size >= 192
            low = dns_byte(message,position+1)
            isnothing(after) && (after=position+2)
            pointers += 1
            pointers > 16 && throw(Malformed("dns: compression loop"))
            target = (size-192)*256+low
            target >= length(message) && throw(Malformed("dns: pointer out of range"))
            position = target
        elseif size >= 64
            throw(Malformed("dns: bad label type"))
        else
            push!(labels,dns_label(dns_chunk(message,position+1,size)))
            position += size+1
        end
    end
    return (isempty(labels) ? "<root>" : join(labels,'.'), after)
end
function ipv6_notation(address)
    groups = [read_integer(address,i,2) for i in 0:2:14]
    best_start,best_length,index = 0,1,1
    while index <= length(groups)
        if groups[index] != 0
            index += 1
            continue
        end
        stop = index
        while stop <= length(groups) && groups[stop] == 0
            stop += 1
        end
        if stop-index > best_length
            best_start,best_length = index,stop-index
        end
        index = stop
    end
    texts = [string(group,base=16) for group in groups]
    best_start == 0 && return join(texts,':')
    join(texts[1:(best_start-1)],':')*"::"*join(texts[(best_start+best_length):end],':')
end
function dns_rdata(message,type,start,size)
    type == 1 && return (ipv4_notation(dns_integer(message,start,4)),start+4)
    type == 28 && return (ipv6_notation(dns_chunk(message,start,16)),start+16)
    type in (2,5,12) && return dns_name(message,start)
    if type == 15
        preference = dns_integer(message,start,2)
        exchange,stop = dns_name(message,start+2)
        return "$preference $exchange",stop
    elseif type == 6
        primary,position = dns_name(message,start)
        mailbox,position = dns_name(message,position)
        parts = [primary,mailbox]
        for _ in 1:5
            push!(parts,string(dns_integer(message,position,4)))
            position += 4
        end
        return join(parts,' '),position
    end
    "$size bytes",start+size
end
function dns_record!(message,position,section,layer)
    name,position = dns_name(message,position)
    fixed = dns_chunk(message,position,10)
    type,class,ttl,size = read_integer(fixed,0,2),read_integer(fixed,2,2),read_integer(
        fixed,
        4,
        4
    ),read_integer(
        fixed,
        8,
        2
    )
    start = position+10
    start+size > length(message) && throw(Malformed("dns: truncated"))
    data,stop = dns_rdata(message,type,start,size)
    stop != start+size && throw(Malformed("dns: bad rdata length"))
    add_field!(layer,section,"$name $(type_name(type)) $(class_name(class)) $ttl $data")
    section == "dns.answer" && type == 1 && add_field!(layer,"dns.a",read_integer(message,start,4))
    start+size
end
function dissect_dns(message)
    header = dns_chunk(message,0,12)
    flags = read_integer(header,2,2)
    counts = [read_integer(header,i,2) for i in 4:2:10]
    layer = Layer()
    set_field!(layer,"dns.id",read_integer(header,0,2))
    set_field!(layer,"dns.flags",flags)
    set_field!(layer,"dns.flags.response",flags÷32768%2)
    set_field!(layer,"dns.flags.opcode",flags÷2048%16)
    set_field!(layer,"dns.flags.rcode",flags%16)
    for (name,count) in zip(
        ("dns.count.queries","dns.count.answers","dns.count.auth_rr","dns.count.add_rr"),
        counts
    )
        set_field!(layer,name,count)
    end
    position = 12
    for _ in 1:counts[1]
        name,position = dns_name(message,position)
        tail = dns_chunk(message,position,4)
        add_field!(layer,"dns.qry.name",name)
        add_field!(layer,"dns.qry.type",read_integer(tail,0,2))
        position += 4
    end
    for (section,count) in zip(("dns.answer","dns.authority","dns.additional"),counts[2:end])
        for _ in 1:count
            position = dns_record!(message,position,section,layer)
        end
    end
    layer
end
