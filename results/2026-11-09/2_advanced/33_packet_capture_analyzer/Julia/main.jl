include("hexdump.jl")
include("link_network.jl")
include("transport.jl")
include("dns_app.jl")
include("flows.jl")

const FIELDS = (
    ("frame.number","integer"),
    ("frame.time","integer"),
    ("frame.len","integer"),
    ("frame.protocols","string"),
    ("frame.malformed","string"),
    ("frame.bad_checksum","presence"),
    ("eth.dst","mac"),
    ("eth.src","mac"),
    ("eth.type","hex4"),
    ("arp.opcode","integer"),
    ("arp.src.hw","mac"),
    ("arp.src.ip","ipv4"),
    ("arp.dst.hw","mac"),
    ("arp.dst.ip","ipv4"),
    ("ip.hdr_len","integer"),
    ("ip.tos","hex2"),
    ("ip.len","integer"),
    ("ip.id","hex4"),
    ("ip.flags.df","integer"),
    ("ip.flags.mf","integer"),
    ("ip.frag_offset","integer"),
    ("ip.ttl","integer"),
    ("ip.proto","integer"),
    ("ip.checksum","hex4"),
    ("ip.checksum.status","string"),
    ("ip.src","ipv4"),
    ("ip.dst","ipv4"),
    ("ip.fragment","presence"),
    ("icmp.type","integer"),
    ("icmp.code","integer"),
    ("icmp.checksum","hex4"),
    ("icmp.checksum.status","string"),
    ("icmp.id","integer"),
    ("icmp.seq","integer"),
    ("udp.srcport","integer"),
    ("udp.dstport","integer"),
    ("udp.length","integer"),
    ("udp.checksum","hex4"),
    ("udp.checksum.status","string"),
    ("tcp.srcport","integer"),
    ("tcp.dstport","integer"),
    ("tcp.stream","integer"),
    ("tcp.seq","integer"),
    ("tcp.seq_raw","integer"),
    ("tcp.ack","integer"),
    ("tcp.ack_raw","integer"),
    ("tcp.hdr_len","integer"),
    ("tcp.flags","hex2"),
    ("tcp.flags.fin","integer"),
    ("tcp.flags.syn","integer"),
    ("tcp.flags.rst","integer"),
    ("tcp.flags.psh","integer"),
    ("tcp.flags.ack","integer"),
    ("tcp.flags.urg","integer"),
    ("tcp.window","integer"),
    ("tcp.window.calc","integer"),
    ("tcp.checksum","hex4"),
    ("tcp.checksum.status","string"),
    ("tcp.urgent","integer"),
    ("tcp.option","string"),
    ("tcp.options.mss","integer"),
    ("tcp.options.wscale","integer"),
    ("tcp.options.malformed","presence"),
    ("tcp.len","integer"),
    ("tcp.analysis.retransmission","presence"),
    ("tcp.analysis.out_of_order","presence"),
    ("tcp.analysis.lost_segment","presence"),
    ("tcp.analysis.duplicate_ack","presence"),
    ("dns.id","hex4"),
    ("dns.flags","hex4"),
    ("dns.flags.response","integer"),
    ("dns.flags.opcode","integer"),
    ("dns.flags.rcode","integer"),
    ("dns.count.queries","integer"),
    ("dns.count.answers","integer"),
    ("dns.count.auth_rr","integer"),
    ("dns.count.add_rr","integer"),
    ("dns.qry.name","string"),
    ("dns.qry.type","integer"),
    ("dns.answer","string"),
    ("dns.authority","string"),
    ("dns.additional","string"),
    ("dns.a","ipv4"),
    ("data.len","integer")
)
const ALIASES = Dict(
    "eth.addr"=>("mac","eth.dst","eth.src"),
    "ip.addr"=>("ipv4","ip.src","ip.dst"),
    "udp.port"=>("integer","udp.srcport","udp.dstport"),
    "tcp.port"=>("integer","tcp.srcport","tcp.dstport")
)
const PROTOCOL_FIELDS = ("eth","arp","ip","icmp","udp","tcp","dns","data")
const PROTOCOL_LABELS = Dict(
    "eth"=>"ETH",
    "arp"=>"ARP",
    "ip"=>"IPv4",
    "icmp"=>"ICMP",
    "udp"=>"UDP",
    "tcp"=>"TCP",
    "dns"=>"DNS"
)
const CHECKSUM_LAYERS = (("ip","IPv4"),("icmp","ICMP"),("udp","UDP"),("tcp","TCP"))
const FLAG_NAMES = ("FIN","SYN","RST","PSH","ACK","URG","ECE","CWR")
const MARK_LABELS = Dict(
    "retransmission"=>"[TCP Retransmission] ",
    "out_of_order"=>"[TCP Out-Of-Order] ",
    "lost_segment"=>"[TCP Previous segment not captured] "
)
const HIERARCHY = (("eth",0),("arp",2),("ip",2),("icmp",4),("udp",4),("dns",6),("tcp",4))
const CONVERSATION_HEADER = "type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b,bytes_a_to_b,packets_b_to_a,bytes_b_to_a,start,duration"
const ENDPOINT_HEADER = "address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes"
const FIELD_TYPES = Dict(FIELDS)

