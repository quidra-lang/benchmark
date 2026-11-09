struct Bid
    number::Int
    bidder::Int
    bundle::Int
    amount::Int
    xor::Bool
end
records(name) = split.(readlines(joinpath("input", name)))
function read_inputs()
    reserves = Dict(String(row[1]) => parse(Int, row[2]) for row in records("items.txt"))
    raw = Dict{String,Any}()
    current = nothing
    for fields in records("bids.txt")
        if fields[1] == "auction"
            current = (name=String(fields[2]), items=String.(fields[3:end]), lines=Any[])
            raw[current.name] = current
        else
            push!(
                current.lines,
                (name=String(fields[2]), language=String(fields[3]), texts=String.(fields[4:end]))
            )
        end
    end
    groups = Any[]
    for fields in records("single_item.txt")
        if fields[1] in ("lot", "slots")
            current = (
                kind=String(fields[1]),
                name=String(fields[2]),
                arguments=String.(fields[3:end]),
                participants=Any[]
            )
            push!(groups, current)
        else
            push!(
                current.participants,
                (name=String(fields[2]), value=parse(Int, fields[3]), bid=parse(Int, fields[4]))
            )
        end
    end
    parameters = Dict{String,Any}()
    for fields in records("params.txt")
        parameters[String(fields[1])] = fields[1] == "run" ? String.(fields[2:end]) : parse(Int, fields[2])
    end
    return reserves, raw, groups, parameters
end
