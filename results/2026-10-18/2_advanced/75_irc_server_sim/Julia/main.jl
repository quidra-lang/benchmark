include("protocol.jl")
include("masks.jl")
include("clients.jl")
include("channels.jl")
include("modes.jl")

words(parts...) = join(string.(parts)," ")
const SIMPLE_NUMERICS = Dict(305=>":You are no longer marked as being away",306=>":You have been marked as being away",
    376=>":End of /MOTD command.",409=>":No origin specified",412=>":No text to send",431=>":No nickname given",
    451=>":You have not registered",462=>":You may not reregister",501=>":Unknown MODE flag",502=>":Cannot change mode for other users")
Base.@kwdef mutable struct IrcServer
    settings::Dict{String,Any}
    traffic::Vector{NamedTuple}
    finish::Int
    time::Int = 0
    clients::Vector{IrcClient} = IrcClient[]
    client_index::Dict{String,Int} = Dict{String,Int}()
    channels::Vector{IrcChannel} = IrcChannel[]
    channel_index::Dict{String,Int} = Dict{String,Int}()
    sent::Vector{String} = String[]
    commands::Dict{String,Int} = Dict{String,Int}()
    numeric_counts::Dict{Int,Int} = Dict{Int,Int}()
    line_counts::Dict{String,Int} = Dict{String,Int}()
    statistics::Dict{String,Int} = Dict{String,Int}()
    disconnections::Dict{String,Int} = Dict{String,Int}()
    gone::Vector{Tuple{Int,String,String,String}} = Tuple{Int,String,String,String}[]
    peak_connections::Tuple{Int,Int} = (0,0)
    peak_registered::Tuple{Int,Int} = (0,0)
end
bump!(counts,key,amount=1) = (counts[key]=get(counts,key,0)+amount)
active_clients(s) = [c for c in s.clients if c.active]
active_channels(s) = [c for c in s.channels if c.active]
function read_inputs()
    settings = Dict{String,Any}("MOTD"=>String[])
    integers = Set([
        "NICKLEN",
        "CHANNELLEN",
        "TOPICLEN",
        "MAXCHANNELS",
        "BUCKET",
        "REFILL",
        "QUEUE",
        "PINGFREQ",
        "TIMEOUT"
    ])
    for line in readlines("input/server.txt")
        key,value = split(line,' ';limit=2)
        if key=="MOTD"
            push!(settings[key],value)
        else
            settings[key] = key in integers ? parse(Int,value) : String(value)
        end
    end
    traffic = NamedTuple[]
    counts = Dict{String,Int}()
    for line in readlines("input/traffic.txt")
        time,id,body = split(line,' ';limit=3)
        kind = occursin(
            r"^CONNECT [A-Za-z0-9.-]{1,63}$",
            body
        ) ? "connect" : body=="DISCONNECT" ? "disconnect" : "messages"
        push!(traffic,(time=parse(Int,time),identifier=String(id),kind=kind,body=String(body)))
        bump!(counts,kind)
    end
    IrcServer(settings=settings,traffic=traffic,finish=traffic[end].time,line_counts=counts)
end
function send_line!(s,client,line)
    push!(s.sent,"$(s.time) $(client.identifier) $line")
    client.sent += 1