seconds(value) = "$(value÷1000000).$(lpad(value%1000000,6,'0'))"
optional(value) = isnothing(value) ? "-" : string(value)
function notation(type,value)
    type == "hex2" && return "0x"*string(value,base=16,pad=2)
    type == "hex4" && return "0x"*string(value,base=16,pad=4)
    type == "ipv4" && return ipv4_notation(value)
    type == "mac" && return mac_notation(value)
    string(value)
end
shown(packet,name) = notation(FIELD_TYPES[name],packet_value(packet,name))
endpoint_text(endpoint) = ipv4_notation(endpoint[1])*(endpoint[2] == -1 ? "" : ":$(endpoint[2])")
function field_type_of(name)
    haskey(FIELD_TYPES,name) && return FIELD_TYPES[name]
    haskey(ALIASES,name) && return ALIASES[name][1]
    name in PROTOCOL_FIELDS ? "presence" : nothing
end
function filter_field_values(packet,name)
    if haskey(ALIASES,name)
        _,first,second = ALIASES[name]
        return vcat(field_values(packet,first),field_values(packet,second))
    end
    field_values(packet,name)
end
function dissect_layer(packet,name,payload)
    name == "eth" && return dissect_ethernet(payload)
    name == "arp" && return dissect_arp(payload)
    name == "ip" && return dissect_ipv4(payload)
    name == "icmp" && return dissect_icmp(payload)
    name == "udp" && return dissect_udp(payload,packet_value(packet,"ip.src"),packet_value(packet,"ip.dst"))
    name == "tcp" && return dissect_tcp(payload,packet_value(packet,"ip.src"),packet_value(packet,"ip.dst"))
    dissect_dns(payload)
end
function dissect_layers!(packet)
    name,payload = "eth",packet.data
    while true
        push!(packet.layers,name)
        layer = try
            dissect_layer(packet,name,payload)
        catch error
            error isa Malformed || rethrow()
            return error.reason
        end
        merge!(packet.fields,layer.fields)
        if isnothing(layer.next_layer)
            packet.remaining = layer.remaining
            return nothing
        end
        name,payload = layer.next_layer,layer.payload
    end
