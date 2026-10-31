floor_div =: 4 : '<.(x:x)%x:y'
split_words =: 3 : '<;._1 '' '',y'
read_topology =: 3 : 0
    rows =. <;._2 (1!:1 <'input/topology.txt')
    names =. }.split_words 0{::rows
    channels =. 0 5$0
    for_row. }.rows do.
        fields =. split_words >row
        source =. names i.<1{::fields
        destination =. names i.<2{::fields
        low =. ".4{::fields
        high =. low
        if. 6=#fields do. high =. ".5{::fields end.
        channels =. channels,source,destination,('FIFO'-:3{::fields),low,high
    end.
    (<names),<channels
)
initialize_network =: 3 : 0
    'channels seed' =. y
    ChannelFIFO =: (N*N)$0
    ChannelLow =: ChannelHigh =: ChannelSequence =: ChannelLast =: ChannelMessages =: ChannelMarkers =: ChannelBuffered =: ChannelMaxDelay =: ChannelEntries =: (N*N)$0
    PreviousVectors =: ((N*N),N)$0
    ChannelOrder =: i.0
    for_source. i.N do.
        for_destination. i.N do.
            if. source~:destination do.
                ChannelOrder =: ChannelOrder,destination+N*source
            end.
        end.
    end.
    for_channel. channels do.
        'source destination fifo low high' =. channel
        index =. destination+N*source
        ChannelFIFO =: fifo index}ChannelFIFO
        ChannelLow =: low index}ChannelLow
        ChannelHigh =: high index}ChannelHigh
    end.
    RandomState =: x:seed
    Draws =: 0
    0
)
random_draw =: 3 : 0
    RandomState =: 2147483647x|48271x*RandomState
    Draws =: Draws+1
    RandomState
)
channel_dispatch =: 4 : 0
    channel =. x
    'now marker vector' =. y
    sequence =. 1+channel{ChannelSequence
    ChannelSequence =: sequence channel}ChannelSequence
    low =. channel{ChannelLow
    high =. channel{ChannelHigh
    delay =. low
    if. low~:high do. delay =. low+(1+high-low)|random_draw '' end.
    arrival =. now+delay
    if. channel{ChannelFIFO do. arrival =. arrival>.channel{ChannelLast end.
    ChannelLast =: (arrival>.channel{ChannelLast)channel}ChannelLast
    ChannelMaxDelay =: ((arrival-now)>.channel{ChannelMaxDelay)channel}ChannelMaxDelay
    if. marker do.
        ChannelMarkers =: (1+channel{ChannelMarkers)channel}ChannelMarkers
    else.
        ChannelMessages =: (1+channel{ChannelMessages)channel}ChannelMessages
        count =. +/vector~:channel{PreviousVectors
        ChannelEntries =: (count+channel{ChannelEntries)channel}ChannelEntries
        PreviousVectors =: vector channel}PreviousVectors
    end.
    sequence,arrival
)
delay_text =: 3 : 0
    low =. y{ChannelLow
    high =. y{ChannelHigh
    if. low=high do. integer low else. (integer low),'-',integer high end.
)