end
function numeric!(
    s,
    client,
    number;channel=nothing,
    user=nothing,
    x="",
    command="",
    character='?',
    ban=nothing,
    motd="",
    display="",
    names="",
    channel_list=""
)
    v = s.settings
    if haskey(SIMPLE_NUMERICS,number)
        content = SIMPLE_NUMERICS[number]
    elseif number==1
        content = ":Welcome to the Internet Relay Network "*client_prefix(client)
    elseif number==2
        content = ":Your host is $(v["NAME"]), running version $(v["VERSION"])"
    elseif number==3
        content = ":This server was created $(v["CREATED"])"
    elseif number==4
        content = "$(v["NAME"]) $(v["VERSION"]) i biklmnotv"
    elseif number==5
        content = "CASEMAPPING=rfc1459 CHANTYPES=# NICKLEN=$(v["NICKLEN"]) CHANNELLEN=$(v["CHANNELLEN"]) "*
            "TOPICLEN=$(v["TOPICLEN"]) CHANLIMIT=#:$(v["MAXCHANNELS"]) CHANMODES=b,k,l,imnt PREFIX=(ov)@+ :are supported by this server"
    elseif number==221
        content = client_mode(client)
    elseif number==301
        content = "$(user.nickname) :$(user.away)"
    elseif number==311
        content = "$(user.nickname) $(user.username) $(user.hostname) * :$(user.realname)"
    elseif number==312
        content = "$(user.nickname) $(v["NAME"]) :$(v["DESCRIPTION"])"
    elseif number==317
        content = "$(user.nickname) $(s.time-user.last_speaking) $(user.registration_time) :seconds idle, signon time"
    elseif number==318
        content = "$x :End of /WHOIS list."
    elseif number==319
        content = "$(user.nickname) :$channel_list"
    elseif number==324
        content = "$(channel.name) $display"
    elseif number==329
        content = "$(channel.name) $(channel.created)"
    elseif number==331
        content = "$(channel.name) :No topic is set"
    elseif number==332
        content = "$(channel.name) :$(channel.topic)"
    elseif number==333
        content = "$(channel.name) $(channel.topic_setter) $(channel.topic_time)"
    elseif number==341
        content = "$(user.nickname) $(channel.name)"
    elseif number==353
        content = "= $(channel.name) :$names"
    elseif number==366
        content = "$x :End of /NAMES list."
    elseif number==367
        content = words(channel.name,ban...)
    elseif number==368
        content = "$(channel.name) :End of channel ban list"
    elseif number==372
        content = ":- $motd"
    elseif number==375
        content = ":- $(v["NAME"]) Message of the day -"
    elseif number==401
        content = "$x :No such nick/channel"
    elseif number==403
        content = "$x :No such channel"
    elseif number==404
        content = "$(channel.name) :Cannot send to channel"
    elseif number==405
        content = "$x :You have joined too many channels"
    elseif number==411
        content = ":No recipient given ($command)"
    elseif number==421
        content = "$command :Unknown command"
    elseif number==432
        content = "$x :Erroneous nickname"
    elseif number==433
        content = "$x :Nickname is already in use"
    elseif number==441
        content = "$(user.nickname) $(channel.name) :They aren't on that channel"
    elseif number==442
        content = "$(channel.name) :You're not on that channel"
    elseif number==443
        content = "$(user.nickname) $(channel.name) :is already on channel"
    elseif number==461
        content = "$command :Not enough parameters"
    elseif number==467
        content = "$(channel.name) :Channel key already set"
    elseif number in (471,473,474,475)
        mode = Dict(471=>'l',473=>'i',474=>'b',475=>'k')[number]
        content = "$(channel.name) :Cannot join channel (+$mode)"
    elseif number==472
        content = "$character :is unknown mode char to me for $(channel.name)"
    else
        content = "$(channel.name) :You're not channel operator"
    end
    bump!(s.numeric_counts,number)
    send_line!(s,client,":$(v["NAME"]) $(lpad(string(number),3,'0')) $(addressee(client)) $content")
end
function broadcast_channel!(s,channel,line,exclude=0)
    for member in channel.members
        member.client!=exclude && send_line!(s,s.clients[member.client],line)
    end
end
function send_peers!(s,client,line)
    peers = Set(m.client for id in client.channels for m in s.channels[id].members)
    for other in s.clients
        other.active && other.index!=client.index && other.index in peers && send_line!(s,other,line)
    end
end
function find_user(s,nickname)
    name = irc_fold(nickname)
    index = findfirst(c->c.active && c.registered && irc_fold(c.nickname)==name,s.clients)
    isnothing(index) ? nothing : s.clients[index]