end
function dissect!(packet,base_time)
    reason = isnothing(packet.error) ? dissect_layers!(packet) : packet.error
    if isnothing(reason) && !isempty(packet.remaining)
        push!(packet.layers,"data")
        set_field!(packet,"data.len",length(packet.remaining))
    end
    set_field!(packet,"frame.number",packet.number)
    set_field!(packet,"frame.time",packet.time-base_time)
    set_field!(packet,"frame.len",packet.length)
    !isempty(packet.layers) && set_field!(packet,"frame.protocols",join(packet.layers,':'))
    !isnothing(reason) && set_field!(packet,"frame.malformed",reason)
    if any(packet_value(packet,layer*".checksum.status") == "bad" for (layer,_) in CHECKSUM_LAYERS)
        set_field!(packet,"frame.bad_checksum",true)
    end
end
function addresses(packet)
    field_exists(packet,"ip.src") && return shown(packet,"ip.src"),shown(packet,"ip.dst")
    field_exists(packet,"eth.src") && return shown(packet,"eth.src"),shown(packet,"eth.dst")
    "-","-"
end
function protocol_label(packet)
    layers = filter(!=("data"),packet.layers)
    isempty(layers) ? "DUMP" : PROTOCOL_LABELS[last(layers)]
end
function option_summary(options)
    parts = String[]
    for option in options
        words = split(option)
        if words[1] == "MSS"
            push!(parts," MSS=$(words[2])")
        elseif words[1] == "WS"
            push!(parts," WS=$(1 << parse(Int,words[2]))")
        elseif words[1] == "SACK_PERM"
            push!(parts," SACK_PERM")
        elseif words[1] == "TS"
            push!(parts," TSval=$(words[2]) TSecr=$(words[3])")
        end
    end
    join(parts)
end
function tcp_info(packet,duplicate_acks)
    prefix = ""
    if field_exists(packet,"tcp.analysis.duplicate_ack")
        original,count = duplicate_acks[packet.number]
        prefix = "[TCP Dup ACK $original#$count] "
    else
        for mark in MARKS[1:3]
            if field_exists(packet,"tcp.analysis."*mark)
                prefix = MARK_LABELS[mark]
                break
            end
        end
    end
    flags = packet_value(packet,"tcp.flags")
    names = [name for (bit,name) in enumerate(FLAG_NAMES) if (flags >> (bit-1)) & 1 == 1]
    flagtext = isempty(names) ? "<None>" : join(names,", ")
    text = prefix*"$(packet_value(packet,"tcp.srcport")) -> $(packet_value(packet,"tcp.dstport")) [$flagtext] Seq=$(packet_value(packet,"tcp.seq"))"
    packet_value(packet,"tcp.flags.ack") == 1 && (text *= " Ack=$(packet_value(packet,"tcp.ack"))")
    text*" Win=$(packet_value(packet,"tcp.window.calc")) Len=$(packet_value(packet,"tcp.len"))"*option_summary(field_values(
        packet,
        "tcp.option"
    ))
end
function dns_info(packet)
    parts = [packet_value(packet,"dns.flags.response") == 1 ? "Response" : "Query",shown(packet,"dns.id")]
    rcode = packet_value(packet,"dns.flags.rcode")
    rcode != 0 && push!(parts,rcode_name(rcode))
    for (name,type) in zip(field_values(packet,"dns.qry.name"),field_values(packet,"dns.qry.type"))
        append!(parts,[type_name(type),name])
    end
    for record in field_values(packet,"dns.answer")
        words = split(record,' ';limit=5)
        append!(parts,[words[2],words[5]])
    end
    join(parts,' ')
