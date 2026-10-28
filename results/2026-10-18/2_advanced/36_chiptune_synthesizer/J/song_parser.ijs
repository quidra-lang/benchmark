read_lines =: 3 : '<;._2 (1!:1 <y)'
split =: 4 : '<;._1 x,y'
num =: 3 : 'x: 0".y'
intdiv =: 4 : '<.(x: x)%x: y'
PitchNames =: 'C-';'C#';'D-';'D#';'E-';'F-';'F#';'G-';'G#';'A-';'A#';'B-'
EffectNames =: '0';'1';'2';'3';'4';'5';'6';'7';'A';'B';'C';'D';'E1';'E2';'E9';'EA';'EB';'EC';'ED';'EE';'F';'P';'Q';'R';'V'
hex_value =: 3 : 0
    value =. 0x
    for_digit. y do.
        value =. (16*value)+'0123456789ABCDEF'i.digit
    end.
    value
)
note_number =: 3 : '(12*num 2}.y)+PitchNames i.<2{.y'
note_name =: 3 : '((12|y){::PitchNames),":y intdiv 12'
parse_cell =: 3 : 0
    note =. _1
    if. 'OFF'-:3{.y do.
        note =. _2
    elseif. -.'...'-:3{.y do.
        note =. note_number 3{.y
    end.
    instrument =. _1
    if. -.'..'-:4 5{y do.
        instrument =. hex_value 4 5{y
    end.
    volume =. _1
    if. '.'~:7{y do.
        volume =. hex_value ,7{y
    end.
    effect =. 0
    argument =. 0
    if. -.'...'-:9}.y do.
        width =. 1+('E'=9{y)
        name =. width{.9}.y
        effect =. 1+EffectNames i.<name
        argument =. hex_value (9+width)}.y
    end.
    note,instrument,volume,effect,argument
)
i_number =: 0&{::
i_name =: 1&{::
i_wave =: 2&{::
i_mode =: 3&{::
i_table =: 4&{::
i_envelope =: 5&{::
i_vibrato =: 6&{::
i_arpeggio =: 7&{::
i_sweep =: 8&{::
read_song =: 3 : 0
    lines =. 0$a:
    for_box. read_lines y do.
        value =. >box
        if. #value do.
            if. '#'~:{.value do.
                lines =. lines,<value
            end.
        end.
    end.
    Title =: 6}.0{::lines
    Rate =: num 5}.1{::lines
    InitialSpeed =: num 6}.2{::lines
    InitialTempo =: num 6}.3{::lines
    Gain =: num 5}.4{::lines
    Instruments =: 0$a:
    Patterns =: 0$a:
    InstrumentIndex =: 256$_1
    PatternIndex =: 256$_1
    Order =: i.0
    index =. 5
    while. index<#lines do.
        header =. ' 'split index{::lines
        index =. index+1
        kind =. 0{::header
        if. kind-:'ORDER' do.
            Order =: hex_value&>}.header
            continue.
        end.
        number =. hex_value 1{::header
        if. kind-:'INSTRUMENT' do.
            wave =. ''
            mode =. 0
            table =. i.0
            envelope =. 0 0 0 0
            vibrato =. i.0
            arpeggio =. i.0
            sweep =. 0
            while. -.'END'-:index{::lines do.
                row =. ' 'split index{::lines
                key =. 0{::row
                if. key-:'WAVE' do.
                    wave =. 1{::row
                    if. wave-:'PULSE' do.
                        mode =. ('12';'25';'50';'75')i.2{row
                    elseif. wave-:'NOISE' do.
                        mode =. 'SHORT'-:2{::row
                    elseif. wave-:'TABLE' do.
                        table =. hex_value&> <"0 ]2{::row
                    end.
                elseif. key-:'ENVELOPE' do.
                    envelope =. num&>}.row
                elseif. key-:'VIBRATO' do.
                    vibrato =. num&>}.row
                elseif. key-:'ARPEGGIO' do.
                    arpeggio =. num&>}.row
                else.
                    sweep =. num 1{::row
                end.
                index =. index+1
            end.
            voice =. (<number),(<2{::header),(<wave),(<mode),(<table),(<envelope),(<vibrato),(<arpeggio),<sweep
            InstrumentIndex =: (#Instruments)number}InstrumentIndex
            Instruments =: Instruments,<voice
        else.
            pattern =. 64 4 5$_1 _1 _1 0 0
            while. -.'END'-:index{::lines do.
                value =. index{::lines
                row =. hex_value 2{.value
                cells =. 4 5$0
                for_channel. i.4 do.
                    cell =. parse_cell 12{.(3+15*channel)}.value
                    cells =. cell channel}cells
                end.
                pattern =. cells row}pattern
                index =. index+1
            end.
            PatternIndex =: (#Patterns)number}PatternIndex
            Patterns =: Patterns,<pattern
        end.
        index =. index+1
    end.
    0
)
song_cells =: 3 : 0
    'position row' =. y
    index =. (position{Order){PatternIndex
    row{index{::Patterns
)
read_params =: 3 : 0
    rows =. 0$a:
    for_box. read_lines y do.
        rows =. rows,<}.' 'split >box
    end.
    MaxSamples =: num 0{::0{::rows
    Loops =: num 0{::1{::rows
    Fade =: num 0{::2{::rows
    Muted =: num&>3{::rows
    'WindowStart WindowLength WindowWidth WindowHeight WindowScope' =: num&>4{::rows
    'RollStart RollRows' =: num&>5{::rows
    PreviewNote =: note_number 0{::6{::rows
    'PreviewTicks PreviewRelease' =: num&>}.6{::rows
    Traces =: 4096$0
    for_index. 7+i.(#rows)-7 do.
        pair =. hex_value&>index{::rows
        Traces =: 1 ((64*0{pair)+1{pair)}Traces
    end.
    0
)