end
function find_channel(s,name)
    index = get(s.channel_index,irc_fold(name),0)
    index==0 ? nothing : s.channels[index]
end
function joined_channels(s,client,separator)
    join(
        [member_status(channel_member(s.channels[i],client))*s.channels[i].name for i in client.channels],
        separator
    )
end
function remove_member!(s,client,channel)
    channel_remove!(channel,client)
    if isempty(channel.members)
        channel.active = false
        delete!(s.channel_index,irc_fold(channel.name))
        for other in s.clients
            other.active && filter!(!=(channel.index),other.invites)
        end
    end
end
function disconnect!(s,client,reason,kind)
    if kind!="closed"
        send_line!(s,client,"ERROR :Closing Link: $(addressee(client))[$(client.hostname)] ($reason)")
        bump!(s.statistics,"errors")
    end
    client.registered && send_peers!(s,client,":"*client_prefix(client)*" QUIT :$reason")
    for i in copy(client.channels)
        remove_member!(s,client,s.channels[i])
    end
    bump!(s.statistics,"discarded",length(client.queue))
    empty!(client.queue)
    delete!(s.client_index,client.identifier)
    client.active = false
    push!(s.gone,(s.time,client.identifier,addressee(client),reason))
    bump!(s.disconnections,kind)
end
function complete_registration!(s,client)
    (client.registered || isnothing(client.nickname) || isnothing(client.username)) && return
    client.registered,client.registration_time,client.last_speaking = true,s.time,s.time
    registered = count(c->c.active && c.registered,s.clients)
    registered>s.peak_registered[1] && (s.peak_registered=(registered,s.time))
    for number in (1,2,3,4,5,375)
        numeric!(s,client,number)
    end
    for line in s.settings["MOTD"]
        numeric!(s,client,372;motd=line)
    end
    numeric!(s,client,376)
    client.invisible && send_line!(s,client,":$(client.nickname) MODE $(client.nickname) :+i")
end
function require_parameters(s,c,p,n,command)
    length(p)>=n && return true
    numeric!(s,c,461;command=command)
    false
end
function nick!(s,c,p)
    if isempty(p) || isempty(p[1])
        numeric!(s,c,431)
        return
    end
    nickname = first(p[1],s.settings["NICKLEN"])
    if !valid_nickname(nickname)
        numeric!(s,c,432;x=nickname)
        return
    end
    nickname==c.nickname && return
    if any(
        o->o.active && o.index!=c.index && !isnothing(o.nickname) && irc_fold(o.nickname)==irc_fold(nickname),
        s.clients
    )
        numeric!(s,c,433;x=nickname)
        return
    end
    if c.registered
        line = ":$(client_prefix(c)) NICK :$nickname"
        send_line!(s,c,line)
        send_peers!(s,c,line)
    end
    c.nickname = nickname
    complete_registration!(s,c)
end
function user!(s,c,p)
    if !isnothing(c.username)
        numeric!(s,c,462)
        return
    end
    require_parameters(s,c,p,4,"USER") || return
    c.username,c.realname = p[1],p[4]
    c.invisible = is_digits(p[2]) && length(p[2])<=3 && (parse(Int,p[2])÷8)%2==1
    complete_registration!(s,c)
end
function names_reply!(s,c,channel)
    names = name_list(channel,c,s.clients)
    !isempty(names) && numeric!(s,c,353;channel=channel,names=names)
    numeric!(s,c,366;x=channel.name)
