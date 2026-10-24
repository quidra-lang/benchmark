LF =: 10{a.
number =: 3 : ',''0'' 8!:2 y'
eq =: 4 : '(,x)-:,y'
unsigned =: 3 : '0".y'
split =: 4 : '<;._1 x,y'
join =: 4 : 0
    r =. ''
    for_i. i.#y do.
        if. i do. r =. r,x end.
        r =. r,i{::y
    end.
    r
)
words =: 3 : 0
    r =. 0$a:
    for_v. y do.
        v =. >v
        if. 2~:3!:0 v do. v =. number v end.
        r =. r,<,v
    end.
    ' ' join r
)
emit =: 3 : 'Output =: Output,<y'
say =: 3 : 'emit words y'
fail =: 3 : 0
    Error =: y
    throw.
)
hex =: 3 : 0
    if. y=0 do. '0x0' return. end.
    '0x',('0123456789ABCDEF'{~|.16|<.y%16^i.1+<.16^.y)
)
unhex =: 3 : '16#. ''0123456789ABCDEF'' i.2}.y'
decimal =: 4 : 0
    if. y=0 do. q =. 0 else. q =. <.(100*x)%y end.
    (number <.q%100),'.',_2{.'00',number 100|q
)
ratio =: 4 : '((100*x)decimal y),''%'''
Policies =: ;:'FIFO LRU LFU NRU AGING CLOCK ECLOCK WSCLOCK RANDOM OPT'
Keys =: ;:'page frames tlb sets policy scope asid tick tau seed'
Defaults =: 256 4 4 1 0 0 0 0 8 1
parameter_text =: 3 : 0
    values =. number&.><"0 Settings
    values =. (<(4{Settings){::Policies) 4}values
    values =. (<(5{Settings){::'GLOBAL';'LOCAL') 5}values
    values =. (<(6{Settings){::'OFF';'ON') 6}values
    text =. 0$a:
    for_i. i.10 do. text =. text,<(i{::Keys),'=',i{::values end.
    ' 'join text
)
parse_settings =: 3 : 0
    Settings =: Defaults
    seen =. 10#0
    for_pair. y do.
        'key value' =. '='split >pair
        key =. >key
        value =. >value
        k =. Keys i.<key
        if. k=10 do. fail 'unknown key ',key end.
        if. k{seen do. fail 'duplicate key ',key end.
        seen =. 1 k}seen
        n =. 0".value
        valid =. 0
        select. k
        case. 0 do. valid =. n e.2^4+i.9
        case. 1 do. valid =. (n>:1)*.n<:16
        case. 2;3 do. valid =. (n>:1)*.n<:8
        case. 4 do. n =. Policies i.<value [ valid =. (<value)e.Policies
        case. 5 do. n =. ('GLOBAL';'LOCAL')i.<value [ valid =. (<value)e.'GLOBAL';'LOCAL'
        case. 6 do. n =. ('OFF';'ON')i.<value [ valid =. (<value)e.'OFF';'ON'
        case. 7 do. valid =. (n>:0)*.n<:1000
        case. 8 do. valid =. (n>:1)*.n<:1000
        case. 9 do. valid =. (n>:1)*.n<:2147483646
        end.
        if. -.valid do. fail 'invalid ',key end.
        Settings =: n k}Settings
    end.
    if. 0~:(3{Settings)|2{Settings do. fail 'invalid sets' end.
)
NB. Processes: pid,count,exited,accesses,faults,writebacks,segfaults,protfaults,peak,hand.
NB. Pages: process index,page,frame,slot,RO,locked,R,M,load,last,uses,age,seen.
reset =: 3 : 0
    Processes =: 0 10$0
    Pages =: 0 13$0
    Frames =: (1{Settings)#_1
    Tlbs =: (3{Settings)$<i.0
    Events =: 0$a:
    FaultHistory =: i.0
    Time =: Faults =: Zero =: Swapin =: TlbHits =: Writebacks =: Switches =: Hand =: 0
    Fixed =: Trace =: 0
    Previous =: _1
    Random =: 9{Settings
)
process =: 3 : 0
    p =. (0{"1 Processes)i.y
    if. p=#Processes do. fail 'unknown process ',number y end.
    if. (<p,2){Processes do. fail 'process ',(number y),' exited' end.
    p
)
resident =: 3 : '+/(y=0{"1 Pages)*.0<:2{"1 Pages'
quota =: 3 : 0
    n =. #Processes
    rank =. +/(0{"1 Processes)<(<y,0){Processes
    (<.(1{Settings)%n)+rank<n|1{Settings
)
declare =: 3 : 0
    'pid count' =. y
    if. Fixed do. fail 'processes are fixed' end.
    if. pid e.0{"1 Processes do. fail 'duplicate process ',number pid end.
    if. (count<1)+.count>256 do. fail 'invalid page count' end.
    if. ((#Processes)>:8)+.((5{Settings)=1)*.(#Processes)>:1{Settings do. fail 'too many processes' end.
    p =. #Processes
    Processes =: Processes,pid,count,8#0
    rows =. (count,13)$0
    rows =. p (<(i.count);0)}rows
    rows =. (i.count) (<(i.count);1)}rows
    rows =. _1 (<(i.count);2 3)}rows
    Pages =: Pages,rows
)
remove_tlb =: 3 : 0
    for_i. i.#Tlbs do. Tlbs =: (<(i{::Tlbs)-.y) i}Tlbs end.
)
writeback =: 3 : 0
    Writebacks =: Writebacks+1
    p =. (<y,0){Pages
    Processes =: (1+(<p,5){Processes) (<p,5)}Processes
    Pages =: 0 (<y,7)}Pages
    if. ((<y,3){Pages)<0 do.
        slots =. 3{"1 Pages
        slot =. 0
        while. slot e.slots do. slot =. slot+1 end.
        Pages =: slot (<y,3)}Pages
    end.
)
clean =: 3 : 0
    count =. 0
    for_page. Frames#~Frames>:0 do.
        if. (<page,7){Pages do. writeback page [ count =. count+1 end.
    end.
    if. y do. Events =: Events,<,2 end.
    count
)
exit_process =: 4 : 0
    p =. process y
    list =. I.p=0{"1 Pages
    freed =. +/0<:list{2{"1 Pages
    slots =. +/0<:list{3{"1 Pages
    for_page. list do.
        frame =. (<page,2){Pages
        if. frame>:0 do. Frames =: _1 frame}Frames end.
        remove_tlb page
    end.
    Pages =: _1 (<list;2 3)}Pages
    Processes =: 1 (<p,2)}Processes
    if. x do. Events =: Events,<1,y end.
    words 'EXIT';('P',number y);('freed=',number freed);'slots=',number slots
)
attributes =: 4 : 0
    'kind pid first last value' =. y
    p =. process pid
    if. (first>last)+.last>:(<p,1){Processes do. fail 'invalid page range' end.
    list =. I.(p=0{"1 Pages)*.((1{"1 Pages)>:first)*.(1{"1 Pages)<:last
    if. kind=0 do. col =. 4 else. col =. 5 end.
    Pages =: value (<list;col)}Pages
    if. x*.kind=1 do. Events =: Events,<3,pid,first,last,value end.
)
choose =: 3 : 0
    candidates =. I.Frames>:0
    if. 5{Settings do. candidates =. candidates#~y=(candidates{Frames){0{"1 Pages end.
    unlocked =. candidates#~0=(candidates{Frames){5{"1 Pages
    if. #unlocked do. candidates =. unlocked end.
    policy =. 4{Settings
    if. policy=8 do.
        Random =: 2147483647|48271*Random
        (Random|~#candidates){candidates return.
    end.
    if. policy=9 do.
        chosen =. {.candidates
        farthest =. _1
        for_frame. candidates do.
            page =. frame{Frames
            pid =. (<((<page,0){Pages),0){Processes
            tail =. (Cursor+1)}.Future
            matches =. I.(pid=0{"1 tail)*.((<page,1){Pages)=<.(2{"1 tail)%0{Settings
            position =. _
            if. #matches do. position =. Cursor+1+{.matches end.
            if. position>farthest do. farthest =. position [ chosen =. frame end.
        end.
        chosen return.
    end.
    if. policy e.5 6 7 do.
        if. 5{Settings do. h =. (<y,9){Processes else. h =. Hand end.
        order =. candidates /: (1{Settings)|candidates-h
        chosen =. _1
        if. policy=5 do.
            while. chosen<0 do.
                for_frame. order do.
                    page =. frame{Frames
                    if. 0=(<page,6){Pages do.
                        chosen =. frame
                        break.
                    end.
                    Pages =: 0 (<page,6)}Pages
                end.
            end.
        elseif. policy=6 do.
            while. chosen<0 do.
                for_frame. order do.
                    page =. frame{Frames
                    if. 0=+/(<page;6 7){Pages do.
                        chosen =. frame
                        break.
                    end.
                end.
                if. chosen>:0 do. break. end.
                for_frame. order do.
                    page =. frame{Frames
                    if. (0=(<page,6){Pages)*.(<page,7){Pages do.
                        chosen =. frame
                        break.
                    end.
                    Pages =: 0 (<page,6)}Pages
                end.
            end.
        else.
            for_frame. order do.
                page =. frame{Frames
                if. (<page,6){Pages do.
                    Pages =: 0 (<page,6)}Pages
                    Pages =: Time (<page,9)}Pages
                elseif. (Time-(<page,9){Pages)>8{Settings do.
                    if. 0=(<page,7){Pages do.
                        chosen =. frame
                        break.
                    end.
                    writeback page
                end.
            end.
            if. chosen<0 do.
                cleanframes =. order#~0=(order{Frames){7{"1 Pages
                if. #cleanframes do. chosen =. {.cleanframes else. chosen =. {.order end.
            end.
        end.
        h =. (1{Settings)|chosen+1
        if. 5{Settings do. Processes =: h (<y,9)}Processes else. Hand =: h end.
        chosen return.
    end.
    scores =. 0 2$0
    for_frame. candidates do.
        row =. (frame{Frames){Pages
        select. policy
        case. 0 do. score =. (8{row),0
        case. 1 do. score =. (9{row),0
        case. 2 do. score =. 10 8{row
        case. 3 do. score =. ((2*6{row)+7{row),frame
        case. 4 do. score =. 11 8{row
        end.
        scores =. scores,score
    end.
    ({./:scores){candidates
)
access =: 4 : 0
    'pid op address' =. y
    Fixed =: 1
    p =. process pid
    if. address>:(0{Settings)*(<p,1){Processes do.
        Processes =: (1+(<p,6){Processes) (<p,6)}Processes
        say 'SEGFAULT';('P',number pid);hex address
        return.
    end.
    pn =. <.address%0{Settings
    page =. {.I.(p=0{"1 Pages)*.pn=1{"1 Pages
    if. op*.(<page,4){Pages do.
        Processes =: (1+(<p,7){Processes) (<p,7)}Processes
        say 'PROTFAULT';('P',number pid);hex address
        return.
    end.
    Time =: Time+1
    Processes =: (1+(<p,3){Processes) (<p,3)}Processes
    switched =. (Previous>:0)*.Previous~:p
    if. switched do.
        Switches =: Switches+1
        if. 0=6{Settings do. Tlbs =: (3{Settings)$<i.0 end.
    end.
    Previous =: p
    set =. (3{Settings)|pn
    entries =. set{::Tlbs
    fault =. 0
    if. page e.entries do.
        TlbHits =: TlbHits+1
        result =. 'TLBHIT'
        Tlbs =: (<page,entries-.page) set}Tlbs
    else.
        result =. 'HIT'
        if. ((<page,2){Pages)<0 do.
            fault =. 1
            Faults =: Faults+1
            Processes =: (1+(<p,4){Processes) (<p,4)}Processes
            if. ((<page,3){Pages)>:0 do. Swapin =: Swapin+1 [ result =. 'FAULT SWAPIN'
            else. Zero =: Zero+1 [ result =. 'FAULT ZERO' end.
            frame =. _1
            if. (0=5{Settings)+.(resident p)<quota p do.
                free =. I.Frames<0
                if. #free do. frame =. {.free end.
            end.
            if. frame<0 do.
                frame =. choose p
                victim =. frame{Frames
                owner =. (<((<victim,0){Pages),0){Processes
                result =. result,' evict=P',(number owner),':',number (<victim,1){Pages
                if. (<victim,7){Pages do.
                    writeback victim
                    result =. result,' writeback'
                end.
                Pages =: _1 (<victim,2)}Pages
                remove_tlb victim
            end.
            Frames =: page frame}Frames
            Pages =: frame (<page,2)}Pages
            Pages =: Time (<page,8)}Pages
            Pages =: 0 (<page;7 10 11)}Pages
            Processes =: (((<p,8){Processes)>.resident p) (<p,8)}Processes
        end.
        entries =. set{::Tlbs
        capacity =. (2{Settings)%3{Settings
        Tlbs =: (<(capacity<.1+#entries){.page,entries) set}Tlbs
    end.
    Pages =: 1 (<page,6)}Pages
    if. op do. Pages =: 1 (<page,7)}Pages end.
    Pages =: Time (<page,9)}Pages
    Pages =: (1+(<page,10){Pages) (<page,10)}Pages
    Pages =: 1 (<page,12)}Pages
    FaultHistory =: FaultHistory,fault
    References =: References,p,pn
    if. x do. Events =: Events,<0,y end.
    tick =. 0
    if. 7{Settings do. tick =. 0=(7{Settings)|Time end.
    if. tick do.
        for_i. Frames#~Frames>:0 do.
            age =. (<.((<i,11){Pages)%2)+128*(<i,6){Pages
            Pages =: age (<i,11)}Pages
            Pages =: 0 (<i,6)}Pages
        end.
    end.
    if. Trace do.
        frame =. (<page,2){Pages
        physical =. (frame*0{Settings)+(0{Settings)|address
        text =. words ('t=',number Time);('P',number pid);(op{'RW');(hex address);('page=',number pn);('frame=',number frame);('phys=',hex physical);result
        if. switched do. text =. text,' switch' end.
        emit text
        if. tick do. emit 't=',(number Time),' tick' end.
    end.
)
StateNames =: ;:'Settings Processes Pages Frames Tlbs Events FaultHistory References Time Faults Zero Swapin TlbHits Writebacks Switches Hand Fixed Trace Previous Random Future Cursor'
save =: 3 : '".&.>StateNames'
restore =: 3 : 0
    for_i. i.#StateNames do. (i{::StateNames) =: i{::y end.
)
replay =: 3 : 0
    saved =. save ''
    'policy frames' =. y
    registry =. 0 1{"1 Processes
    events =. Events
    Settings =: policy 4}Settings
    Settings =: frames 1}Settings
    reset ''
    References =: 0 2$0
    for_row. registry do. declare row end.
    Future =: 0 3$0
    for_event. events do.
        event =. >event
        if. 0={.event do. Future =: Future,}.event end.
    end.
    Cursor =: 0
    for_event. events do.
        event =. >event
        select. {.event
        case. 0 do.
            0 access }.event
            Cursor =: Cursor+1
        case. 1 do. 0 exit_process 1{event
        case. 2 do. clean 0
        case. 3 do. 0 attributes 1,(}.event)
        end.
    end.
    result =. Faults,Writebacks,TlbHits
    restore saved
    result
)
summary =: 3 : 0
    say 'SUMMARY';('policy=',(4{Settings){::Policies);('scope=',(5{Settings){::'GLOBAL';'LOCAL');'time=',number Time
    say 'total';('faults=',number Faults);('zero=',number Zero);('swapin=',number Swapin);('faultrate=',Faults ratio Time);('tlbhits=',number TlbHits);('tlbrate=',TlbHits ratio Time);('writebacks=',number Writebacks);('switches=',number Switches);('segfaults=',number +/6{"1 Processes);'protfaults=',number +/7{"1 Processes
    for_p. /:0{"1 Processes do.
        row =. p{Processes
        text =. words ('P',number 0{row);('accesses=',number 3{row);('faults=',number 4{row);('writebacks=',number 5{row);('segfaults=',number 6{row);('protfaults=',number 7{row);('resident=',number resident p);'peak=',number 8{row
        if. 5{Settings do. text =. text,' quota=',number quota p end.
        if. 2{row do. text =. text,' exited' end.
        emit text
    end.
)
label =: 3 : 0
    row =. y{Pages
    'P',(number (<(0{row),0){Processes),':',number 1{row
)
handle =: 4 : 0
    select. x
    case. 'PROCESS' do. declare >unsigned&.>y
    case. 'EXIT' do. emit 1 exit_process 0".0{::y
    case. 'PROTECT';'LOCK';'UNLOCK' do.
        values =. >unsigned&.>3{.y
        if. x eq 'PROTECT' do. 1 attributes 0,values,(3{::y)eq'RO'
        else. 1 attributes 1,values,x eq 'LOCK' end.
    case. 'TRACE' do. Trace =: (0{::y)eq'ON'
    case. 'SUMMARY' do. summary ''
    case. 'FRAMES' do.
        say 'FRAMES';'used=',(number +/Frames>:0),'/',number #Frames
        for_f. i.#Frames do.
            page =. f{Frames
            if. page<0 do. say f;'free'
            else.
                row =. page{Pages
                text =. words f;(label page);('R=',number 6{row);('M=',number 7{row);('load=',number 8{row);('last=',number 9{row);('uses=',number 10{row);'age=',number 11{row
                if. 5{row do. text =. text,' locked' end.
                emit text
            end.
        end.
        if. (4{Settings)e.5 6 7 do.
            if. 0=5{Settings do. emit 'hand=',number Hand
            else.
                text =. 'hand'
                for_p. /:0{"1 Processes do. text =. text,' P',(number (<p,0){Processes),'=',number (<p,9){Processes end.
                emit text
            end.
        end.
    case. 'PAGETABLE' do.
        p =. process 0".0{::y
        say 'PAGETABLE';('P',number (<p,0){Processes);('pages=',number (<p,1){Processes);'resident=',number resident p
        for_page. I.(p=0{"1 Pages)*.12{"1 Pages do.
            row =. page{Pages
            if. (2{row)>:0 do. state =. words ('frame=',number 2{row);('R=',number 6{row);'M=',number 7{row
            elseif. (3{row)>:0 do. state =. 'swap=',number 3{row
            else. state =. 'zero' end.
            text =. (number 1{row),' ',state
            if. 4{row do. text =. text,' RO' end.
            if. 5{row do. text =. text,' locked' end.
            emit text
        end.
    case. 'TLB' do.
        say 'TLB';('used=',(number +/>#&.>Tlbs),'/',number 2{Settings);'sets=',number 3{Settings
        for_i. i.#Tlbs do.
            text =. 'set ',(number i),':'
            for_page. i{::Tlbs do. text =. text,' ',(label page),'->',number (<page,2){Pages end.
            emit text
        end.
    case. 'SWAP' do.
        list =. I.0<:3{"1 Pages
        list =. list /:list{3{"1 Pages
        emit 'SWAP used=',number #list
        for_page. list do. say ((<page,3){Pages);label page end.
    case. 'CLEAN' do. emit 'CLEAN written=',number clean 1
    case. 'COMPARE' do.
        say 'COMPARE';('accesses=',number Time);'frames=',number 1{Settings
        results =. 0 3$0
        for_i. i.10 do.
            r =. replay i,1{Settings
            results =. results,r
            say (i{::Policies);('faults=',number 0{r);('writebacks=',number 1{r);'tlbhits=',number 2{r
        end.
        emit 'ranking ',' 'join (/:0 1{"1 results){Policies
    case. 'CURVE' do.
        policy =. Policies i.0{y
        if. policy=10 do. fail 'unknown policy' end.
        'lo hi' =. >unsigned&.>}.y
        if. (lo<1)+.(lo>hi)+.(hi>16)+.((5{Settings)=1)*.lo<#Processes do. fail 'invalid frame range' end.
        say 'CURVE';(policy{::Policies);'frames=',(number lo),'..',number hi
        previous =. _
        for_f. lo+i.1+hi-lo do.
            r =. replay policy,f
            text =. words ('F=',number f);'faults=',number 0{r
            if. (0{r)>previous do. text =. text,' ANOMALY' end.
            emit text
            previous =. 0{r
        end.
    case. 'EAT' do.
        if. Time=0 do. emit 'EAT accesses=0'
        else.
            'a b c' =. >unsigned&.>y
            total =. (a*Time)+(b*(2*Time)-TlbHits)+c*Swapin+Writebacks
            say 'EAT';('accesses=',number Time);('total=',number total);'average=',total decimal Time
        end.
    case. 'TIMELINE' do.
        w =. 0".0{::y
        if. w<1 do. fail 'invalid window' end.
        text =. 'TIMELINE window=',number w
        for_a. w*i.>.Time%w do. text =. text,' ',number +/w{.a}.FaultHistory end.
        emit text
    case. 'WSET';'HOT' do.
        p =. process 0".0{::y
        k =. 0".1{::y
        if. k<1 do.
            if. x eq 'WSET' do. fail 'invalid window' else. fail 'invalid count' end.
        end.
        refs =. 1{"1 References#~p=0{"1 References
        if. x eq 'WSET' do.
            pages =. /:~~.(-(k<.#refs)){.refs
            text =. words 'WSET';('P',number (<p,0){Processes);('window=',number k);'size=',number #pages
            for_page. pages do. text =. text,' ',number page end.
        else.
            pages =. /:~~.refs
            counts =. +/"1 pages=/refs
            order =. (k<.#pages){./:(-counts),.pages
            order =. order#~order<#pages
            text =. 'HOT P',number (<p,0){Processes
            for_i. order do. text =. text,' ',(number i{pages),':',number i{counts end.
        end.
        emit text
    end.
)
main =: 3 : 0
    n =. 0".1!:1 3
    Commands =: 0$a:
    for_i. i.n do.
        fields =. ' 'split 1!:1 3
        cmd =. 0{::fields
        if. ({.cmd)e.'0123456789' do.
            Commands =: Commands,<((0".cmd),('W'e.1{::fields),unhex 2{::fields)
        elseif. cmd eq 'LOOP' do.
            pid =. 0".1{::fields
            op =. 'W'e.2{::fields
            start =. unhex 3{::fields
            'interval length repeats' =. >unsigned&.>4}.fields
            for_repeat. i.repeats do.
                for_j. i.length do. Commands =: Commands,<pid,op,start+j*interval end.
            end.
        elseif. cmd eq 'RAND' do.
            pid =. 0".1{::fields
            lo =. unhex 2{::fields
            hi =. unhex 3{::fields
            'count random rate' =. >unsigned&.>4}.fields
            for_j. i.count do.
                random =. 2147483647|48271*random
                address =. lo+(hi-lo)|random
                random =. 2147483647|48271*random
                Commands =: Commands,<pid,((100|random)<rate),address
            end.
        else. Commands =: Commands,<fields end.
    end.
    Active =: 0
    Output =: 0$a:
    for_i. i.#Commands do.
        command =. i{::Commands
        isaccess =. 32~:3!:0 command
        try.
            if. -.isaccess do.
                if. (0{::command)eq'SYSTEM' do.
                    Active =: 0
                    parse_settings }.command
                    reset ''
                    References =: 0 2$0
                    Future =: 0 3$0
                    for_j. (i+1)+i.(#Commands)-i+1 do.
                        if. j>:#Commands do. break. end.
                        next =. j{::Commands
                        if. 32=3!:0 next do.
                            if. (0{::next)eq'SYSTEM' do. break. end.
                        else. Future =: Future,next end.
                    end.
                    Cursor =: 0
                    Active =: 1
                    emit 'SYSTEM ',parameter_text ''
                    continue.
                end.
            end.
            if. -.Active do. emit 'ERROR no system'
            elseif. isaccess do.
                try. 1 access command
                catcht. emit 'ERROR ',Error end.
                Cursor =: Cursor+1
            else. (0{::command)handle }.command end.
        catcht. emit 'ERROR ',Error end.
    end.
    for_line. Output do. ((>line),LF)1!:2 4 end.
    i.0
)
main ''
