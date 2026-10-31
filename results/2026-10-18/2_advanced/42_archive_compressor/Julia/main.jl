include("bitio.jl")
include("lzw.jl")
include("lz77.jl")
include("huffman.jl")
include("arith_coder.jl")
const METHODS = ("STORE","LZW","LZ77","LZH","ARITH")
const STATUSES = ("ok","repaired","checksum","error","unsupported","truncated","bad_header")
const MODULUS = 65521
mutable struct Entry
    number::Int
    offset::Int
    status::String
    valid::Bool
    name::String
    method::Int
    original::Int
    compressed::Int
    checksum::Int
    start::Int
    stop::Int
    data::Vector{Int}
    error::Union{Nothing,DecodeError}
    repair::Tuple{Int,Int,Int}
    computed::Int
end
Entry(number,offset) = Entry(number,offset,"",false,"",0,0,0,0,0,0,Int[],nothing,(0,0,0),0)
function read_inputs()
    lines = split.(readlines("input/manifest.txt"),' ')
    b,k,m = [parse(Int,line[2]) for line in lines[1:3]]
    files = [(String(line[2]),Int.(read(joinpath("input/files",line[2])))) for line in lines[4:end]]
    hex = join(readlines("input/archive.hex"))
    supplied = [parse(Int,hex[i:i+1];base=16) for i in 1:2:length(hex)]
    (b=b,k=k,m=m),files,supplied
end
ratio(compressed,original) = original==0 ? "-" : string(fld(1000compressed,original))
method_name(method) = method<5 ? METHODS[method+1] : "#$method"
hexadecimal(value,width) = lpad(string(value;base=16),width,'0')
function adler32(data)
    a,b = 1,0
    for value in data
        a = (a+value)%MODULUS
        b = (b+a)%MODULUS
    end
    65536b+a
end
function modular_power(value,exponent,modulus)
    result = 1
    while exponent>0
        isodd(exponent) && (result=(result*value)%modulus)
        value = (value*value)%modulus
        exponent ÷= 2
    end
    result
end
function repair_byte(data,stored,computed)
    da = mod(stored%65536-computed%65536,MODULUS)
    db = mod(stored÷65536-computed÷65536,MODULUS)
    delta = 1<=da<=255 ? da : MODULUS-255<=da<MODULUS ? da-MODULUS : 0
    delta==0 && return nothing
    inverse = modular_power(mod(delta,MODULUS),MODULUS-2,MODULUS)
    distance = (db*inverse)%MODULUS
    1<=distance<=length(data) || return nothing
    position = length(data)-distance
    before = data[position+1]
    after = before+delta
    0<=after<=255 || return nothing
    repaired = copy(data)
    repaired[position+1] = after
    adler32(repaired)==stored ? (repaired,(position,before,after)) : nothing
end
function encode_lz77(tokens,b,k)
    writer = BitWriter()
    for (kind,value,matched) in tokens
        write_bits!(writer,kind,1)
        if kind==0
            write_bits!(writer,value,8)
        else
            write_bits!(writer,value-1,b)
            write_bits!(writer,matched-3,k)
        end
    end
    finish(writer)
end
function decode_lz77(payload,original,b,k)
    reader,output = BitReader(payload),Int[]
    while length(output)<original
        if read_bits!(reader,1,length(output))==0
            push!(output,read_bits!(reader,8,length(output)))
        else
            distance = read_bits!(reader,b,length(output))+1
            matched = read_bits!(reader,k,length(output))+3
            copy_match!(output,distance,matched,original)
        end
    end
    output
end
function fixed_lengths(n)
    width = bits(n-1)
    shorter = (1<<width)-n
    [s<shorter ? width-1 : width for s in 0:n-1]
end
function write_code_table!(writer,lengths)
    s = 1
    while s<=length(lengths)
        if lengths[s]>0
            write_bits!(writer,lengths[s],4)
            s += 1
        else
            run = 1
            while run<256 && s+run<=length(lengths) && lengths[s+run]==0
                run += 1
            end
            write_bits!(writer,0,4)
            write_bits!(writer,run-1,8)
            s += run
        end
    end
end
function read_code_table!(reader,n,position)
    lengths = Int[]
    while length(lengths)<n
        value = read_bits!(reader,4,position)
        if value>0
            push!(lengths,value)
        else
            run = read_bits!(reader,8,position)+1
            length(lengths)+run>n && throw(DecodeError("bad_table",position))
            append!(lengths,zeros(Int,run))
        end
    end
    positive = filter(>(0),lengths)
    valid = length(positive)==1 ? positive[1]==1 : isempty(positive) || sum(1<<(15-l) for l in positive)==1<<15
    valid || throw(DecodeError("bad_table",position))
    lengths