end
function join_channels!(s,c,p)
    require_parameters(s,c,p,1,"JOIN") || return
    if p[1]=="0"
        for i in copy(c.channels)
            channel = s.channels[i]
            broadcast_channel!(s,channel,":$(client_prefix(c)) PART $(channel.name)")
            remove_member!(s,c,channel)
        end
        return
    end
    keys = length(p)>=2 ? split(p[2],',') : String[]
    for (i,name) in enumerate(split(p[1],','))
        key = i<=length(keys) ? keys[i] : ""
        if !valid_channel(name,s.settings["CHANNELLEN"])
            numeric!(s,c,403;x=name)
            continue
        end
        channel = find_channel(s,name)
        !isnothing(channel) && !isnothing(channel_member(channel,c)) && continue
        if length(c.channels)>=s.settings["MAXCHANNELS"]
            numeric!(s,c,405;x=name)
            continue
        end
        if isnothing(channel)
            channel = IrcChannel(index=length(s.channels)+1,name=String(name),created=s.time)
            push!(s.channels,channel)
            s.channel_index[irc_fold(name)] = channel.index
        else
            invited = channel.index in c.invites
            failure = banned(channel,c) && !invited ? 474 : 'i' in channel.flags && !invited ? 473 :
                !isempty(channel.key) && key!=channel.key ? 475 : channel.limit>0 && length(channel.members)>=channel.limit ? 471 : 0
            if failure!=0
                numeric!(s,c,failure;channel=channel)
                continue
            end
        end
        filter!(!=(channel.index),c.invites)
        channel_add!(channel,c,isempty(channel.members))
        broadcast_channel!(s,channel,":$(client_prefix(c)) JOIN $(channel.name)")
        if !isempty(channel.topic)
            numeric!(s,c,332;channel=channel)
            numeric!(s,c,333;channel=channel)
        end
        names_reply!(s,c,channel)
    end
end
function part_channels!(s,c,p)
    require_parameters(s,c,p,1,"PART") || return
    suffix = length(p)>=2 && !isempty(p[2]) ? " :"*p[2] : ""
    for name in split(p[1],',')
        channel = find_channel(s,name)
        if isnothing(channel)
            numeric!(s,c,403;x=name)
        elseif isnothing(channel_member(channel,c))
            numeric!(s,c,442;channel=channel)
        else
            broadcast_channel!(s,channel,":$(client_prefix(c)) PART $(channel.name)$suffix")
            remove_member!(s,c,channel)
        end
    end
end
function message!(s,c,p,command)
    replies = command=="PRIVMSG"
    replies && (c.last_speaking=s.time)
    if isempty(p) || isempty(p[1])
        replies && numeric!(s,c,411;command=command)
        return
    elseif length(p)<2 || isempty(p[2])
        replies && numeric!(s,c,412)
        return
    end
    text = p[2]
    for target in split(p[1],',')
        if startswith(target,"#")
            channel = find_channel(s,target)
            if isnothing(channel)
                replies && numeric!(s,c,401;x=target)
            elseif !can_speak(channel,c)
                replies && numeric!(s,c,404;channel=channel)
            else
                channel.messages += 1
                broadcast_channel!(s,channel,":$(client_prefix(c)) $command $(channel.name) :$text",c.index)
            end
        else
            user = find_user(s,target)
            if isnothing(user)
                replies && numeric!(s,c,401;x=target)
                continue
            end
            send_line!(s,user,":$(client_prefix(c)) $command $(user.nickname) :$text")
            replies && !isempty(user.away) && numeric!(s,c,301;user=user)
        end
    end
end
function topic!(s,c,p)
    require_parameters(s,c,p,1,"TOPIC") || return
    channel = find_channel(s,p[1])
    if isnothing(channel)
        numeric!(s,c,403;x=p[1])
        return
    end
    member = channel_member(channel,c)
    if isnothing(member)
        numeric!(s,c,442;channel=channel)
        return
    elseif length(p)==1
        numeric!(s,c,isempty(channel.topic) ? 331 : 332;channel=channel)
        !isempty(channel.topic) && numeric!(s,c,333;channel=channel)
        return
    elseif 't' in channel.flags && !member.operator
        numeric!(s,c,482;channel=channel)
        return
    end
    channel.topic,channel.topic_setter,channel.topic_time = first(
        p[2],
        s.settings["TOPICLEN"]
    ),c.nickname,s.time
    broadcast_channel!(s,channel,":$(client_prefix(c)) TOPIC $(channel.name) :$(channel.topic)")
