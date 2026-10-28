mutable struct FrequencyTable
    frequencies::Vector{Int}
    total::Int
    rescales::Int
end
FrequencyTable() = FrequencyTable(ones(Int,257),257,0)
function update_frequency!(table,symbol)
    table.frequencies[symbol+1] += 32
    table.total += 32
    if table.total>=8192
        table.frequencies = fld.(table.frequencies.+1,2)
        table.total = sum(table.frequencies)
        table.rescales += 1
    end
end
function encode_arith(data)
    writer = BitWriter()
    tables = Dict{Int,FrequencyTable}()
    low,high,follow,context = 0,65535,0,10
    function emit(bit)
        write_bits!(writer,bit,1)
        for _ in 1:follow
            write_bits!(writer,1-bit,1)
        end
        follow = 0
    end
    for symbol in Iterators.flatten((data,[256]))
        table = get!(FrequencyTable,tables,context)
        cumulative = sum(table.frequencies[1:symbol])
        frequency = table.frequencies[symbol+1]
        span = high-low+1
        high = low+fld(span*(cumulative+frequency),table.total)-1
        low += fld(span*cumulative,table.total)
        while true
            if high<32768
                emit(0)
            elseif low>=32768
                emit(1)
                low -= 32768
                high -= 32768
            elseif low>=16384 && high<49152
                follow += 1
                low -= 16384
                high -= 16384
            else
                break
            end
            low *= 2
            high = 2high+1
        end
        if symbol!=256
            update_frequency!(table,symbol)
            context = symbol
        end
    end
    follow += 1
    emit(low<16384 ? 0 : 1)
    finish(writer),(
        bits=writer.count,
        contexts=length(tables),
        rescales=sum(t.rescales for t in values(tables))
    )
end
function decode_arith(payload,original)
    reader = BitReader(payload;zero_fill=true)
    tables = Dict{Int,FrequencyTable}()
    output = Int[]
    low,high,context = 0,65535,10
    value = read_bits!(reader,16)
    while true
        table = get!(FrequencyTable,tables,context)
        span = high-low+1
        quantile = fld((value-low+1)*table.total-1,span)
        cumulative,symbol = 0,0
        while quantile>=cumulative+table.frequencies[symbol+1]
            cumulative += table.frequencies[symbol+1]
            symbol += 1
        end
        frequency = table.frequencies[symbol+1]
        high = low+fld(span*(cumulative+frequency),table.total)-1
        low += fld(span*cumulative,table.total)
        while true
            if high<32768
            elseif low>=32768
                low -= 32768
                high -= 32768
                value -= 32768
            elseif low>=16384 && high<49152
                low -= 16384
                high -= 16384
                value -= 16384
            else
                break
            end
            low *= 2
            high = 2high+1
            value = 2value+read_bits!(reader,1)
        end
        if symbol==256
            length(output)<original && throw(DecodeError("early_end",length(output)))
            return output
        end
        length(output)==original && throw(DecodeError("overrun",length(output)))
        push!(output,symbol)
        update_frequency!(table,symbol)
        context = symbol
    end
end
