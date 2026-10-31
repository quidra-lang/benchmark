LF =: 10{a.
Digits =: '0123456789'
Letters =: 'CDEFGAB'
Natural =: 0 2 4 5 7 9 11
FifthValues =: 0 2 4 _1 1 3 5
Accidentals =: 'bb';'b';'';'#';'x'
SharpNames =: <;._1 ' C C# D D# E F F# G G# A A# B'
FlatNames =: <;._1 ' C Db D Eb E F Gb G Ab A Bb B'
IntervalQualities =: ;:'P M m A d AA dd'
PerfectDeltas =: 0 _99 _99 1 _1 2 _2
MajorDeltas =: _99 0 _1 1 _2 2 _3
RomanUpper =: ;:'I II III IV V VI VII'
RomanLower =: ;:'i ii iii iv v vi vii'
ModeNames =: ;:'major minor ionian dorian phrygian lydian mixolydian aeolian locrian'
ModeScales =: 0 1 4 5 6 7 8 9 10
ModeOffsets =: 0 _3 0 _2 _4 1 _1 _3 _5
Commands =: ;:'MIDI NOTE FREQ TUNING PITCH INTERVAL INVERT TRANSPOSE SCALE CHORD VOICE IDENTIFY MELODY ENHARMONIC KEYSIG RELATIVE CIRCLE DIATONIC PROGRESSION ANALYZE FINDKEY DEGREE SPELL KEYDIST'
Limits =: 24 2$1 1 1 1 1 1 1 1 1 1 2 2 1 1 3 3 2 2 2 3 2 3 2 15 2 15 1 1 2 2 2 2 1 1 2 2 3 15 3 15 1 15 3 3 3 3 4 4
Tuning =: 44000
Error =: ''
Output =: 0$a:
split =: 4 : '<;._1 x,y'
emit =: 3 : 'Output =: Output,<y'
fail =: 3 : 0
    Error =: y
    throw.
)
number =: 3 : 0
    text =. ,'0' 8!:2 |y
    if. y<0 do. '-',text else. text end.
)
signed =: 4 : 0
    if. (y>0)+.x*.y=0 do. '+',number y else. number y end.
)
frequency_text =: 3 : '(number <.y%100),''.'',_2{.''00'',number 100|y'
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
all_digits =: 3 : '(0<#y)*.*./y e.Digits'
canonical =: 4 : 0
    if. -.all_digits y do. _1 return. end.
    if. ((#y)>1)*.'0'={.y do. _1 return. end.
    if. (#y)>3 do. _1 return. end.
    value =. 0".y
    if. value>x do. _1 else. value end.
)
pitch_prefix =: 3 : 0
    letter =. Letters i.{.y
    if. letter=7 do. _1 0 0 return. end.
    alteration =. 0
    finish =. 1
    if. finish<#y do.
        select. finish{y
        case. 'b' do.
            alteration =. _1
            finish =. finish+1
            if. finish<#y do.
                if. 'b'=finish{y do. alteration =. _2 [ finish =. finish+1 end.
            end.
        case. '#' do. alteration =. 1 [ finish =. finish+1
        case. 'x' do. alteration =. 2 [ finish =. finish+1
        end.
    end.
    letter,alteration,finish
)
parse_pitch =: 3 : 0
    result =. pitch_prefix y
    if. (({.result)<0)+.({:result)~:#y do. fail 'BAD PITCH ',y end.
    2{.result
)
midi =: 3 : 0
    'letter alteration octave' =. y
    (12*(octave+1))+(letter{Natural)+alteration
)
position =: 3 : '(7*2{y)+0{y'
pitch_class =: 3 : '12|((0{y){Natural)+1{y'
valid_note =: 3 : '((2{y)e._1+i.11)*.((midi y)>:0)*.(midi y)<:127'
parse_note =: 3 : 0
    prefix =. pitch_prefix y
    if. ({.prefix)<0 do. fail 'BAD NOTE ',y end.
    text =. ({:prefix)}.y
    if. text-:'-1' do. octave =. _1
    elseif. ((#text)=1)*.all_digits text do. octave =. 0".text
    else. fail 'BAD NOTE ',y
    end.
    result =. (2{.prefix),octave
    if. -.valid_note result do. fail 'BAD NOTE ',y end.
    result
)
parse_number =: 3 : 0
    value =. 127 canonical y
    if. value<0 do. fail 'BAD NUMBER ',y end.
    value
)
parse_frequency =: 4 : 0
    dots =. I.'.'=y
    if. (#dots)>1 do. fail 'BAD FREQUENCY ',y end.
    if. #dots do.
        index =. {.dots
        whole =. index{.y
        tail =. (index+1)}.y
        if. -.((#tail)e.1 2)*.all_digits tail do. fail 'BAD FREQUENCY ',y end.
        cents =. (0".tail)*10^(2-#tail)
    else. whole =. y [ cents =. 0
    end.
    if. -.((#whole)e.1+i.5)*.all_digits whole do. fail 'BAD FREQUENCY ',y end.
    cents =. cents+100*0".whole
    if. (cents=0)+.x*.((cents<40000)+.cents>48000) do. fail 'BAD FREQUENCY ',y end.
    cents
)
pitch_text =: 3 : '((0{y){Letters),((1{y)+2){::Accidentals'
note_text =: 3 : '(pitch_text 2{.y),number 2{y'
pitch_list =: 3 : ''' '' join <@pitch_text"1 y'
note_list =: 3 : ''' '' join <@note_text"1 y'
make_note =: 4 : 'x,(<.(y-((0{x){Natural)+1{x)%12)-1'
spelling =: 4 : 0
    if. x do. names =. FlatNames else. names =. SharpNames end.
    ((12|y){::names),number (<.y%12)-1
)
perfect_type =: 3 : '(7|y-1)e.0 3 4'
parse_interval =: 3 : 0
    starts =. I.y e.Digits
    if. 0=#starts do. fail 'BAD INTERVAL ',y end.
    first =. {.starts
    quality =. IntervalQualities i.<first{.y
    interval_number =. 99 canonical first}.y
    if. (quality=7)+.interval_number<1 do. fail 'BAD INTERVAL ',y end.
    if. perfect_type interval_number do. delta =. quality{PerfectDeltas else. delta =. quality{MajorDeltas end.
    if. (delta=_99)+.(interval_number=1)*.quality e.4 6 do. fail 'BAD INTERVAL ',y end.
    quality,interval_number
)
interval_tone =: 3 : 0
    'quality interval_number' =. y
    distance =. interval_number-1
    if. perfect_type interval_number do. delta =. quality{PerfectDeltas else. delta =. quality{MajorDeltas end.
    distance,((12*<.distance%7)+((7|distance){Natural)+delta)
)
interval_text =: 3 : '((0{y){::IntervalQualities),number 1{y'
simple_interval =: 3 : 0
    value =. 1{y
    while. value>8 do. value =. value-7 end.
    ({.y),value
)
between =: 4 : 0
    distance =. (position y)-position x
    semitones =. (midi y)-midi x
    down =. (distance<0)+.(distance=0)*.semitones<0
    if. down do. distance =. -distance [ semitones =. -semitones end.
    difference =. semitones-((12*<.distance%7)+(7|distance){Natural)
    if. perfect_type distance+1 do. deltas =. PerfectDeltas else. deltas =. MajorDeltas end.
    quality =. deltas i.difference
    if. quality=7 do. fail 'UNNAMEABLE INTERVAL' end.
    quality,(distance+1),down,semitones
)
raise_pitch =: 4 : 0
    target =. (0{x)+0{y
    alteration =. (((0{x){Natural)+(1{x)+1{y)-(((7|target){Natural)+12*<.target%7)
    if. -.alteration e._2 _1 0 1 2 do. fail 'CANNOT SPELL' end.
    (7|target),alteration
)
build =: raise_pitch"1

ScaleRows =: <;._2 (0 : 0)
major P1 M2 M3 P4 P5 M6 M7
natural_minor P1 M2 m3 P4 P5 m6 m7
harmonic_minor P1 M2 m3 P4 P5 m6 M7
melodic_minor P1 M2 m3 P4 P5 M6 M7
ionian P1 M2 M3 P4 P5 M6 M7
dorian P1 M2 m3 P4 P5 M6 m7
phrygian P1 m2 m3 P4 P5 m6 m7
lydian P1 M2 M3 A4 P5 M6 M7
mixolydian P1 M2 M3 P4 P5 M6 m7
aeolian P1 M2 m3 P4 P5 m6 m7
locrian P1 m2 m3 P4 d5 m6 m7
major_pentatonic P1 M2 M3 P5 M6
minor_pentatonic P1 m3 P4 P5 m7
blues P1 m3 P4 A4 P5 m7
whole_tone P1 M2 M3 A4 A5 A6
)
ChordRows =: <;._2 (0 : 0)
maj - 0 - P1 M3 P5
min m 1 - P1 m3 P5
dim dim 1 o P1 m3 d5
aug aug 0 + P1 M3 A5
sus2 sus2 0 sus2 P1 M2 P5
sus4 sus4 0 sus4 P1 P4 P5
6 6 0 6 P1 M3 P5 M6
m6 m6 1 6 P1 m3 P5 M6
7 7 0 7 P1 M3 P5 m7
maj7 maj7 0 maj7 P1 M3 P5 M7
m7 m7 1 7 P1 m3 P5 m7
mMaj7 mMaj7 1 maj7 P1 m3 P5 M7
m7b5 m7b5 1 h7 P1 m3 d5 m7
dim7 dim7 1 o7 P1 m3 d5 d7
9 9 0 9 P1 M3 P5 m7 M9
add9 add9 0 add9 P1 M3 P5 M9
)
initialize =: 3 : 0
    ScaleNames =: ScaleTones =: 0$a:
    for_row. ScaleRows do.
        words =. ' ' split >row
        ScaleNames =: ScaleNames,{.words
        ScaleTones =: ScaleTones,<interval_tone"1 >parse_interval&.>}.words
    end.
    ChordNames =: ChordSuffixes =: NumeralSuffixes =: ChordTones =: 0$a:
    ChordLower =: i.0
    for_row. ChordRows do.
        words =. ' ' split >row
        ChordNames =: ChordNames,{.words
        suffix =. 1{::words
        if. suffix-:'-' do. suffix =. '' end.
        ChordSuffixes =: ChordSuffixes,<suffix
        ChordLower =: ChordLower,0".2{::words
        suffix =. 3{::words
        if. suffix-:'-' do. suffix =. '' end.
        NumeralSuffixes =: NumeralSuffixes,<suffix
        ChordTones =: ChordTones,<interval_tone"1 >parse_interval&.>4}.words
    end.
)
parse_scale =: 3 : 0
    index =. ScaleNames i.<y
    if. index=#ScaleNames do. fail 'BAD SCALE ',y end.
    index
)
parse_quality =: 3 : 0
    index =. ChordNames i.<y
    if. index=#ChordNames do. fail 'BAD QUALITY ',y end.
    index
)
parse_mode =: 3 : 0
    index =. ModeNames i.<y
    if. index=#ModeNames do. fail 'BAD MODE ',y end.
    index
)
make_key =: 4 : 0
    fifths =. ((0{x){FifthValues)+(7*1{x)+y{ModeOffsets
    if. (fifths<_7)+.fifths>7 do. fail 'THEORETICAL KEY' end.
    x,y,fifths
)
parse_key =: 3 : 0
    tonic =. parse_pitch 0{::y
    mode =. parse_mode 1{::y
    tonic make_key mode
)
key_scale =: 3 : 0
    mode =. 2{y
    (2{.y) build (mode{ModeScales){::ScaleTones
)
fifth_pitch =: 3 : '((7|y+1){3 0 4 1 5 2 6),<.(y+1)%7'
parse_numeral =: 3 : 0
    start =. 0
    alteration =. 0
    if. ({.y)e.'b#' do.
        start =. 1
        if. 'b'={.y do. alteration =. _1 else. alteration =. 1 end.
    end.
    finish =. start
    while. finish<#y do.
        if. -.(finish{y)e.'IViv' do. break. end.
        finish =. finish+1
    end.
    part =. (finish-start){.start}.y
    degree =. RomanUpper i.<part
    lower =. 0
    if. degree=7 do. degree =. RomanLower i.<part [ lower =. 1 end.
    if. degree=7 do. fail 'BAD NUMERAL ',y end.
    candidates =. I.(ChordLower=lower)*.NumeralSuffixes=<finish}.y
    if. 0=#candidates do. fail 'BAD NUMERAL ',y end.
    alteration,degree,{.candidates
)
parse_symbol =: 3 : 0
    prefix =. pitch_prefix y
    if. ({.prefix)<0 do. fail 'BAD SYMBOL ',y end.
    quality =. ChordSuffixes i.<({:prefix)}.y
    if. quality=#ChordNames do. fail 'BAD SYMBOL ',y end.
    (2{.prefix),quality
)
symbol_text =: 4 : '(pitch_text x),y{::ChordSuffixes'
roman_text =: 4 : 0
    if. y{ChordLower do. parts =. RomanLower else. parts =. RomanUpper end.
    (x{::parts),y{::NumeralSuffixes
)
degree_of =: 4 : '7|(0{y)-0{x'
degree_prefix =: 4 : 0
    scale =. key_scale x
    difference =. (1{y)-1{(x degree_of y){scale
    if. difference<0 do. (-difference)#'b' else. difference#'#' end.
)
degree_label =: 4 : '(x degree_prefix y),number 1+x degree_of y'
parse_notes =: 3 : 0
    result =. 0 3$0
    for_word. y do. result =. result,parse_note >word end.
    result
)
parse_pitches =: 3 : 0
    result =. 0 2$0
    for_word. y do. result =. result,parse_pitch >word end.
    result
)
execute =: 3 : 0
    words =. ' ' split y
    command =. 0{::words
    index =. Commands i.<command
    if. index=#Commands do. fail 'UNKNOWN COMMAND ',command end.
    args =. }.words
    count =. #args
    'minimum maximum' =. index{Limits
    if. (count<minimum)+.count>maximum do. fail 'ARGUMENT COUNT' end.
    select. command
    case. 'MIDI';'FREQ';'ENHARMONIC' do.
        note =. parse_note 0{::args
        value =. midi note
        if. command-:'MIDI' do. emit 'MIDI ',(0{::args),' ',number value
        elseif. command-:'FREQ' do.
            cents =. <.0.5+Tuning*2^((value-69)%12)
            emit 'FREQ ',(0{::args),' ',frequency_text cents
        else.
            names =. 0$a:
            for_octave. _1+i.11 do.
                for_letter. i.7 do.
                    alteration =. value-((12*(octave+1))+letter{Natural)
                    if. alteration e._2 _1 0 1 2 do. names =. names,<note_text letter,alteration,octave end.
                end.
            end.
            emit 'ENHARMONIC ',(0{::args),' ',' ' join names
        end.
    case. 'NOTE' do.
        value =. parse_number 0{::args
        emit 'NOTE ',(number value),' ',(0 spelling value),' ',1 spelling value
    case. 'TUNING';'PITCH' do.
        frequency =. (command-:'TUNING') parse_frequency 0{::args
        if. command-:'TUNING' do.
            Tuning =: frequency
            emit 'TUNING ',frequency_text frequency
        else.
            height =. 69+12*(2 ^. frequency%Tuning)
            value =. <.0.5+height
            if. (value<0)+.value>127 do. fail 'OUT OF RANGE' end.
            cents =. <.0.5+100*(height-value)
            emit 'PITCH ',(frequency_text frequency),' ',(0 spelling value),' ',1 signed cents
        end.
    case. 'INTERVAL' do.
        first =. parse_note 0{::args
        second =. parse_note 1{::args
        result =. first between second
        simple =. simple_interval 2{.result
        class =. 'dissonant'
        if. (0=0{simple)*.(1{simple)e.1 5 8 do. class =. 'perfect'
        elseif. ((0{simple)e.1 2)*.(1{simple)e.3 6 do. class =. 'imperfect'
        end.
        direction =. (2{result){::'up';'down'
        emit 'INTERVAL ',(0{::args),' ',(1{::args),' ',(interval_text result),' ',direction,' semitones=',(number 3{result),' simple=',(interval_text simple),' class=',class
    case. 'INVERT' do.
        simple =. simple_interval parse_interval 0{::args
        inverse =. ((0{simple){0 2 1 4 3 6 5),9-1{simple
        if. (1=1{inverse)*.(0{inverse)e.4 6 do. fail 'CANNOT INVERT' end.
        emit 'INVERT ',(0{::args),' ',(interval_text simple),' ',interval_text inverse
    case. 'TRANSPOSE' do.
        note =. parse_note 0{::args
        tone =. interval_tone parse_interval 1{::args
        direction =. 2{::args
        if. -.(<direction)e.;:'UP DOWN' do. fail 'BAD DIRECTION ',direction end.
        if. direction-:'UP' do. sign =. 1 else. sign =. _1 end.
        target =. (position note)+sign*0{tone
        value =. (midi note)+sign*1{tone
        letter =. 7|target
        octave =. <.target%7
        alteration =. value-((12*(octave+1))+letter{Natural)
        if. -.alteration e._2 _1 0 1 2 do. fail 'CANNOT SPELL' end.
        result =. letter,alteration,octave
        if. -.valid_note result do. fail 'OUT OF RANGE' end.
        emit 'TRANSPOSE ',(' ' join args),' ',note_text result
    case. 'SCALE' do.
        root =. parse_pitch 0{::args
        scale =. parse_scale 1{::args
        tones =. scale{::ScaleTones
        pitches =. root build tones
        semitones =. 1{"1 tones
        steps =. ((}.semitones),12)-semitones
        emit 'SCALE ',(' ' join args),' ',(pitch_list pitches),' steps=',',' join number&.><"0 steps
    case. 'CHORD';'VOICE' do.
        if. command-:'VOICE' do.
            note =. parse_note 0{::args
            root =. 2{.note
        else. root =. parse_pitch 0{::args
        end.
        quality =. parse_quality 1{::args
        tones =. quality{::ChordTones
        inversion =. 0
        if. count=3 do.
            inversion =. ((#tones)-1) canonical 2{::args
            if. inversion<0 do. fail 'BAD INVERSION ',2{::args end.
        end.
        pitches =. inversion|.root build tones
        symbol =. root symbol_text quality
        if. inversion do. symbol =. symbol,'/',pitch_text {.pitches end.
        if. command-:'CHORD' do. emit 'CHORD ',symbol,' ',pitch_list pitches
        else.
            voiced =. 0 3$0
            value =. midi note
            for_i. i.#pitches do.
                pitch =. i{pitches
                if. (i>0)+.inversion>0 do.
                    difference =. 12|(pitch_class pitch)-value
                    if. difference=0 do. difference =. 12 end.
                    value =. value+difference
                end.
                result =. pitch make_note value
                if. -.valid_note result do. fail 'OUT OF RANGE' end.
                voiced =. voiced,result
            end.
            emit 'VOICE ',symbol,' ',(note_list voiced),' midi=',',' join number&.><"0 midi"1 voiced
        end.
    case. 'IDENTIFY';'MELODY' do.
        notes =. parse_notes args
        values =. midi"1 notes
        if. command-:'MELODY' do.
            low =. values i.<./values
            high =. values i.>./values
            range =. (low{notes) between high{notes
            steps =. 0$a:
            for_i. i.(#notes)-1 do.
                result =. (i{notes) between (i+1){notes
                steps =. steps,<((2{result){'+-'),interval_text result
            end.
            leaps =. +/3<:|(}.values)-}:values
            emit 'MELODY n=',(number #notes),' low=',(low{::args),' high=',(high{::args),' range=',(interval_text range),' leaps=',(number leaps),' steps=',',' join steps
        else.
            notes =. (/:values){notes
            classes =. pitch_class"1 notes
            notes =. (~:classes)#notes
            target =. /:~~.classes
            bass =. {.notes
            for_root. notes do.
                for_quality. i.#ChordNames do.
                    semitones =. 1{"1 quality{::ChordTones
                    candidate =. 12|(midi root)+semitones
                    if. target-:/:~~.candidate do.
                        inversion =. candidate i.pitch_class bass
                        symbol =. (2{.root) symbol_text quality
                        if. inversion do. symbol =. symbol,'/',pitch_text bass end.
                        emit 'IDENTIFY ',symbol,' root=',(pitch_text root),' quality=',(quality{::ChordNames),' inversion=',number inversion
                        return.
                    end.
                end.
            end.
            emit 'IDENTIFY UNKNOWN'
        end.
    case. 'CIRCLE' do.
        mode =. parse_mode 0{::args
        names =. 0$a:
        for_p. _7+i.15 do. names =. names,<pitch_text fifth_pitch p-mode{ModeOffsets end.
        emit 'CIRCLE ',(0{::args),' ',' ' join names
    case. 'FINDKEY' do.
        pitches =. parse_pitches args
        names =. 0$a:
        for_p. _7+i.15 do.
            for_mode. i.2 do.
                tonic =. fifth_pitch p-mode{ModeOffsets
                key =. tonic make_key mode
                scale =. key_scale key
                degrees =. 7|(0{"1 pitches)-0{key
                if. (1{"1 pitches)-:1{"1 degrees{scale do.
                    names =. names,<(pitch_text tonic),' ',mode{::ModeNames
                end.
            end.
        end.
        text =. 'FINDKEY ',number #names
        if. #names do. text =. text,' ',', ' join names end.
        emit text
    case. 'SPELL' do.
        value =. parse_number 0{::args
        key =. parse_key }.args
        scale =. key_scale key
        index =. (pitch_class"1 scale)i.12|value
        if. index<7 do. pitch =. index{scale
        else.
            if. (3{key)<0 do. names =. FlatNames else. names =. SharpNames end.
            pitch =. parse_pitch (12|value){::names
        end.
        result =. pitch make_note value
        if. -.valid_note result do. fail 'OUT OF RANGE' end.
        emit 'SPELL ',(number value),' ',(' ' join }.args),' ',(note_text result),' ',key degree_label pitch
    case. 'KEYSIG';'RELATIVE';'DIATONIC';'PROGRESSION';'ANALYZE';'DEGREE';'KEYDIST' do.
        key =. parse_key 2{.args
        heading =. command,' ',' ' join 2{.args
        fifths =. 3{key
        select. command
        case. 'KEYSIG' do.
            if. fifths=0 do. emit heading,' none'
            else.
                if. fifths>0 do.
                    names =. ' ' split 'F# C# G# D# A# E# B#'
                    label =. 'sharps'
                else.
                    names =. ' ' split 'Bb Eb Ab Db Gb Cb Fb'
                    label =. 'flats'
                end.
                emit heading,' ',label,'=',(number |fifths),' ',' ' join (|fifths){.names
            end.
        case. 'RELATIVE' do.
            emit heading,' major=',(pitch_text fifth_pitch fifths),' minor=',pitch_text fifth_pitch fifths+3
        case. 'DEGREE' do.
            pitch =. parse_pitch 2{::args
            emit heading,' ',(2{::args),' ',key degree_label pitch
        case. 'KEYDIST' do.
            other =. parse_key 2}.args
            first_set =. /:~~.pitch_class"1 key_scale key
            second_set =. /:~~.pitch_class"1 key_scale other
            common =. +/first_set e.second_set
            distance =. 12|(3{other)-fifths
            if. distance>6 do. distance =. distance-12 end.
            same_tonic =. (pitch_class key)=pitch_class other
            if. first_set-:second_set do.
                if. same_tonic do. relation =. 'same' else. relation =. 'relative' end.
            elseif. same_tonic do. relation =. 'parallel'
            elseif. 1=|distance do. relation =. 'close'
            else. relation =. 'distant'
            end.
            emit 'KEYDIST ',(' ' join args),' fifths=',(0 signed distance),' common=',(number common),' relation=',relation
        case. 'DIATONIC' do.
            scale =. key_scale key
            classes =. pitch_class"1 scale
            emit heading
            for_size. 3 4 do.
                items =. 0$a:
                for_i. i.7 do.
                    root_class =. i{classes
                    third =. 12|((7|i+2){classes)-root_class
                    fifth =. 12|((7|i+4){classes)-root_class
                    if. size=3 do.
                        if. third=4 do. quality =. 0
                        elseif. fifth=7 do. quality =. 1
                        else. quality =. 2
                        end.
                    else.
                        seventh =. 12|((7|i+6){classes)-root_class
                        if. third=4 do.
                            if. seventh=11 do. quality =. 9 else. quality =. 8 end.
                        elseif. fifth=7 do. quality =. 10
                        else. quality =. 12
                        end.
                    end.
                    items =. items,<(i roman_text quality),'=',(i{scale) symbol_text quality
                end.
                if. size=3 do. label =. 'TRIADS' else. label =. 'SEVENTHS' end.
                emit label,' ',' ' join items
            end.
        case. 'ANALYZE' do.
            symbols =. 0 3$0
            for_word. 2}.args do. symbols =. symbols,parse_symbol >word end.
            results =. 0$a:
            for_symbol. symbols do.
                root =. 2{.symbol
                results =. results,<(key degree_prefix root),(key degree_of root) roman_text 2{symbol
            end.
            emit heading,' ',' ' join results
        case. 'PROGRESSION' do.
            numerals =. 0 3$0
            for_word. 2}.args do. numerals =. numerals,parse_numeral >word end.
            scale =. key_scale key
            emit heading,' ',number #numerals
            for_i. i.#numerals do.
                'alteration degree quality' =. i{numerals
                root =. degree{scale
                root =. (0{root),(1{root)+alteration
                pitches =. root build quality{::ChordTones
                emit ((i+2){::args),' ',(root symbol_text quality),' ',pitch_list pitches
            end.
            cadence =. 'none'
            if. (#numerals)>1 do.
                first =. _2{numerals
                last =. _1{numerals
                if. (0=0{first)*.(0=0{last)*.(4=1{first)*.0=1{last do. cadence =. 'authentic'
                elseif. (0=0{first)*.(0=0{last)*.(3=1{first)*.0=1{last do. cadence =. 'plagal'
                elseif. (0=0{first)*.(0=0{last)*.(4=1{first)*.5=1{last do. cadence =. 'deceptive'
                elseif. (0=0{last)*.4=1{last do. cadence =. 'half'
                end.
            end.
            emit 'CADENCE ',cadence
        end.
    end.
)
main =: 3 : 0
    initialize ''
    count =. 0".1!:1 3
    for_i. i.count do.
        line =. 1!:1 3
        Output =: 0$a:
        try. execute line
        catcht. Output =: <'ERROR ',Error
        end.
        for_row. Output do. ((>row),LF) 1!:2 4 end.
    end.
)
main ''
exit 0