end
function names!(s,c,p)
    if isempty(p)
        numeric!(s,c,366;x="*")
        return
    end
    for name in split(p[1],',')
        channel = find_channel(s,name)
        isnothing(channel) ? numeric!(s,c,366;x=name) : names_reply!(s,c,channel)
    end
end
function whois!(s,c,p)
    if isempty(p)
        numeric!(s,c,431)
        return
    end
    user = find_user(s,p[1])
    if isnothing(user)
        numeric!(s,c,401;x=p[1])
        numeric!(s,c,318;x=p[1])
        return
    end
    numeric!(s,c,311;user=user)
    !isempty(user.channels) && numeric!(s,c,319;user=user,channel_list=joined_channels(s,user," "))
    numeric!(s,c,312;user=user)
    !isempty(user.away) && numeric!(s,c,301;user=user)
    numeric!(s,c,317;user=user)
    numeric!(s,c,318;x=user.nickname)
end
function invite!(s,c,p)
    require_parameters(s,c,p,2,"INVITE") || return
    user = find_user(s,p[1])
    if isnothing(user)
        numeric!(s,c,401;x=p[1])
        return
    end
    channel = find_channel(s,p[2])
    if isnothing(channel)
        numeric!(s,c,403;x=p[2])
        return
    end
    member = channel_member(channel,c)
    if isnothing(member)
        numeric!(s,c,442;channel=channel)
        return
    elseif !isnothing(channel_member(channel,user))
        numeric!(s,c,443;user=user,channel=channel)
        return
    elseif 'i' in channel.flags && !member.operator
        numeric!(s,c,482;channel=channel)
        return
    end
    !(channel.index in user.invites) && push!(user.invites,channel.index)
    numeric!(s,c,341;user=user,channel=channel)
    !isempty(user.away) && numeric!(s,c,301;user=user)
    send_line!(s,user,":$(client_prefix(c)) INVITE $(user.nickname) :$(channel.name)")
end
function kick!(s,c,p)
    require_parameters(s,c,p,2,"KICK") || return
    channel = find_channel(s,p[1])
    if isnothing(channel)
        numeric!(s,c,403;x=p[1])
        return
    end
    member = channel_member(channel,c)
    if isnothing(member)
        numeric!(s,c,442;channel=channel)
        return
    elseif !member.operator
        numeric!(s,c,482;channel=channel)
        return
    end
    user = find_user(s,p[2])
    if isnothing(user)
        numeric!(s,c,401;x=p[2])
        return
    elseif isnothing(channel_member(channel,user))
        numeric!(s,c,441;user=user,channel=channel)
        return
    end
    reason = length(p)>=3 && !isempty(p[3]) ? p[3] : c.nickname
    broadcast_channel!(s,channel,":$(client_prefix(c)) KICK $(channel.name) $(user.nickname) :$reason")
    remove_member!(s,user,channel)
end
function user_mode!(s,c,p)
    user = find_user(s,p[1])
    if isnothing(user)
        numeric!(s,c,401;x=p[1])
        return
    elseif user.index!=c.index
        numeric!(s,c,502)
        return
    elseif length(p)==1
        numeric!(s,c,221)
        return
    end
    sign,changes,unknown = '+',Tuple{Char,Char,Union{Nothing,String}}[],false
    for character in p[2]
        if character in "+-"
            sign = character
        elseif character=='i'
            desired = sign=='+'
            if c.invisible!=desired
                c.invisible = desired
                push!(changes,(sign,character,nothing))
            end
        else
            unknown = true
        end
    end
    !isempty(changes) && send_line!(s,c,":$(c.nickname) MODE $(c.nickname) :$(change_string(changes))")
    unknown && numeric!(s,c,501)