end
function huffman_table(lengths)
    codes = canonical_codes(lengths)
    symbols = Dict((lengths[s],codes[s])=>s-1 for s in eachindex(lengths) if lengths[s]>0)
    (symbols=symbols,maximum=maximum(lengths))
end
function read_symbol!(reader,table,position)
    isempty(table.symbols) && throw(DecodeError("bad_code",position))
    code = 0
    for width in 1:table.maximum
        code = 2code+read_bits!(reader,1,position)
        haskey(table.symbols,(width,code)) && return table.symbols[(width,code)]
    end
    throw(DecodeError("bad_code",position))
end
function write_lzh_tokens!(writer,tokens,p,q)
    pc,qc = canonical_codes(p),canonical_codes(q)
    for (kind,value,matched) in tokens
        if kind==0
            write_bits!(writer,pc[value+1],p[value+1])
        else
            symbol = 256+matched-3
            write_bits!(writer,pc[symbol+1],p[symbol+1])
            offset = value-1
            slot = bits(offset)
            write_bits!(writer,qc[slot+1],q[slot+1])
            slot>=2 && write_bits!(writer,offset-(1<<(slot-1)),slot-1)
        end
    end
end
function encode_lzh(tokens,params)
    p,q = zeros(Int,256+(1<<params.k)),zeros(Int,params.b+1)
    for (kind,value,matched) in tokens
        if kind==0
            p[value+1] += 1
        else
            p[256+matched-3+1] += 1
            q[bits(value-1)+1] += 1
        end
    end
    lengths_p,hp = limited_lengths(p,params.m)
    lengths_q,hq = limited_lengths(q,params.m)
    fixed,dynamic = BitWriter(),BitWriter()
    write_bits!(fixed,0,1)
    write_lzh_tokens!(fixed,tokens,fixed_lengths(length(p)),fixed_lengths(length(q)))
    fixed_bits = fixed.count-1
    write_bits!(dynamic,1,1)
    write_code_table!(dynamic,lengths_p)
    write_code_table!(dynamic,lengths_q)
    table_bits = dynamic.count-1
    write_lzh_tokens!(dynamic,tokens,lengths_p,lengths_q)
    code_bits = dynamic.count-1-table_bits
    use_fixed = fixed_bits<=table_bits+code_bits
    stats = (mode=use_fixed ? "fixed" : "dynamic",fixed_bits=fixed_bits,table_bits=table_bits,
        code_bits=code_bits,halvings=hp+hq,litlen_used=count(>(0),lengths_p),litlen_max=maximum(lengths_p),
        offset_used=count(>(0),lengths_q),offset_max=maximum(lengths_q),slots=q)
    finish(use_fixed ? fixed : dynamic),stats
end
function decode_lzh(payload,original,b,k)
    reader = BitReader(payload)
    if read_bits!(reader,1)==1
        p = read_code_table!(reader,256+(1<<k),0)
        q = read_code_table!(reader,b+1,0)
    else
        p,q = fixed_lengths(256+(1<<k)),fixed_lengths(b+1)
    end
    pt,qt = huffman_table(p),huffman_table(q)
    output = Int[]
    while length(output)<original
        symbol = read_symbol!(reader,pt,length(output))
        if symbol<256
            push!(output,symbol)
        else
            matched = symbol-253
            slot = read_symbol!(reader,qt,length(output))
            offset = slot>=2 ? (1<<(slot-1))+read_bits!(reader,slot-1,length(output)) : slot
            copy_match!(output,offset+1,matched,original)
        end
    end
    output
end
function decode_payload(method,payload,original,b,k)
    if method==0
        length(payload)<original && throw(DecodeError("end_of_data",length(payload)))
        return payload[1:original]
    elseif method==1
        return decode_lzw(payload,original)
    elseif method==2
        return decode_lz77(payload,original,b,k)
    elseif method==3
        return decode_lzh(payload,original,b,k)
    end
    decode_arith(payload,original)
end
function encode_file(name,data,params)
    tokens = tokenize(data,params.b,params.k)
    zw,zw_stats = encode_lzw(data)
    zh,zh_stats = encode_lzh(tokens,params)
    arithmetic,arithmetic_stats = encode_arith(data)
    payloads = [data,zw,encode_lz77(tokens,params.b,params.k),zh,arithmetic]
    best = argmin(length.(payloads))
    matches = [t for t in tokens if t[1]==1]
    z_stats = (tokens=length(tokens),literals=length(tokens)-length(matches),matches=length(matches),
        matched=sum((t[3] for t in matches);init=0),longest=maximum((t[3] for t in matches);init=0),
        farthest=maximum((t[2] for t in matches);init=0))
    (
        name=name,
        data=data,
        payloads=payloads,
        best=best,
        payload=payloads[best],
        lzw=zw_stats,
        lz77=z_stats,
        lzh=zh_stats,
        arith=arithmetic_stats
    )
