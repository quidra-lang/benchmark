channel_value =: 4 : 0
    state =. y
    if. -.28{state do.
        (<state),<0 return.
    end.
    level =. x wave_value 14 15 16{state
    phase =. (15{state)+25{state
    register =. 16{state
    if. phase>:65536 do.
        phase =. phase-65536
        if. 'NOISE'-:i_wave x do.
            register =. register clock_register 14{state
        end.
    end.
    state =. phase 15}state
    state =. register 16}state
    (<state),<((2*level)-15)*24{state
)
mix_tick =: 4 : 0
    channels =. x
    'count gain muted' =. y
    samples =. i.0
    lanes =. (#channels)$<i.0
    clipped =. 0
    for_tick. i.count do.
        total =. 0x
        for_index. i.#channels do.
            state =. index{channels
            value =. 0
            if. 28{state do.
                'state value' =. ((0{state){::Instruments)channel_value state
                channels =. state index}channels
            end.
            lanes =. (<(index{::lanes),value)index}lanes
            if. 0=index{muted do.
                total =. total+value
            end.
        end.
        sample =. 128+(gain*total)intdiv 4096
        if. (sample<0)+.sample>255 do.
            clipped =. clipped+1
            sample =. 0 255 clamp sample
        end.
        samples =. samples,sample
    end.
    (<channels),(<samples),(<lanes),<clipped
)
fade_out =: 4 : 0
    samples =. y
    count =. #samples
    length =. x<.count
    for_index. (count-length)+i.length do.
        sample =. 128+(((index{samples)-128)*((count-1)-index))intdiv length
        samples =. sample index}samples
    end.
    samples
)