end
function basic_info(packet,protocol,duplicate_acks)
    value(name) = packet_value(packet,name)
    field_exists(packet,"frame.malformed") && return value("frame.malformed")
    protocol == "ETH" && return "EtherType "*shown(packet,"eth.type")
    if protocol == "ARP"
        opcode = value("arp.opcode")
        opcode == 1 && return "Who has $(shown(packet,"arp.dst.ip"))? Tell $(shown(packet,"arp.src.ip"))"
        opcode == 2 && return "$(shown(packet,"arp.src.ip")) is at $(shown(packet,"arp.src.hw"))"
        return "Opcode $opcode"
    elseif protocol == "IPv4"
        !field_exists(packet,"ip.fragment") && return "Protocol $(value("ip.proto"))"
        return "Fragment id=$(shown(packet,"ip.id")) off=$(value("ip.frag_offset"))"*(value("ip.flags.mf") == 1 ? " MF" : "")
    elseif protocol == "ICMP"
        type = value("icmp.type")
        type in (
            0,
            8
        ) && return "Echo $(type == 8 ? "request" : "reply") id=$(value("icmp.id")) seq=$(value("icmp.seq"))"
        return "Type $type code $(value("icmp.code"))"
    elseif protocol == "UDP"
        return "$(value("udp.srcport")) -> $(value("udp.dstport")) Len=$(value("udp.length")-8)"
    elseif protocol == "TCP"
        return tcp_info(packet,duplicate_acks)
    end
    dns_info(packet)
end
function summary_line(packet,duplicate_acks)
    source,destination = addresses(packet)
    protocol = protocol_label(packet)
    info = basic_info(packet,protocol,duplicate_acks)
    field_exists(packet,"tcp.options.malformed") && (info *= " [bad TCP options]")
    for (layer,label) in CHECKSUM_LAYERS
        packet_value(packet,layer*".checksum.status") == "bad" && (info *= " [bad $label checksum]")
    end
    "$(packet.number) $(seconds(packet_value(packet,"frame.time"))) $source -> $destination $protocol $(packet.length) $info"
end
struct FilterError <: Exception
    reason::String
end
Base.showerror(io::IO,error::FilterError) = print(io,error.reason)
struct Token
    kind::String
    text::String
    column::Int
end
Base.@kwdef mutable struct FilterNode
    kind::String
    left::Union{Nothing,FilterNode} = nothing
    right::Union{Nothing,FilterNode} = nothing
    field::String = ""
    operator::String = ""
    value::Any = nothing
end
function tokenize(expression)
    tokens = Token[]
    index = 1
    wordchar(c) = 'a' <= c <= 'z' || 'A' <= c <= 'Z' || '0' <= c <= '9' || c in "._:"
    while index <= length(expression)
        character = expression[index]
        pair = expression[index:min(index+1,length(expression))]
        if character == ' '
            index += 1
        elseif pair in ("==","!=","<=",">=","&&","||")
            push!(tokens,Token(pair,pair,index))
            index += 2
        elseif character in "()!<>"
            push!(tokens,Token(string(character),string(character),index))
            index += 1
        elseif character == '"'
            closing = findnext('"',expression,index+1)
            isnothing(closing) && throw(FilterError("unterminated string at column $index"))
            push!(tokens,Token("string",expression[index:closing],index))
            index = closing+1
        elseif wordchar(character)
            after = index
            while after <= length(expression) && wordchar(expression[after])
                after += 1
            end
            word = expression[index:after-1]
            kind = get(Dict("and"=>"&&","or"=>"||","not"=>"!"),word,"word")
            push!(tokens,Token(kind,word,index))
            index = after
        else
            throw(FilterError("invalid character '$character' at column $index"))
        end
    end
    tokens
end
function parse_filter_value(type,token)
    type == "string" && return token.kind == "string" ? token.text[2:end-1] : nothing
    token.kind != "word" && return nothing
    text = token.text
    if type in ("integer","hex2","hex4")
        occursin(r"^[0-9]{1,15}$",text) && return parse(Int,text)
        occursin(r"^0x[0-9a-fA-F]{1,12}$",text) && return parse(Int,text[3:end],base=16)
    else
        parts = split(text,type == "ipv4" ? '.' : ':';keepempty=true)
        length(parts) != (type == "ipv4" ? 4 : 6) && return nothing
        value = 0
        for part in parts
            if type == "ipv4"
                occursin(r"^[0-9]{1,3}$",part) || return nothing
                octet = parse(Int,part)
                octet > 255 && return nothing
            else
                occursin(r"^[0-9a-fA-F]{2}$",part) || return nothing
                octet = parse(Int,part,base=16)
            end
            value = value*256+octet
        end
        return value
    end
    nothing