end
big_endian(value,n) = [(value>>(8shift))&255 for shift in n-1:-1:0]
function build_archive(encodings,params)
    archive = vcat(Int.(codeunits("TXAR")),[params.b,params.k],big_endian(length(encodings),2))
    for encoding in encodings
        name = Int.(codeunits(encoding.name))
        header = vcat([length(name)],name,[encoding.best-1],big_endian(length(encoding.data),4),
                      big_endian(length(encoding.payload),4),big_endian(adler32(encoding.data),4))
        push!(header,sum(header)%256)
        append!(archive,header)
        append!(archive,encoding.payload)
    end
    archive
end
function read_big_endian(bytes,start,n)
    result = 0
    for i in start:start+n-1
        result = 256result+bytes[i]
    end
    result
end
function parse_archive(archive)
    n = length(archive)
    entries = Entry[]
    if n<8 || archive[1:4]!=Int.(codeunits("TXAR"))
        return (size=n,b=0,k=0,declared=0,entries=entries,error="bad_magic",stopped=false,trailing=0)
    end
    b,k = archive[5],archive[6]
    if !(6<=b<=12 && 2<=k<=5)
        return (size=n,b=b,k=k,declared=0,entries=entries,error="bad_params",stopped=false,trailing=0)
    end
    declared = read_big_endian(archive,7,2)
    position,stopped = 8,false
    for number in 1:declared
        entry = Entry(number,position)
        push!(entries,entry)
        if position>=n || position+15+archive[position+1]>n
            entry.status,stopped = "truncated",true
            break
        end
        m = archive[position+1]
        name = archive[position+2:position+1+m]
        cursor = position+1+m
        entry.method = archive[cursor+1]
        entry.original = read_big_endian(archive,cursor+2,4)
        entry.compressed = read_big_endian(archive,cursor+6,4)
        entry.checksum = read_big_endian(archive,cursor+10,4)
        entry.start = position+15+m
        entry.stop = entry.start+entry.compressed
        valid_name = 1<=m<=32 && all(c->c in codeunits("abcdefghijklmnopqrstuvwxyz0123456789._-"),name)
        valid_check = sum(archive[position+1:entry.start-1])%256==archive[entry.start]
        entry.valid = valid_name && valid_check
        if !entry.valid
            entry.status = "bad_header"
            position = entry.stop
            if position>n
                stopped = true
                break
            end
            continue
        end
        entry.name = String(UInt8.(name))
        if entry.stop>n
            entry.status,stopped = "truncated",true
            break
        end
        if entry.method>=5
            entry.status = "unsupported"
        else
            try
                entry.data = decode_payload(entry.method,archive[entry.start+1:entry.stop],entry.original,b,k)
                entry.computed = adler32(entry.data)
                if entry.computed==entry.checksum
                    entry.status = "ok"
                else
                    repair = repair_byte(entry.data,entry.checksum,entry.computed)
                    if isnothing(repair)
                        entry.status = "checksum"
                    else
                        entry.data,entry.repair = repair
                        entry.status = "repaired"
                    end
                end
            catch error
                error isa DecodeError || rethrow()
                entry.status,entry.error = "error",error
            end
        end
        position = entry.stop
    end
    (
        size=n,
        b=b,
        k=k,
        declared=declared,
        entries=entries,
        error=nothing,
        stopped=stopped,
        trailing=stopped ? 0 : n-position
    )
end
intact(parsed) = [e for e in parsed.entries if e.status in ("ok","repaired")]
function verify_archive(archive,originals)
    parsed = parse_archive(archive)
    verified = count(pair->pair[1].status=="ok" && pair[1].data==pair[2],zip(parsed.entries,originals))
    length(parsed.entries),verified
