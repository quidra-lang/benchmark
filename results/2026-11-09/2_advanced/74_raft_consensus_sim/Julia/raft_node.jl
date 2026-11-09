const NODE_STATISTICS = (
    "elections",
    "leader_terms",
    "votes_granted",
    "leader_ticks",
    "ae_ok",
    "ae_fail",
    "appended",
    "truncated",
    "applies"
)
struct LogEntry
    term::Int
    command::Tuple
    request::Int
end
Base.:(==)(
    left::LogEntry,
    right::LogEntry
) = left.term==right.term && left.command==right.command && left.request==right.request
Base.@kwdef mutable struct RaftNode
    number::Int
    term::Int = 0
    voted_for::Int = 0
    log::Vector{LogEntry} = LogEntry[]
    up::Bool = true
    stats::Dict{String,Int} = Dict(k=>0 for k in NODE_STATISTICS)
    role::String = "FOLLOWER"
    commit::Int = 0
    applied::Int = 0
    store::Dict{String,Int} = Dict{String,Int}()
    known_leader::Int = 0
    votes::Set{Int} = Set{Int}()
    election_deadline::Int = -1
    election_record::Int = 0
    next::Vector{Int} = Int[]
    match::Vector{Int} = Int[]
    heartbeat_deadline::Int = -1
    quorum_deadline::Int = -1
    heard::Set{Int} = Set{Int}()
    transfer_target::Int = 0
    transfer_sent::Bool = false
    transfer_deadline::Int = -1
end
function cancel_transfer!(node)
    node.transfer_target,node.transfer_sent,node.transfer_deadline = 0,false,-1
end
function crash!(node)
    node.up = false
    node.role,node.commit,node.applied = "FOLLOWER",0,0
    node.store,node.known_leader,node.votes = Dict{String,Int}(),0,Set{Int}()
    node.election_deadline,node.election_record = -1,0
    node.next,node.match = Int[],Int[]
    node.heartbeat_deadline,node.quorum_deadline,node.heard = -1,-1,Set{Int}()
    cancel_transfer!(node)
end
last_index(node) = length(node.log)
last_term(node) = isempty(node.log) ? 0 : node.log[end].term
term_at(node,index) = index==0 ? 0 : node.log[index].term
accepts_log(node,index,term) = (term,index)>=(last_term(node),last_index(node))
function apply_command!(store,command)
    operation = command[1]
    operation=="NOOP" && return nothing
    key = command[2]
    if operation=="SET"
        store[key] = command[3]
        return "ok"
    elseif operation=="ADD"
        store[key] = get(store,key,0)+command[3]
        return store[key]
    elseif operation=="DEL"
        if haskey(store,key)
            delete!(store,key)
            return "deleted"
        end
        return "missing"
    end
    get(store,key,"missing")
end
