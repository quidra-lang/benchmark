struct CausalEvent
    number::Int
    local_number::Int
    process::Int
    kind::String
    details::NamedTuple
    time::Int
    lamport::Int
    vector::Vector{Int}
    balance::Int
end
Base.@kwdef mutable struct ProcessState
    initial::Int
    balance::Int
    lamport::Int = 0
    vector::Vector{Int}
    broadcast::Vector{Int}
    at::Vector{NamedTuple}
    on::Vector{NamedTuple}
    events::Vector{Int} = Int[]
    next_sequence::Vector{Int}
    reorder::Vector{Dict{Int,Int}}
    holdback::Vector{Int} = Int[]
    delivered::Vector{Int} = Int[]
    max_held::Int = 0
    incoming::Int = 0
    outgoing::Int = 0
    refused::Int = 0
    min_balance::Int
    types::Dict{String,Int} = Dict{String,Int}()
end
function parse_action(words,names)
    kind = words[1]
    if kind in ("LOCAL","BROADCAST","SNAPSHOT")
        return (kind=kind,text=words[2],destination=0,amount=0)
    end
    destination = words[2]=="SENDER" ? 0 : something(findfirst(==(words[2]),names))
    (
        kind=kind,
        text=kind=="SEND" ? words[3] : "transfer",
        destination=destination,
        amount=kind=="TRANSFER" ? parse(Int,words[3]) : 0
    )
end
function read_scripts(names)
    blocks = NamedTuple[]
    balance,at,on = 0,NamedTuple[],NamedTuple[]
    for line in readlines(joinpath("input","programs.txt"))
        words = String.(split(line))
        if words[1]=="PROCESS"
            balance,at,on = parse(Int,words[4]),NamedTuple[],NamedTuple[]
        elseif words[1]=="END"
            push!(blocks,(balance=balance,at=at,on=on))
        elseif words[1]=="AT"
            start = parse(Int,words[2])
            periodic = words[3]=="EVERY"
            push!(
                at,
                (
                    start=start,
                    period=periodic ? parse(Int,words[4]) : 0,
                    action=parse_action(words[(periodic ? 5 : 3):end],names)
                )
            )
        else
            push!(on,(tag=words[2],action=parse_action(words[3:end],names)))
        end
    end
    blocks
end
function initialize_processes(names,blocks)
    n = length(names)
    [ProcessState(initial=block.balance,balance=block.balance,vector=zeros(Int,n),broadcast=zeros(Int,n),at=block.at,on=block.on,
        next_sequence=ones(
            Int,
            n
        ),reorder=[Dict{Int,Int}() for _ in 1:n],min_balance=block.balance) for block in blocks]
end
function schedule_actions(processes,limit,enqueue)
    for (p,process) in enumerate(processes),entry in process.at
        if entry.period==0
            entry.start<=limit && enqueue(entry.start,p,entry.action)
        else
            for time in entry.start:entry.period:limit
                enqueue(time,p,entry.action)
            end
        end
    end
end
reaction_actions(process,tag) = [entry.action for entry in process.on if entry.tag==tag]
balance_at_cut(process,count,events) = count==0 ? process.initial : events[process.events[count]].balance
held_count(process) = sum(length(buffer) for buffer in process.reorder)+length(process.holdback)
