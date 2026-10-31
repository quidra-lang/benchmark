decimal_integer(text, maximum=typemax(Int)) = length(text) <= maximum && occursin(r"^(0|[1-9][0-9]*)$", text)
valid_hex_address(text) = occursin(r"^[0-9a-f]{8}$", text)
hex_address(value) = string(value; base=16, pad=8)
read_trace() = readlines("input/trace.txt")

function read_config()
    config = Dict{Symbol,Any}(:scenarios => NamedTuple[], :regions => NamedTuple[], :watch => Int[])
    for line in readlines("input/config.txt")
        fields = split(line, ' ')
        kind = fields[1]
        if kind in ("CORES", "LINE", "INTERVAL", "TOP")
            config[Dict(
                "CORES" => :cores,
                "LINE" => :line_size,
                "INTERVAL" => :interval,
                "TOP" => :top
            )[kind]] = parse(Int, fields[2])
        elseif kind in ("L1", "L2")
            prefix = lowercase(kind)
            config[Symbol(prefix * "_size")] = parse(Int, fields[2])
            config[Symbol(prefix * "_ways")] = parse(Int, fields[3])
        elseif kind == "LATENCY"
            for (key, value) in zip((:t1, :t2, :tm, :tb), fields[2:end])
                config[key] = parse(Int, value)
            end
        elseif kind == "SCENARIO"
            push!(
                config[:scenarios],
                (
                    name=String(fields[2]),
                    protocol=String(fields[3]),
                    l1=String(fields[4]),
                    l2=String(fields[5]),
                    order=length(config[:scenarios])
                )
            )
        elseif kind == "PRIMARY"
            config[:primary] = String(fields[2])
        elseif kind == "REGION"
            push!(
                config[:regions],
                (
                    name=String(fields[2]),
                    low=parse(Int, fields[3]; base=16),
                    high=parse(Int, fields[4]; base=16)
                )
            )
        elseif kind == "WATCH"
            push!(config[:watch], parse(Int, fields[2]; base=16) ÷ config[:line_size])
        end
    end
    config[:l1_sets] = config[:l1_size] ÷ (config[:line_size] * config[:l1_ways])
    config[:l2_sets] = config[:l2_size] ÷ (config[:line_size] * config[:l2_ways])
    config[:cap] = config[:l1_sets] * config[:l1_ways]
    return (; config...)
end

function write_lines(filename, lines)
    mkpath("output")
    write(joinpath("output", filename), join((line * "\n" for line in lines)))
end
