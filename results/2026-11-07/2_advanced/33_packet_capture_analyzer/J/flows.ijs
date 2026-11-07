power2 =: 3 : 0
    result =. 1x
    for_i. i.y do.
        result =. result*2
    end.
    result
)
endpoint_key =: 3 : 0
    result =. (text {.y),':'
    if. ({:y)>:0 do.
        result =. result,text {:y
    end.
    result
)
pair_key =: 3 : 0
    'first second' =. y
    '|'join /:~(<endpoint_key first),<endpoint_key second
)
sd_name =: 0&{::
sd_isn =: 1&{::
sd_mss =: 2&{::
sd_wscale =: 3&{::
sd_base =: 4&{::
sd_expected =: 5&{::
sd_advanced =: 6&{::
sd_intervals =: 7&{::
sd_previous =: 8&{::
sd_packets =: 9&{::
sd_payload =: 10&{::
sd_marks =: 11&{::
new_side =: 3 : 0
    (<y),(<_1),(<_1),(<_1),(<_1),(<_1),(<_1),(<0 2$0),(<_1 _1 _1 0),(<0),(<0),<4$0
)
st_number =: 0&{::
st_client =: 1&{::
st_server =: 2&{::
st_state =: 3&{::
st_history =: 4&{::
st_start =: 5&{::
st_finish =: 6&{::
st_packets =: 7&{::
st_bytes =: 8&{::
st_syn =: 9&{::
st_syn_ack =: 10&{::
st_ack =: 11&{::
st_events =: 12&{::
st_closer =: 13&{::
st_final_ack =: 14&{::
st_client_side =: 15&{::
st_server_side =: 16&{::
new_stream =: 3 : 0
    'number client server state time first' =. y
    history =. ,<(<state),<first
    (<number),(<client),(<server),(<state),(<history),(<time),(<time),(<0),(<0),(<_1),(<_1),(<_1),(<0$a:),(<_1),(<_1),(<new_side 'client'),<new_side 'server'
)
record_syn =: 4 : 0
    stream =. x
    'direction packet' =. y
    index =. 15+direction
    side =. index{::stream
    side =. (<packet p_value 'tcp.seq_raw')1}side
    side =. (<packet p_value 'tcp.options.mss')2}side
    side =. (<packet p_value 'tcp.options.wscale')3}side
    stream =. (<side)index}stream
    (<p_number packet)(9+direction)}stream
)
init_tracker =: 3 : 0
    Streams =: 0$a:
    LatestKeys =: 0$a:
    LatestNumbers =: i.0
    DuplicateOriginal =: y$_1
    DuplicateCount =: y$0
    MarkNames =: 'retransmission';'out_of_order';'lost_segment';'duplicate_ack'
    i.0
)
track_packet =: 3 : 0
    packet =. y
    source =. (packet p_value 'ip.src'),packet p_value 'tcp.srcport'
    destination =. (packet p_value 'ip.dst'),packet p_value 'tcp.dstport'
    seq =. packet p_value 'tcp.seq_raw'
    ack =. packet p_value 'tcp.ack_raw'
    window =. packet p_value 'tcp.window'
    size =. packet p_value 'tcp.len'
    syn =. 1=packet p_value 'tcp.flags.syn'
    fin =. 1=packet p_value 'tcp.flags.fin'
    rst =. 1=packet p_value 'tcp.flags.rst'
    has_ack =. 1=packet p_value 'tcp.flags.ack'
    key =. pair_key (<source),<destination
    latest_index =. LatestKeys i.<key
    number =. _1
    if. latest_index<#LatestKeys do.
        number =. latest_index{LatestNumbers
    end.
    create =. number<0
    if. -.create do.
        stream =. number{::Streams
        create =. ((<st_state stream)e.'CLOSED';'RESET')*.syn*.-.has_ack
    end.
    if. create do.
        state =. 'ESTABLISHED'
        client =. source
        server =. destination
        if. syn do.
            if. has_ack do.
                state =. 'SYN_RECEIVED'
                client =. destination
                server =. source
            else.
                state =. 'SYN_SENT'
            end.
        end.
        number =. #Streams
        stream =. new_stream (<number),(<client),(<server),(<state),(<p_time packet),<p_number packet
        if. syn do.
            stream =. stream record_syn (<has_ack),<packet
        end.
        Streams =: Streams,<stream
        if. latest_index=#LatestKeys do.
            LatestKeys =: LatestKeys,<key
            LatestNumbers =: LatestNumbers,number
        else.
            LatestNumbers =: number latest_index}LatestNumbers
        end.
    end.
    stream =. number{::Streams
    direction =. -.source-:st_client stream
    side =. (15+direction){::stream
    other =. (16-direction){::stream
    packet =. packet p_put 'tcp.stream';number
    if. 0>sd_base side do.
        side =. (<seq)4}side
    end.
    if. has_ack*.0>sd_base other do.
        other =. (<ack)4}other
    end.
    relative =. 4294967296x|seq-sd_base side
    packet =. packet p_put 'tcp.seq';relative
    if. has_ack do.
        packet =. packet p_put 'tcp.ack';4294967296x|ack-sd_base other
    end.
    span =. size+syn+fin
    mark =. ''
    if. span>0 do.
        expected =. sd_expected side
        interval =. relative,span
        if. (expected>:0)*.relative~:expected do.
            if. relative>expected do.
                mark =. 'lost_segment'
            elseif. (<interval)e.<"1 sd_intervals side do.
                mark =. 'retransmission'
            elseif. ((p_time packet)-sd_advanced side)<3000 do.
                mark =. 'out_of_order'
            else.
                mark =. 'retransmission'
            end.
        end.
        side =. (<(sd_intervals side),interval)7}side
        if. (expected<0)+.(relative+span)>expected do.
            side =. (<relative+span)5}side
            side =. (<p_time packet)6}side
        end.
    elseif. has_ack*.-.rst do.
        previous =. sd_previous side
        if. ((0{previous)>:0)*.((0{previous)=ack)*.(1{previous)=window do.
            mark =. 'duplicate_ack'
            previous =. (>:(3{previous))3}previous
            side =. (<previous)8}side
            DuplicateOriginal =: (2{previous)((p_number packet)-1)}DuplicateOriginal
            DuplicateCount =: (3{previous)((p_number packet)-1)}DuplicateCount
        end.
    end.
    if. has_ack*.-.mark-:'duplicate_ack' do.
        side =. (<ack,window,(p_number packet),0)8}side
    end.
    if. #mark do.
        packet =. packet p_put (<'tcp.analysis.',mark),<1
        marks =. sd_marks side
        index =. MarkNames i.<mark
        marks =. (>:(index{marks))index}marks
        side =. (<marks)11}side
        event =. (<p_number packet),(<sd_name side),(<mark),(<relative),<span
        stream =. (<(st_events stream),<event)12}stream
    end.
    calculated =. window
    if. ((sd_wscale side)>:0)*.((sd_wscale other)>:0)*.-.syn do.
        calculated =. window*power2 sd_wscale side
    end.
    packet =. packet p_put 'tcp.window.calc';calculated
    old =. state =. st_state stream
    client_side =. side
    server_side =. other
    if. direction do.
        client_side =. other
        server_side =. side
    end.
    if. rst do.
        if. -.(<old)e.'CLOSED';'RESET' do.
            state =. 'RESET'
        end.
    elseif. (old-:'SYN_SENT')*.direction*.syn*.has_ack*.ack=4294967296x|1+sd_isn client_side do.
        state =. 'SYN_RECEIVED'
        side =. (<seq)1}side
        side =. (<packet p_value 'tcp.options.mss')2}side
        side =. (<packet p_value 'tcp.options.wscale')3}side
        stream =. (<p_number packet)10}stream
    elseif. (old-:'SYN_RECEIVED')*.(-.direction)*.has_ack*.(-.syn)*.ack=4294967296x|1+sd_isn server_side do.
        state =. 'ESTABLISHED'
        stream =. (<p_number packet)11}stream
    elseif. (old-:'ESTABLISHED')*.fin do.
        state =. 'FIN_WAIT'
        stream =. (<direction)13}stream
    elseif. (old-:'FIN_WAIT')*.fin*.direction~:st_closer stream do.
        state =. 'CLOSING'
        stream =. (<4294967296x|seq+size+1)14}stream
    elseif. (old-:'CLOSING')*.(direction=st_closer stream)*.has_ack*.ack=st_final_ack stream do.
        state =. 'CLOSED'
    end.
    if. -.state-:old do.
        stream =. (<state)3}stream
        change =. (<state),<p_number packet
        stream =. (<(st_history stream),<change)4}stream
    end.
    side =. (<1+sd_packets side)9}side
    side =. (<size+sd_payload side)10}side
    stream =. (<side)(15+direction)}stream
    stream =. (<other)(16-direction)}stream
    stream =. (<1+st_packets stream)7}stream
    stream =. (<(p_length packet)+st_bytes stream)8}stream
    stream =. (<p_time packet)6}stream
    Streams =: (<stream)number}Streams
    packet
)
cv_kind =: 0&{::
cv_source =: 1&{::
cv_destination =: 2&{::
cv_first =: 3&{::
cv_start =: 4&{::
cv_finish =: 5&{::
cv_ap =: 6&{::
cv_ab =: 7&{::
cv_bp =: 8&{::
cv_bb =: 9&{::
cv_packets =: 3 : '(cv_ap y)+cv_bp y'
cv_bytes =: 3 : '(cv_ab y)+cv_bb y'
build_conversations =: 3 : 0
    result =. 0$a:
    keys =. 0$a:
    for_box. y do.
        packet =. >box
        if. -.packet p_exists 'ip.src' do.
            continue.
        end.
        a =. packet p_value 'ip.src'
        b =. packet p_value 'ip.dst'
        source =. a,_1
        destination =. b,_1
        view =. (<'ipv4'),(<pair_key (<source),<destination),(<source),<destination
        views =. ,<view
        if. packet p_exists 'tcp.stream' do.
            view =. (<'tcp'),(<text packet p_value 'tcp.stream'),(<a,packet p_value 'tcp.srcport'),<b,packet p_value 'tcp.dstport'
            views =. views,<view
        end.
        if. packet p_exists 'udp.srcport' do.
            source =. a,packet p_value 'udp.srcport'
            destination =. b,packet p_value 'udp.dstport'
            view =. (<'udp'),(<pair_key (<source),<destination),(<source),<destination
            views =. views,<view
        end.
        for_view_box. views do.
            'kind key source destination' =. >view_box
            key =. kind,'|',key
            index =. keys i.<key
            if. index=#keys do.
                row =. (<kind),(<source),(<destination),(<p_number packet),(<p_time packet),(<p_time packet),(<0),(<0),(<0),<0
                result =. result,<row
                keys =. keys,<key
            end.
            row =. index{::result
            direction =. -.source-:cv_source row
            pi =. 6+2*direction
            bi =. pi+1
            row =. (<1+pi{::row)pi}row
            row =. (<(p_length packet)+bi{::row)bi}row
            row =. (<p_time packet)5}row
            result =. (<row)index}result
        end.
    end.
    order =. 0 4$0
    for_row_box. result do.
        row =. >row_box
        kind_order =. ('ipv4';'tcp';'udp')i.<cv_kind row
        order =. order,(-cv_bytes row),(-cv_packets row),kind_order,cv_first row
    end.
    result /:order
)
build_endpoints =: 3 : 0
    result =. 0 5$0
    for_box. y do.
        packet =. >box
        if. -.packet p_exists 'ip.src' do.
            continue.
        end.
        addresses =. (packet p_value 'ip.src'),packet p_value 'ip.dst'
        for_direction. i.2 do.
            address =. direction{addresses
            index =. (0{"1 result)i.address
            if. index=#result do.
                result =. result,address,0 0 0 0
            end.
            pi =. 1+2*direction
            bi =. pi+1
            result =. (>:(<index,pi){result)(<index,pi)}result
            result =. ((p_length packet)+(<index,bi){result)(<index,bi)}result
        end.
    end.
    bytes =. (2{"1 result)+4{"1 result
    packets =. (1{"1 result)+3{"1 result
    result /:(-bytes),.(-packets),.0{"1 result
)
