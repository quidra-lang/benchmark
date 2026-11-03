Base.@kwdef mutable struct ClientRequest
    number::Int
    time::Int
    initial_destination::Int
    command::Tuple
    scheduled::Int
    destination::Int
    attempts::Int = 0
    redirects::Int = 0
    accepted_index::Int = 0
    accepted_term::Int = 0
    abandoned::Bool = false
    status::String = ""
    latency::Int = 0
    result::Union{Nothing,Int,String} = nothing
end
function read_settings()
    values = Dict(f[1]=>parse.(Int,f[2:end]) for f in split.(readlines("input/cluster.txt")))
    (nodes=values["NODES"][1],election_min=values["ELECTION"][1],election_max=values["ELECTION"][2],heartbeat=values["HEARTBEAT"][1],
        batch=values["BATCH"][1],quorum=values["QUORUM"][1],seed=values["SEED"][1],
        finish=values["END"][1],retry=values["RETRY"][1],attempts=values["ATTEMPTS"][1],sample=values["SAMPLE"][1])
end
function read_script()
    controls,requests = NamedTuple[],ClientRequest[]
    for line in readlines("input/script.txt")
        f = split(line)
        time,kind = parse(Int,f[1]),String(f[2])
        if kind=="REQUEST"
            destination = parse(Int,f[3])
            command = f[4] in ("SET","ADD") ? (
                String(f[4]),
                String(f[5]),
                parse(Int,f[6])
            ) : (String(f[4]),String(f[5]))
            push!(
                requests,
                ClientRequest(
                    number=length(requests)+1,
                    time=time,
                    initial_destination=destination,
                    command=command,
                    scheduled=time,
                    destination=destination
                )
            )
        else
            arguments = kind=="PARTITION" ? [parse.(
                Int,
                split(g,',')
            ) for g in f[3:end]] : parse.(Int,f[3:end])
            push!(controls,(time=time,kind=kind,arguments=arguments))
        end
    end
    controls,requests
end
