NoteTable =: 26163 27718 29366 31113 32963 34923 36999 39200 41530 44000 46616 49388
SineTable =: 0 24 49 74 97 120 141 161 180 197 212 224 235 244 250 253 255 253 250 244 235 224 212 197 180 161 141 120 97 74 49 24
clamp =: 4 : '(0{x)>.(1{x)<.y'
frequency =: 3 : 0
    octave =. y intdiv 12
    value =. (12|y){NoteTable
    if. octave>:4 do.
        value*2x^(octave-4)
    else.
        value intdiv 2x^(4-octave)
    end.
)
transpose =: 4 : '((x*((12|y){NoteTable))intdiv 0{NoteTable)*2x^(y intdiv 12)'
oscillation =: 3 : 0
    'position depth divisor' =. y
    value =. (((32|position){SineTable)*depth)intdiv divisor
    if. position<32 do.
        value
    else.
        -value
    end.
)
envelope_value =: 4 : 0
    'attack decay sustain release' =. x
    'age released release_age release_level' =. y
    if. released do.
        elapsed =. age-release_age
        if. elapsed<release do.
            (release_level*((release-1)-elapsed))intdiv release
        else.
            0
        end.
    elseif. age<attack do.
        (15*(age+1))intdiv attack
    elseif. age<attack+decay do.
        15-((15-sustain)*((age-attack)+1))intdiv decay
    else.
        sustain
    end.
)
wave_value =: 4 : 0
    'mode phase register' =. y
    wave =. i_wave x
    if. wave-:'PULSE' do.
        15*(phase intdiv 8192)<mode{1 2 4 6
    elseif. wave-:'TRIANGLE' do.
        step =. phase intdiv 2048
        if. step<16 do.
            15-step
        else.
            step-16
        end.
    elseif. wave-:'SAW' do.
        phase intdiv 4096
    elseif. wave-:'TABLE' do.
        (phase intdiv 2048){i_table x
    else.
        15*0=2|register
    end.
)
clock_register =: 4 : 0
    divisor =. 2
    if. y=1 do.
        divisor =. 64
    end.
    feedback =. 2|(2|x)+2|x intdiv divisor
    (x intdiv 2)+16384*feedback
)
