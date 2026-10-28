using Printf
include("entropy.jl")
include("image_io.jl")
include("color.jl")
include("dct.jl")
include("bitstream.jl")

const COMPONENT_NAMES = ("Y","Cb","Cr")
words(args...) = join(string.(args)," ")
function standard_components(h,v)
    [
        (identifier=1,h=h,v=v,tq=0,td=0,ta=0),
        (identifier=2,h=1,v=1,tq=1,td=1,ta=1),
        (identifier=3,h=1,v=1,tq=1,td=1,ta=1)
    ]
end
function make_layout(width,height,components,restart_interval)
    hmax,vmax = maximum(c.h for c in components),maximum(c.v for c in components)
    mx,my = cld(width,8hmax),cld(height,8vmax)
    mcus = mx*my
    blocks = NamedTuple[]
    for mcu in 0:mcus-1,(k,c) in enumerate(components),v in 0:c.v-1,h in 0:c.h-1
        push!(blocks,(mcu=mcu,component=k,bx=c.h*(mcu%mx)+h,by=c.v*(mcu÷mx)+v))
    end
    step = restart_interval==0 ? mcus : restart_interval
    intervals = [(first,min(step,mcus-first)) for first in 0:step:mcus-1]
    (
        width=width,
        height=height,
        components=components,
        restart_interval=restart_interval,
        factors=[(c.h,c.v) for c in components],
        hmax=hmax,
        vmax=vmax,
        mx=mx,
        my=my,
        mcus=mcus,
        blocks_per_mcu=sum(c.h*c.v for c in components),
        blocks=blocks,
        intervals=intervals
    )
end
function interval_blocks(layout,interval)
    first,n = layout.intervals[interval]
    first*layout.blocks_per_mcu+1:(first+n)*layout.blocks_per_mcu
end
word(value) = [value÷256,value%256]
read_word(data,offset) = 256data[offset+1]+data[offset+2]
segment(marker,contents) = [255;marker;word(length(contents)+2);contents]
function read_symbol!(reader,table)
    code = 0
    for length in 1:16
        code = 2code+read_bit!(reader)
        haskey(table.decode,(length,code)) && return table.decode[(length,code)]
    end
    throw(CodecDecodeError("code"))
end
function decode_block!(reader,k,component,tables,predictors)
    coefficients = zeros(Int,64)
    n = read_symbol!(reader,tables[(0,component.td)])
    predictors[k] += amplitude(read_bits!(reader,n),n)
    coefficients[1] = predictors[k]
    index = 1
    while index<=63
        symbol = read_symbol!(reader,tables[(1,component.ta)])
        symbol==0 && break
        run,n = divrem(symbol,16)
        index += run
        index>63 && throw(CodecDecodeError("index"))
        n>0 && (coefficients[index+1]=amplitude(read_bits!(reader,n),n))
        index += 1
    end
    coefficients
end
function prepare(codec,image,quality,sampling,restart_interval)
    h,v = sampling=="444" ? (1,1) : sampling=="422" ? (2,1) : (2,2)
    layout = make_layout(size(image,2),size(image,1),standard_components(h,v),restart_interval)
    planes = component_planes(split_planes(image),layout.factors,layout.mx,layout.my)
    quantization = quantization_tables(codec.basic,quality)
    coefficients = Vector{Int}[]
    for block in layout.blocks
        pixels = planes[block.component][8*block.by+1:8*block.by+8,8*block.bx+1:8*block.bx+8]
        transformed = forward_dct(pixels,codec.transform)
        push!(coefficients,zigzag(quantize(transformed,quantization[layout.components[block.component].tq])))
    end
    (layout=layout,planes=planes,quantization=quantization,coefficients=coefficients)