end
mutable struct FilterParser
    tokens::Vector{Token}
    position::Int
end
next_kind(parser) = parser.position <= length(parser.tokens) ? parser.tokens[parser.position].kind : nothing
unexpected(token) = FilterError("unexpected '$(token.text)' at column $(token.column)")
function take!(parser)
    parser.position > length(parser.tokens) && throw(FilterError("unexpected end of filter"))
    token = parser.tokens[parser.position]
    parser.position += 1
    token
end
function parse_negation!(parser)
    if next_kind(parser) == "!"
        take!(parser)
        return FilterNode(kind="not",left=parse_negation!(parser))
    end
    token = take!(parser)
    if token.kind == "("
        node = parse_expression!(parser)
        closing = take!(parser)
        closing.kind != ")" && throw(unexpected(closing))
        return node
    end
    token.kind != "word" && throw(unexpected(token))
    name = token.text
    type = field_type_of(name)
    isnothing(type) && throw(FilterError("unknown field $name"))
    !(next_kind(parser) in ("==","!=","<",">","<=",">=")) && return FilterNode(kind="exists",field=name)
    operator = take!(parser).kind
    if type == "presence" || (type == "string" && !(operator in ("==","!=")))
        throw(FilterError("operator $operator not allowed for $name"))
    end
    token = take!(parser)
    !(token.kind in ("word","string")) && throw(unexpected(token))
    value = parse_filter_value(type,token)
    isnothing(value) && throw(FilterError("invalid value $(token.text) for $name"))
    FilterNode(kind="compare",field=name,operator=operator,value=value)
end
function parse_product!(parser)
    node = parse_negation!(parser)
    while next_kind(parser) == "&&"
        take!(parser)
        node = FilterNode(kind="and",left=node,right=parse_negation!(parser))
    end
    node
end
function parse_expression!(parser)
    node = parse_product!(parser)
    while next_kind(parser) == "||"
        take!(parser)
        node = FilterNode(kind="or",left=node,right=parse_product!(parser))
    end
    node
end
function parse_filter(expression)
    parser = FilterParser(tokenize(expression),1)
    node = parse_expression!(parser)
    parser.position <= length(parser.tokens) && throw(unexpected(parser.tokens[parser.position]))
    node
end
function compare_value(left,operator,right)
    operator == "==" && return left == right
    operator == "<" && return left < right
    operator == ">" && return left > right
    operator == "<=" ? left <= right : left >= right
end
function evaluate(node,packet)
    node.kind == "or" && return evaluate(node.left,packet) || evaluate(node.right,packet)
    node.kind == "and" && return evaluate(node.left,packet) && evaluate(node.right,packet)
    node.kind == "not" && return !evaluate(node.left,packet)
    if node.kind == "exists"
        return node.field in PROTOCOL_FIELDS ? node.field in packet.layers : !isempty(filter_field_values(
            packet,
            node.field
        ))
    end
    values = filter_field_values(packet,node.field)
    isempty(values) && return false
    node.operator == "!=" && return all(value != node.value for value in values)
    any(compare_value(value,node.operator,node.value) for value in values)
end
function filter_block(expression,packets,summaries)
    lines = ["","filter $expression"]
    tree = try
        parse_filter(expression)
    catch error
        error isa FilterError || rethrow()
        push!(lines,"error: $(error.reason)")
        return lines
    end
    matched = filter(packet->evaluate(tree,packet),packets)
    append!(lines,[summaries[packet.number] for packet in matched])
    push!(lines,"matched $(length(matched)) of $(length(packets))")
    lines
