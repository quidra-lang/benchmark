LF =: 10{a.
number =: 3 : ',''0'' 8!:2 y'
eq =: 4 : '(,x)-:,y'
unsigned =: 3 : '0".y'
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
Modes =: ;:'FIRST NEXT BEST WORST SEGFIT BUDDY'
Active =: S =: Mode =: Age =: Rover =: Peak =: 0
Blocks =: 0 4$0
Ids =: Contents =: Histories =: 0$a:
States =: Requested =: Roots =: i.0
Edges =: 0 2$0
Counts =: 6#0
sort_blocks =: 3 : 'Blocks =: Blocks /:0{"1 Blocks'
remove =: 3 : 'Blocks =: ((i.#Blocks)-.y){Blocks'
freeblock =: 3 : 0
    Age =: Age+1
    y,_1,Age
)
initialize =: 3 : 0
    'S Mode' =: y
    Age =: Rover =: Peak =: 0
    Blocks =: ,:freeblock 0,S
    Ids =: Contents =: Histories =: 0$a:
    States =: Requested =: Roots =: i.0
    Edges =: 0 2$0
    Counts =: 6#0
    Active =: 1
)
required =: 3 : 0
    s =. 8+8*>.y%8
    if. Mode=5 do. s =. 32>.2^>.2^.s end.
    s
)
locate =: 3 : '(0{"1 Blocks)i.y'
ownerblock =: 3 : '(2{"1 Blocks)i.y'
ensure =: 3 : 0
    i =. Ids i.<,y
    if. i=#Ids do.
        Ids =: Ids,<,y
        States =: States,0
        Requested =: Requested,0
        Roots =: Roots,0
        Contents =: Contents,<i.0
        Histories =: Histories,<0$a:
    end.
    i
)
state =: 3 : 0
    i =. Ids i.<,y
    if. i=#Ids do. fail 'UNKNOWN ID ',y end.
    if. (i{States)=2 do. fail 'USE AFTER FREE ',y end.
    if. (i{States)=0 do. fail 'UNKNOWN ID ',y end.
    i
)
history =: 4 : 0
    emit y
    Histories =: (<(x{::Histories),<y) x}Histories
)
used =: 3 : '+/(1{"1 Blocks)#~_1~:2{"1 Blocks'
fragmentation =: 3 : 0
    sizes =. (1{"1 Blocks)#~_1=2{"1 Blocks
    f =. +/sizes
    if. f=0 do. 0 else. <.(100*f->./0,sizes)%f end.
)
NB. Allocation returns an index after restoring address order, or _1.
allocate =: 3 : 0
    's al' =. y
    eligible =. positions =. i.0
    for_i. I._1=2{"1 Blocks do.
        'f z owner age' =. i{Blocks
        q =. (al*>.(f+8)%al)-8
        p =. q
        if. (q>f)*.(q-f)<16 do. p =. q+al end.
        if. (p+s)<:f+z do.
            eligible =. eligible,i
            positions =. positions,p
        end.
    end.
    if. 0=#eligible do. _1 return. end.
    scores =. 0 2$0
    start =. {.I.Rover<(0{"1 Blocks)+1{"1 Blocks
    for_i. eligible do.
        'f z owner age' =. i{Blocks
        select. Mode
        case. 0 do. score =. f,0
        case. 1 do. score =. ((#Blocks)|i-start),0
        case. 2;5 do. score =. z,f
        case. 3 do. score =. (-z),f
        case. 4 do. score =. (<.2^.z),-age
        end.
        scores =. scores,score
    end.
    chosen =. {./:scores
    index =. chosen{eligible
    p =. chosen{positions
    'f z owner age' =. index{Blocks
    remove index
    if. Mode=5 do.
        while. z>s do.
            z =. -:z
            Blocks =: Blocks,freeblock (f+z),z
        end.
        p =. f
        b =. s
    else.
        if. p>f do. Blocks =: Blocks,freeblock f,p-f end.
        b =. f+z-p
        if. (b-s)>:16 do.
            Blocks =: Blocks,freeblock (p+s),b-s
            b =. s
        end.
    end.
    Blocks =: Blocks,p,b,_2,0
    sort_blocks ''
    if. Mode=1 do. Rover =: S|p+b end.
    locate p
)
NB. Free/coalesce does not alter ID metadata, so realloc can retain references.
freeproc =: 3 : 0
    'a b owner age' =. y{Blocks
    remove y
    merges =. 0
    if. Mode=5 do.
        while. b<S do.
            if. 0=(2*b)|a do. buddy =. a+b else. buddy =. a-b end.
            list =. I.(buddy=0{"1 Blocks)*.(b=1{"1 Blocks)*._1=2{"1 Blocks
            if. 0=#list do. break. end.
            remove {.list
            a =. a<.buddy
            b =. 2*b
            merges =. merges+1
        end.
    else.
        list =. I.((a+b)=0{"1 Blocks)*._1=2{"1 Blocks
        if. #list do.
            index =. {.list
            b =. b+(<index,1){Blocks
            remove index
            merges =. merges+1
        end.
        list =. I.(a=(0{"1 Blocks)+1{"1 Blocks)*._1=2{"1 Blocks
        if. #list do.
            index =. {.list
            a =. (<index,0){Blocks
            b =. b+(<index,1){Blocks
            remove index
            merges =. merges+1
        end.
    end.
    Blocks =: Blocks,freeblock a,b
    sort_blocks ''
    merges,a,b
)
retire =: 3 : 0
    States =: 2 y}States
    Roots =: 0 y}Roots
    Edges =: Edges#~*./"1 y~:Edges
    Contents =: (<i.0) y}Contents
)
release =: 4 : 0
    i =. Ids i.<,y
    if. i<#Ids do.
        if. (i{States)=2 do. fail 'DOUBLE FREE ',y end.
    end.
    if. i=#Ids do. fail 'UNKNOWN ID ',y end.
    if. (i{States)=0 do. fail 'UNKNOWN ID ',y end.
    index =. ownerblock i
    b =. (<index,1){Blocks
    'merges a z' =. freeproc index
    retire i
    if. x eq 'FREE' do. Counts =: (1+1{Counts) 1}Counts
    else. Counts =: (1+5{Counts) 5}Counts end.
    i history words x;y;('block=',number b);('merges=',number merges);'free=',(number a),'+',number z
)
malloc =: 4 : 0
    'id n al zero' =. y
    id =. >id
    n =. >n
    al =. >al
    zero =. >zero
    if. n=0 do. fail 'BAD SIZE' end.
    i =. ensure id
    if. (i{States)=1 do. fail 'DUPLICATE ID ',id end.
    index =. allocate (required n),al
    if. index<0 do.
        Counts =: (1+4{Counts) 4}Counts
        fail 'OUT OF MEMORY ',id
    end.
    Blocks =: i (<index,2)}Blocks
    States =: 1 i}States
    Requested =: n i}Requested
    if. zero do. bytes =. n#0 else. bytes =. n#_1 end.
    Contents =: (<bytes) i}Contents
    Counts =: (1+0{Counts) 0}Counts
    i history words x;id;('addr=',number 8+(<index,0){Blocks);'block=',number (<index,1){Blocks
)
realloc =: 3 : 0
    'id n' =. y
    id =. >id
    n =. >n
    if. n=0 do. 'FREE'release id return. end.
    i =. Ids i.<id
    if. i=#Ids do. 'MALLOC'malloc id;n;8;0 return. end.
    if. (i{States)=0 do. 'MALLOC'malloc id;n;8;0 return. end.
    i =. state id
    index =. ownerblock i
    'a b owner age' =. index{Blocks
    s =. required n
    kind =. 'kept'
    if. s<:b do.
        if. Mode=5 do.
            if. s<b do.
                kind =. 'shrunk'
                z =. b
                while. z>s do.
                    z =. -:z
                    Blocks =: Blocks,freeblock (a+z),z
                end.
                Blocks =: s (<index,1)}Blocks
                sort_blocks ''
            end.
        elseif. (b-s)>:16 do.
            kind =. 'shrunk'
            Blocks =: s (<index,1)}Blocks
            Blocks =: Blocks,(a+s),(b-s),_2,0
            freeproc (#Blocks)-1
        end.
    else.
        grow =. 0
        absorb =. i.0
        if. Mode=5 do.
            t =. b
            grow =. 1
            while. t<s do.
                list =. I.((a+t)=0{"1 Blocks)*.(t=1{"1 Blocks)*._1=2{"1 Blocks
                if. ((2*t)|a)+.0=#list do.
                    grow =. 0
                    break.
                end.
                absorb =. absorb,{.list
                t =. 2*t
            end.
            newsize =. s
        else.
            list =. I.((a+b)=0{"1 Blocks)*._1=2{"1 Blocks
            if. #list do.
                next =. {.list
                combined =. b+(<next,1){Blocks
                if. combined>:s do.
                    grow =. 1
                    absorb =. next
                    newsize =. combined
                    if. (combined-s)>:16 do. newsize =. s end.
                end.
            end.
        end.
        if. grow do.
            kind =. 'grown'
            remove absorb
            index =. ownerblock i
            Blocks =: newsize (<index,1)}Blocks
            if. Mode~:5 do.
                if. newsize<combined do. Blocks =: Blocks,freeblock (a+s),combined-s end.
            end.
            sort_blocks ''
        else.
            index =. allocate s,8
            if. index<0 do.
                Counts =: (1+4{Counts) 4}Counts
                fail 'OUT OF MEMORY ',id
            end.
            Blocks =: i (<index,2)}Blocks
            old =. locate a
            freeproc old
            kind =. 'moved'
            Counts =: (1+3{Counts) 3}Counts
        end.
    end.
    oldbytes =. i{::Contents
    keep =. n<.#oldbytes
    Contents =: (<(keep{.oldbytes),(n-keep)#_1) i}Contents
    Requested =: n i}Requested
    Counts =: (1+2{Counts) 2}Counts
    index =. ownerblock i
    text =. words 'REALLOC';id;('addr=',number 8+(<index,0){Blocks);('block=',number (<index,1){Blocks);kind
    if. kind eq 'moved' do. text =. text,' from=',number a+8 end.
    i history text
)
reachable =: 3 : 0
    seen =. I.Roots
    todo =. seen
    while. #todo do.
        id =. {.todo
        todo =. }.todo
        destinations =. 1{"1 Edges#~id=0{"1 Edges
        fresh =. destinations-.seen
        seen =. seen,fresh
        todo =. todo,fresh
    end.
    seen
)
rangecheck =: 4 : 0
    'off len' =. y
    i =. state x
    if. (off+len)>i{Requested do. fail 'OUT OF BOUNDS ',x end.
    i
)
tree =: 3 : 0
    'a size depth' =. y
    list =. I.(a=0{"1 Blocks)*.size=1{"1 Blocks
    text =. ((2*depth)#' '),(number a),'+',number size
    if. #list do.
        owner =. (<({.list),2){Blocks
        if. owner=_1 do. emit text,' FREE' else. emit text,' USED ',owner{::Ids end.
    else.
        emit text,' split'
        tree a,(-:size),depth+1
        tree (a+-:size),(-:size),depth+1
    end.
)
SavedNames =: ;:'Active S Mode Age Rover Peak Blocks Ids States Requested Roots Contents Histories Edges Counts'
save =: 3 : '".&.>SavedNames'
restore =: 3 : 0
    for_i. i.#SavedNames do. (i{::SavedNames) =: i{::y end.
)
bench =: 3 : 0
    'size seed ops maxreq' =. y
    if. -.size e.2^5+i.12 do. fail 'BAD HEAP SIZE' end.
    saved =. save ''
    say 'BENCH';('heap=',number size);('seed=',number seed);('ops=',number ops);'maxreq=',number maxreq
    for_mode. i.6 do.
        initialize size,mode
        random =. seed
        live =. i.0
        ok =. failures =. peak =. 0
        for_step. i.ops do.
            random =. 2147483647|48271*random
            alloc =. (0=#live)+.0~:3|random
            random =. 2147483647|48271*random
            if. alloc do.
                n =. 1+maxreq|random
                index =. allocate (required n),8
                if. index<0 do. failures =. failures+1
                else. ok =. ok+1 [ live =. live,(<index,0){Blocks end.
            else.
                pos =. (#live)|random
                freeproc locate pos{live
                live =. ((i.#live)-.pos){live
            end.
            peak =. peak>.used ''
        end.
        say 'BENCH';(mode{::Modes);('ok=',number ok);('fail=',number failures);('peak=',number peak);('used=',number used '');('frag=',number fragmentation '');'blocks=',number #Blocks
    end.
    restore saved
)
handle =: 4 : 0
    if. x eq 'HEAP' do.
        size =. 0".0{::y
        mode =. Modes i.1{y
        good =. (size>:32)*.(size<:65536)*.0=8|size
        if. mode=5 do. good =. good*.size e.2^5+i.12 end.
        if. -.good do. fail 'BAD HEAP SIZE' end.
        initialize size,mode
        say 'HEAP';('size=',number S);'mode=',Mode{::Modes
        return.
    end.
    if. x eq 'BENCH' do. bench >unsigned&.>y return. end.
    if. -.Active do. fail 'NO HEAP' end.
    select. x
    case. 'MALLOC';'CALLOC';'MEMALIGN' do.
        id =. 0{::y
        al =. 8
        zero =. 0
        if. x eq 'MEMALIGN' do.
            if. Mode=5 do. fail 'UNSUPPORTED IN BUDDY MODE' end.
            al =. 0".1{::y
            if. -.al e.2^3+i.10 do. fail 'BAD ALIGNMENT' end.
            n =. 0".2{::y
        elseif. x eq 'CALLOC' do. n =. */>unsigned&.>}.y [ zero =. 1
        else. n =. 0".1{::y end.
        x malloc id;n;al;zero
    case. 'FREE' do. 'FREE'release 0{::y
    case. 'REALLOC' do. realloc (0{y),<0".1{::y
    case. 'FILL';'READ' do.
        id =. 0{::y
        'off len' =. >unsigned&.>1 2{y
        i =. id rangecheck off,len
        bytes =. i{::Contents
        if. x eq 'FILL' do.
            value =. 0".3{::y
            bytes =. value (off+i.len)}bytes
            Contents =: (<bytes) i}Contents
            say x;id;((number off),'+',number len);'=';value
        else.
            text =. 0$a:
            for_byte. len{.off}.bytes do.
                if. byte<0 do. text =. text,<'?' else. text =. text,<number byte end.
            end.
            say x;id;((number off),'+',number len);'=';' 'join text
        end.
    case. 'COPY' do.
        dst =. 0{::y
        doff =. 0".1{::y
        src =. 2{::y
        soff =. 0".3{::y
        len =. 0".4{::y
        d =. dst rangecheck doff,len
        s =. src rangecheck soff,len
        contents =. d{::Contents
        values =. len{.soff}.s{::Contents
        contents =. values (doff+i.len)}contents
        Contents =: (<contents) d}Contents
        say x;dst;((number doff),'+',number len);'from';src;soff
    case. 'ROOT';'UNROOT' do.
        id =. 0{::y
        i =. state id
        if. x eq 'ROOT' do. Roots =: 1 i}Roots
        else.
            if. -.i{Roots do. fail 'NOT ROOT ',id end.
            Roots =: 0 i}Roots
        end.
        say x;id
    case. 'LINK';'UNLINK' do.
        src =. 0{::y
        dst =. 1{::y
        a =. state src
        b =. state dst
        list =. I.(a=0{"1 Edges)*.b=1{"1 Edges
        if. x eq 'LINK' do.
            if. 0=#list do. Edges =: Edges,a,b end.
        else.
            if. 0=#list do. fail 'NO LINK ',src,' ',dst end.
            Edges =: ((i.#Edges)-.list){Edges
        end.
        say x;src;dst
    case. 'GC' do.
        live =. reachable ''
        list =. I.(_1~:2{"1 Blocks)*.-.(2{"1 Blocks)e.live
        ids =. list{2{"1 Blocks
        bytes =. +/list{1{"1 Blocks
        say 'GC';('collected=',number #ids);'bytes=',number bytes
        for_i. ids do. 'COLLECT'release i{::Ids end.
    case. 'SBRK' do.
        k =. 0".0{::y
        good =. (k>:16)*.(0=8|k)*.(S+k)<:65536
        if. Mode=5 do. good =. (k=S)*.(2*S)<:65536 end.
        if. -.good do. fail 'BAD SBRK SIZE' end.
        Blocks =: Blocks,S,k,_2,0
        S =: S+k
        'merges a z' =. freeproc (#Blocks)-1
        say 'SBRK';('heap=',number S);'free=',(number a),'+',number z
    case. 'TRIM' do.
        original =. S
        if. Mode=5 do.
            while. #Blocks do.
                last =. _1{Blocks
                if. ((2{last)~:_1)+.(1{last)~:-:S do. break. end.
                S =: -:S
                Blocks =: }:Blocks
            end.
        elseif. (#Blocks)>1 do.
            if. _1=(<_1,2){Blocks do.
                S =: (<_1,0){Blocks
                Blocks =: }:Blocks
            end.
        end.
        if. Rover>:S do. Rover =: 0 end.
        say 'TRIM';('heap=',number S);'released=',number original-S
    case. 'COMPACT' do.
        if. Mode=5 do. fail 'UNSUPPORTED IN BUDDY MODE' end.
        blocks =. Blocks#~_1~:2{"1 Blocks
        moves =. 0$a:
        owners =. i.0
        next =. 0
        for_i. i.#blocks do.
            'a b owner age' =. i{blocks
            if. a~:next do.
                moves =. moves,<words 'MOVE';(owner{::Ids);(a+8);'->';next+8
                owners =. owners,owner
            end.
            blocks =. next (<i,0)}blocks
            next =. next+b
        end.
        Blocks =: blocks
        free =. 'none'
        if. next<S do.
            Blocks =: Blocks,freeblock next,S-next
            free =. (number next),'+',number S-next
        end.
        Rover =: 0
        Counts =: ((3{Counts)+#moves) 3}Counts
        say 'COMPACT';('moved=',number #moves);'free=',free
        for_i. i.#moves do. (i{owners)history i{::moves end.
    case. 'WHO' do.
        p =. 0".0{::y
        if. p>:S do. say 'WHO';p;'outside'
        else.
            index =. {.I.p<(0{"1 Blocks)+1{"1 Blocks
            'a b owner age' =. index{Blocks
            if. owner=_1 do. say 'WHO';p;'free';(number a),'+',number b
            elseif. p<a+8 do. say 'WHO';p;'header';owner{::Ids
            else.
                d =. p-a+8
                if. d<owner{Requested do. kind =. 'data' else. kind =. 'slack' end.
                say 'WHO';p;kind;(owner{::Ids),'+',number d
            end.
        end.
    case. 'DUMP' do.
        text =. words 'DUMP';('mode=',Mode{::Modes);('heap=',number S);'blocks=',number #Blocks
        if. Mode=1 do. text =. text,' rover=',number Rover end.
        emit text
        for_row. Blocks do.
            'a b owner age' =. row
            if. owner=_1 do. say a;b;'FREE'
            else. say a;b;'USED';(owner{::Ids);'req=',number owner{Requested end.
        end.
    case. 'MAP' do.
        emit 'MAP heap=',number S
        chars =. ''
        for_row. Blocks do.
            'a b owner age' =. row
            count =. <.b%8
            if. owner=_1 do. chars =. chars,'F',(count-1)#'.'
            else. chars =. chars,'H',((8*i.count-1)<owner{Requested){'-#' end.
        end.
        for_a. 64*i.>.(#chars)%64 do.
            emit (_5{.'00000',number 8*a),' ',(64<.(#chars)-a){.a}.chars
        end.
    case. 'FREELIST' do.
        list =. I._1=2{"1 Blocks
        emit 'FREELIST count=',number #list
        for_k. /:~~.<.2^.list{1{"1 Blocks do.
            members =. list#~k=<.2^.list{1{"1 Blocks
            if. Mode=4 do. members =. members \:members{3{"1 Blocks end.
            parts =. 0$a:
            for_i. members do. parts =. parts,<(number (<i,0){Blocks),'+',number (<i,1){Blocks end.
            emit (number 2^k),'-',(number <:2^k+1),': ',' 'join parts
        end.
    case. 'TREE' do.
        if. Mode~:5 do. fail 'REQUIRES BUDDY MODE' end.
        emit 'TREE heap=',number S
        tree 0,S,0
    case. 'STATS' do.
        u =. used ''
        list =. I._1=2{"1 Blocks
        f =. +/list{1{"1 Blocks
        largest =. >./0,list{1{"1 Blocks
        ids =. I.States=1
        say 'STATS';('used=',number u);('used_blocks=',number #ids);('free=',number f);('free_blocks=',number #list);('largest=',number largest);('frag=',number fragmentation '');('requested=',number +/ids{Requested);'peak=',number Peak
        say 'OPS';('allocs=',number 0{Counts);('frees=',number 1{Counts);('reallocs=',number 2{Counts);('moves=',number 3{Counts);('failures=',number 4{Counts);'collected=',number 5{Counts
    case. 'LEAKS' do.
        ids =. I.States=1
        reachableids =. reachable ''
        say 'LEAKS';('count=',number #ids);('requested=',number +/ids{Requested);'lost=',number #ids-.reachableids
        for_i. ids /:s:ids{Ids do.
            index =. ownerblock i
            status =. (i e.reachableids){::'lost';'reachable'
            say 'LEAK';(i{::Ids);('addr=',number 8+(<index,0){Blocks);('block=',number (<index,1){Blocks);('req=',number i{Requested);status
        end.
    case. 'HISTORY' do.
        id =. 0{::y
        i =. Ids i.<id
        historylines =. 0$a:
        if. i<#Ids do. historylines =. i{::Histories end.
        say 'HISTORY';id;'events=',number #historylines
        for_line. historylines do. emit >line end.
    end.
)
main =: 3 : 0
    n =. 0".1!:1 3
    Output =: 0$a:
    for_i. i.n do.
        fields =. ' 'split 1!:1 3
        try. (0{::fields)handle }.fields
        catcht. emit 'ERROR ',Error end.
        if. Active do. Peak =: Peak>.used '' end.
    end.
    for_line. Output do. ((>line),LF)1!:2 4 end.
    i.0
)
main ''