end
function build_symbols(prepared)
    layout = prepared.layout
    frequencies = Dict(key=>zeros(Int,256) for key in TABLE_KEYS)
    blocks,differences = Vector{NamedTuple}[],Int[]
    for interval in eachindex(layout.intervals)
        predictors = zeros(Int,3)
        for number in interval_blocks(layout,interval)
            block = layout.blocks[number]
            component = layout.components[block.component]
            sequence = prepared.coefficients[number]
            difference = sequence[1]-predictors[block.component]
            predictors[block.component] = sequence[1]
            push!(differences,difference)
            bits,n = extra_bits(difference)
            symbols = [(table=(0,component.td),value=n,extra=bits,width=n)]
            ac_table,run = (1,component.ta),0
            for value in sequence[2:end]
                if value==0
                    run += 1
                    continue
                end
                while run>=16
                    push!(symbols,(table=ac_table,value=240,extra=0,width=0))
                    run -= 16
                end
                bits,n = extra_bits(value)
                push!(symbols,(table=ac_table,value=16run+n,extra=bits,width=n))
                run = 0
            end
            run>0 && push!(symbols,(table=ac_table,value=0,extra=0,width=0))
            for symbol in symbols
                frequencies[symbol.table][symbol.value+1] += 1
            end
            push!(blocks,symbols)
        end
    end
    blocks,differences,frequencies
end
function header_bytes(layout,quantization,tables)
    header,contents = [255,216],Int[]
    for id in 0:1
        append!(contents,[id;zigzag(quantization[id])])
    end
    append!(header,segment(219,contents))
    contents = [8;word(layout.height);word(layout.width);3]
    for c in layout.components
        append!(contents,[c.identifier,16*c.h+c.v,c.tq])
    end
    append!(header,segment(192,contents))
    contents = Int[]
    for (class,id) in TABLE_KEYS
        table = tables[(class,id)]
        append!(contents,[16class+id;table.counts;table.symbols])
    end
    append!(header,segment(196,contents))
    layout.restart_interval>0 && append!(header,segment(221,word(layout.restart_interval)))
    contents = [3]
    for c in layout.components
        append!(contents,[c.identifier,16*c.td+c.ta])
    end
    append!(contents,[0,63,0])
    append!(header,segment(218,contents))
    header
end
function encode_prepared(codec,prepared,mode)
    symbols,differences,frequencies = build_symbols(prepared)
    tables = mode=="standard" ? codec.standard : Dict(key=>optimized_table(frequencies[key]) for key in TABLE_KEYS)
    header = header_bytes(prepared.layout,prepared.quantization,tables)
    writer = BitWriter()
    block_bits,intervals = zeros(Int,length(prepared.coefficients)),NTuple{4,Int}[]
    for (interval,(first,n)) in enumerate(prepared.layout.intervals)
        interval>1 && restart!(writer,interval-2)
        start = length(writer.data)
        for number in interval_blocks(prepared.layout,interval),symbol in symbols[number]
            code_length,code = tables[symbol.table].codes[symbol.value]
            write_bits!(writer,code,code_length)
            write_bits!(writer,symbol.extra,symbol.width)
            block_bits[number] += code_length+symbol.width
        end
        pad_bits!(writer)
        push!(intervals,(first,n,length(header)+start,length(writer.data)-start))
    end
    (
        ;prepared...,
        tables=tables,
        frequencies=frequencies,
        differences=differences,
        block_bits=block_bits,
        intervals=intervals,
        data=[header;writer.data;255;217],
        header_bytes=length(header),
        scan_bytes=length(writer.data),
        padding_bits=writer.padding_bits,
        stuffed_bytes=writer.stuffed_bytes
    )