end
function detail_lines(packets,number)
    !(1 <= number <= length(packets)) && return ["packet $number not found"]
    packet = packets[number]
    lines = ["packet $number"]
    for layer in vcat(["frame"],packet.layers)
        push!(lines,layer)
        for (name,type) in FIELDS
            startswith(name,layer*".") || continue
            for value in field_values(packet,name)
                push!(lines,type == "presence" ? "  $name" : "  $name = $(notation(type,value))")
            end
        end
        layer == "data" && append!(lines,["  "*line for line in hex_dump_lines(packet.remaining)])
    end
    lines
end
function dns_transactions(packets)
    queries,responses,pending = Packet[],Packet[],Packet[]
    times = Int[]
    for packet in packets
        field_exists(packet,"dns.id") || continue
        if packet_value(packet,"dns.flags.response") == 0
            push!(queries,packet)
            push!(pending,packet)
        else
            push!(responses,packet)
            index = findfirst(pending) do query
                packet_value(query,"dns.id") == packet_value(packet,"dns.id") &&
                all(packet_value(query,a) == packet_value(packet,b) for (a,b) in (
                    ("ip.src","ip.dst"),
                    ("udp.srcport","udp.dstport"),
                    ("ip.dst","ip.src"),
                    ("udp.dstport","udp.srcport")
                ))
            end
            if !isnothing(index)
                push!(times,packet.time-pending[index].time)
                deleteat!(pending,index)
            end
        end
    end
    (queries=queries,responses=responses,times=times,unanswered=length(pending))
end
function protocol_stats_lines(packets,transactions)
    lines = [
        "packets $(length(packets))",
        "bytes $(sum(packet.length for packet in packets))",
        "duration $(seconds(packets[end].time-packets[1].time))",
        "hierarchy"
    ]
    for (name,indent) in HIERARCHY
        members = filter(packet->name in packet.layers,packets)
        push!(
            lines,
            "$(repeat(" ",indent))$name $(length(members)) $(sum(packet.length for packet in members;init=0))"
        )
    end
    push!(lines,"checksums")
    for (layer,_) in CHECKSUM_LAYERS
        statuses = [packet_value(packet,layer*".checksum.status") for packet in packets]
        text = "$layer good $(count(==("good"),statuses)) bad $(count(==("bad"),statuses))"
        layer == "udp" && (text *= " none $(count(==("none"),statuses))")
        push!(lines,text)
    end
    append!(lines,["malformed","dump $(count(packet->!isnothing(packet.error),packets))"])
    for name in PROTOCOL_FIELDS[1:7]
        total = count(
            packet->isnothing(packet.error) && field_exists(
                packet,
                "frame.malformed"
            ) && last(packet.layers) == name,
            packets
        )
        push!(lines,"$name $total")
    end
    push!(lines,"tcp analysis")
    for mark in MARKS
        push!(lines,"$mark $(count(packet->field_exists(packet,"tcp.analysis."*mark),packets))")
    end
    append!(
        lines,
        [
            "dns",
            "queries $(length(transactions.queries))",
            "responses $(length(transactions.responses))",
            "transactions $(length(transactions.times))",
            "unanswered $(transactions.unanswered)"
        ]
    )
    times = transactions.times
    push!(
        lines,
        isempty(times) ? "response_time -" : "response_time min $(seconds(minimum(times))) max $(seconds(maximum(times)))"
    )
    for rcode in 0:15
        total = count(packet->packet_value(packet,"dns.flags.rcode") == rcode,transactions.responses)
        total > 0 && push!(lines,"rcode $(rcode_name(rcode)) $total")
    end
    push!(lines,"names")
    counts = Dict{String,Int}()
    for query in transactions.queries, name in field_values(query,"dns.qry.name")
        counts[name] = get(counts,name,0)+1
    end
    for name in sort(collect(keys(counts)),by=name->(-counts[name],name))
        push!(lines,"$name $(counts[name])")
    end
    lines
