envelope =: 3 : 0
    'samples attack release' =. y
    levels =. 0$0
    level =. 0
    for_input. samples do.
        magnitude =. 32767<.|input
        if. magnitude>level do. coefficient =. attack else. coefficient =. release end.
        level =. level+(((magnitude-level)*coefficient) rdiv 32768)
        levels =. levels,level
    end.
    levels
)
normalize =: 4 : 0
    sourcepeak =. peak x
    if. sourcepeak>0 do. samples =. (x*y) rdiv sourcepeak else. samples =. x end.
    'samples source_peak' record (<samples),<sourcepeak
)
gate =: 3 : 0
    'samples threshold hold' =. y
    output =. 0$0
    lastloud =. -(hold+1)
    muted =. 0
    for_index. i.#samples do.
        value =. index{samples
        if. (|value)>:threshold do. lastloud =. index end.
        if. (index-lastloud)>hold do. value =. 0
            muted =. muted+1 end.
        output =. output,value
    end.
    'samples muted' record (<output),<muted
)
compress =: 3 : 0
    'samples threshold rationum ratioden attack release' =. y
    levels =. envelope (<samples),(<attack),<release
    output =. gains =. 0$0
    gain =. 32768
    for_index. i.#samples do.
        level =. index{levels
        target =. 32768
        if. level>threshold do.
            limited =. threshold+(((level-threshold)*ratioden) rdiv rationum)
            target =. (limited*32768) rdiv level
        end.
        if. target<gain do. gain =. target else. gain =. gain+(((target-gain)*release) rdiv 32768) end.
        gains =. gains,gain
        output =. output,((index{samples)*gain) rdiv 32768
    end.
    'samples min_gain reduced' record (<output),(<<./gains),<+/gains<32768
)