end
encode(codec,image,q,sampling,mode,restart) = encode_prepared(
    codec,
    prepare(codec,image,q,sampling,restart),
    mode
)
function parse_header(data)
    position,segments = 2,[(0,"SOI",0)]
    quantization,tables = Dict{Int,Matrix{Int}}(),Dict{Tuple{Int,Int},HuffmanTable}()
    restart_interval,width,height,components = 0,0,0,NamedTuple[]
    names = Dict(192=>"SOF0",196=>"DHT",219=>"DQT",221=>"DRI",218=>"SOS",254=>"COM")
    while true
        marker = data[position+2]
        segment_length = read_word(data,position+2)
        contents = data[position+5:position+segment_length+2]
        name = 224<=marker<=239 ? "APP$(marker-224)" : names[marker]
        push!(segments,(position,name,segment_length))
        position += segment_length+2
        if marker==219
            for offset in 0:65:length(contents)-1
                quantization[contents[offset+1]] = unzigzag(contents[offset+2:offset+65])
            end
        elseif marker==196
            offset = 0
            while offset<length(contents)
                class,id = divrem(contents[offset+1],16)
                counts = contents[offset+2:offset+17]
                n = sum(counts)
                tables[(class,id)] = HuffmanTable(counts,contents[offset+18:offset+17+n])
                offset += 17+n
            end
        elseif marker==192
            height,width = read_word(contents,1),read_word(contents,3)
            for index in 0:2
                offset = 6+3index
                h,v = divrem(contents[offset+2],16)
                push!(components,(identifier=contents[offset+1],h=h,v=v,tq=contents[offset+3],td=0,ta=0))
            end
        elseif marker==221
            restart_interval = read_word(contents,0)
        elseif marker==218
            for index in 1:3
                td,ta = divrem(contents[2index+1],16)
                components[index] = (;components[index]...,td=td,ta=ta)
            end
            break
        end
    end
    push!(segments,(length(data)-2,"EOI",0))
    (
        layout=make_layout(width,height,components,restart_interval),
        quantization=quantization,
        tables=tables,
        segments=segments,
        scan_start=position,
        scan_bytes=length(data)-2-position
    )
end
function decode_intervals(data,parsed)
    layout = parsed.layout
    coefficients = [zeros(Int,64) for _ in layout.blocks]
    states = NamedTuple[(state="lost",) for _ in layout.intervals]
    reader,interval = BitReader(data,parsed.scan_start),1
    while interval<=length(layout.intervals)
        predictors,pending = zeros(Int,3),Vector{Int}[]
        current_mcu = layout.intervals[interval][1]
        try
            for number in interval_blocks(layout,interval)
                block = layout.blocks[number]
                current_mcu = block.mcu
                push!(
                    pending,
                    decode_block!(
                        reader,
                        block.component,
                        layout.components[block.component],
                        parsed.tables,
                        predictors
                    )
                )
            end
            discard_bits!(reader)
            expected = interval<length(layout.intervals) ? 208+(interval-1)%8 : 217
            (data[reader.position+1]!=255 || data[reader.position+2]!=expected) && throw(CodecDecodeError("sync"))
            for (number,sequence) in zip(interval_blocks(layout,interval),pending)
                coefficients[number] = sequence
            end
            states[interval] = (state="ok",)
            reader.position += 2
            interval += 1
        catch error
            error isa CodecDecodeError || rethrow()
            offset = reader.position
            discard_bits!(reader)
            resync = find_resync(data,offset)
            states[interval] = (state="damaged",kind=error.kind,mcu=current_mcu,offset=offset,resync=resync)
            marker = data[resync+2]
            marker==217 && break
            interval = interval+1+mod(marker-208-(interval-1),8)
            reader.position = resync+2
        end
    end
    coefficients,states
end
function reconstruct_component(codec,layout,k,coefficients,quantization,keep=64)
    c = layout.components[k]
    plane = fill(128,8*c.v*layout.my,8*c.h*layout.mx)
    for (block,sequence) in zip(layout.blocks,coefficients)
        block.component==k || continue
        pixels = inverse_dct(dequantize(sequence,quantization[c.tq],keep),codec.transform)
        plane[8*block.by+1:8*block.by+8,8*block.bx+1:8*block.bx+8] = pixels
    end
    plane
end
function decode(codec,data)
    parsed = parse_header(data)
    coefficients,states = decode_intervals(data,parsed)
    planes = [reconstruct_component(codec,parsed.layout,k,coefficients,parsed.quantization) for k in 1:3]
    expanded = upsample(planes,parsed.layout.factors,parsed.layout.width,parsed.layout.height)
    (
        ;parsed...,
        coefficients=coefficients,
        states=states,
        planes=planes,
        expanded=expanded,
        image=combine_rgb(expanded)
    )
end
function repair(codec,decoded)
    source = decoded.layout
    first = source.components[1]
    layout = make_layout(
        source.width,
        source.height,
        standard_components(first.h,first.v),
        source.restart_interval
    )
    quantization = Dict(0=>decoded.quantization[first.tq],1=>decoded.quantization[source.components[2].tq])
    encode_prepared(
        codec,
        (layout=layout,planes=nothing,quantization=quantization,coefficients=decoded.coefficients),
        "optimized"
    )