end
function apply_channel_mode!(s,c,channel,sign,character,argument)
    adding,changed,change_argument = sign=='+',false,nothing
    if character in "ov"
        user = find_user(s,argument)
        if isnothing(user)
            numeric!(s,c,401;x=argument)
            return nothing
        end
        member = channel_member(channel,user)
        if isnothing(member)
            numeric!(s,c,441;user=user,channel=channel)
            return nothing
        end
        before = character=='o' ? member.operator : member.voice
        if before!=adding
            character=='o' ? (member.operator=adding) : (member.voice=adding)
            changed,change_argument = true,user.nickname
        end
    elseif character=='b'
        mask = normalize_mask(argument)
        found = findfirst(b->irc_fold(b[1])==irc_fold(mask),channel.bans)
        if adding && isnothing(found)
            push!(channel.bans,(mask,c.nickname,s.time))
            changed,change_argument = true,mask
        elseif !adding && !isnothing(found)
            change_argument = channel.bans[found][1]
            deleteat!(channel.bans,found)
            changed = true
        end
    elseif character=='k'
        if adding
            if !isempty(channel.key)
                numeric!(s,c,467;channel=channel)
            else
                channel.key = argument
                changed,change_argument = true,argument
            end
        elseif !isempty(channel.key)
            channel.key = ""
            changed,change_argument = true,"*"
        end
    elseif character=='l'
        if adding
            limit = parse(Int,argument)
            if channel.limit!=limit
                channel.limit = limit
                changed,change_argument = true,string(limit)
            end
        elseif channel.limit>0
            channel.limit = 0
            changed = true
        end
    elseif adding && !(character in channel.flags)
        push!(channel.flags,character)
        changed = true
    elseif !adding && character in channel.flags
        delete!(channel.flags,character)
        changed = true
    end
    changed ? (sign,character,change_argument) : nothing
end
function channel_mode!(s,c,p)
    channel = find_channel(s,p[1])
    if isnothing(channel)
        numeric!(s,c,403;x=p[1])
        return
    elseif length(p)==1
        numeric!(s,c,324;channel=channel,display=mode_display(channel,!isnothing(channel_member(channel,c))))
        numeric!(s,c,329;channel=channel)
        return
    end
    items = channel_items(p[2],p[3:end])
    member = channel_member(channel,c)
    authorized = !isnothing(member) && member.operator
    bans_sent,denial_sent,changes = false,false,Tuple{Char,Char,Union{Nothing,String}}[]
    for (sign,character,argument) in items
        if !(character in "biklmnotv")
            numeric!(s,c,472;character=character,channel=channel)
            continue
        elseif character=='b' && isnothing(argument)
            if sign=='+' && !bans_sent
                for ban in channel.bans
                    numeric!(s,c,367;channel=channel,ban=ban)
                end
                numeric!(s,c,368;channel=channel)
                bans_sent = true
            end
            continue
        elseif isnothing(argument) && (character in "ov" || (sign=='+' && character in "kl"))
            continue
        elseif !authorized
            !denial_sent && numeric!(s,c,482;channel=channel)
            denial_sent = true
            continue
        end
        change = apply_channel_mode!(s,c,channel,sign,character,argument)
        !isnothing(change) && push!(changes,change)
    end
    !isempty(changes) && broadcast_channel!(
        s,
        channel,
        ":$(client_prefix(c)) MODE $(channel.name) $(change_string(changes))"
    )
