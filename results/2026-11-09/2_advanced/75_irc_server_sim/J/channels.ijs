initialize_channels =: 3 : 0
    ChannelNames =: 0$a:
    ChannelActive =: i.0
    CreatedTimes =: i.0
    Members =: 0$a:
    Operators =: 0$a:
    Voices =: 0$a:
    Topics =: 0$a:
    TopicSetters =: 0$a:
    TopicTimes =: i.0
    Bans =: 0$a:
    Flags =: 0$a:
    Keys =: 0$a:
    Limits =: i.0
    MemberPeaks =: i.0
    MessageCounts =: i.0
    i.0
)
new_channel =: 3 : 0
    index =. #ChannelNames
    ChannelNames =: ChannelNames,<y
    ChannelActive =: ChannelActive,1
    CreatedTimes =: CreatedTimes,CurrentTime
    Members =: Members,<i.0
    Operators =: Operators,<i.0
    Voices =: Voices,<i.0
    Topics =: Topics,<''
    TopicSetters =: TopicSetters,<''
    TopicTimes =: TopicTimes,_1
    Bans =: Bans,<0$a:
    Flags =: Flags,<'nt'
    Keys =: Keys,<''
    Limits =: Limits,0
    MemberPeaks =: MemberPeaks,0
    MessageCounts =: MessageCounts,0
    index
)
member_index =: 4 : 0
    members =. x{::Members
    index =. members i.y
    if. index=#members do.
        _1
    else.
        index
    end.
)
add_member =: 4 : 0
    old =. x{::Members
    Members =: (<old,y)x}Members
    Operators =: (<(x{::Operators),0=#old)x}Operators
    Voices =: (<(x{::Voices),0)x}Voices
    Joined =: (<(y{::Joined),x)y}Joined
    MemberPeaks =: ((x{MemberPeaks)>.1+#old)x}MemberPeaks
    i.0
)
erase_member =: 4 : 0
    index =. x member_index y
    keep =. index~:i.#x{::Members
    Members =: (<keep#x{::Members)x}Members
    Operators =: (<keep#x{::Operators)x}Operators
    Voices =: (<keep#x{::Voices)x}Voices
    Joined =: (<(y{::Joined)-.x)y}Joined
    0=#x{::Members
)
member_status =: 4 : 0
    index =. x member_index y
    if. index{ x{::Operators do.
        '@'
    elseif. index{ x{::Voices do.
        '+'
    else.
        ''
    end.
)
member_display =: 4 : '(x member_status y),y{::Nicknames'
name_list =: 4 : 0
    inside =. 0<:x member_index y
    names =. 0$a:
    for_client. x{::Members do.
        if. inside+.-.client{Invisible do.
            names =. names,<x member_display client
        end.
    end.
    ' 'join names
)
banned =: 4 : 0
    for_ban. x{::Bans do.
        mask =. 0{::>ban
        if. mask matches prefix y do.
            1 return.
        end.
    end.
    0
)
can_speak =: 4 : 0
    index =. x member_index y
    privileged =. 0
    if. index>:0 do.
        privileged =. (index{x{::Operators)+.index{x{::Voices
    end.
    flags =. x{::Flags
    ((index>:0)+.-.'n'e.flags)*.((-. 'm'e.flags)+.privileged)*.(privileged+.-.x banned y)
)
mode_display =: 4 : 0
    channel =. y
    mode =. '+'
    for_character. 'iklmnt' do.
        if. character='k' do.
            present =. 0<#channel{::Keys
        elseif. character='l' do.
            present =. 0<channel{Limits
        else.
            present =. character e.channel{::Flags
        end.
        if. present do.
            mode =. mode,character
        end.
    end.
    if. x*.0<#channel{::Keys do.
        mode =. mode,' ',channel{::Keys
    end.
    if. channel{Limits do.
        mode =. mode,' ',integer channel{Limits
    end.
    mode
)
