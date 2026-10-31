load 'protocol.ijs'
load 'masks.ijs'
load 'clients.ijs'
load 'channels.ijs'
load 'modes.ijs'

integer =: 3 : 0
    text =. ":y
    '-'(I.text='_')}text
)
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do.
            result =. result,x
        end.
        result =. result,i{::y
    end.
    result
)
number_text =: 3 : '_3{.''000'',integer y'
read_lines =: 3 : '<;._2 (1!:1 <y)'
read_inputs =: 3 : 0
    Motd =: 0$a:
    for_line. read_lines 'input/server.txt' do.
        'key value' =. split_first >line
        select. key
        case. 'NAME' do. ServerName =: value
        case. 'VERSION' do. ServerVersion =: value
        case. 'CREATED' do. ServerCreated =: value
        case. 'DESCRIPTION' do. ServerDescription =: value
        case. 'NICKLEN' do. NickLength =: ".value
        case. 'CHANNELLEN' do. ChannelLength =: ".value
        case. 'TOPICLEN' do. TopicLength =: ".value
        case. 'MAXCHANNELS' do. MaxChannels =: ".value
        case. 'BUCKET' do. BucketCapacity =: ".value
        case. 'REFILL' do. RefillInterval =: ".value
        case. 'QUEUE' do. QueueLimit =: ".value
        case. 'PINGFREQ' do. PingFrequency =: ".value
        case. 'TIMEOUT' do. TimeoutLimit =: ".value
        case. 'MOTD' do. Motd =: Motd,<value
        end.
    end.
    Traffic =: 0$a:
    LineCounts =: 3$0
    for_line. read_lines 'input/traffic.txt' do.
        'time rest' =. split_first >line
        'identifier body' =. split_first rest
        kind =. 2
        if. 'CONNECT '-:8{.body do.
            host =. 8}.body
            valid =. (1<:#host)*.((#host)<:63)*.*./host e.Letters,'0123456789.-'
            if. valid do.
                kind =. 0
            end.
        elseif. body-:'DISCONNECT' do.
            kind =. 1
        end.
        Traffic =: Traffic,< (".time);identifier;kind;body
        LineCounts =: (1+kind{LineCounts)kind}LineCounts
    end.
    EndTime =: 0{::>{:Traffic
    i.0
)
initialize_state =: 3 : 0
    initialize_clients ''
    initialize_channels ''
    CurrentTime =: 0
    SentLines =: 0$a:
    CommandNames =: 0$a:
    CommandCounts =: i.0
    NumericCounts =: 1000$0
    Gone =: 0$a:
    DisconnectCounts =: 4$0
    PeakConnections =: 0 0
    PeakRegistered =: 0 0
    Dropped =: 0
    Queued =: 0
    Processed =: 0
    Discarded =: 0
    EmptyMessages =: 0
    PingCount =: 0
    ErrorCount =: 0
    i.0
)
send =: 4 : 0
    SentLines =: SentLines,<(integer CurrentTime),' ',(x{::ClientIds),' ',y
    SentCounts =: (1+x{SentCounts)x}SentCounts
    i.0
)
numeric =: 4 : 0
    'number content' =. y
    NumericCounts =: (1+number{NumericCounts)number}NumericCounts
    x send ':',ServerName,' ',(number_text number),' ',(addressee x),' ',content
)
broadcast =: 4 : 0
    'line excluded' =. y
    for_client. x{::Members do.
        if. client~:excluded do.
            client send line
        end.
    end.
    i.0
)
send_peers =: 4 : 0
    peers =. i.0
    for_channel. x{::Joined do.
        peers =. peers,channel{::Members
    end.
    peers =. ~.peers
    for_client. I.Active do.
        if. (client~:x)*.client e.peers do.
            client send y
        end.
    end.
    i.0
)
find_connection =: 3 : 0
    index =. ClientIds i.<y
    if. index<#ClientIds do.
        if. index{Active do.
            index return.
        end.
    end.
    _1
)
find_user =: 3 : 0
    name =. fold y
    for_client. I.Active do.
        if. client{Registered do.
            if. name-:fold client{::Nicknames do.
                client return.
            end.
        end.
    end.
    _1
)
find_channel =: 3 : 0
    name =. fold y
    for_channel. I.ChannelActive do.
        if. name-:fold channel{::ChannelNames do.
            channel return.
        end.
    end.
    _1
)
joined_channels =: 4 : 0
    names =. 0$a:
    for_channel. y{::Joined do.
        names =. names,<(channel member_status y),channel{::ChannelNames
    end.
    x join names
)
remove_member =: 4 : 0
    if. x erase_member y do.
        ChannelActive =: 0 x}ChannelActive
        for_client. I.Active do.
            Invites =: (<(client{::Invites)-.x)client}Invites
        end.
    end.
    i.0
)
disconnect =: 4 : 0
    client =. x
    'reason kind' =. y
    if. kind~:1 do.
        client send 'ERROR :Closing Link: ',(addressee client),'[',(client{::Hosts),'] (',reason,')'
        ErrorCount =: ErrorCount+1
    end.
    if. client{Registered do.
        client send_peers ':',(prefix client),' QUIT :',reason
    end.
    channels =. client{::Joined
    for_channel. channels do.
        channel remove_member client
    end.
    Discarded =: Discarded+#client{::Queues
    Queues =: (<0$a:)client}Queues
    Active =: 0 client}Active
    Gone =: Gone,<CurrentTime;(client{::ClientIds);(addressee client);reason
    DisconnectCounts =: (1+kind{DisconnectCounts)kind}DisconnectCounts
    i.0
)
complete_registration =: 3 : 0
    if. y{Registered do.
        i.0 return.
    end.
    if. (0=#y{::Nicknames)+.0=#y{::Usernames do.
        i.0 return.
    end.
    Registered =: 1 y}Registered
    SignonTimes =: CurrentTime y}SignonTimes
    LastSpeaking =: CurrentTime y}LastSpeaking
    count =. +/Active*.Registered
    if. count>0{PeakRegistered do.
        PeakRegistered =: count,CurrentTime
    end.
    y numeric 1;':Welcome to the Internet Relay Network ',prefix y
    y numeric 2;':Your host is ',ServerName,', running version ',ServerVersion
    y numeric 3;':This server was created ',ServerCreated
    y numeric 4;ServerName,' ',ServerVersion,' i biklmnotv'
    content =. 'CASEMAPPING=rfc1459 CHANTYPES=# NICKLEN=',(integer NickLength),' CHANNELLEN=',integer ChannelLength
    content =. content,' TOPICLEN=',(integer TopicLength),' CHANLIMIT=#:',integer MaxChannels
    content =. content,' CHANMODES=b,k,l,imnt PREFIX=(ov)@+ :are supported by this server'
    y numeric 5;content
    y numeric 375;':- ',ServerName,' Message of the day -'
    for_line. Motd do.
        y numeric 372;':- ',>line
    end.
    y numeric 376;':End of /MOTD command.'
    if. y{Invisible do.
        nickname =. y{::Nicknames
        y send ':',nickname,' MODE ',nickname,' :+i'
    end.
    i.0
)
names_reply =: 4 : 0
    names =. y name_list x
    if. #names do.
        x numeric 353;'= ',(y{::ChannelNames),' :',names
    end.
    x numeric 366;(y{::ChannelNames),' :End of /NAMES list.'
)
require_parameters =: 4 : 0
    'parameters count' =. y
    if. (#parameters)<count do.
        x numeric 461;CurrentCommand,' :Not enough parameters'
        0
    else.
        1
    end.
)
command_nick =: 4 : 0
    client =. x
    parameters =. y
    if. 0=#parameters do.
        client numeric 431;':No nickname given'
        i.0 return.
    end.
    nickname =. 0{::parameters
    if. 0=#nickname do.
        client numeric 431;':No nickname given'
        i.0 return.
    end.
    nickname =. (NickLength<.#nickname){.nickname
    if. -.valid_nickname nickname do.
        client numeric 432;nickname,' :Erroneous nickname'
        i.0 return.
    end.
    if. nickname-:client{::Nicknames do.
        i.0 return.
    end.
    for_other. I.Active do.
        if. other~:client do.
            if. (fold nickname)-:fold other{::Nicknames do.
                client numeric 433;nickname,' :Nickname is already in use'
                i.0 return.
            end.
        end.
    end.
    if. client{Registered do.
        line =. ':',(prefix client),' NICK :',nickname
        client send line
        client send_peers line
    end.
    Nicknames =: (<nickname)client}Nicknames
    complete_registration client
)
command_user =: 4 : 0
    if. #x{::Usernames do.
        x numeric 462;':You may not reregister'
        i.0 return.
    end.
    if. -.x require_parameters (<y),<4 do.
        i.0 return.
    end.
    Usernames =: (0{y)x}Usernames
    Realnames =: (3{y)x}Realnames
    mode =. 1{::y
    invisible =. 0
    if. (digits mode)*.(#mode)<:3 do.
        invisible =. 1=2|(".mode)intdiv 8
    end.
    Invisible =: invisible x}Invisible
    complete_registration x
)
command_ping =: 4 : 0
    if. 0=#y do.
        x numeric 409;':No origin specified'
        i.0 return.
    end.
    origin =. 0{::y
    if. 0=#origin do.
        x numeric 409;':No origin specified'
        i.0 return.
    end.
    x send ':',ServerName,' PONG ',ServerName,' :',origin
)
command_quit =: 4 : 0
    reason =. 'Client Quit'
    if. #y do.
        if. #0{::y do.
            reason =. 'Quit: ',0{::y
        end.
    end.
    x disconnect reason;0
)
command_join =: 4 : 0
    client =. x
    parameters =. y
    if. -.client require_parameters (<parameters),<1 do.
        i.0 return.
    end.
    if. (,'0')-:,0{::parameters do.
        channels =. client{::Joined
        for_channel. channels do.
            line =. ':',(prefix client),' PART ',channel{::ChannelNames
            channel broadcast line;_1
            channel remove_member client
        end.
        i.0 return.
    end.
    keys =. 0$a:
    if. 1<#parameters do.
        keys =. split_commas 1{::parameters
    end.
    names =. split_commas 0{::parameters
    for_i. i.#names do.
        name =. i{::names
        key =. ''
        if. i<#keys do.
            key =. i{::keys
        end.
        if. -.ChannelLength valid_channel name do.
            client numeric 403;name,' :No such channel'
            continue.
        end.
        channel =. find_channel name
        if. channel>:0 do.
            if. 0<:channel member_index client do.
                continue.
            end.
        end.
        if. MaxChannels<:#client{::Joined do.
            client numeric 405;name,' :You have joined too many channels'
            continue.
        end.
        if. channel=_1 do.
            channel =. new_channel name
        else.
            invited =. channel e.client{::Invites
            failure =. 0
            if. (channel banned client)*.-.invited do.
                failure =. 474
            elseif. ('i'e.channel{::Flags)*.-.invited do.
                failure =. 473
            elseif. #channel{::Keys do.
                if. -.key-:channel{::Keys do.
                    failure =. 475
                end.
            end.
            if. failure=0 do.
                if. channel{Limits do.
                    if. (channel{Limits)<:#channel{::Members do.
                        failure =. 471
                    end.
                end.
            end.
            if. failure do.
                suffix =. (474 473 475 471 i.failure){::'b';'i';'k';'l'
                client numeric failure;(channel{::ChannelNames),' :Cannot join channel (+',suffix,')'
                continue.
            end.
        end.
        Invites =: (<(client{::Invites)-.channel)client}Invites
        channel add_member client
        channel broadcast (':',(prefix client),' JOIN ',channel{::ChannelNames);_1
        if. #channel{::Topics do.
            client numeric 332;(channel{::ChannelNames),' :',channel{::Topics
            client numeric 333;(channel{::ChannelNames),' ',(channel{::TopicSetters),' ',integer channel{TopicTimes
        end.
        client names_reply channel
    end.
    i.0
)
command_part =: 4 : 0
    client =. x
    parameters =. y
    if. -.client require_parameters (<parameters),<1 do.
        i.0 return.
    end.
    suffix =. ''
    if. 1<#parameters do.
        if. #1{::parameters do.
            suffix =. ' :',1{::parameters
        end.
    end.
    for_name. split_commas 0{::parameters do.
        name =. >name
        channel =. find_channel name
        if. channel=_1 do.
            client numeric 403;name,' :No such channel'
        elseif. _1=channel member_index client do.
            client numeric 442;(channel{::ChannelNames),' :You''re not on that channel'
        else.
            line =. ':',(prefix client),' PART ',(channel{::ChannelNames),suffix
            channel broadcast line;_1
            channel remove_member client
        end.
    end.
    i.0
)
command_message =: 4 : 0
    client =. x
    parameters =. y
    replies =. CurrentCommand-:'PRIVMSG'
    if. replies do.
        LastSpeaking =: CurrentTime client}LastSpeaking
    end.
    missing =. 0=#parameters
    if. -.missing do.
        missing =. 0=#0{::parameters
    end.
    if. missing do.
        if. replies do.
            client numeric 411;':No recipient given (',CurrentCommand,')'
        end.
        i.0 return.
    end.
    missing =. 2>#parameters
    if. -.missing do.
        missing =. 0=#1{::parameters
    end.
    if. missing do.
        if. replies do.
            client numeric 412;':No text to send'
        end.
        i.0 return.
    end.
    text =. 1{::parameters
    for_target. split_commas 0{::parameters do.
        target =. >target
        if. '#'={.target do.
            channel =. find_channel target
            if. channel=_1 do.
                if. replies do.
                    client numeric 401;target,' :No such nick/channel'
                end.
            elseif. -.channel can_speak client do.
                if. replies do.
                    client numeric 404;(channel{::ChannelNames),' :Cannot send to channel'
                end.
            else.
                MessageCounts =: (1+channel{MessageCounts)channel}MessageCounts
                line =. ':',(prefix client),' ',CurrentCommand,' ',(channel{::ChannelNames),' :',text
                channel broadcast line;client
            end.
        else.
            user =. find_user target
            if. user=_1 do.
                if. replies do.
                    client numeric 401;target,' :No such nick/channel'
                end.
                continue.
            end.
            user send ':',(prefix client),' ',CurrentCommand,' ',(user{::Nicknames),' :',text
            if. replies*.0<#user{::AwayMessages do.
                client numeric 301;(user{::Nicknames),' :',user{::AwayMessages
            end.
        end.
    end.
    i.0
)
command_topic =: 4 : 0
    client =. x
    parameters =. y
    if. -.client require_parameters (<parameters),<1 do.
        i.0 return.
    end.
    channel =. find_channel 0{::parameters
    if. channel=_1 do.
        client numeric 403;(0{::parameters),' :No such channel'
        i.0 return.
    end.
    member =. channel member_index client
    if. member=_1 do.
        client numeric 442;(channel{::ChannelNames),' :You''re not on that channel'
        i.0 return.
    end.
    if. 1=#parameters do.
        if. #channel{::Topics do.
            client numeric 332;(channel{::ChannelNames),' :',channel{::Topics
            client numeric 333;(channel{::ChannelNames),' ',(channel{::TopicSetters),' ',integer channel{TopicTimes
        else.
            client numeric 331;(channel{::ChannelNames),' :No topic is set'
        end.
        i.0 return.
    end.
    if. ('t'e.channel{::Flags)*.-.member{channel{::Operators do.
        client numeric 482;(channel{::ChannelNames),' :You''re not channel operator'
        i.0 return.
    end.
    topic =. 1{::parameters
    topic =. (TopicLength<.#topic){.topic
    Topics =: (<topic)channel}Topics
    TopicSetters =: (client{Nicknames)channel}TopicSetters
    TopicTimes =: CurrentTime channel}TopicTimes
    channel broadcast (':',(prefix client),' TOPIC ',(channel{::ChannelNames),' :',topic);_1
)
command_names =: 4 : 0
    if. 0=#y do.
        x numeric 366;'* :End of /NAMES list.'
        i.0 return.
    end.
    for_name. split_commas 0{::y do.
        name =. >name
        channel =. find_channel name
        if. channel=_1 do.
            x numeric 366;name,' :End of /NAMES list.'
        else.
            x names_reply channel
        end.
    end.
    i.0
)
command_whois =: 4 : 0
    if. 0=#y do.
        x numeric 431;':No nickname given'
        i.0 return.
    end.
    name =. 0{::y
    user =. find_user name
    if. user=_1 do.
        x numeric 401;name,' :No such nick/channel'
        x numeric 318;name,' :End of /WHOIS list.'
        i.0 return.
    end.
    nickname =. user{::Nicknames
    x numeric 311;nickname,' ',(user{::Usernames),' ',(user{::Hosts),' * :',user{::Realnames
    if. #user{::Joined do.
        x numeric 319;nickname,' :',' 'joined_channels user
    end.
    x numeric 312;nickname,' ',ServerName,' :',ServerDescription
    if. #user{::AwayMessages do.
        x numeric 301;nickname,' :',user{::AwayMessages
    end.
    idle =. CurrentTime-user{LastSpeaking
    x numeric 317;nickname,' ',(integer idle),' ',(integer user{SignonTimes),' :seconds idle, signon time'
    x numeric 318;nickname,' :End of /WHOIS list.'
)
command_away =: 4 : 0
    message =. ''
    if. #y do.
        message =. 0{::y
    end.
    AwayMessages =: (<message)x}AwayMessages
    if. #message do.
        x numeric 306;':You have been marked as being away'
    else.
        x numeric 305;':You are no longer marked as being away'
    end.
)
command_invite =: 4 : 0
    if. -.x require_parameters (<y),<2 do.
        i.0 return.
    end.
    user =. find_user 0{::y
    if. user=_1 do.
        x numeric 401;(0{::y),' :No such nick/channel'
        i.0 return.
    end.
    channel =. find_channel 1{::y
    if. channel=_1 do.
        x numeric 403;(1{::y),' :No such channel'
        i.0 return.
    end.
    member =. channel member_index x
    if. member=_1 do.
        x numeric 442;(channel{::ChannelNames),' :You''re not on that channel'
        i.0 return.
    end.
    if. 0<:channel member_index user do.
        x numeric 443;(user{::Nicknames),' ',(channel{::ChannelNames),' :is already on channel'
        i.0 return.
    end.
    if. ('i'e.channel{::Flags)*.-.member{channel{::Operators do.
        x numeric 482;(channel{::ChannelNames),' :You''re not channel operator'
        i.0 return.
    end.
    if. -.channel e.user{::Invites do.
        Invites =: (<(user{::Invites),channel)user}Invites
    end.
    x numeric 341;(user{::Nicknames),' ',channel{::ChannelNames
    if. #user{::AwayMessages do.
        x numeric 301;(user{::Nicknames),' :',user{::AwayMessages
    end.
    user send ':',(prefix x),' INVITE ',(user{::Nicknames),' :',channel{::ChannelNames
)
command_kick =: 4 : 0
    if. -.x require_parameters (<y),<2 do.
        i.0 return.
    end.
    channel =. find_channel 0{::y
    if. channel=_1 do.
        x numeric 403;(0{::y),' :No such channel'
        i.0 return.
    end.
    member =. channel member_index x
    if. member=_1 do.
        x numeric 442;(channel{::ChannelNames),' :You''re not on that channel'
        i.0 return.
    end.
    if. -.member{channel{::Operators do.
        x numeric 482;(channel{::ChannelNames),' :You''re not channel operator'
        i.0 return.
    end.
    user =. find_user 1{::y
    if. user=_1 do.
        x numeric 401;(1{::y),' :No such nick/channel'
        i.0 return.
    end.
    if. _1=channel member_index user do.
        x numeric 441;(user{::Nicknames),' ',(channel{::ChannelNames),' :They aren''t on that channel'
        i.0 return.
    end.
    reason =. x{::Nicknames
    if. 2<#y do.
        if. #2{::y do.
            reason =. 2{::y
        end.
    end.
    channel broadcast (':',(prefix x),' KICK ',(channel{::ChannelNames),' ',(user{::Nicknames),' :',reason);_1
    channel remove_member user
)
apply_channel_mode =: 4 : 0
    client =. x
    'channel sign character argument has_argument' =. y
    adding =. sign='+'
    changed =. 0
    change_argument =. ''
    change_has_argument =. 0
    if. character e.'ov' do.
        user =. find_user argument
        if. user=_1 do.
            client numeric 401;argument,' :No such nick/channel'
            0$a: return.
        end.
        member =. channel member_index user
        if. member=_1 do.
            client numeric 441;(user{::Nicknames),' ',(channel{::ChannelNames),' :They aren''t on that channel'
            0$a: return.
        end.
        privileges =. channel{::Operators
        if. character='v' do.
            privileges =. channel{::Voices
        end.
        if. adding~:member{privileges do.
            privileges =. adding member}privileges
            if. character='o' do.
                Operators =: (<privileges)channel}Operators
            else.
                Voices =: (<privileges)channel}Voices
            end.
            changed =. 1
            change_argument =. user{::Nicknames
            change_has_argument =. 1
        end.
    elseif. character='b' do.
        mask =. normalize_mask argument
        bans =. channel{::Bans
        found =. _1
        for_i. i.#bans do.
            if. (fold mask)-:fold 0{::i{::bans do.
                found =. i
                break.
            end.
        end.
        if. adding*.found=_1 do.
            bans =. bans,<mask;(client{::Nicknames);CurrentTime
            changed =. 1
            change_argument =. mask
        elseif. (-.adding)*.found~:_1 do.
            change_argument =. 0{::found{::bans
            bans =. (found~:i.#bans)#bans
            changed =. 1
        end.
        Bans =: (<bans)channel}Bans
        change_has_argument =. changed
    elseif. character='k' do.
        if. adding do.
            if. #channel{::Keys do.
                client numeric 467;(channel{::ChannelNames),' :Channel key already set'
            else.
                Keys =: (<argument)channel}Keys
                changed =. 1
                change_argument =. argument
            end.
        elseif. #channel{::Keys do.
            Keys =: (<'')channel}Keys
            changed =. 1
            change_argument =. '*'
        end.
        change_has_argument =. changed
    elseif. character='l' do.
        if. adding do.
            value =. ".argument
            if. value~:channel{Limits do.
                Limits =: value channel}Limits
                changed =. 1
                change_argument =. integer value
                change_has_argument =. 1
            end.
        elseif. channel{Limits do.
            Limits =: 0 channel}Limits
            changed =. 1
        end.
    else.
        flags =. channel{::Flags
        if. adding*.(-.character e.flags) do.
            flags =. flags,character
            changed =. 1
        elseif. (-.adding)*.character e.flags do.
            flags =. flags-.character
            changed =. 1
        end.
        Flags =: (<flags)channel}Flags
    end.
    if. changed do.
        sign;character;change_argument;change_has_argument
    else.
        0$a:
    end.
)
user_mode =: 4 : 0
    client =. x
    parameters =. y
    user =. find_user 0{::parameters
    if. user=_1 do.
        client numeric 401;(0{::parameters),' :No such nick/channel'
        i.0 return.
    end.
    if. user~:client do.
        client numeric 502;':Cannot change mode for other users'
        i.0 return.
    end.
    if. 1=#parameters do.
        client numeric 221;client_mode client
        i.0 return.
    end.
    sign =. '+'
    changes =. 0$a:
    unknown =. 0
    for_character. 1{::parameters do.
        if. character e.'+-' do.
            sign =. character
        elseif. character='i' do.
            desired =. sign='+'
            if. desired~:client{Invisible do.
                Invisible =: desired client}Invisible
                changes =. changes,<sign;character;'';0
            end.
        else.
            unknown =. 1
        end.
    end.
    if. #changes do.
        nickname =. client{::Nicknames
        client send ':',nickname,' MODE ',nickname,' :',change_string changes
    end.
    if. unknown do.
        client numeric 501;':Unknown MODE flag'
    end.
    i.0
)
channel_mode =: 4 : 0
    client =. x
    parameters =. y
    channel =. find_channel 0{::parameters
    if. channel=_1 do.
        client numeric 403;(0{::parameters),' :No such channel'
        i.0 return.
    end.
    member =. channel member_index client
    if. 1=#parameters do.
        display =. (member>:0)mode_display channel
        client numeric 324;(channel{::ChannelNames),' ',display
        client numeric 329;(channel{::ChannelNames),' ',integer channel{CreatedTimes
        i.0 return.
    end.
    authorized =. 0
    if. member>:0 do.
        authorized =. member{channel{::Operators
    end.
    bans_sent =. 0
    denial_sent =. 0
    changes =. 0$a:
    items =. (1{::parameters)channel_items 2}.parameters
    for_item. items do.
        'sign character argument has_argument' =. >item
        if. -.character e.'biklmnotv' do.
            client numeric 472;character,' :is unknown mode char to me for ',channel{::ChannelNames
            continue.
        end.
        if. (character='b')*.-.has_argument do.
            if. (sign='+')*.-.bans_sent do.
                for_ban. channel{::Bans do.
                    'mask setter time' =. >ban
                    client numeric 367;(channel{::ChannelNames),' ',mask,' ',setter,' ',integer time
                end.
                client numeric 368;(channel{::ChannelNames),' :End of channel ban list'
                bans_sent =. 1
            end.
            continue.
        end.
        if. (-.has_argument)*.((character e.'ov')+.((sign='+')*.character e.'kl')) do.
            continue.
        end.
        if. -.authorized do.
            if. -.denial_sent do.
                client numeric 482;(channel{::ChannelNames),' :You''re not channel operator'
                denial_sent =. 1
            end.
            continue.
        end.
        change =. client apply_channel_mode channel;sign;character;argument;has_argument
        if. #change do.
            changes =. changes,<change
        end.
    end.
    if. #changes do.
        channel broadcast (':',(prefix client),' MODE ',(channel{::ChannelNames),' ',change_string changes);_1
    end.
    i.0
)
command_mode =: 4 : 0
    if. -.x require_parameters (<y),<1 do.
        i.0 return.
    end.
    if. '#'={.0{::y do.
        x channel_mode y
    else.
        x user_mode y
    end.
)
process_raw =: 4 : 0
    Processed =: Processed+1
    'command parameters' =. parse_message y
    if. 0=#command do.
        EmptyMessages =: EmptyMessages+1
        i.0 return.
    end.
    index =. CommandNames i.<command
    if. index=#CommandNames do.
        CommandNames =: CommandNames,<command
        CommandCounts =: CommandCounts,1
    else.
        CommandCounts =: (1+index{CommandCounts)index}CommandCounts
    end.
    if. -.x{Registered do.
        if. -. (<command)e.'NICK';'USER';'PING';'PONG';'QUIT' do.
            x numeric 451;':You have not registered'
            i.0 return.
        end.
    end.
    CurrentCommand =: command
    select. command
    case. 'NICK' do. x command_nick parameters
    case. 'USER' do. x command_user parameters
    case. 'PING' do. x command_ping parameters
    case. 'PONG' do. i.0
    case. 'QUIT' do. x command_quit parameters
    case. 'JOIN' do. x command_join parameters
    case. 'PART' do. x command_part parameters
    case. 'PRIVMSG' do. x command_message parameters
    case. 'NOTICE' do. x command_message parameters
    case. 'TOPIC' do. x command_topic parameters
    case. 'NAMES' do. x command_names parameters
    case. 'WHOIS' do. x command_whois parameters
    case. 'AWAY' do. x command_away parameters
    case. 'INVITE' do. x command_invite parameters
    case. 'KICK' do. x command_kick parameters
    case. 'MODE' do. x command_mode parameters
    case. do. x numeric 421;command,' :Unknown command'
    end.
    i.0
)
arrival =: 3 : 0
    'time identifier kind body' =. y
    if. kind=0 do.
        new_client (<identifier),(<8}.body),(<CurrentTime),<BucketCapacity
        count =. +/Active
        if. count>0{PeakConnections do.
            PeakConnections =: count,CurrentTime
        end.
        i.0 return.
    end.
    client =. find_connection identifier
    if. kind=1 do.
        if. client>:0 do.
            client disconnect 'Remote host closed the connection';1
        end.
        i.0 return.
    end.
    if. client=_1 do.
        Dropped =: Dropped+1
        i.0 return.
    end.
    ReceivedCounts =: (1+client{ReceivedCounts)client}ReceivedCounts
    LastReceived =: CurrentTime client}LastReceived
    PingTimes =: _1 client}PingTimes
    queue =. client{::Queues
    if. (0=#queue)*.0<client{Tokens do.
        use_token client
        client process_raw body
    elseif. QueueLimit<:#queue do.
        Discarded =: Discarded+1
        client disconnect 'Excess Flood';2
    else.
        Queues =: (<queue,<body)client}Queues
        Queued =: Queued+1
    end.
    i.0
)
run_simulation =: 3 : 0
    position =. 0
    for_time. i.1+EndTime do.
        CurrentTime =: time
        clients =. I.Active
        for_client. clients do.
            refill_tokens client
            while. (client{Active)*.(0<#client{::Queues)*.0<client{Tokens do.
                use_token client
                queue =. client{::Queues
                raw =. 0{::queue
                Queues =: (<}.queue)client}Queues
                client process_raw raw
            end.
        end.
        while. position<#Traffic do.
            record =. position{::Traffic
            if. CurrentTime~:0{::record do.
                break.
            end.
            arrival record
            position =. position+1
        end.
        clients =. I.Active
        for_client. clients do.
            ping_time =. client{PingTimes
            if. ping_time>:0 do.
                if. TimeoutLimit<:CurrentTime-ping_time do.
                    reason =. 'Ping timeout: ',(integer CurrentTime-client{LastReceived),' seconds'
                    client disconnect reason;3
                end.
            elseif. PingFrequency<:CurrentTime-client{LastReceived do.
                client send 'PING :',ServerName
                PingCount =: PingCount+1
                PingTimes =: CurrentTime client}PingTimes
            end.
        end.
    end.
    i.0
)
channel_report =: 3 : 0
    lines =. 0$a:
    total_members =. 0
    total_bans =. 0
    for_channel. I.ChannelActive do.
        members =. channel{::Members
        bans =. channel{::Bans
        total_members =. total_members+#members
        total_bans =. total_bans+#bans
        line =. 'CHANNEL ',(channel{::ChannelNames),' created ',(integer channel{CreatedTimes),' members ',integer #members
        line =. line,' peak ',(integer channel{MemberPeaks),' messages ',(integer channel{MessageCounts),' modes ',1 mode_display channel
        lines =. lines,<line
        if. #channel{::Topics do.
            lines =. lines,<'TOPIC ',(channel{::TopicSetters),' ',(integer channel{TopicTimes),' ',channel{::Topics
        else.
            lines =. lines,<'TOPIC none'
        end.
        for_ban. bans do.
            'mask setter time' =. >ban
            lines =. lines,<'BAN ',mask,' ',setter,' ',integer time
        end.
        names =. 0$a:
        for_client. members do.
            names =. names,<channel member_display client
        end.
        lines =. lines,<'MEMBERS ',' 'join names
    end.
    lines,<'TOTAL channels ',(integer +/ChannelActive),' members ',(integer total_members),' bans ',integer total_bans
)
client_report =: 3 : 0
    lines =. 0$a:
    away =. 0
    for_client. I.Active do.
        username =. client{::Usernames
        if. 0=#username do.
            username =. '*'
        end.
        signon =. '-'
        if. client{Registered do.
            signon =. integer client{SignonTimes
        end.
        channels =. ','joined_channels client
        if. 0=#channels do.
            channels =. 'none'
        end.
        invites =. ','join (client{::Invites){ChannelNames
        if. 0=#invites do.
            invites =. 'none'
        end.
        line =. 'CLIENT ',(client{::ClientIds),' ',(addressee client),' ',username,' ',(client{::Hosts),' ',client_mode client
        line =. line,' connected ',(integer client{ConnectionTimes),' signon ',signon,' received ',integer client{ReceivedCounts
        line =. line,' sent ',(integer client{SentCounts),' tokens ',(integer client{Tokens),' queue ',integer #client{::Queues
        line =. line,' channels ',channels,' invites ',invites
        lines =. lines,<line
        if. #client{::AwayMessages do.
            lines =. lines,<'AWAY ',(client{::ClientIds),' ',client{::AwayMessages
            away =. away+1
        end.
    end.
    registered =. +/Active*.Registered
    invisible =. +/Active*.Invisible
    lines,<'TOTAL clients ',(integer +/Active),' registered ',(integer registered),' invisible ',(integer invisible),' away ',integer away
)
statistics_report =: 3 : 0
    pending =. 0
    for_client. I.Active do.
        pending =. pending+#client{::Queues
    end.
    lines =. <'END ',integer EndTime
    line =. 'LINES total ',(integer #Traffic),' connect ',(integer 0{LineCounts),' disconnect ',(integer 1{LineCounts),' messages ',integer 2{LineCounts
    lines =. lines,<line
    line =. 'MESSAGES dropped ',(integer Dropped),' queued ',(integer Queued),' processed ',integer Processed
    line =. line,' discarded ',(integer Discarded),' pending ',(integer pending),' empty ',integer EmptyMessages
    lines =. lines,<line
    lines =. lines,<'SENT lines ',(integer #SentLines),' numerics ',(integer +/NumericCounts),' pings ',(integer PingCount),' errors ',integer ErrorCount
    for_index. /:CommandNames do.
        lines =. lines,<'COMMAND ',(index{::CommandNames),' ',integer index{CommandCounts
    end.
    for_number. I.NumericCounts>0 do.
        lines =. lines,<'NUMERIC ',(number_text number),' ',integer number{NumericCounts
    end.
    lines =. lines,<'PEAK connections ',(integer 0{PeakConnections),' at ',integer 1{PeakConnections
    lines =. lines,<'PEAK registered ',(integer 0{PeakRegistered),' at ',integer 1{PeakRegistered
    line =. 'DISCONNECTS quit ',(integer 0{DisconnectCounts),' closed ',(integer 1{DisconnectCounts)
    line =. line,' flood ',(integer 2{DisconnectCounts),' timeout ',integer 3{DisconnectCounts
    lines =. lines,<line
    for_record. Gone do.
        'time identifier nickname reason' =. >record
        lines =. lines,<'GONE ',(integer time),' ',identifier,' ',nickname,' ',reason
    end.
    lines
)
save =: 4 : 0
    text =. ''
    if. #y do.
        text =. (LF join y),LF
    end.
    text 1!:2 <'output/',x
)
run =: 3 : 0
    read_inputs ''
    initialize_state ''
    run_simulation ''
    'sent.txt'save SentLines
    'channels.txt'save channel_report ''
    'clients.txt'save client_report ''
    'stats.txt'save statistics_report ''
    i.0
)
run ''
