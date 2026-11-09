function encode_lzw(data)
    writer = BitWriter()
    dictionary = Dict{Tuple{Vararg{Int}},Int}((value,)=>value for value in 0:255)
    next_code,since_clear,codes,clears,longest = 258,0,0,0,0
    widths = zeros(Int,4)
    function emit(code,sequence_length=0)
        width = min(12,bits(258+since_clear))
        write_bits!(writer,code,width)
        codes += 1
        widths[width-8] += 1
        longest = max(longest,sequence_length)
        if code==256
            clears += 1
            since_clear = 0
        else
            since_clear += 1
        end
    end
    emit(256)
    sequence = ()
    for value in data
        extended = (sequence...,value)
        if haskey(dictionary,extended)
            sequence = extended
            continue
        end
        emit(dictionary[sequence],length(sequence))
        dictionary[extended] = next_code
        next_code += 1
        if next_code==4096
            emit(256)
            dictionary = Dict{Tuple{Vararg{Int}},Int}((value,)=>value for value in 0:255)
            next_code = 258
        end
        sequence = (value,)
    end
    isempty(sequence) || emit(dictionary[sequence],length(sequence))
    emit(257)
    finish(writer),(codes=codes,clears=clears,widths=widths,longest=longest)
end
function decode_lzw(payload,original)
    reader = BitReader(payload)
    dictionary = vcat([[value] for value in 0:255],[Int[],Int[]])
    previous,since_clear = -1,0
    output = Int[]
    while true
        count = since_clear
        code = read_bits!(reader,min(12,bits(258+count)),length(output))
        if code==256
            dictionary = vcat([[value] for value in 0:255],[Int[],Int[]])
            previous,since_clear = -1,0
            continue
        end
        since_clear += 1
        if code==257
            length(output)<original && throw(DecodeError("early_end",length(output)))
            return output
        end
        count==3838 && throw(DecodeError("bad_code",length(output)))
        next_code = length(dictionary)
        sequence = if previous<0
            code>=256 && throw(DecodeError("bad_code",length(output)))
            dictionary[code+1]
        elseif code<next_code
            dictionary[code+1]
        elseif code==next_code
            vcat(dictionary[previous+1],dictionary[previous+1][1])
        else
            throw(DecodeError("bad_code",length(output)))
        end
        length(output)+length(sequence)>original && throw(DecodeError("overrun",length(output)))
        append!(output,sequence)
        previous<0 || push!(dictionary,vcat(dictionary[previous+1],sequence[1]))
        previous = code
    end
end
