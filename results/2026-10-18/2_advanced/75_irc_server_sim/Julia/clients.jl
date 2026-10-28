Base.@kwdef mutable struct IrcClient
    index::Int
    identifier::String
    hostname::String
    connection_time::Int
    last_received::Int
    tokens::Int
    nickname::Union{Nothing,String} = nothing
    username::Union{Nothing,String} = nothing
    realname::String = ""
    invisible::Bool = false
    registered::Bool = false
    registration_time::Int = -1
    last_speaking::Int = -1
    ping_sent::Int = -1
    refill_time::Int = -1
    queue::Vector{String} = String[]
    channels::Vector{Int} = Int[]
    invites::Vector{Int} = Int[]
    away::String = ""
    received::Int = 0
    sent::Int = 0
    active::Bool = true
end
addressee(client) = isnothing(client.nickname) ? "*" : client.nickname
client_prefix(client) = "$(client.nickname)!$(client.username)@$(client.hostname)"
client_mode(client) = client.invisible ? "+i" : "+"
function use_token!(client,time,capacity,interval)
    client.tokens==capacity && (client.refill_time=time+interval)
    client.tokens -= 1
end
function refill!(client,time,capacity,interval)
    if client.refill_time==time
        client.tokens += 1
        client.refill_time = client.tokens<capacity ? time+interval : -1
    end
end
