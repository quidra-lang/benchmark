load 'song_parser.ijs'
load 'instruments.ijs'
load 'sequencer.ijs'
load 'mixer.ijs'
load 'report.ijs'
join =: 4 : 0
    result =. ''
    for_index. i.#y do.
        if. index do.
            result =. result,x
        end.
        result =. result,index{::y
    end.
    result
)
text =: 3 : 0
    result =. ":y
    '-'(I.result='_')}result
)
pad =: 4 : '((0>.x-#y)#'' ''),y'
hex_list =: 3 : 0
    if. #y do.
        ' 'join hex2&.>y
    else.
        'none'
    end.
)
note_range =: 3 : 0
    if. #y do.
        (note_name <./y),'..',note_name >./y
    else.
        'none'
    end.
)
Tonics =: 'C';'C#';'D';'D#';'E';'F';'F#';'G';'G#';'A';'A#';'B'
new_channel =: 3 : 0
    state =. 36$0x
    state =. (_1 _1 _1)0 1 29}state
    state =. (15,1,y)13 16 35}state
    state
)
effect_name =: 3 : 0
    if. 26{y do.
        ((26{y)-1){::EffectNames
    else.
        ''
    end.
)
effect_text =: 3 : 0
    name =. effect_name y
    if. 0=#name do.
        '...'
    elseif. 'E'={.name do.
        name,hex1 27{y
    else.
        name,hex2 27{y
    end.
)
key_off =: 3 : 0
    ((17{y),(21{y),1)19 20 18}y
)
approach =: 4 : 0
    frequency =. 2{x
    target =. 3{x
    if. frequency<target do.
        frequency =. target<.frequency+y
    else.
        frequency =. target>.frequency-y
    end.
    frequency 2}x
)
volume_slide =: 3 : 0
    argument =. 27{y
    value =. 0 15 clamp ((13{y)+(argument intdiv 16))-16|argument
    value 13}y
)
update_output =: 4 : 0
    state =. x
    tick =. y
    voice =. (0{state){::Instruments
    name =. effect_name state
    argument =. 27{state
    semitones =. 0
    if. name-:'0' do.
        semitones =. (3|tick){0,(argument intdiv 16),16|argument
    end.
    arpeggio =. i_arpeggio voice
    age =. 17{state
    if. #arpeggio do.
        semitones =. semitones+((#arpeggio)|age){arpeggio
    end.
    frequency =. ((2{state)transpose semitones)+6{state
    if. (name-:'4')+.name-:'6' do.
        frequency =. frequency+oscillation (9{state),(8{state),4
    end.
    vibrato =. i_vibrato voice
    if. #vibrato do.
        'delay speed depth' =. vibrato
        if. age>:delay do.
            frequency =. frequency+oscillation (64|(age-delay)*speed),depth,4
        end.
    end.
    frequency =. (1000,50*Rate)clamp frequency
    envelope =. (i_envelope voice)envelope_value 17 18 19 20{state
    volume =. 13{state
    if. name-:'7' do.
        volume =. 0 15 clamp volume+oscillation (12{state),(11{state),255
    end.
    amplitude =. envelope*volume
    increment =. (frequency*65536)intdiv 100*Rate
    (envelope,frequency,volume,amplitude,increment)21 22 23 24 25}state
)
warn =: 4 : 0
    Warnings =: Warnings,<'warning ',(hex2 CurrentPosition),':',(hex2 CurrentRow),' ch',(text x),' ',y
    0
)
end_record =: 4 : 0
    state =. x
    index =. 29{state
    record =. index{Records
    length =. (#Samples)-6{record
    record =. (length,y)7 9}record
    Records =: record index}Records
    _1 (29)}state
)
note_on =: 4 : 0
    state =. x
    if. (29{state)>:0 do.
        state =. state end_record 1
    end.
    frequency =. frequency y
    state =. (frequency,frequency,0,0,0,0,0,y)2 3 15 17 9 12 18 1}state
    state =. (1+30{state)30}state
    state =. (#Records)29}state
    record =. (1+#Records),(35{state),CurrentPosition,CurrentRow,(0{state),y,(#Samples),0,_1,0
    Records =: Records,record
    state
)
apply_cell =: 4 : 0
    state =. x
    'cell portamento' =. y
    'note instrument volume code argument' =. cell
    if. instrument>:0 do.
        selected =. instrument{InstrumentIndex
        if. selected<0 do.
            (35{state)warn 'undefined instrument ',hex2 instrument
        else.
            voice =. selected{::Instruments
            state =. (selected,15,i_mode voice)0 13 14}state
        end.
    end.
    if. volume>:0 do.
        state =. volume 13}state
    end.
    if. note=_2 do.
        if. ((1{state)>:0)*.-.18{state do.
            state =. key_off state
            index =. 29{state
            record =. index{Records
            record =. ((#Samples)-6{record)8}record
            Records =: record index}Records
        else.
            (35{state)warn 'key off without note'
        end.
    elseif. note>:0 do.
        if. (0{state)<0 do.
            (35{state)warn 'note without instrument'
        elseif. portamento*.(1{state)>:0 do.
            state =. ((frequency note),note)3 1}state
        else.
            if. portamento do.
                (35{state)warn 'portamento without note'
            end.
            state =. state note_on note
        end.
    end.
    state
)
start_effect =: 3 : 0
    state =. y
    name =. effect_name state
    value =. 27{state
    high =. value intdiv 16
    low =. 16|value
    if. name-:'3' do.
        if. value>0 do.
            state =. value 4}state
        end.
    elseif. name-:'4' do.
        if. high>0 do.
            state =. high 7}state
        end.
        if. low>0 do.
            state =. low 8}state
        end.
    elseif. name-:'7' do.
        if. high>0 do.
            state =. high 10}state
        end.
        if. low>0 do.
            state =. low 11}state
        end.
    elseif. name-:'C' do.
        state =. (15<.value)13}state
    elseif. name-:'E1' do.
        state =. ((1000,50*Rate)clamp (2{state)+10*value)2}state
    elseif. name-:'E2' do.
        state =. ((1000,50*Rate)clamp (2{state)-10*value)2}state
    elseif. name-:'EA' do.
        state =. (15<.(13{state)+value)13}state
    elseif. name-:'EB' do.
        state =. (0>.(13{state)-value)13}state
    elseif. name-:'EE' do.
        RowDelay =: value
    elseif. name-:'F' do.
        if. (value>:1)*.value<:31 do.
            Speed =: value
        elseif. value>:32 do.
            Tempo =: value
        end.
    elseif. name-:'P' do.
        state =. (value-128)6}state
    elseif. (name-:'Q')+.name-:'R' do.
        if. (1{state)<0 do.
            (35{state)warn 'slide without note'
        else.
            note =. (1{state)+low
            if. name-:'R' do.
                note =. (1{state)-low
            end.
            note =. 12 95 clamp note
            state =. (note,(frequency note),(1+2*high))1 3 5}state
        end.
    elseif. name-:'V' do.
        valid =. 0
        if. (0{state)>:0 do.
            wave =. i_wave (0{state){::Instruments
            valid =. ((wave-:'PULSE')*.value<:3)+.((wave-:'NOISE')*.value<:1)
        end.
        if. valid do.
            state =. value 14}state
        else.
            (35{state)warn 'invalid mode ',hex2 value
        end.
    end.
    state
)
tick_effect =: 3 : 0
    state =. y
    name =. effect_name state
    value =. 27{state
    if. name-:'1' do.
        state =. ((1000,50*Rate)clamp (2{state)+10*value)2}state
    elseif. name-:'2' do.
        state =. ((1000,50*Rate)clamp (2{state)-10*value)2}state
    elseif. (name-:'3')+.name-:'5' do.
        state =. state approach 10*4{state
        if. name-:'5' do.
            state =. volume_slide state
        end.
    elseif. (name-:'6')+.name-:'A' do.
        state =. volume_slide state
    elseif. (name-:'Q')+.name-:'R' do.
        if. 5{state do.
            state =. state approach 10*5{state
        end.
    end.
    state
)
start_row =: 3 : 0
    RowDelay =: 0
    for_index. i.4 do.
        state =. index{Channels
        cell =. index{Cells
        state =. (3 4{cell)26 27}state
        state =. 0 (5)}state
        name =. effect_name state
        value =. 27{state
        if. #name do.
            code =. (26{state)-1
            EffectCounts =: (1+code{EffectCounts)code}EffectCounts
        end.
        if. -.((name-:'ED')*.value>:1) do.
            state =. state apply_cell (<cell),<((name-:'3')+.name-:'5')
        end.
        if. #name do.
            state =. start_effect state
        end.
        Channels =: state index}Channels
    end.
    0
)
process_tick =: 3 : 0
    tick =. y
    for_index. i.4 do.
        state =. index{Channels
        name =. effect_name state
        value =. 27{state
        if. ((1{state)>:0)*.(17{state)>:1 do.
            sweep =. i_sweep (0{state){::Instruments
            if. sweep do.
                state =. ((1000,50*Rate)clamp (2{state)+10*sweep)2}state
            end.
        end.
        if. (tick>:1)*.0<#name do.
            state =. tick_effect state
        end.
        if. ((name-:'ED')*.value>:1)*.tick=value do.
            state =. state apply_cell (<index{Cells),<0
        end.
        if. ((name-:'E9')*.value>:1)*.tick>:1 do.
            if. (0=value|tick)*.(1{state)>:0 do.
                state =. 0 (15 17 18)}state
                state =. (1+31{state)31}state
            end.
        end.
        if. ((name-:'EC')*.tick=value)*.(1{state)>:0 do.
            state =. state end_record 2
            state =. _1 (1)}state
            state =. (1+32{state)32}state
        end.
        sounding =. (1{state)>:0
        state =. sounding 28}state
        if. sounding do.
            state =. state update_output tick
            state =. (1+33{state)33}state
            if. (24{state)>0 do.
                state =. (1+34{state)34}state
            end.
            voice =. 0{state
            InstrumentTicks =: (1+voice{InstrumentTicks)voice}InstrumentTicks
        end.
        Channels =: state index}Channels
    end.
    0
)
advance =: 3 : 0
    for_index. i.4 do.
        state =. index{Channels
        name =. effect_name state
        if. (1{state)>:0 do.
            state =. (1+17{state)17}state
        end.
        if. (name-:'4')+.name-:'6' do.
            state =. (64|(9{state)+7{state)9}state
        elseif. name-:'7' do.
            state =. (64|(12{state)+10{state)12}state
        end.
        Channels =: state index}Channels
    end.
    TickCount =: TickCount+1
    0
)
log_row =: 3 : 0
    start =. y
    header =. (hex2 CurrentPosition),' ',(hex2 CurrentPosition{Order),' ',(hex2 CurrentRow),' ',(7 pad text start),' ',(2 pad text Speed),' ',3 pad text Tempo
    parts =. ,<header
    notes =. i.0
    for_state. Channels do.
        effect =. effect_text state
        if. (1{state)>:0 do.
            number =. i_number (0{state){::Instruments
            field =. (note_name 1{state),' ',(hex2 number),' ',(7 pad text 22{state),' ',(hex1 21{state),' ',(hex1 23{state),' ',effect
        else.
            field =. '--- --       - - ',(hex1 13{state),' ',effect
        end.
        parts =. parts,<field
        notes =. notes,1{state
    end.
    Log =: Log,<' | 'join parts
    Played =: Played,CurrentPosition,CurrentRow,start,Speed,Tempo,notes
    0
)
log_tick =: 3 : 0
    parts =. ,<'  tick ',(3 pad text y),' ',7 pad text #Samples
    for_state. Channels do.
        if. 28{state do.
            field =. (7 pad text 22{state),' ',(5 pad text 25{state),' ',(hex1 21{state),hex1 23{state
        else.
            field =. '      -     - --'
        end.
        parts =. parts,<field
    end.
    Log =: Log,<' | 'join parts
    0
)
play_row =: 3 : 0
    CurrentPosition =: y intdiv 64
    CurrentRow =: 64|y
    Cells =: song_cells CurrentPosition,CurrentRow
    start =. #Samples
    if. (y{FirstStarts)<0 do.
        FirstStarts =: start y}FirstStarts
    end.
    start_row 0
    ticks =. Speed*1+RowDelay
    for_state. Channels do.
        name =. effect_name state
        if. (name-:'EC')*.(27{state)>:ticks do.
            (35{state)warn 'cut beyond row'
        elseif. (name-:'ED')*.(27{state)>:ticks do.
            (35{state)warn 'delay beyond row'
        end.
    end.
    tick_samples =. Rate samples_per_tick Tempo
    for_tick. i.ticks do.
        process_tick tick
        if. tick=0 do.
            log_row start
        end.
        if. y{Traces do.
            log_tick tick
        end.
        count =. tick_samples<.MaxSamples-#Samples
        'updated samples lanes clipped' =. Channels mix_tick (<count),(<Gain),<Muted
        Channels =: updated
        Samples =: Samples,samples
        for_channel. i.4 do.
            Lanes =: (<(channel{::Lanes),channel{::lanes)channel}Lanes
        end.
        Clipped =: Clipped+clipped
        advance 0
        if. MaxSamples=#Samples do.
            0 return.
        end.
    end.
    1
)
play =: 3 : 0
    Channels =: new_channel"0 ]1+i.4
    Lanes =: 4$<i.0
    Samples =: i.0
    Records =: 0 10$0x
    Played =: 0 9$0x
    Warnings =: 0$a:
    Log =: 0$a:
    PlayCounts =: (64*#Order)$0
    FirstStarts =: (64*#Order)$_1
    InstrumentTicks =: (#Instruments)$0
    EffectCounts =: (#EffectNames)$0
    Speed =: InitialSpeed
    Tempo =: InitialTempo
    TickCount =: 0
    Clipped =: 0
    EndReason =: 'finished'
    EndRow =: _1
    LoopStart =: _1
    current =. 0
    while. 1 do.
        PlayCounts =: (1+current{PlayCounts)current}PlayCounts
        if. -.play_row current do.
            EndReason =: 'limit'
            break.
        end.
        following =. Cells next_row CurrentPosition,CurrentRow
        if. following<0 do.
            EndReason =: 'stop'
            EndRow =: current
            break.
        end.
        current =. following
        if. current>:64*#Order do.
            EndReason =: 'finished'
            break.
        end.
        if. (current{PlayCounts)>:Loops do.
            EndReason =: 'loop'
            EndRow =: current
            LoopStart =: current{FirstStarts
            break.
        end.
    end.
    for_index. i.4 do.
        state =. index{Channels
        if. (29{state)>:0 do.
            Channels =: (state end_record 3)index}Channels
        end.
    end.
    if. ((EndReason-:'limit')+.EndReason-:'loop')*.Fade>0 do.
        Samples =: Fade fade_out Samples
    end.
    0
)
note_lines =: 3 : 0
    reasons =. 'next';'cut';'end'
    lines =. 0$a:
    for_record. Records do.
        'serial channel position row instrument note start length release reason' =. record
        values =. (start+i.length){(channel-1){::Lanes
        cycles =. +/((}:values)<0)*.(}.values)>:0
        released =. '-'
        if. release>:0 do.
            released =. text release
        end.
        number =. i_number instrument{::Instruments
        lines =. lines,<(4 pad text serial),' ch=',(text channel),' at=',(hex2 position),':',(hex2 row),' ins=',(hex2 number),' note=',(note_name note),' start=',(text start),' length=',(text length),' release=',released,' end=',((reason-1){::reasons),' peak=',(text 0 peak values),' cycles=',text cycles
    end.
    lines
)
roll_lines =: 3 : 0
    width =. 0>.RollRows<.(#Played)-RollStart
    targets =. (RollStart+i.width){Played
    notes =. ,5 6 7 8{"1 targets
    pitches =. \:~ ~.notes#~notes>:0
    lines =. ,<'ROLL start=',(text RollStart),' rows=',(text width),' pitches=',text #pitches
    for_pitch. pitches do.
        marks =. ''
        for_row. targets do.
            owners =. I.pitch=5 6 7 8{row
            mark =. ' '
            if. 1=#owners do.
                mark =. text 1+{.owners
            elseif. 1<#owners do.
                mark =. '*'
            end.
            marks =. marks,mark
        end.
        lines =. lines,<(note_name pitch),' |',marks,'|'
    end.
    ruler =. ''
    for_index. i.width do.
        character =. '-'
        if. 0=16|index do.
            character =. '+'
        end.
        ruler =. ruler,character
    end.
    lines,<'    +',ruler,'+'
)
voice_order =: 3 : '/:i_number&>Instruments'
stats_lines =: 3 : 0
    count =. #Samples
    ending =. EndReason
    if. (ending-:'stop')+.ending-:'loop' do.
        ending =. ending,' order=',(hex2 EndRow intdiv 64),' row=',hex2 64|EndRow
    end.
    start =. '-'
    length =. '-'
    if. LoopStart>:0 do.
        start =. text LoopStart
        length =. text count-LoopStart
    end.
    lines =. (<'title=',Title),(<'rate=',text Rate),(<'samples=',text count),(<'duration_ms=',text (1000*count)intdiv Rate),(<'end=',ending),(<'loop_start=',start),<'loop_length=',length
    lines =. lines,(<'rows=',text #Played),(<'ticks=',text TickCount),(<'clipped=',text Clipped),(<'peak=',text 128 peak Samples),(<'min=',text <./Samples),(<'max=',text >./Samples),(<'rms=',text 128 rms Samples),(<'zero_crossings=',text zero_crossings Samples),<'adler32=',adler Samples
    path =. i.0
    previous =. _1
    for_row. Played do.
        if. previous~:0{row do.
            previous =. 0{row
            path =. path,previous
        end.
    end.
    lines =. lines,<'path ',' 'join hex2&.>path
    previous =. _1 _1
    for_row. Played do.
        if. -.previous-:3 4{row do.
            lines =. lines,<'timing sample=',(text 2{row),' order=',(hex2 0{row),' row=',(hex2 1{row),' speed=',(text 3{row),' tempo=',text 4{row
        end.
        previous =. 3 4{row
    end.
    for_index. i.4 do.
        state =. index{Channels
        lane =. index{::Lanes
        lines =. lines,<'channel ',(text index+1),' notes=',(text 30{state),' retriggers=',(text 31{state),' cuts=',(text 32{state),' active=',(text 33{state),' audible=',(text 34{state),' peak=',(text 0 peak lane),' rms=',text 0 rms lane
    end.
    order =. voice_order 0
    used_instruments =. (#Instruments)$0
    note_counts =. 96$0
    pitch_classes =. 12$0x
    for_record. Records do.
        instrument =. 4{record
        note =. 5{record
        used_instruments =. 1 instrument}used_instruments
        note_counts =. (1+note{note_counts)note}note_counts
        if. -.'NOISE'-:i_wave instrument{::Instruments do.
            pitch =. 12|note
            pitch_classes =. ((pitch{pitch_classes)+7{record)pitch}pitch_classes
        end.
    end.
    for_index. order do.
        voice =. index{::Instruments
        records =. ((4{"1 Records)=index)#Records
        notes =. 5{"1 records
        average =. '-'
        if. #records do.
            average =. text (+/7{"1 records)intdiv #records
        end.
        lines =. lines,<'instrument ',(hex2 i_number voice),' ',(i_name voice),' ',(i_wave voice),' notes=',(text #records),' ticks=',(text index{InstrumentTicks),' range=',(note_range notes),' average=',average
    end.
    pattern_numbers =. I.PatternIndex>:0
    for_number. pattern_numbers do.
        pattern =. (number{PatternIndex){::Patterns
        rows =. 0
        notes =. 0
        for_cells. pattern do.
            nonempty =. 0
            for_cell. cells do.
                nonempty =. nonempty+.-.cell-:_1 _1 _1 0 0
                notes =. notes+(_1~:0{cell)
            end.
            rows =. rows+nonempty
        end.
        lines =. lines,<'pattern ',(hex2 number),' rows=',(text rows),' notes=',(text notes),' orders=',text +/Order=number
    end.
    following =. i.0
    for_position. i.#Order do.
        for_row. i.64 do.
            following =. following,(song_cells position,row)next_row position,row
        end.
    end.
    reached =. reachable_rows following
    played_positions =. (#Order)$0
    for_position. i.#Order do.
        starts =. 2{"1 ((0{"1 Played)=position)#Played
        first =. '-'
        if. #starts do.
            first =. text {.starts
            played_positions =. 1 position}played_positions
        end.
        dead =. 0
        for_row. i.64 do.
            if. -.((64*position)+row){reached do.
                cells =. song_cells position,row
                dead =. dead+(+./_1~:0{"1 cells)
            end.
        end.
        lines =. lines,<'order ',(hex2 position),' pattern=',(hex2 position{Order),' rows=',(text #starts),' first=',first,' dead=',text dead
    end.
    for_note. I.note_counts>0 do.
        lines =. lines,<'note ',(note_name note),' count=',text note{note_counts
    end.
    effects =. 0$a:
    for_index. I.EffectCounts>0 do.
        effects =. effects,<(index{::EffectNames),'=',text index{EffectCounts
    end.
    effect_summary =. 'none'
    if. #effects do.
        effect_summary =. ' 'join effects
    end.
    lines =. lines,<'effects ',effect_summary
    unused_instruments =. i_number&>(I.-.used_instruments){Instruments
    unused_instruments =. /:~unused_instruments
    unused_patterns =. pattern_numbers#~-.pattern_numbers e.Order
    unreached_orders =. I.-.played_positions
    lines =. lines,(<'unused_instruments=',hex_list unused_instruments),(<'unused_patterns=',hex_list unused_patterns),<'unreached_orders=',hex_list unreached_orders
    classes =. 0$a:
    for_index. i.12 do.
        classes =. classes,<(index{::Tonics),'=',text index{pitch_classes
    end.
    lines =. lines,<'pitch_classes ',' 'join classes
    weights =. 2 12$64 22 35 23 44 41 25 52 24 37 23 29 64 27 35 54 27 35 25 48 40 27 34 32
    modes =. 'major';'minor'
    key_names =. 0$a:
    key_scores =. i.0
    for_mode. i.2 do.
        for_tonic. i.12 do.
            score =. 0x
            for_pitch. i.12 do.
                score =. score+((<mode,12|pitch-tonic){weights)*pitch{pitch_classes
            end.
            key_names =. key_names,<(tonic{::Tonics),' ',mode{::modes
            key_scores =. key_scores,score
        end.
    end.
    key_order =. /:-key_scores
    best =. 0{key_order
    runner =. 1{key_order
    lines =. lines,<'key=',(best{::key_names),' score=',(text best{key_scores),' runner_up=',(runner{::key_names),' score=',text runner{key_scores
    for_channel. 1+i.4 do.
        records =. ((1{"1 Records)=channel)#Records
        fields =. ,<'usage ch',(text channel),' range=',note_range 5{"1 records
        for_index. order do.
            count =. +/index=4{"1 records
            fields =. fields,<(hex2 i_number index{::Instruments),'=',text count
        end.
        lines =. lines,<' 'join fields
    end.
    lines,Warnings
)
plot_row =: 3 : 0
    'value low high height' =. y
    (((2*(high-value))*(height-1))+(high-low))intdiv 2*(high-low)
)
plot_lines =: 4 : 0
    'low high middle height width' =. x
    values =. y
    middle_row =. plot_row middle,low,high,height
    columns =. 0 2$0
    for_column. i.width do.
        first =. (column*#values)intdiv width
        last =. ((column+1)*#values)intdiv width
        selected =. (first+i.last-first){values
        top =. plot_row (>./selected),low,high,height
        bottom =. plot_row (<./selected),low,high,height
        columns =. columns,top,bottom
    end.
    lines =. 0$a:
    for_row. i.height do.
        label =. ''
        if. row=0 do.
            label =. text high
        elseif. row=middle_row do.
            label =. text middle
        elseif. row=height-1 do.
            label =. text low
        end.
        marks =. ''
        for_limits. columns do.
            character =. ' '
            if. ((0{limits)<:row)*.row<:1{limits do.
                character =. '#'
            elseif. row=middle_row do.
                character =. '-'
            end.
            marks =. marks,character
        end.
        lines =. lines,<(5 pad label),' |',marks,'|'
    end.
    lines
)
waveform_lines =: 3 : 0
    ruler =. ''
    labels =. '    ms'
    for_column. i.WindowWidth do.
        character =. '-'
        if. 0=10|column do.
            character =. '+'
            spaces =. 0>.(7+column)-#labels
            milliseconds =. (1000*(WindowStart+(column*WindowLength)intdiv WindowWidth))intdiv Rate
            labels =. labels,(spaces#' '),text milliseconds
        end.
        ruler =. ruler,character
    end.
    axes =. (<'      +',ruler,'+'),<labels
    selected =. WindowStart+i.WindowLength
    lines =. ,<'MIX start=',(text WindowStart),' length=',(text WindowLength),' width=',(text WindowWidth),' height=',text WindowHeight
    lines =. lines,(0,255,128,WindowHeight,WindowWidth)plot_lines selected{Samples
    lines =. lines,axes
    for_channel. i.4 do.
        lines =. lines,<'CHANNEL ',text channel+1
        lines =. lines,(_3375,3375,0,WindowScope,WindowWidth)plot_lines selected{channel{::Lanes
    end.
    lines,axes
)
preview_lines =: 3 : 0
    voice_index =. y
    voice =. voice_index{::Instruments
    state =. new_channel 1
    note_frequency =. frequency PreviewNote
    state =. (voice_index,(i_mode voice),PreviewNote,note_frequency,note_frequency,1)0 14 1 2 3 28}state
    samples =. i.0
    envelopes =. ''
    frequencies =. 0$a:
    tick_samples =. Rate samples_per_tick InitialTempo
    for_tick. i.PreviewTicks do.
        state =. tick 17}state
        if. tick=PreviewRelease do.
            state =. key_off state
        end.
        if. (tick>:1)*.0~:i_sweep voice do.
            frequency =. (1000,50*Rate)clamp (2{state)+10*i_sweep voice
            state =. frequency 2}state
        end.
        state =. state update_output tick
        envelopes =. envelopes,hex1 21{state
        frequencies =. frequencies,<text 22{state
        'updated generated lanes clipped' =. (,:state)mix_tick (<tick_samples),(<Gain),<,0
        state =. 0{updated
        samples =. samples,generated
    end.
    first =. 'instrument ',(hex2 i_number voice),' ',(i_name voice),' wave=',(i_wave voice),' samples=',(text #samples),' peak=',(text 128 peak samples),' rms=',(text 128 rms samples),' adler32=',adler samples
    (<first),(<'  env ',envelopes),<'  freq ',' 'join frequencies
)
write_lines =: 4 : 0
    content =. ''
    for_row. y do.
        content =. content,(>row),LF
    end.
    content 1!:2 <'output/',x
)
run =: 3 : 0
    read_song 'input/song.txt'
    read_params 'input/params.txt'
    play 0
    previews =. 0$a:
    for_voice. voice_order 0 do.
        previews =. previews,preview_lines voice
    end.
    try.
        1!:5 <'output'
    catch.
    end.
    'samples.txt'write_lines hex_lines Samples
    'channel_log.txt'write_lines Log
    'notes.txt'write_lines note_lines 0
    'roll.txt'write_lines roll_lines 0
    'stats.txt'write_lines stats_lines 0
    'waveform.txt'write_lines waveform_lines 0
    'instruments.txt'write_lines previews
    i.0 0
)
run 0
