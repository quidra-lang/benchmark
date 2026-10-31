LF =: 10{a.
number =: 3 : ',''0'' 8!:2 y'
eq =: 4 : '(,x)-:,y'
split =: 4 : '<;._1 x,y'
join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do. text =. text,x end.
        text =. text,i{::y
    end.
    text
)
words =: 3 : 0
    fields =. 0$a:
    for_v. y do.
        v =. >v
        if. 2~:3!:0 v do. v =. number v end.
        fields =. fields,<,v
    end.
    ' 'join fields
)
emit =: 3 : 'Output =: Output,<y'
say =: 3 : 'emit words y'
fail =: 3 : 0
    Error =: y
    throw.
)
parse =: 3 : '0". ''_'' (I.y=''-'')}y'
fixed =: 4 : 0
    'den digits' =. y
    scale =. 10^digits
    q =. <.(scale*x)%den
    (number <.q%scale),'.',(-digits){.(digits#'0'),number scale|q
)
Protocols =: ;:'SW GBN SR'
TraceNames =: ;:'all sender receiver none'
Keys =: ;:'PROTOCOL FRAMES WINDOW SEQBITS TIMEOUT DELAY INTERVAL MAXTICKS DUPACK NAK BACKOFF CONGESTION UNSAFE TRACE RANDOM LOSEDATA LOSECTRL CORRUPTDATA CORRUPTCTRL DELAYDATA DELAYCTRL SNAPSHOT'
Low =: 0 1 1 1 1 1 0 1 1
High =: 0 60 32 6 50 10 10 2000 10
validate =: 3 : 0
    Raw =: 22$<0$a:
    Seen =: 22#0
    for_line. y do.
        fields =. ' 'split >line
        key =. 0{::fields
        k =. Keys i.<key
        if. k=22 do. fail 'unknown key ',key end.
        if. k{Seen do. fail 'duplicate key ',key end.
        values =. }.fields
        if. k=14 do. good =. 3=#values
        elseif. k>:15 do. good =. 0<#values
        else. good =. 1=#values end.
        if. -.good do. fail 'wrong number of values for ',key end.
        Raw =: (<values) k}Raw
        Seen =: 1 k}Seen
    end.
    for_k. i.6 do.
        if. -.k{Seen do. fail 'missing key ',k{::Keys end.
    end.
    Config =: (<0),(<0),(<0),(<0),(<0),(<0),(<0),(<1000),(<0),(<0),(<0),(<0),(<0),(<0),(<i.0),4$<i.0
    Config =: Config,(<0 2$0),(<0 2$0),<i.0
    for_k. I.Seen do.
        values =. k{::Raw
        good =. 1
        select. k
        case. 0 do.
            decoded =. Protocols i.{.values
            good =. decoded<3
        case. 9;10;11;12 do.
            decoded =. ('OFF';'ON')i.{.values
            good =. decoded<2
        case. 13 do.
            decoded =. (;:'ALL SENDER RECEIVER NONE')i.{.values
            good =. decoded<4
        case. 19;20 do.
            decoded =. 0 2$0
            for_value. values do. decoded =. decoded,>parse&.>':'split >value end.
            numbers =. 0{"1 decoded
            extra =. 1{"1 decoded
            good =. (*./(numbers>:1)*.numbers<:9999)*.(*./(extra>:1)*.extra<:50)*.(#numbers)=#~.numbers
        case. do.
            decoded =. >parse&.>values
            if. k<9 do.
                decoded =. {.decoded
                good =. (decoded>:k{Low)*.decoded<:k{High
            elseif. k=14 do.
                'seed loss corrupt' =. decoded
                good =. (seed>:1)*.(seed<:2147483646)*.(loss>:0)*.(corrupt>:0)*.(loss+corrupt)<:100
            else.
                if. k=21 do. low =. 0 [ high =. 2000 else. low =. 1 [ high =. 9999 end.
                good =. (*./(decoded>:low)*.decoded<:high)*.(#decoded)=#~.decoded
            end.
        end.
        if. -.good do. fail 'bad value for ',k{::Keys end.
        Config =: (<decoded) k}Config
    end.
    Protocol =: 0{::Config
    N =: 1{::Config
    W =: 2{::Config
    K =: 3{::Config
    T =: 4{::Config
    Delay =: 5{::Config
    Interval =: 6{::Config
    Limit =: 7{::Config
    Dupack =: 8{::Config
    Nak =: 9{::Config
    Backoff =: 10{::Config
    Congestion =: 11{::Config
    Unsafe =: 12{::Config
    Trace =: 13{::Config
    M =: 2^K
    if. (Protocol=2)*.8{Seen do. fail 'DUPACK not supported for SR' end.
    upper =. Protocol{1,(M-1),-:M
    if. (W>upper)*.-.Unsafe*.Protocol>0 do.
        fail words 'window';W;'exceeds limit';upper;'for';Protocol{::Protocols
    end.
    both =. (15{::Config) e.17{::Config
    if. +./both do. fail 'data #',(number <./both#15{::Config),' both lost and corrupted' end.
    both =. (16{::Config) e.18{::Config
    if. +./both do. fail 'control #',(number <./both#16{::Config),' both lost and corrupted' end.
)
event =: 4 : 0
    if. (x=0)+.(Trace=0)+.Trace=x do. emit (number Time),' ',y end.
)
effective =: 3 : 0
    if. Congestion do. W<.Cwnd else. W end.
)
outcome =: 4 : 0
    result =. 0
    if. 14{Seen do.
        Random =: 2147483647|48271*Random
        v =. 100|Random
        'seed loss corrupt' =. 14{::Config
        if. v<loss do. result =. 1 elseif. v<loss+corrupt do. result =. 2 end.
    end.
    if. y e.(15+x){::Config do. result =. 1 end.
    if. y e.(17+x){::Config do. result =. 2 end.
    result
)
extra_delay =: 4 : 0
    pairs =. (19+x){::Config
    list =. I.y=0{"1 pairs
    if. #list do. (<({.list),1){pairs else. 0 end.
)
control =: 4 : 0
    Control =: Control+1
    Naks =: Naks+x
    2 event words (x{::'ACK';'NAK');('a=',number y);'#',number Control
    result =. 1 outcome Control
    arrival =. Time+Delay+1 extra_delay Control
    ControlEvents =: ControlEvents,arrival,Control,result,x,y
)
deliver =: 3 : 0
    if. y=Receiver do.
        2 event 'DELIVER f=',number Receiver
        Records =: Time (<Receiver,2)}Records
        Delivered =: Delivered+1
    else.
        2 event words 'DELIVER';('f=',number Receiver);'wrong=',number y
        Errors =: Errors+1
    end.
    Receiver =: Receiver+1
    NakSent =: 0
)
discard =: 3 : 0
    Discarded =: Discarded+1
    2 event 'DISCARD seq=',number y
)
receive_data =: 3 : 0
    'arrival sequence result s payload' =. y
    if. result do.
        Channel =: (1+((result-1)*2){Channel) ((result-1)*2)}Channel
        2 event words (result{::'';'LOST';'CORRUPT');'data';'#',number sequence
        return.
    end.
    2 event words 'RECV';('seq=',number s);'#',number sequence
    if. Protocol<2 do.
        if. s=M|Receiver do.
            deliver payload
            0 control s
        else.
            discard s
            if. Nak*.-.NakSent do.
                1 control M|Receiver
                NakSent =: 1
            elseif. Receiver>0 do. 0 control M|Receiver-1 end.
        end.
    else.
        offset =. M|s-Receiver
        if. offset<W do.
            position =. Receiver+offset
            if. position e.0{"1 Buffer do.
                discard s
                0 control s
            elseif. offset=0 do.
                deliver payload
                while. Receiver e.0{"1 Buffer do.
                    index =. (0{"1 Buffer)i.Receiver
                    payload =. (<index,1){Buffer
                    Buffer =: ((i.#Buffer)-.index){Buffer
                    deliver payload
                end.
                0 control s
            else.
                Buffer =: Buffer,position,payload
                MaxBuffer =: MaxBuffer>.#Buffer
                2 event 'BUFFER f=',number position
                0 control s
                if. Nak*.-.NakSent do.
                    1 control M|Receiver
                    NakSent =: 1
                end.
            end.
        else.
            discard s
            if. (M|Receiver-s)<:W do. 0 control s end.
        end.
    end.
)
goback =: 3 : 0
    Next =: Base
    Timer =: _1
    Duplicates =: 0
)
grow =: 3 : 0
    if. -.Congestion do. return. end.
    for_i. i.y do.
        if. Cwnd<W do.
            if. Cwnd<Threshold do. Cwnd =: Cwnd+1
            else.
                Additive =: Additive+1
                if. Additive=Cwnd do. Cwnd =: Cwnd+1 [ Additive =: 0 end.
            end.
        end.
    end.
)
decrease =: 3 : 0
    if. Congestion do.
        Threshold =: 1>.<.Cwnd%2
        if. y do. Cwnd =: 1 else. Cwnd =: Threshold end.
        Additive =: 0
    end.
)
cwnd_line =: 3 : 0
    if. -.y-:Cwnd,Threshold do. 1 event words 'CWND';Cwnd;'ssthresh=',number Threshold end.
)
ack_range =: 3 : 0
    'first last' =. y
    for_f. first+i.0>.last-first do.
        if. ((<f,3){Records)<0 do. Records =: Time (<f,3)}Records end.
    end.
)
base_changed =: 3 : 0
    if. Base>y do.
        C =: T
        if. Protocol<2 do. Duplicates =: 0 end.
    end.
)
receive_control =: 3 : 0
    'arrival sequence result kind a' =. y
    if. result do.
        index =. 1+2*result-1
        Channel =: (1+index{Channel) index}Channel
        1 event words (result{::'';'LOST';'CORRUPT');(kind{::'ack';'nak');'#',number sequence
        return.
    end.
    before =. Cwnd,Threshold
    oldbase =. Base
    f =. Base+M|a-Base
    accepted =. 0
    if. kind=0 do.
        if. f<H do.
            if. Protocol<2 do.
                accepted =. 1
                Base =: f+1
                ack_range oldbase,Base
                base_changed oldbase
                grow Base-oldbase
                Next =: Next>.Base
                if. Base=Next do. Timer =: _1 else. Timer =: Time+C end.
            elseif. -.f{Acked do.
                accepted =. 1
                Acked =: 1 f}Acked
                Timers =: _1 f}Timers
                Queue =: Queue-.f
                if. ((<f,3){Records)<0 do. Records =: Time (<f,3)}Records end.
                while. Base<H do.
                    if. -.Base{Acked do. break. end.
                    Base =: Base+1
                end.
                base_changed oldbase
                grow 1
            end.
        end.
    else.
        if. Protocol<2 do.
            if. f<:H do.
                accepted =. 1
                Base =: f
                ack_range oldbase,Base
                base_changed oldbase
                grow Base-oldbase
                goback ''
                decrease 0
            end.
        elseif. f<H do.
            if. -.f{Acked do.
                accepted =. 1
                Timers =: _1 f}Timers
                if. -.f e.Queue do. Queue =: Queue,f end.
                decrease 0
            end.
        end.
    end.
    noun =. kind{::'ACK';'NAK'
    if. accepted do.
        1 event words ('GOT',noun);('a=',number a);('#',number sequence);'base=',number Base
    else.
        1 event words ('OLD',noun);('a=',number a);'#',number sequence
        if. (kind=0)*.(Protocol<2)*.(Dupack>0)*.(Base>:1)*.a=M|Base-1 do.
            Duplicates =: Duplicates+1
            if. Duplicates=Dupack do.
                Fast =: Fast+1
                1 event 'FASTRETX f=',number Base
                goback ''
                decrease 0
            end.
        end.
    end.
    cwnd_line before
)
timeout =: 3 : 0
    before =. Cwnd,Threshold
    1 event 'TIMEOUT f=',number y
    Timeouts =: Timeouts+1
    if. Backoff do. C =: (2*C)<.8*T end.
    decrease 1
    cwnd_line before
)
send =: 3 : 0
    f =. y
    tx =. (<f,0){Records
    if. tx=0 do.
        Records =: Time (<f,1)}Records
        verb =. 'SEND'
    else. Resent =: Resent+1 [ verb =. 'RESEND' end.
    Records =: (tx+1) (<f,0)}Records
    Data =: Data+1
    s =. M|f
    1 event words verb;('f=',number f);('seq=',number s);'#',number Data
    result =. 0 outcome Data
    arrival =. Time+Delay+0 extra_delay Data
    DataEvents =: DataEvents,arrival,Data,result,s,f
)
snapshot =: 3 : 0
    sender =. receiver =. ''
    e =. effective ''
    for_f. i.N do.
        if. Protocol<2 do.
            if. f<Base do. c =. 'A'
            elseif. (f>:Next)*.f<H do. c =. 'R'
            elseif. f<Next do. c =. 'O'
            elseif. f<Base+e do. c =. 'W'
            else. c =. '.' end.
        else.
            if. f{Acked do. c =. 'A'
            elseif. f e.Queue do. c =. 'R'
            elseif. f<H do. c =. 'O'
            elseif. f<Base+e do. c =. 'W'
            else. c =. '.' end.
        end.
        sender =. sender,c
        if. f<Receiver do. c =. 'D'
        elseif. (Protocol=2)*.f e.0{"1 Buffer do. c =. 'B'
        elseif. ((Protocol=2)*.f<Receiver+W)+.((Protocol<2)*.f=Receiver) do. c =. 'W'
        else. c =. '.' end.
        receiver =. receiver,c
    end.
    0 event words 'SNAPSHOT';('sender=',sender);'receiver=',receiver
)
optional_tick =: 3 : 0
    if. y<0 do. '-' else. number y end.
)
simulate =: 3 : 0
    say 'config:';(Protocol{::Protocols);('n=',number N);('w=',number W);('k=',number K);('T=',number T);'d=',number Delay
    if. Dupack do. dup =. number Dupack else. dup =. 'off' end.
    randomtext =. 'off'
    if. 14{Seen do. randomtext =. '/'join number&.><"0 14{::Config end.
    say 'options:';('interval=',number Interval);('limit=',number Limit);('dupack=',dup);('nak=',Nak{::'off';'on');('backoff=',Backoff{::'off';'on');('congestion=',Congestion{::'off';'on');('unsafe=',Unsafe{::'off';'on');('trace=',Trace{::TraceNames);'random=',randomtext
    Base =: H =: Next =: Duplicates =: Receiver =: NakSent =: 0
    C =: T
    Timer =: _1
    Timers =: N#_1
    Acked =: N#0
    Queue =: i.0
    Buffer =: 0 2$0
    DataEvents =: ControlEvents =: 0 5$0
    Records =: (N,4)$0
    Records =: _1 (<(i.N);1 2 3)}Records
    Cwnd =: 1
    Threshold =: W
    Additive =: 0
    Random =: 1
    if. 14{Seen do. Random =: {.14{::Config end.
    Data =: Resent =: Control =: Naks =: Timeouts =: Fast =: 0
    Channel =: 4#0
    Delivered =: Errors =: Discarded =: MaxBuffer =: 0
    Complete =: 0
    for_t. i.Limit+1 do.
        Time =: t
        arrivals =. DataEvents#~Time=0{"1 DataEvents
        DataEvents =: DataEvents#~Time~:0{"1 DataEvents
        for_row. arrivals do. receive_data row end.
        arrivals =. ControlEvents#~Time=0{"1 ControlEvents
        ControlEvents =: ControlEvents#~Time~:0{"1 ControlEvents
        for_row. arrivals do. receive_control row end.
        if. Base=N do. Complete =: 1
        else.
            if. Protocol<2 do.
                if. Timer=Time do.
                    f =. Base
                    goback ''
                    timeout f
                end.
            else.
                for_f. Base+i.H-Base do.
                    if. Time=f{Timers do.
                        Timers =: _1 f}Timers
                        Queue =: Queue,f
                        timeout f
                    end.
                end.
            end.
            e =. effective ''
            if. Protocol<2 do.
                if. (Next<N)*.(Next<Base+e)*.((Next<H)+.(Next*Interval)<:Time) do.
                    send Next
                    H =: H>.Next+1
                    Next =: Next+1
                    if. Timer<0 do. Timer =: Time+C end.
                end.
            elseif. #Queue do.
                f =. {.Queue
                Queue =: }.Queue
                send f
                Timers =: (Time+C) f}Timers
            elseif. (H<N)*.(H<Base+e)*.(H*Interval)<:Time do.
                send H
                Timers =: (Time+C) H}Timers
                H =: H+1
            end.
        end.
        if. Time e.21{::Config do. snapshot '' end.
        if. Complete do.
            0 event 'DONE'
            break.
        end.
        if. Time=Limit do.
            0 event 'ABORT'
            break.
        end.
    end.
    for_f. i.N do.
        'tx first delivered acked' =. f{Records
        say 'frame';((number f),':');('seq=',number M|f);('tx=',number tx);('first=',optional_tick first);('delivered=',optional_tick delivered);'acked=',optional_tick acked
    end.
    say 'totals:';('data=',number Data);('resent=',number Resent);('control=',number Control);('nak=',number Naks);('timeouts=',number Timeouts);'fastretx=',number Fast
    say 'channel:';('lost_data=',number 0{Channel);('lost_ctrl=',number 1{Channel);('corrupt_data=',number 2{Channel);'corrupt_ctrl=',number 3{Channel
    say 'receiver:';('delivered=',number Delivered);('errors=',number Errors);('discarded=',number Discarded);'max_buffer=',number MaxBuffer
    completion =. goodput =. latency =. '-'
    if. Complete do. completion =. number Time [ goodput =. Delivered fixed Time,2 end.
    efficiency =. (100*Delivered)fixed Data,1
    utilization =. (100*Data)fixed (Time+1),1
    if. Delivered do.
        list =. I.0<:2{"1 Records
        total =. +/(list{2{"1 Records)-list{1{"1 Records
        latency =. total fixed Delivered,2
    end.
    say 'result:';('completion=',completion);('goodput=',goodput);('efficiency=',efficiency,'%');('utilization=',utilization,'%');'latency=',latency
    Protocol,(1+Complete),Delivered,Time,Data
)
better =: 4 : 0
    'p status d t data' =. x{Results
    'p status e u other' =. y{Results
    a =. d*u
    b =. e*t
    if. a~:b do. a>b else. (d*other)>e*data end.
)
main =: 3 : 0
    q =. 0".1!:1 3
    Output =: 0$a:
    Names =: 0$a:
    Results =: 0 5$0
    for_i. i.q do.
        fields =. ' 'split 1!:1 3
        name =. 1{::fields
        Names =: Names,<name
        settings =. 0$a:
        while. 1 do.
            line =. 1!:1 3
            if. line eq 'END' do. break. end.
            settings =. settings,<line
        end.
        emit '== ',name,' =='
        try.
            validate settings
            result =. simulate ''
        catcht.
            emit 'error: ',Error
            result =. _1,0,0,0,0
        end.
        Results =: Results,result
    end.
    emit '== ranking =='
    ranking =. I.2=1{"1 Results
    for_i. i.#ranking do.
        j =. i
        while. j>0 do.
            a =. j{ranking
            b =. (j-1){ranking
            if. -.a better b do. break. end.
            ranking =. a (j-1)}ranking
            ranking =. b j}ranking
            j =. j-1
        end.
    end.
    for_i. i.#ranking do.
        index =. i{ranking
        'protocol status d t data' =. index{Results
        say ((number i+1),'.');(index{::Names);(protocol{::Protocols);('goodput=',d fixed t,2);'efficiency=',((100*d)fixed data,1),'%'
    end.
    for_i. I.2~:1{"1 Results do.
        status =. (<i,1){Results
        say '-';(i{::Names);status{::'invalid';'aborted'
    end.
    emit '== protocols =='
    for_p. i.3 do.
        list =. I.(p=0{"1 Results)*.2=1{"1 Results
        if. #list do.
            totals =. +/list{Results
            d =. 2{totals
            t =. 3{totals
            data =. 4{totals
            say ((p{::Protocols),':');('runs=',number #list);('goodput=',d fixed t,2);'efficiency=',((100*d)fixed data,1),'%'
        end.
    end.
    for_line. Output do. ((>line),LF)1!:2 4 end.
    i.0
)
main ''