end
function sizes_report(encodings,params,archive,examined,verified)
    lines = ["params offset_bits $(params.b) length_bits $(params.k) window $(1<<params.b) lookahead $((1<<params.k)+2) max_code_length $(params.m)"]
    totals,chosen = zeros(Int,5),zeros(Int,5)
    original_total,best_total = 0,0
    for e in encodings
        original = length(e.data)
        original_total += original
        chosen[e.best] += 1
        best_total += length(e.payload)
        fields = ["file $(e.name) original $original"]
        for k in 1:5
            compressed = length(e.payloads[k])
            totals[k] += compressed
            push!(fields,"$(METHODS[k]) $compressed $(ratio(compressed,original))")
        end
        push!(fields,"best $(METHODS[e.best])")
        push!(lines,join(fields," "))
    end
    fields = ["total original $original_total"]
    append!(fields,["$(METHODS[k]) $(totals[k]) $(ratio(totals[k],original_total))" for k in 1:5])
    push!(fields,"best $best_total $(ratio(best_total,original_total))")
    push!(lines,join(fields," "),"chosen "*join(["$(METHODS[k]) $(chosen[k])" for k in 1:5]," "),
        "archive bytes $(length(archive)) entries $(length(encodings)) ratio $(ratio(length(archive),original_total))",
        "verify entries $examined ok $verified")
    lines
end
function analysis_report(encodings)
    lines = String[]
    for e in encodings
        zw,z,zh,ar = e.lzw,e.lz77,e.lzh,e.arith
        push!(lines,"lzw $(e.name) codes $(zw.codes) clears $(zw.clears) widths $(join(zw.widths," ")) longest $(zw.longest)",
            "lz77 $(e.name) tokens $(z.tokens) literals $(z.literals) matches $(z.matches) matched $(z.matched) longest $(z.longest) farthest $(z.farthest)",
            "lzh $(e.name) mode $(zh.mode) fixed_bits $(zh.fixed_bits) table_bits $(zh.table_bits) code_bits $(zh.code_bits) halvings $(zh.halvings) litlen_used $(zh.litlen_used) litlen_max $(zh.litlen_max) offset_used $(zh.offset_used) offset_max $(zh.offset_max)",
            "slots $(e.name) "*join(
                zh.slots,
                " "
            ),"arith $(e.name) bits $(ar.bits) contexts $(ar.contexts) rescales $(ar.rescales)")
    end
    lines
end
function listing_report(parsed)
    !isnothing(parsed.error) && return ["archive bytes $(parsed.size) error $(parsed.error)"]
    lines = ["archive bytes $(parsed.size) offset_bits $(parsed.b) length_bits $(parsed.k) entries $(parsed.declared)"]
    totals = zeros(Int,5,3)
    listed = 0
    for e in parsed.entries
        prefix = "entry $(e.number) offset $(e.offset)"
        if !e.valid
            push!(lines,prefix*(e.status=="bad_header" ? " bad_header" : " truncated header"))
            continue
        end
        listed += 1
        push!(
            lines,
            "$prefix method $(method_name(e.method)) original $(e.original) compressed $(e.compressed) ratio $(ratio(e.compressed,e.original)) adler $(hexadecimal(e.checksum,8)) name $(e.name)"
        )
        e.method<5 && (totals[e.method+1,:] .+= [1,e.original,e.compressed])
    end
    for k in 1:5
        count,original,compressed = totals[k,:]
        push!(
            lines,
            "method $(METHODS[k]) entries $count original $original compressed $compressed ratio $(ratio(compressed,original))"
        )
    end
    push!(
        lines,
        "end listed $listed of $(parsed.declared) stop $(parsed.stopped ? "truncated" : "complete") trailing $(parsed.trailing)"
    )
    lines
end
function entry_test_line(e,archive_size)
    prefix = "entry $(e.number) offset $(e.offset)"
    !e.valid && return prefix*(e.status=="bad_header" ? " status bad_header" : " status truncated header")
    line = "$prefix name $(e.name) method $(method_name(e.method)) status $(e.status)"
    if e.status=="repaired"
        position,before,after = e.repair
        line *= " byte $position from $before to $after"
    elseif e.status=="checksum"
        line *= " stored $(hexadecimal(e.checksum,8)) computed $(hexadecimal(e.computed,8))"
    elseif e.status=="error"
        line *= " $(e.error.kind) at $(e.error.position)"
    elseif e.status=="truncated"
        line *= " payload have $(archive_size-e.start) need $(e.compressed)"
    end
    line