end
function process_line!(s,c,raw)
    bump!(s.statistics,"processed")
    command,p = parse_message(raw)
    if isempty(command)
        bump!(s.statistics,"empty")
        return
    end
    bump!(s.commands,command)
    if !c.registered && !(command in ("NICK","USER","PING","PONG","QUIT"))
        numeric!(s,c,451)
        return
    end
    if command=="NICK"
        nick!(s,c,p)
    elseif command=="USER"
        user!(s,c,p)
    elseif command=="PING"
        if isempty(p) || isempty(p[1])
            numeric!(s,c,409)
        else
            name = s.settings["NAME"]
            send_line!(s,c,":$name PONG $name :$(p[1])")
        end
    elseif command=="PONG"
        return
    elseif command=="QUIT"
        reason = !isempty(p) && !isempty(p[1]) ? "Quit: "*p[1] : "Client Quit"
        disconnect!(s,c,reason,"quit")
    elseif command=="JOIN"
        join_channels!(s,c,p)
    elseif command=="PART"
        part_channels!(s,c,p)
    elseif command in ("PRIVMSG","NOTICE")
        message!(s,c,p,command)
    elseif command=="TOPIC"
        topic!(s,c,p)
    elseif command=="NAMES"
        names!(s,c,p)
    elseif command=="WHOIS"
        whois!(s,c,p)
    elseif command=="AWAY"
        c.away = !isempty(p) && !isempty(p[1]) ? p[1] : ""
        numeric!(s,c,isempty(c.away) ? 305 : 306)
    elseif command=="INVITE"
        invite!(s,c,p)
    elseif command=="KICK"
        kick!(s,c,p)
    elseif command=="MODE"
        require_parameters(s,c,p,1,"MODE") || return
        startswith(p[1],"#") ? channel_mode!(s,c,p) : user_mode!(s,c,p)
    else
        numeric!(s,c,421;command=command)
    end
end
function arrival!(s,record)
    id,kind,body = record.identifier,record.kind,record.body
    if kind=="connect"
        c = IrcClient(
            index=length(s.clients)+1,
            identifier=id,
            hostname=body[9:end],
            connection_time=s.time,
            last_received=s.time,
            tokens=s.settings["BUCKET"]
        )
        push!(s.clients,c)
        s.client_index[id] = c.index
        n = length(s.client_index)
        n>s.peak_connections[1] && (s.peak_connections=(n,s.time))
        return
    end
    index = get(s.client_index,id,0)
    if kind=="disconnect"
        index!=0 && disconnect!(s,s.clients[index],"Remote host closed the connection","closed")
        return
    elseif index==0
        bump!(s.statistics,"dropped")
        return
    end
    c = s.clients[index]
    c.received,c.last_received,c.ping_sent = c.received+1,s.time,-1
    if isempty(c.queue) && c.tokens>=1
        use_token!(c,s.time,s.settings["BUCKET"],s.settings["REFILL"])
        process_line!(s,c,body)
    elseif length(c.queue)>=s.settings["QUEUE"]
        bump!(s.statistics,"discarded")
        disconnect!(s,c,"Excess Flood","flood")
    else
        push!(c.queue,body)
        bump!(s.statistics,"queued")
    end
end
function run_server!(s)
    position = 1
    for time in 0:s.finish
        s.time = time
        for c in active_clients(s)
            refill!(c,time,s.settings["BUCKET"],s.settings["REFILL"])
            while c.active && !isempty(c.queue) && c.tokens>=1
                use_token!(c,time,s.settings["BUCKET"],s.settings["REFILL"])
                process_line!(s,c,popfirst!(c.queue))
            end
        end
        while position<=length(s.traffic) && s.traffic[position].time==time
            arrival!(s,s.traffic[position])
            position += 1
        end
        for c in active_clients(s)
            if c.ping_sent!=-1
                time-c.ping_sent>=s.settings["TIMEOUT"] && disconnect!(
                    s,
                    c,
                    "Ping timeout: $(time-c.last_received) seconds",
                    "timeout"
                )
            elseif time-c.last_received>=s.settings["PINGFREQ"]
                send_line!(s,c,"PING :$(s.settings["NAME"])")
                bump!(s.statistics,"pings")
                c.ping_sent = time
            end
        end
    end
