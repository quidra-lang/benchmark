LF =: 10{a.
num =: 3 : ',''0'' 8!:2 y'
eq =: 4 : '(,x)-:,y'
split =: 4 : '<;._1 x,y'
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
words =: 3 : 0
    fields =. 0$a:
    for_v. y do.
        v =. >v
        if. 2~:3!:0 v do. v =. num v end.
        fields =. fields,<,v
    end.
    ' 'join fields
)
emit =: 3 : 'Output =: Output,<y'
say =: 3 : 'emit words y'
parse =: 3 : '0". ''_'' (I.y=''-'')}y'
fail =: 3 : 0
    Error =: y
    throw.
)
hex =: 3 : 0
    digits =. '0123456789ABCDEF'
    digits{~16 16#:y
)
unhex =: 3 : '16#.''0123456789ABCDEF''i.y'
hexdata =: 3 : ';hex each <"0 y'
be =: 4 : '(x#256)#:y'
Channel =: ;:'NOTE_OFF NOTE_ON POLY_PRESSURE CONTROL PROGRAM CHANNEL_PRESSURE PITCH_BEND'
Text =: ;:'TEXT_EVENT COPYRIGHT TRACK_NAME INSTRUMENT_NAME LYRIC MARKER CUE_POINT'
MetaNumbers =: 0 1 2 3 4 5 6 7 32 47 81 84 88 89 127
MetaNames =: ('SEQUENCE_NUMBER';Text),'CHANNEL_PREFIX';'END_OF_TRACK';'TEMPO';'SMPTE_OFFSET';'TIME_SIGNATURE';'KEY_SIGNATURE';'SEQUENCER_SPECIFIC'
Types =: Channel,MetaNames,;:'SYSEX SYSEX_ESCAPE META'
Major =: ;:'Cb Gb Db Ab Eb Bb F C G D A E B F# C#'
Minor =: ;:'Ab Eb Bb F C G D A E B F# C# G# D# A#'
NoteNames =: 0$a:
initNotes =: 3 : 0
for_n. i.128 do.
    NoteNames =: NoteNames,<((12|n){::;:'C C# D D# E F F# G G# A A# B'),num (<.n%12)-1
end.
)
initNotes''
makeEvent =: 3 : 0
    'tick type data ch meta' =. y
    tick;type;ch;data;meta
)
isOn =: 3 : 0
    if. -.'NOTE_ON'eq 1{::y do. 0 return. end.
    0<1{3{::y
)
isOff =: 3 : 0
    if. 'NOTE_OFF'eq 1{::y do. 1 return. end.
    if. -.'NOTE_ON'eq 1{::y do. 0 return. end.
    0=1{3{::y
)
channel =: 3 : '(<1{::y)e.Channel'
value =: 3 : '256#.3{::y'
globalEvents =: 3 : 0
    tracks =. 2{::y
    events =. 0$a:
    ranks =. 0 3$0
    for_t. i.#tracks do.
        track =. t{::tracks
        for_i. i.#track do.
            e =. i{::track
            events =. events,<e;t;i
            ranks =. ranks,(0{::e),t,i
        end.
    end.
    (/:ranks){events
)
eventCount =: 3 : '+/>#each 2{::y'
songLength =: 3 : 0
    result =. 0
    for_t. 2{::y do. result =. result>.0{::>{:>t end.
    result
)
description =: 3 : 0
    'f d tracks' =. y
    words 'format';f;'tracks';(#tracks);'division';d;'events';eventCount y
)
fields =: 3 : 0
    'tick type ch data meta' =. y
    if. (<type)e.Channel do.
        if. (<type)e.;:'NOTE_ON NOTE_OFF POLY_PRESSURE' do.
            words ch;((0{data){::NoteNames);1{data
        elseif. 'PITCH_BEND'eq type do. words ch;((128#. |.data)-8192)
        else. words (<ch),<"0 data end.
        return.
    end.
    if. (<type)e.Text do. '"',(data{a.),'"' return. end.
    select. type
    case. 'SEQUENCE_NUMBER';'TEMPO' do. num 256#.data
    case. 'CHANNEL_PREFIX' do. num >:{.data
    case. 'END_OF_TRACK' do. ''
    case. 'SMPTE_OFFSET' do. words <"0 data
    case. 'TIME_SIGNATURE' do. words ((num 0{data),'/',num 2^1{data);(2{data);3{data
    case. 'KEY_SIGNATURE' do.
        sf =. {.data
        if. sf>127 do. sf =. sf-256 end.
        if. 1{data do. ((sf+7){::Minor),' minor' else. ((sf+7){::Major),' major' end.
    case. do.
        result =. ''
        if. 'META'eq type do. result =. (hex meta),' ' end.
        result =. result,num #data
        if. #data do. result =. result,' ',hexdata data end.
        result
    end.
)
eventLine =: 3 : 0
    'e track' =. y
    result =. words (0{::e);track;1{::e
    f =. fields e
    if. #f do. result =. result,' ',f end.
    result
)
byteFail =: 3 : 'fail ''byte '',(num y),'': '',Reason'
chunk =: 3 : 0
    p =. Pos
    if. ((#Bytes)-p)<8 do. Reason =: 'truncated chunk'
        byteFail p end.
    if. -.y eq a.{~(p+i.4){Bytes do. Reason =: 'bad chunk id'
        byteFail p end.
    size =. 256#.(p+4+i.4){Bytes
    if. (p+8+size)>#Bytes do. Reason =: 'truncated chunk'
        byteFail p end.
    Pos =: p+8
    Pos+size
)
readByte =: 3 : 0
    if. Pos>:End do. Reason =: 'truncated event'
        byteFail EventStart end.
    b =. Pos{Bytes
    Pos =: >:Pos
    b
)
vlq =: 3 : 0
    start =. Pos
    result =. 0
    for_i. i.4 do.
        b =. readByte''
        result =. (128*result)+128|b
        if. b<128 do. result return. end.
    end.
    Reason =: 'variable-length value too long'
    byteFail start
)
parseHex =: 3 : 0
    Bytes =: y
    Pos =: 0
    end =. chunk 'MThd'
    if. (end-Pos)~:6 do. Reason =: 'bad header length'
        byteFail 4 end.
    f =. 256#.8 9{Bytes
    ntracks =. 256#.10 11{Bytes
    d =. 256#.12 13{Bytes
    if. f>2 do. Reason =: 'bad format'
        byteFail 8 end.
    if. (ntracks=0)+.(f=0)*.ntracks~:1 do. Reason =: 'bad track count'
        byteFail 10 end.
    if. d>:32768 do. Reason =: 'smpte timing not supported'
        byteFail 12 end.
    if. d=0 do. Reason =: 'bad division'
        byteFail 12 end.
    Pos =: 14
    tracks =. 0$a:
    for_t. i.ntracks do.
        if. Pos=#Bytes do. Reason =: 'missing track'
            byteFail #Bytes end.
        End =: chunk 'MTrk'
        tick =. 0
        running =. 0
        track =. 0$a:
        while. Pos<End do.
            EventStart =: Pos
            if. #track do.
                if. 'END_OF_TRACK'eq 1{::>{:track do. Reason =: 'event after end of track'
                    byteFail Pos end.
            end.
            tick =. tick+vlq''
            statusPos =. Pos
            status =. readByte''
            if. status<128 do.
                if. running=0 do. Reason =: 'data byte without running status'
                    byteFail statusPos end.
                Pos =: <:Pos
                status =. running
            end.
            if. status<240 do.
                running =. status
                high =. <.status%16
                n =. 2-(high e.12 13)
                data =. i.0
                for_i. i.n do.
                    at =. Pos
                    b =. readByte''
                    if. b>:128 do. Reason =: 'bad data byte'
                        byteFail at end.
                    data =. data,b
                end.
                e =. makeEvent tick;((high-8){::Channel);data;(1+16|status);_1
            elseif. status e.240 247 255 do.
                running =. 0
                meta =. _1
                if. status=255 do. meta =. readByte'' end.
                n =. vlq''
                if. (Pos+n)>End do. Reason =: 'truncated event'
                    byteFail EventStart end.
                data =. (Pos+i.n){Bytes
                Pos =: Pos+n
                if. status=255 do.
                    fixed =. 0 32 47 81 84 88 89 i.meta
                    if. fixed<7 do.
                        if. n~:fixed{2 1 0 3 5 4 2 do. Reason =: 'bad meta length'
                            byteFail statusPos end.
                    end.
                    bad =. 0
                    select. meta
                    case. 81 do. bad =. 0=256#.data
                    case. 32 do. bad =. 15<{.data
                    case. 88 do. bad =. (0={.data)+.6<1{data
                    case. 89 do.
                        sf =. {.data
                        if. sf>127 do. sf =. sf-256 end.
                        bad =. (7<|sf)+.1<1{data
                    end.
                    if. bad do. Reason =: 'bad meta data'
                        byteFail statusPos end.
                    type =. 'META'
                    at =. MetaNumbers i.meta
                    if. at<#MetaNumbers do. type =. at{::MetaNames end.
                elseif. status=240 do. type =. 'SYSEX'
                else. type =. 'SYSEX_ESCAPE' end.
                e =. makeEvent tick;type;data;0;meta
            else. Reason =: 'unknown status byte'
                byteFail statusPos end.
            track =. track,<e
        end.
        if. 0=#track do. Reason =: 'missing end of track'
            byteFail End end.
        if. -.'END_OF_TRACK'eq 1{::>{:track do. Reason =: 'missing end of track'
            byteFail End end.
        tracks =. tracks,<track
    end.
    if. Pos~:#Bytes do. Reason =: 'extra data'
        byteFail Pos end.
    f;d;<tracks
)
lineFail =: 3 : 'fail ''line '',(num y),'': '',Reason'
range =: 4 : '(x>:{.y)*.x<:{:y'
parseText =: 3 : 0
    lines =. y
    header =. ' 'split 0{::lines
    good =. 4=#header
    if. good do. good =. 'HEADER'eq 0{::header end.
    if. good do.
        'f ntracks d' =. parse each }.header
        good =. (f range 0 2)*.(ntracks range 1 65535)*.(d range 1 32767)*.((f~:0)+.ntracks=1)
    end.
    if. -.good do. Reason =: 'bad header'
        lineFail 1 end.
    tracks =. ,<0$a:
    current =. 0
    for_i. >:i.<:#lines do.
        fields =. ' 'split i{::lines
        tick =. parse 0{::fields
        t =. parse 1{::fields
        type =. 2{::fields
        raw =. 3}.fields
        if. -.(<type)e.Types do. Reason =: 'unknown event type'
            lineFail >:i end.
        data =. i.0
        ch =. 0
        meta =. _1
        valid =. 0
        if. (<type)e.Channel do.
            if. #raw do. ch =. parse 0{::raw end.
            if. (<type)e.;:'NOTE_ON NOTE_OFF POLY_PRESSURE' do.
                if. 3=#raw do.
                    p =. NoteNames i.1{raw
                    v =. parse 2{::raw
                    valid =. (ch range 1 16)*.(p<128)*.v range 0 127
                    data =. p,v
                end.
            elseif. 'PITCH_BEND'eq type do.
                if. 2=#raw do.
                    v =. parse 1{::raw
                    valid =. (ch range 1 16)*.v range _8192 8191
                    n =. v+8192
                    data =. (128|n),<.n%128
                end.
            else.
                n =. 2+'CONTROL'eq type
                if. n=#raw do.
                    data =. >parse each }.raw
                    valid =. (ch range 1 16)*.*./(data>:0)*.data<:127
                end.
            end.
        elseif. (<type)e.Text do.
            text =. ' 'join raw
            if. (#text)>:2 do.
                valid =. ('"'={.text)*.('"'={:text)*.-.'"'e.}.}:text
                data =. a.i.}.}:text
            end.
        else.
            select. type
            case. 'SEQUENCE_NUMBER';'TEMPO';'CHANNEL_PREFIX' do.
                if. 1=#raw do.
                    n =. parse 0{::raw
                    if. 'SEQUENCE_NUMBER'eq type do. valid =. n range 0 65535
                        data =. 2 be n
                    elseif. 'TEMPO'eq type do. valid =. n range 1 16777215
                        data =. 3 be n
                    else. valid =. n range 1 16
                        data =. ,n-1 end.
                end.
            case. 'END_OF_TRACK' do. valid =. 0=#raw
            case. 'SMPTE_OFFSET' do.
                if. 5=#raw do. data =. >parse each raw
                    valid =. *./(data>:0)*.data<:255 end.
            case. 'TIME_SIGNATURE' do.
                if. 3=#raw do.
                    signature =. '/'split 0{::raw
                    if. 2=#signature do.
                        'nn dd' =. parse each signature
                        cc =. parse 1{::raw
                        bb =. parse 2{::raw
                        valid =. (nn range 1 255)*.(dd e.1 2 4 8 16 32 64)*.(cc range 0 255)*.bb range 0 255
                        if. valid do. data =. nn,(2^.dd),cc,bb end.
                    end.
                end.
            case. 'KEY_SIGNATURE' do.
                if. 2=#raw do.
                    key =. 0{raw
                    mode =. 1{::raw
                    minor =. 'minor'eq mode
                    names =. Major
                    if. minor do. names =. Minor end.
                    index =. names i.key
                    valid =. (index<15)*.(<mode)e.;:'major minor'
                    data =. (256|index-7),minor
                end.
            case. do.
                offset =. 'META'eq type
                if. (#raw)>offset do.
                    n =. parse offset{::raw
                    valid =. n range 0 1000000
                    valid =. valid *. (#raw)=offset+1+(n>0)
                    text =. ''
                    if. (#raw)>offset+1 do. text =. (offset+1){::raw end.
                    valid =. valid *. ((#text)=2*n)*.*./text e.'0123456789ABCDEF'
                    if. offset do.
                        tt =. 0{::raw
                        valid =. valid *. (2=#tt)*.*./tt e.'0123456789ABCDEF'
                        if. valid do.
                            meta =. unhex tt
                            valid =. -.meta e.MetaNumbers
                        end.
                    end.
                    if. valid do.
                        for_j. i.n do. data =. data,unhex ((2*j)+i.2){text end.
                    end.
                end.
            end.
        end.
        if. -.valid do. Reason =: 'bad value'
            lineFail >:i end.
        if. t>:ntracks do. Reason =: 'bad track'
            lineFail >:i end.
        track =. current{::tracks
        ended =. 0
        if. #track do. ended =. 'END_OF_TRACK'eq 1{::>{:track end.
        if. t<current do. Reason =: 'out of order'
            lineFail >:i end.
        if. (t>current)*.((-.ended)+.t>current+1) do. Reason =: 'missing end of track'
            lineFail >:i end.
        if. (t=current)*.ended do. Reason =: 'event after end of track'
            lineFail >:i end.
        if. t=current+1 do. current =. >:current
            track =. 0$a:
            tracks =. tracks,<0$a: end.
        if. #track do.
            if. tick<0{::>{:track do. Reason =: 'out of order'
                lineFail >:i end.
        end.
        track =. track,<makeEvent tick;type;data;ch;meta
        tracks =. (<track)current}tracks
    end.
    track =. current{::tracks
    good =. (current+1)=ntracks
    if. 0=#track do. good =. 0 else. good =. good*.'END_OF_TRACK'eq 1{::>{:track end.
    if. -.good do. Reason =: 'missing end of track'
        lineFail >:#lines end.
    f;d;<tracks
)
pairing =: 3 : 0
    all =. globalEvents y
    queues =. (16*128)$<i.0
    notes =. 0 2$0
    unmatched =. i.0
    for_i. i.#all do.
        e =. 0{::i{::all
        if. -.((isOn e)+.isOff e) do. continue. end.
        key =. (128*<:2{::e)+{.3{::e
        queue =. key{::queues
        if. isOn e do. queue =. queue,i
        elseif. #queue do. notes =. notes,({.queue),i
            queue =. }.queue
        else. unmatched =. unmatched,i end.
        queues =. (<queue)key}queues
    end.
    for_q. queues do. unmatched =. unmatched,>q end.
    ranks =. 0 4$0
    for_pair. <"1 notes do.
        i =. {.,>pair
        e =. 0{::i{::all
        ranks =. ranks,(0{::e),(2{::e),({.3{::e),i
    end.
    all;((/:ranks){notes);/:~unmatched
)
timeAt =: 4 : 0
    song =. x
    tick =. y
    division =. 1{::song
    total =. last =. start =. 0
    tempo =. 500000
    bar =. 1
    nn =. 4
    beat =. division
    for_l. globalEvents song do.
        e =. 0{::>l
        u =. 0{::e
        if. u>tick do. break. end.
        if. 'TEMPO'eq 1{::e do. total =. total+(u-last)*tempo
            last =. u
            tempo =. value e end.
        if. 'TIME_SIGNATURE'eq 1{::e do.
            bar =. bar+>.(u-start)%(nn*beat)
            start =. u
            data =. 3{::e
            nn =. {.data
            beat =. 1>.<.(division*4)%2^1{data
        end.
    end.
    micros =. <.(total+(tick-last)*tempo)%division
    time =. (num <.micros%1000),'.',(_3{.'000',num 1000|micros)
    delta =. tick-start
    position =. (num bar+<.delta%(nn*beat)),':',(num 1+<.((nn*beat)|delta)%beat),':',num beat|delta
    time;position
)
encodeVlq =: 3 : 0
    n =. y
    bytes =. ,128|n
    n =. <.n%128
    while. n do. bytes =. (128+128|n),bytes
        n =. <.n%128 end.
    bytes
)
encode =: 3 : 0
    'f division tracks' =. y
    result =. 77 84 104 100 0 0 0 6,(2 be f),(2 be #tracks),2 be division
    for_t. tracks do.
        data =. i.0
        last =. status =. 0
        for_e. >t do.
            'tick type ch payload meta' =. >e
            data =. data,encodeVlq tick-last
            last =. tick
            if. (<type)e.Channel do.
                zero =. Noteoff*.('NOTE_OFF'eq type)
                next =. (128+16*Channel i.<type)+ch-1
                if. zero do. next =. 144+ch-1
                    payload =. ({.payload),0 end.
                if. (-.Running)+.status~:next do. data =. data,next end.
                status =. next
                data =. data,payload
            else.
                status =. 0
                if. 'SYSEX'eq type do. data =. data,240
                elseif. 'SYSEX_ESCAPE'eq type do. data =. data,247
                else.
                    if. -.'META'eq type do. meta =. (MetaNames i.<type){MetaNumbers end.
                    data =. data,255,meta
                end.
                data =. data,(encodeVlq #payload),payload
            end.
        end.
        result =. result,77 84 114 107,(4 be #data),data
    end.
    result
)
SongNames =: Songs =: 0$a:
Running =: 1
Noteoff =: 0
Output =: 0$a:
store =: 4 : 0
    index =. SongNames i.<x
    if. index=#SongNames do.
        SongNames =: SongNames,<x
        Songs =: Songs,<y
    else. Songs =: (<y)index}Songs end.
)
execute =: 3 : 0
    tokens =. ' 'split y
    cmd =. 0{::tokens
    args =. }.tokens
    known =. ;:'DECODE ENCODE TIMING NOTES STATS ROLL TRANSPOSE QUANTIZE VELOCITY TEMPO FILTER MERGE SPLIT COPY LIST RUNNING NOTEOFF'
    if. -.(<cmd)e.known do. fail 'unknown command' end.
    if. 'LIST'eq cmd do.
        if. 0=#Songs do. emit 'no songs' else.
            for_i. /:SongNames do. emit (i{::SongNames),' ',description i{::Songs end.
        end.
        return.
    end.
    name =. 0{::args
    if. (<cmd)e.;:'RUNNING NOTEOFF' do.
        if. 'RUNNING'eq cmd do.
            if. -.(<name)e.;:'ON OFF' do. fail 'bad argument' end.
            Running =: 'ON'eq name
            if. Running do. emit 'running on' else. emit 'running off' end.
        else.
            if. -.(<name)e.;:'ZERO KEEP' do. fail 'bad argument' end.
            Noteoff =: 'ZERO'eq name
            if. Noteoff do. emit 'noteoff zero' else. emit 'noteoff keep' end.
        end.
        return.
    end.
    index =. SongNames i.<name
    if. index=#Songs do. fail 'no song ',name end.
    song =. index{::Songs
    'format division tracks' =. song
    raw =. }.args
    a =. >parse each raw
    valid =. 1
    select. cmd
    case. 'TRANSPOSE' do.
        valid =. (0{a)range _127 127
        if. 2=#a do. valid =. valid*.(1{a)range 1 16 end.
    case. 'QUANTIZE' do. valid =. ((0{a)range 1 1000000)*.(1{a)range 0 100
    case. 'VELOCITY' do. valid =. ((0{a)range 0 1000)*.(1{a)range _127 127
    case. 'TEMPO' do. valid =. *./(a>:1)*.a<:1000
    case. 'FILTER' do. valid =. *./(a>:1)*.a<:16
    case. 'ROLL' do.
        'from to step' =. a
        valid =. (from range 0 10000000)*.(to range 1 10000000)*.(step range 1 10000000)*.to>from
        if. valid do. valid =. 64>:>.(to-from)%step end.
    end.
    if. -.valid do. fail 'bad argument' end.
    if. ((<cmd)e.;:'TIMING STATS')*.format=2 do. fail 'format 2 not supported' end.
    select. cmd
    case. 'COPY' do.
        (0{::raw)store song
        say 'copied';name;'to';0{::raw
    case. 'DECODE' do.
        say 'HEADER';format;(#tracks);division
        for_t. i.#tracks do. for_e. t{::tracks do. emit eventLine (>e);t end. end.
    case. 'ENCODE' do.
        bytes =. encode song
        for_i. 16*i.>.16%~#bytes do.
            pos =. '0123456789ABCDEF'{~16 16 16 16#:i
            emit pos,': ',' 'join hex each <"0 (i}.bytes){.~16<.(#bytes)-i
        end.
        say (#bytes);'bytes'
    case. 'TIMING' do.
        for_l. globalEvents song do.
            'e t order' =. >l
            'time bar' =. song timeAt 0{::e
            say (0{::e);t;(1{::e);time;bar
        end.
        tick =. songLength song
        'time bar' =. song timeAt tick
        say 'end';tick;time;bar
    case. 'NOTES';'STATS';'ROLL';'QUANTIZE' do.
        'all notes unmatched' =. pairing song
        if. 'NOTES'eq cmd do.
            say 'notes';(#notes);'unmatched';#unmatched
            for_pair. <"1 notes do.
                'on off' =. ,>pair
                e =. 0{::on{::all
                f =. 0{::off{::all
                say (0{::e);((0{::f)-0{::e);(2{::e);(({.3{::e){::NoteNames);1{3{::e
            end.
            for_i. unmatched do.
                'e t order' =. i{::all
                kind =. 'off'
                if. isOn e do. kind =. 'on' end.
                say 'unmatched';kind;(0{::e);t;(2{::e);({.3{::e){::NoteNames
            end.
        elseif. 'QUANTIZE'eq cmd do.
            targets =. notes
            for_i. unmatched do.
                if. isOn 0{::i{::all do. targets =. targets,i,_1 end.
            end.
            moved =. 0
            for_pair. <"1 targets do.
                'on off' =. ,>pair
                'e t order' =. on{::all
                tick =. 0{::e
                lower =. (0{a)*<.tick%0{a
                g =. lower
                if. (tick-lower)>(lower+(0{a))-tick do. g =. lower+0{a end.
                delta =. <.(100+2*(g-tick)*1{a)%200
                moved =. moved+delta~:0
                ids =. ,on
                if. off~:_1 do. ids =. ids,off end.
                for_id. ids do.
                    'e t order' =. id{::all
                    e =. (<delta+0{::e)0}e
                    track =. t{::tracks
                    track =. (<e)order}track
                    tracks =. (<track)t}tracks
                end.
            end.
            for_t. i.#tracks do.
                track =. t{::tracks
                end =. >{:track
                rest =. }:track
                ticks =. 0{::each rest
                if. #ticks do. end =. (<(0{::end)>.>./>ticks)0}end end.
                track =. ((/:>ticks){rest),<end
                tracks =. (<track)t}tracks
            end.
            say 'quantized';(#targets);'moved';moved
        elseif. 'ROLL'eq cmd do.
            'from to step' =. a
            rows =. 0
            for_p. |.i.128 do.
                cells =. ''
                for_tick. from+step*i.>.(to-from)%step do.
                    char =. '.'
                    for_pair. <"1 notes do.
                        'on off' =. ,>pair
                        e =. 0{::on{::all
                        f =. 0{::off{::all
                        if. p~:{.3{::e do. continue. end.
                        start =. 0{::e
                        if. (tick<:start)*.start<tick+step do. char =. '#' break.
                        elseif. (start<:tick)*.tick<0{::f do. char =. '=' end.
                    end.
                    cells =. cells,char
                end.
                if. +./cells~:'.' do.
                    label =. 4{.(p{::NoteNames),'    '
                    emit label,' ',cells
                    rows =. >:rows
                end.
            end.
            if. rows=0 do. emit 'empty' end.
        else.
            emit description song
            say 'notes';(#notes);'unmatched';#unmatched
            pitches =. i.0
            channels =. i.0
            changes =. 0 2$0
            for_pair. <"1 notes do.
                'on off' =. ,>pair
                e =. 0{::on{::all
                f =. 0{::off{::all
                pitches =. pitches,{.3{::e
                channels =. channels,2{::e
                if. (0{::f)>0{::e do. changes =. changes,((0{::e),1),:(0{::f),_1 end.
            end.
            for_ch. /:~~.channels do.
                ps =. pitches#~channels=ch
                say 'channel';ch;'notes';(#ps);'range';((<./ps){::NoteNames);(>./ps){::NoteNames
            end.
            if. #pitches do. say 'range';((<./pitches){::NoteNames);(>./pitches){::NoteNames else. emit 'range none' end.
            tick =. songLength song
            say 'length';tick;'ticks';(0{::song timeAt tick);'ms'
            maximum =. active =. at =. 0
            for_tick. /:~~.0{"1 changes do.
                active =. active++/1{"1 changes#~tick=0{"1 changes
                if. active>maximum do. maximum =. active
                    at =. tick end.
            end.
            if. maximum do. say 'polyphony';maximum;'at';at else. emit 'polyphony 0' end.
        end.
    case. 'TRANSPOSE';'VELOCITY';'FILTER';'TEMPO' do.
        kept =. dropped =. converted =. clamped =. removed =. scaled =. 0
        deleted =. 0$a:
        anyZero =. 0
        for_t. i.#tracks do.
            track =. 0$a:
            for_box. t{::tracks do.
                'tick type ch data meta' =. >box
                keep =. 1
                if. 'TRANSPOSE'eq cmd do.
                    target =. (<type)e.;:'NOTE_ON NOTE_OFF POLY_PRESSURE'
                    if. 2=#a do. target =. target*.ch=1{a end.
                    if. target do.
                        p =. {.data
                        n =. p+0{a
                        if. (n<0)+.n>127 do.
                            deleted =. deleted,<words 'dropped';tick;t;type;ch;p{::NoteNames
                            dropped =. >:dropped
                            keep =. 0
                        else. kept =. >:kept
                            data =. n 0}data end.
                    end.
                elseif. 'VELOCITY'eq cmd do.
                    if. isOn >box do.
                        n =. (1{a)+<.(50+(1{data)*0{a)%100
                        clamped =. clamped+((n<1)+.n>127)
                        data =. (1>.127<.n)1}data
                        converted =. >:converted
                    end.
                elseif. 'FILTER'eq cmd do.
                    if. ((<type)e.Channel)*.-.ch e.a do. keep =. 0
                        removed =. >:removed end.
                elseif. 'TEMPO'eq type do.
                    n =. <.((0{a)+2*(256#.data)*1{a)%(2*0{a)
                    if. -.n range 1 16777215 do. fail 'tempo out of range' end.
                    anyZero =. anyZero+.tick=0
                    data =. 3 be n
                    scaled =. >:scaled
                end.
                if. keep do. track =. track,<makeEvent tick;type;data;ch;meta end.
            end.
            tracks =. (<track)t}tracks
        end.
        select. cmd
        case. 'TRANSPOSE' do.
            say 'transposed';kept;'dropped';dropped
            for_l. deleted do. emit >l end.
        case. 'VELOCITY' do. say 'velocity';converted;'clamped';clamped
        case. 'FILTER' do. say 'removed';removed
        case. 'TEMPO' do.
            n =. <.((0{a)+2*500000*1{a)%(2*0{a)
            if. -.anyZero do.
                if. -.n range 1 16777215 do. fail 'tempo out of range' end.
                e =. makeEvent 0;'TEMPO';(3 be n);0;_1
                track =. (<e),0{::tracks
                tracks =. (<track)0}tracks
            end.
            say 'scaled';scaled
            if. -.anyZero do. say 'inserted';0;0;'TEMPO';n end.
        end.
    case. 'MERGE' do.
        if. format~:1 do. fail 'not format 1' end.
        track =. 0$a:
        for_l. globalEvents song do.
            e =. 0{::>l
            if. -.'END_OF_TRACK'eq 1{::e do. track =. track,<e end.
        end.
        track =. track,<makeEvent (songLength song);'END_OF_TRACK';(i.0);0;_1
        original =. #tracks
        tracks =. ,<track
        format =. 0
        say 'merged';original;'tracks';'events';#track
    case. 'SPLIT' do.
        if. format~:0 do. fail 'not format 0' end.
        source =. }:0{::tracks
        tracks =. 17$<0$a:
        used =. 17#0
        for_box. source do.
            e =. >box
            dest =. 0
            if. channel e do. dest =. 2{::e end.
            track =. (dest{::tracks),<e
            tracks =. (<track)dest}tracks
            used =. 1 dest}used
        end.
        used =. 1 0}used
        tracks =. used#tracks
        end =. makeEvent (songLength song);'END_OF_TRACK';(i.0);0;_1
        tracks =. tracks ,each <,<end
        format =. 1
        say 'split';'tracks';(#tracks);'events';eventCount format;division;<tracks
    end.
    if. (<cmd)e.;:'TRANSPOSE QUANTIZE VELOCITY TEMPO FILTER MERGE SPLIT' do.
        name store format;division;<tracks
    end.
)
main =: 3 : 0
    lines =. <;._2 (1!:1 <'/dev/stdin'),LF
    n =. parse 0{::lines
    cursor =. 1
    for_i. i.n do.
        text =. cursor{::lines
        cursor =. >:cursor
        tokens =. ' 'split text
        cmd =. 0{::tokens
        try.
            if. (<cmd)e.;:'HEX TEXT' do.
                name =. 1{::tokens
                k =. parse 2{::tokens
                data =. (cursor+i.k){lines
                cursor =. cursor+k
                if. 'HEX'eq cmd do.
                    bytes =. >unhex each ' 'split ' 'join data
                    song =. parseHex bytes
                else. song =. parseText data end.
                name store song
                emit 'loaded ',name,' ',description song
            else. execute text end.
        catcht. emit 'error: ',Error end.
    end.
    1!:2&2 (LF join Output),LF
)
main''