end
function test_report(parsed,salvaged,archive,verified)
    if !isnothing(parsed.error)
        lines = ["archive error $(parsed.error)"]
    else
        lines = [entry_test_line(e,parsed.size) for e in parsed.entries]
        counts = [count(e->e.status==status,parsed.entries) for status in STATUSES]
        summary = "summary entries $(parsed.declared) checked $(length(parsed.entries)) "
        summary *= join(["$(STATUSES[k]) $(counts[k])" for k in eachindex(STATUSES)]," ")
        push!(lines,summary*" missing $(parsed.declared-length(parsed.entries)) trailing $(parsed.trailing)")
    end
    for (e,encoding) in zip(intact(parsed),salvaged)
        push!(
            lines,
            "salvage $(e.name) method $(METHODS[encoding.best]) compressed $(length(encoding.payload)) was $(method_name(e.method)) $(e.compressed)"
        )
    end
    total = sum((length(e.data) for e in salvaged);init=0)
    push!(
        lines,
        "salvaged entries $(length(salvaged)) bytes $(length(archive)) original $total verified $verified"
    )
    lines
end
function text_lines(data)
    isempty(data) && return String[]
    String.(split(String(UInt8.(data)),'\n';keepempty=true)[1:end-1])
end
function extraction_report(entries)
    lines = String[]
    for e in entries
        contents = text_lines(e.data)
        words = sum((length(split(line,' ';keepempty=false)) for line in contents);init=0)
        longest = maximum(length.(contents);init=0)
        push!(
            lines,
            "file $(e.name) bytes $(length(e.data)) lines $(length(contents)) words $words longest $longest"
        )
        append!(lines,contents)
    end
    lines
end
function edit_list(old,new)
    a,b = length(old),length(new)
    below,current = zeros(Int,b+1),zeros(Int,b+1)
    deletions = [falses(b) for _ in 1:a]
    for i in a:-1:1
        right = 0
        for j in b:-1:1
            if old[i]==new[j]
                value = below[j+1]+1
            elseif below[j]>=right
                value = below[j]
                deletions[i][j] = true
            else
                value = right
            end
            current[j] = value
            right = value
        end
        below,current = current,below
    end
    edits = Tuple{String,Int,String}[]
    i,j = 1,1
    while i<=a || j<=b
        if i<=a && j<=b && old[i]==new[j]
            i += 1
            j += 1
        elseif j>b || i<=a && deletions[i][j]
            push!(edits,("-",i,old[i]))
            i += 1
        else
            push!(edits,("+",j,new[j]))
            j += 1
        end
    end
    edits
end
function comparison_report(entries,files)
    manifest = Dict(files)
    seen = Set{String}()
    lines = String[]
    for e in entries
        push!(seen,e.name)
        if !haskey(manifest,e.name)
            push!(lines,"archive_only $(e.name)")
            continue
        end
        old,new = text_lines(e.data),text_lines(manifest[e.name])
        if old==new
            push!(lines,"same $(e.name) lines $(length(old))")
            continue
        end
        first_difference = 1
        while first_difference<=min(length(old),length(new)) && old[first_difference]==new[first_difference]
            first_difference += 1
        end
        edits = edit_list(old,new)
        removed = count(edit->edit[1]=="-",edits)
        push!(
            lines,
            "differs $(e.name) first_line $first_difference archive_lines $(length(old)) manifest_lines $(length(new)) removed $removed added $(length(edits)-removed)"
        )
        append!(lines,["$sign$number:$contents" for (sign,number,contents) in edits])
    end
    append!(lines,["new $name" for (name,_) in files if !(name in seen)])
    lines
end
function write_lines(name,lines)
    open(joinpath("output",name),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
write_hex(name,archive) = write_lines(
    name,
    [join(hexadecimal(v,2) for v in archive[i:min(i+31,end)]) for i in 1:32:length(archive)]
)
function main()
    params,files,supplied = read_inputs()
    encodings = [encode_file(name,data,params) for (name,data) in files]
    created = build_archive(encodings,params)
    examined,verified = verify_archive(created,[data for (_,data) in files])
    parsed = parse_archive(supplied)
    salvage_params = isnothing(parsed.error) ? (b=parsed.b,k=parsed.k,m=params.m) : params
    entries = intact(parsed)
    salvaged = [encode_file(e.name,e.data,salvage_params) for e in entries]
    archive = build_archive(salvaged,salvage_params)
    _,salvage_verified = verify_archive(archive,[e.data for e in salvaged])
    mkpath("output")
    write_lines("sizes.txt",sizes_report(encodings,params,created,examined,verified))
    write_lines("analysis.txt",analysis_report(encodings))
    write_hex("archive.hex",created)
    write_lines("listing.txt",listing_report(parsed))
    write_lines("test_report.txt",test_report(parsed,salvaged,archive,salvage_verified))
    write_lines("extracted.txt",extraction_report(entries))
    write_lines("compare.txt",comparison_report(entries,files))
    write_hex("salvaged.hex",archive)
end
main()