end
function conversation_lines(conversations,base_time)
    lines = [CONVERSATION_HEADER]
    for c in conversations
        row = (
            c.kind,
            endpoint_text(c.endpoint_a),
            endpoint_text(c.endpoint_b),
            flow_packets(c),
            flow_bytes(c),
            c.packets_a_to_b,
            c.bytes_a_to_b,
            c.packets_b_to_a,
            c.bytes_b_to_a,
            seconds(c.first_time-base_time),
            seconds(c.last_time-c.first_time)
        )
        push!(lines,join(row,','))
    end
    lines
end
function endpoint_lines(endpoints)
    lines = [ENDPOINT_HEADER]
    for e in endpoints
        row = (
            ipv4_notation(e.address),
            endpoint_packets(e),
            endpoint_bytes(e),
            e.tx_packets,
            e.tx_bytes,
            e.rx_packets,
            e.rx_bytes
        )
        push!(lines,join(row,','))
    end
    lines
end
side_line(side) = "$(side.name) packets $(side.packets) payload $(side.payload) "*join(
    ("$mark $(side.marks[mark])" for mark in MARKS),
    ' '
)
function stream_lines(stream,packets)
    client,server = stream.client_side,stream.server_side
    rtt = isnothing(stream.syn) || isnothing(stream.handshake_ack) ? "-" : seconds(packets[stream.handshake_ack].time-packets[stream.syn].time)
    lines = [
        "stream $(stream.number) $(endpoint_text(stream.client)) -> $(endpoint_text(stream.server))",
        "packets $(stream.packets) bytes $(stream.bytes) start $(seconds(stream.start_time-packets[1].time)) duration $(seconds(stream.end_time-stream.start_time))",
        "states "*join(("$state $number" for (state,number) in stream.history),", "),
        "handshake syn $(optional(stream.syn)) syn_ack $(optional(stream.syn_ack)) ack $(optional(stream.handshake_ack)) rtt $rtt",
        "options client mss $(optional(client.mss)) wscale $(optional(client.wscale)) server mss $(optional(server.mss)) wscale $(optional(server.wscale))",
        side_line(client),side_line(server)
    ]
    for (number,side,mark,start,size) in stream.events
        push!(lines,"event $number $side $mark seq $start len $size")
    end
    lines
end
function joined_blocks(blocks)
    lines = String[]
    for (index,block) in enumerate(blocks)
        index > 1 && push!(lines,"")
        append!(lines,block)
    end
    lines
end
function main()
    packets = read_capture(joinpath("input","capture.txt"))
    filters,detail_numbers = String[],Int[]
    for line in readlines(joinpath("input","filters.txt"))
        startswith(line,"FILTER ") && push!(filters,line[8:end])
        startswith(line,"DETAIL ") && push!(detail_numbers,parse(Int,line[8:end]))
    end
    base_time = packets[1].time
    for packet in packets
        dissect!(packet,base_time)
    end
    tracker = StreamTracker()
    for packet in packets
        field_exists(packet,"tcp.srcport") && track!(tracker,packet)
    end
    summaries = [summary_line(packet,tracker.duplicate_acks) for packet in packets]
    summary = copy(summaries)
    for expression in filters
        append!(summary,filter_block(expression,packets,summaries))
    end
    outputs = (
        "summary.txt"=>summary,
        "details.txt"=>joined_blocks(detail_lines(packets,number) for number in detail_numbers),
        "conversations.csv"=>conversation_lines(build_conversations(packets),base_time),
        "endpoints.csv"=>endpoint_lines(build_endpoints(packets)),
        "protocol_stats.txt"=>protocol_stats_lines(packets,dns_transactions(packets)),
        "tcp_streams.txt"=>joined_blocks(stream_lines(stream,packets) for stream in tracker.streams)
    )
    mkpath("output")
    for (name,lines) in outputs
        open(joinpath("output",name),"w") do handle
            foreach(line->println(handle,line),lines)
        end
    end
end
main()
