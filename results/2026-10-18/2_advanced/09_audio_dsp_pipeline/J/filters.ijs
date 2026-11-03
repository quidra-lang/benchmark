fir =: 3 : 0
    'samples divisor taps' =. y
    output =. 0$0
    for_index. i.#samples do.
        total =. 0
        for_tap. i.(#taps)<.index+1 do. total =. total+(tap{taps)*(index-tap){samples end.
        output =. output,total div divisor
    end.
    clipped_result output
)
biquad =: 3 : 0
    'samples sections' =. y
    clips =. 0
    for_sectionbox. sections do.
        'b0 b1 b2 a1 a2' =. >sectionbox
        output =. 0$0
        u1 =. u2 =. v1 =. v2 =. 0
        for_input. samples do.
            total =. (b0*input)+(b1*u1)
            total =. total+b2*u2
            total =. total-a1*v1
            total =. total-a2*v2
            value =. total div 16384
            clips =. clips+(value<_32768)+.value>32767
            value =. sat value
            output =. output,value
            u2 =. u1
            u1 =. input
            v2 =. v1
            v1 =. value
        end.
        samples =. output
    end.
    'samples clipped' record (<samples),<clips
)
moving_average =: 4 : 0
    output =. 0$0
    total =. 0
    for_index. i.#x do.
        total =. total+index{x
        if. index>:y do. total =. total-(index-y){x end.
        output =. output,total rdiv y
    end.
    output
)
dc_block =: 3 : 0
    'samples numerator denominator' =. y
    output =. 0$0
    previousinput =. previousoutput =. clips =. 0
    for_input. samples do.
        value =. (input-previousinput)+((numerator*previousoutput) rdiv denominator)
        clips =. clips+(value<_32768)+.value>32767
        previousinput =. input
        previousoutput =. sat value
        output =. output,previousoutput
    end.
    'samples clipped' record (<output),<clips
)