end
plane_values(plane) = [plane[y,x] for y in axes(plane,1) for x in axes(plane,2)]
image_values(image) = [value for y in axes(image,1) for x in axes(image,2) for value in image[y,x]]
psnr_from_error(error,n) = error==0 ? "inf" : @sprintf("%.2f",10*log10(65025*n/error))
function psnr(first,second)
    error = 0
    for (a,b) in zip(first,second)
        difference = a-b
        error += difference*difference
    end
    psnr_from_error(error,length(first))
end
image_psnr(a,b) = psnr(image_values(a),image_values(b))
function quality_metrics(original,original_planes,decoded)
    metrics = [psnr(plane_values(a),plane_values(b)) for (a,b) in zip(original_planes,decoded.expanded)]
    differences = abs.(image_values(original)-image_values(decoded.image))
    push!(metrics,psnr_from_error(sum(value*value for value in differences),length(differences)))
    metrics,maximum(differences)
end
function bits_per_pixel(n,width,height)
    numerator,denominator = 8n,width*height
    divisor = gcd(numerator,denominator)
    "$(numerator÷divisor)/$(denominator÷divisor)"
end
function block_statistics(encoded,decoded)
    lines,errors = [words("blocks",length(encoded.layout.blocks))],Int[]
    for (number,(block,sequence)) in enumerate(zip(encoded.layout.blocks,encoded.coefficients))
        original,restored = encoded.planes[block.component],decoded.planes[block.component]
        error = 0
        for y in 8*block.by+1:8*block.by+8,x in 8*block.bx+1:8*block.bx+8
            difference = original[y,x]-restored[y,x]
            error += difference*difference
        end
        push!(errors,error)
        last = findlast(!=(0),sequence)
        push!(
            lines,
            words(
                "block",
                number-1,
                COMPONENT_NAMES[block.component],
                block.bx,
                block.by,
                "dc",
                sequence[1],
                "diff",
                encoded.differences[number],
                "nonzero",
                count(!=(0),sequence[2:end]),
                "last",
                isnothing(last) ? 0 : last-1,
                "bits",
                encoded.block_bits[number],
                "sse",
                error
            )
        )
    end
    lines,errors
end
function huffman_lines(encoded)
    lines = String[]
    for (key,name) in zip(TABLE_KEYS,TABLE_NAMES)
        table,frequencies = encoded.tables[key],encoded.frequencies[key]
        bits = sum(frequencies[symbol+1]*table.codes[symbol][1] for symbol in table.symbols)
        push!(
            lines,
            words(
                "table",
                name,
                "class",
                key[1],
                "id",
                key[2],
                "symbols",
                length(table.symbols),
                "coded",
                sum(frequencies),
                "bits",
                bits
            )
        )
        push!(lines,"counts "*join(table.counts," "))
        for symbol in table.symbols
            code_length,code = table.codes[symbol]
            push!(
                lines,
                words(
                    "symbol",
                    string(symbol;base=16,pad=2),
                    "length",
                    code_length,
                    "code",
                    string(code;base=2,pad=code_length),
                    "count",
                    frequencies[symbol+1]
                )
            )
        end
    end
    lines
end
function thumbnail(decoded)
    layout = decoded.layout
    dc = Dict((block.component,block.bx,block.by)=>sequence[1] for (block,sequence) in zip(
        layout.blocks,
        decoded.coefficients
    ))
    image = Matrix{NTuple{3,Int}}(undef,cld(layout.height,8),cld(layout.width,8))
    for y in 0:size(image,1)-1,x in 0:size(image,2)-1
        values = Int[]
        for (k,c) in enumerate(layout.components)
            value = dc[(k,x*c.h÷layout.hmax,y*c.v÷layout.vmax)]
            push!(values,clamp_byte(fld(value*decoded.quantization[c.tq][1,1]+4,8)+128))
        end
        image[y+1,x+1] = to_rgb(values...)
    end
    image
