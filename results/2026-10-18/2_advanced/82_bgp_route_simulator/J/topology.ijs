Origins =: ;:'IGP EGP INCOMPLETE'
Roles =: ;:'customer peer provider'
address_value =: 3 : '256#.>parse_integer&.><;._1 ''.'',y'
address_text =: 3 : '''.''join integer&.>(4#256)#:y'
parse_prefix =: 3 : 0
    slash =. y i.'/'
    (address_value slash{.y),parse_integer(slash+1)}.y
)
prefix_text =: 3 : '(address_text 0{y),''/'',integer 1{y'
contains_address =: 4 : 0
    divisor =. 2^32-1{x
    (y intdiv divisor)=(0{x)intdiv divisor
)
other_end =: 4 : 0
    if. x=y{LinkFirst do.
        y{LinkSecond
    else.
        y{LinkFirst
    end.
)
link_role =: 4 : 0
    if. y{LinkPeer do.
        1
    elseif. x=y{LinkFirst do.
        0
    else.
        2
    end.
)
link_direction =: 4 : '''DPU''{~x link_role y'
connecting_link =: 4 : 0
    {.I.((LinkFirst=x)*.LinkSecond=y)+.((LinkFirst=y)*.LinkSecond=x)
)
read_topology =: 3 : 0
    lines =. read_lines 'input/topology.txt'
    ASNumbers =: i.0
    RouterIds =: i.0
    for_line. lines do.
        fields =. split_words >line
        if. 'AS'-:0{::fields do.
            ASNumbers =: ASNumbers,parse_integer 1{::fields
            RouterIds =: RouterIds,address_value 2{::fields
        end.
    end.
    order =. /:ASNumbers
    ASNumbers =: order{ASNumbers
    RouterIds =: order{RouterIds
    LinkNames =: 0$a:
    LinkFirst =: i.0
    LinkSecond =: i.0
    LinkPeer =: i.0
    LinkDelay =: i.0
    LinkMrai =: i.0
    Initial =: 0$a:
    for_line. lines do.
        fields =. split_words >line
        if. 'LINK'-:0{::fields do.
            LinkNames =: LinkNames,1{fields
            LinkFirst =: LinkFirst,ASNumbers i.parse_integer 2{::fields
            LinkSecond =: LinkSecond,ASNumbers i.parse_integer 3{::fields
            LinkPeer =: LinkPeer,'P2P'-:4{::fields
            LinkDelay =: LinkDelay,parse_integer 5{::fields
            LinkMrai =: LinkMrai,parse_integer 6{::fields
        elseif. 'PREFIX'-:0{::fields do.
            owner =. ASNumbers i.parse_integer 1{::fields
            prefix =. parse_prefix 2{::fields
            origin =. Origins i.3{fields
            communities =. parse_communities 4}.fields
            Initial =: Initial,<( <owner),(<prefix),(<origin),<communities
            PrefixCandidates =: PrefixCandidates,prefix
        end.
    end.
    LinkUp =: (#LinkNames)$1
    LinkDownCounts =: (#LinkNames)$0
    SessionOwners =: i.0
    SessionLinks =: i.0
    SessionOthers =: i.0
    SessionRoles =: i.0
    SessionIndex =: ((#ASNumbers),#LinkNames)$_1
    SessionsByAS =: 0$a:
    for_owner. i.#ASNumbers do.
        sessions =. i.0
        for_link. i.#LinkNames do.
            if. (owner=link{LinkFirst)+.owner=link{LinkSecond do.
                session =. #SessionOwners
                SessionIndex =: session(<owner,link)}SessionIndex
                SessionOwners =: SessionOwners,owner
                SessionLinks =: SessionLinks,link
                SessionOthers =: SessionOthers,owner other_end link
                SessionRoles =: SessionRoles,owner link_role link
                sessions =. sessions,session
            end.
        end.
        SessionsByAS =: SessionsByAS,<sessions
    end.
)