end
function channel_report(s)
    lines = String[]
    channels = active_channels(s)
    for ch in channels
        push!(
            lines,
            words(
                "CHANNEL",
                ch.name,
                "created",
                ch.created,
                "members",
                length(ch.members),
                "peak",
                ch.peak,
                "messages",
                ch.messages,
                "modes",
                mode_display(ch)
            )
        )
        push!(lines,isempty(ch.topic) ? "TOPIC none" : words("TOPIC",ch.topic_setter,ch.topic_time,ch.topic))
        for ban in ch.bans
            push!(lines,words("BAN",ban...))
        end
        push!(lines,"MEMBERS "*join([member_display(m,s.clients) for m in ch.members],' '))
    end
    push!(
        lines,
        words(
            "TOTAL channels",
            length(channels),
            "members",
            sum((length(ch.members) for ch in channels);init=0),
            "bans",
            sum((length(ch.bans) for ch in channels);init=0)
        )
    )
    lines
end
function client_report(s)
    lines = String[]
    clients = active_clients(s)
    for c in clients
        username = isnothing(c.username) ? "*" : c.username
        signon = c.registered ? string(c.registration_time) : "-"
        channels = isempty(c.channels) ? "none" : joined_channels(s,c,",")
        invites = isempty(c.invites) ? "none" : join([s.channels[i].name for i in c.invites],',')
        push!(lines,words("CLIENT",c.identifier,addressee(c),username,c.hostname,client_mode(c),"connected",c.connection_time,"signon",signon,
            "received",c.received,"sent",c.sent,"tokens",c.tokens,"queue",length(c.queue),"channels",channels,"invites",invites))
        !isempty(c.away) && push!(lines,words("AWAY",c.identifier,c.away))
    end
    push!(
        lines,
        words(
            "TOTAL clients",
            length(clients),
            "registered",
            count(c->c.registered,clients),
            "invisible",
            count(c->c.invisible,clients),
            "away",
            count(c->!isempty(c.away),clients)
        )
    )
    lines
end
function statistics_report(s)
    pending = sum((length(c.queue) for c in s.clients if c.active);init=0)
    stat(key) = get(s.statistics,key,0)
    lines = ["END $(s.finish)",words("LINES total",length(s.traffic),"connect",get(s.line_counts,"connect",0),
        "disconnect",get(s.line_counts,"disconnect",0),"messages",get(s.line_counts,"messages",0)),
        words(
            "MESSAGES dropped",
            stat("dropped"),
            "queued",
            stat("queued"),
            "processed",
            stat("processed"),
            "discarded",
            stat("discarded"),
            "pending",
            pending,
            "empty",
            stat("empty")
        ),
        words(
            "SENT lines",
            length(s.sent),
            "numerics",
            sum(values(s.numeric_counts);init=0),
            "pings",
            stat("pings"),
            "errors",
            stat("errors")
        )]
    for command in sort!(collect(keys(s.commands)))
        push!(lines,words("COMMAND",command,s.commands[command]))
    end
    for number in sort!(collect(keys(s.numeric_counts)))
        push!(lines,words("NUMERIC",lpad(string(number),3,'0'),s.numeric_counts[number]))
    end
    push!(lines,words("PEAK connections",s.peak_connections[1],"at",s.peak_connections[2]))
    push!(lines,words("PEAK registered",s.peak_registered[1],"at",s.peak_registered[2]))
    push!(
        lines,
        "DISCONNECTS "*join(
            [words(kind,get(s.disconnections,kind,0)) for kind in ("quit","closed","flood","timeout")],
            ' '
        )
    )
    for record in s.gone
        push!(lines,words("GONE",record...))
    end
    lines
end
function main()
    s = read_inputs()
    run_server!(s)
    outputs = [
        ("sent.txt",s.sent),
        ("channels.txt",channel_report(s)),
        ("clients.txt",client_report(s)),
        ("stats.txt",statistics_report(s))
    ]
    mkpath("output")
    for (filename,lines) in outputs
        write(joinpath("output",filename),isempty(lines) ? "" : join(lines,"\n")*"\n")
    end
end
main()