end
function reference_report(image,params,codec,original_planes,encoded,decoded,errors)
    layout = encoded.layout
    lines = [
        words("image",layout.width,layout.height),
        words("sampling",params["sampling"],"mcu",8*layout.hmax,8*layout.vmax,"grid",layout.mx,layout.my),
        words("padded",8*layout.hmax*layout.mx,8*layout.vmax*layout.my),
        "blocks "*join([c.h*c.v*layout.mcus for c in layout.components]," "),
        words("restart_interval",layout.restart_interval,"markers",length(layout.intervals)-1),
        words("huffman",params["huffman"]),
        words("quality",params["qualities"][1])
    ]
    for id in 0:1
        push!(lines,words("quant",id,join(zigzag(encoded.quantization[id])," ")))
    end
    push!(lines,"symbols "*join([sum(encoded.frequencies[key]) for key in TABLE_KEYS]," "))
    push!(
        lines,
        words(
            "eob",
            encoded.frequencies[(1,0)][1]+encoded.frequencies[(1,1)][1],
            "zrl",
            encoded.frequencies[(1,0)][241]+encoded.frequencies[(1,1)][241]
        )
    )
    push!(lines,words("zero_ac_blocks",count(sequence->all(==(0),sequence[2:end]),encoded.coefficients)))
    push!(lines,"nonzero "*join([count(sequence->sequence[i]!=0,encoded.coefficients) for i in 1:64]," "))
    for (k,name) in enumerate(COMPONENT_NAMES)
        numbers = [i for (i,block) in enumerate(layout.blocks) if block.component==k]
        push!(
            lines,
            words(
                "component",
                name,
                "bits",
                sum(encoded.block_bits[numbers]),
                "nonzero",
                sum(count(!=(0),encoded.coefficients[i]) for i in numbers),
                "sse",
                sum(errors[numbers])
            )
        )
    end
    for name in (:padding_bits,:stuffed_bytes,:header_bytes,:scan_bytes)
        push!(lines,words(name,getproperty(encoded,name)))
    end
    push!(lines,words("total_bytes",length(encoded.data)))
    for (i,interval) in enumerate(encoded.intervals)
        push!(lines,words("interval",i-1,interval...))
    end
    histogram = zeros(Int,8)
    for (a,b) in zip(image_values(image),image_values(decoded.image))
        histogram[searchsortedlast([1,2,4,8,16,32,64],abs(a-b))+1] += 1
    end
    push!(lines,"error_histogram "*join(histogram," "))
    for keep in params["truncate"]
        plane = reconstruct_component(codec,decoded.layout,1,decoded.coefficients,decoded.quantization,keep)
        push!(
            lines,
            words(
                "truncate",
                keep,
                psnr(plane_values(original_planes[1]),plane_values(plane[1:layout.height,1:layout.width]))
            )
        )
    end
    lines
end
function stream_report(decoded,repaired,repaired_decoded)
    layout = decoded.layout
    lines = [words("stream_segment",entry...) for entry in decoded.segments]
    push!(lines,words("stream_image",layout.width,layout.height))
    for c in layout.components
        push!(lines,words("stream_component",c.identifier,c.h,c.v,c.tq,c.td,c.ta))
    end
    for id in sort!(collect(keys(decoded.quantization)))
        push!(lines,words("stream_quant",id,join(zigzag(decoded.quantization[id])," ")))
    end
    for (class,id) in sort!(collect(keys(decoded.tables)))
        table = decoded.tables[(class,id)]
        push!(
            lines,
            words(
                "stream_huffman",
                class,
                id,
                "symbols",
                length(table.symbols),
                "longest",
                findlast(>(0),table.counts)
            )
        )
    end
    push!(
        lines,
        words(
            "stream_restart",
            layout.restart_interval,
            "intervals",
            length(layout.intervals),
            "ok",
            count(s->s.state=="ok",decoded.states),
            "damaged",
            count(s->s.state=="damaged",decoded.states),
            "lost",
            count(s->s.state=="lost",decoded.states)
        )
    )
    for (i,((first,n),result)) in enumerate(zip(layout.intervals,decoded.states))
        state = result.state=="damaged" ? words(
            "damaged",
            result.kind,
            "mcu",
            result.mcu,
            "offset",
            result.offset,
            "resync",
            result.resync
        ) : result.state
        push!(lines,words("stream_interval",i-1,first,n,state))
    end
    push!(lines,words("stream_scan_bytes",decoded.scan_bytes))
    push!(
        lines,
        words(
            "repair",
            length(repaired.data),
            repaired.header_bytes,
            repaired.scan_bytes,
            "identical",
            decoded.image==repaired_decoded.image ? "yes" : "no"
        )
    )
    lines
