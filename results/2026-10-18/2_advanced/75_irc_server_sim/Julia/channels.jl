Base.@kwdef mutable struct ChannelMember
    client::Int
    operator::Bool = false
    voice::Bool = false
end
Base.@kwdef mutable struct IrcChannel
    index::Int
    name::String
    created::Int
    members::Vector{ChannelMember} = ChannelMember[]
    topic::String = ""
    topic_setter::String = ""
    topic_time::Int = -1
    bans::Vector{Tuple{String,String,Int}} = Tuple{String,String,Int}[]
    flags::Set{Char} = Set(['n','t'])
    key::String = ""
    limit::Int = 0
    peak::Int = 0
    messages::Int = 0
    active::Bool = true
end
function channel_member(channel,client)
    index = findfirst(m->m.client==client.index,channel.members)
    isnothing(index) ? nothing : channel.members[index]
end
member_status(member) = member.operator ? "@" : member.voice ? "+" : ""
member_display(member,clients) = member_status(member)*clients[member.client].nickname
function channel_add!(channel,client,operator=false)
    member = ChannelMember(client=client.index,operator=operator)
    push!(channel.members,member)
    push!(client.channels,channel.index)
    channel.peak = max(channel.peak,length(channel.members))
    member
end
function channel_remove!(channel,client)
    filter!(m->m.client!=client.index,channel.members)
    filter!(!=(channel.index),client.channels)
end
function name_list(channel,viewer,clients)
    inside = !isnothing(channel_member(channel,viewer))
    join([member_display(m,clients) for m in channel.members if inside || !clients[m.client].invisible],' ')
end
banned(channel,client) = any(b->mask_matches(b[1],client_prefix(client)),channel.bans)
function can_speak(channel,client)
    member = channel_member(channel,client)
    privileged = !isnothing(member) && (member.operator || member.voice)
    (!isnothing(member) || !('n' in channel.flags)) && (!('m' in channel.flags) || privileged) && (privileged || !banned(
        channel,
        client
    ))
end
function mode_display(channel,include_key=true)
    mode = "+"
    for c in "iklmnt"
        present = c=='k' ? !isempty(channel.key) : c=='l' ? channel.limit>0 : c in channel.flags
        present && (mode*=c)
    end
    include_key && !isempty(channel.key) && (mode*=" "*channel.key)
    channel.limit>0 && (mode*=" $(channel.limit)")
    mode
end
