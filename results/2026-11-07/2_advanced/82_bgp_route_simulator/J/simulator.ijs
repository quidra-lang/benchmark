read_events_params =: 3 : 0
    EventTimes =: ,0
    EventTexts =: ,<'INITIAL'
    EventKinds =: ,<'INITIAL'
    EventFields =: ,<,<'INITIAL'
    for_line. read_lines 'input/events.txt' do.
        line =. >line
        at =. line i.' '
        time =. parse_integer at{.line
        text =. (at+1)}.line
        fields =. split_words text
        kind =. 0{::fields
        if. (<kind)e.;:'LINK POLICY' do.
            kind =. '_'join 2{.fields
        end.
        EventTimes =: EventTimes,time
        EventTexts =: EventTexts,<text
        EventKinds =: EventKinds,<kind
        EventFields =: EventFields,<fields
        if. (0{fields)e.;:'ANNOUNCE WITHDRAW' do.
            PrefixCandidates =: PrefixCandidates,parse_prefix 2{::fields
        end.
    end.
    lines =. read_lines 'input/params.txt'
    DefaultPrefs =: parse_integer ' 'join }.split_words 0{::lines
    StepCap =: parse_integer 1{::split_words 1{::lines
    TraceSources =: i.0
    TraceAddresses =: i.0
    TraceTexts =: 0$a:
    for_line. 2}.lines do.
        fields =. split_words >line
        TraceSources =: TraceSources,ASNumbers i.parse_integer 1{::fields
        TraceAddresses =: TraceAddresses,address_value 2{::fields
        TraceTexts =: TraceTexts,2{fields
    end.
)
initialize_messages =: 3 : 0
    MsgArrival =: i.0
    MsgSender =: i.0
    MsgReceiver =: i.0
    MsgLink =: i.0
    MsgPrefix =: i.0
    MsgContent =: 0$a:
    MsgActive =: i.0
)
enqueue_message =: 3 : 0
    'sender receiver link prefix content' =. y
    index =. #MsgActive
    MsgArrival =: MsgArrival,Time+link{LinkDelay
    MsgSender =: MsgSender,sender
    MsgReceiver =: MsgReceiver,receiver
    MsgLink =: MsgLink,link
    MsgPrefix =: MsgPrefix,prefix
    MsgContent =: MsgContent,<content
    MsgActive =: MsgActive,1
    index
)
message_order =: 3 : 0
    keys =. (y{MsgArrival),.(y{MsgReceiver),.(y{MsgSender),.y
    (/:keys){y
)
ordered_messages =: 3 : 'message_order I.MsgActive'
due_messages =: 3 : 'message_order I.MsgActive*.MsgArrival=Time'
remove_link_messages =: 3 : 0
    indices =. message_order I.MsgActive*.MsgLink=y
    MsgActive =: 0 indices}MsgActive
    indices
)