end
function main()
    image,params,codec,stream = read_ppm("input/image.ppm"),read_params("input/params.txt"),read_tables("input/tables.txt"),read_hex("input/stream.hex")
    width,height = size(image,2),size(image,1)
    quality,sampling,mode,restart = params["qualities"][1],params["sampling"],params["huffman"],params["restart_interval"]
    original_planes = split_planes(image)
    prepared,encodings,decodings = Dict{Tuple{Int,String},NamedTuple}(),Dict{Tuple{Int,String,String},NamedTuple}(),Dict{Tuple{Int,String},NamedTuple}()
    function encoding(q,s=sampling,m=mode)
        get!(encodings,(q,s,m)) do
            p = get!(prepared,(q,s)) do
                prepare(codec,image,q,s,restart)
            end
            encode_prepared(codec,p,m)
        end
    end
    function decoding(q,s=sampling)
        get!(decodings,(q,s)) do
            decode(codec,encoding(q,s).data)
        end
    end
    rate_lines = ["quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error"]
    for q in params["qualities"]
        standard,optimized,selected = encoding(q,sampling,"standard"),encoding(
            q,
            sampling,
            "optimized"
        ),encoding(q)
        metrics,maximum_error = quality_metrics(image,original_planes,decoding(q))
        push!(
            rate_lines,
            join(
                [
                    string(q),
                    string(length(standard.data)),
                    string(length(optimized.data)),
                    bits_per_pixel(length(selected.data),width,height),
                    metrics...,
                    string(maximum_error)
                ],
                ","
            )
        )
    end
    reference,reference_decoded = encoding(quality),decoding(quality)
    block_lines,errors = block_statistics(reference,reference_decoded)
    report = reference_report(image,params,codec,original_planes,reference,reference_decoded,errors)
    for s in ("444","422","420")
        metrics,_ = quality_metrics(image,original_planes,decoding(quality,s))
        push!(report,words("sampling_compare",s,length(encoding(quality,s).data),join(metrics[2:end]," ")))
    end
    previous = image
    for generation in 1:params["generations"]
        encoded = generation==1 ? reference : encode(codec,previous,quality,sampling,mode,restart)
        decoded = generation==1 ? reference_decoded : decode(codec,encoded.data)
        changed = count(pair->pair[1]!=pair[2],zip(previous,decoded.image))
        push!(
            report,
            words("generation",generation,length(encoded.data),image_psnr(image,decoded.image),changed)
        )
        previous = decoded.image
    end
    lo,hi = 1,100
    while lo<hi
        mid = (lo+hi+1)÷2
        bytes = length(encoding(mid).data)
        push!(report,words("rate_control_step",mid,bytes))
        if bytes<=params["target_bytes"]
            lo = mid
        else
            hi = mid-1
        end
    end
    bytes = length(encoding(lo).data)
    push!(
        report,
        words(
            "rate_control",
            lo,
            bytes,
            bytes<=params["target_bytes"] ? "yes" : "no",
            image_psnr(image,decoding(lo).image)
        )
    )
    stream_decoded = decode(codec,stream)
    repaired = repair(codec,stream_decoded)
    append!(report,stream_report(stream_decoded,repaired,decode(codec,repaired.data)))
    mkpath("output")
    write_ppm("output/decoded.ppm",reference_decoded.image)
    write_hex("output/bitstream.hex",reference.data)
    write_ppm("output/thumbnail.ppm",thumbnail(reference_decoded))
    write_ppm("output/stream_decoded.ppm",stream_decoded.image)
    write_hex("output/repaired.hex",repaired.data)
    for (name,lines) in [
        "rate_distortion.csv"=>rate_lines,
        "huffman_tables.txt"=>huffman_lines(reference),
        "blocks.txt"=>block_lines,
        "report.txt"=>report
    ]
        open(joinpath("output",name),"w") do io
            for line in lines
                println(io,line)
            end
        end
    end
end
main()
