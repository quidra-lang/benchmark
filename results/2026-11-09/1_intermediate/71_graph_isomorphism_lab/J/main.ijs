LF =: 10{a.
Output =: 0$a:
num =: 3 : ',''0'' 8!:2 y'
emit =: 3 : 'Output=:Output,<y'
join =: 4 : '(#x)}.;(<x),&.>y'
numbers =: 3 : ''' ''join num&.>y'
yesno =: 3 : 'if. y do. ''yes'' else. ''no'' end.'
fail =: 3 : 0
    Reason=:y
    throw.
)
check =: 4 : 'if. -.y do. fail x end.'
split =: 4 : 0
    result=.0$a:
    start=.0
    for_i. i.#y do.
        if. x=i{y do. result=.result,<(i-start){.start}.y
            start=.i+1 end.
    end.
    result,<start}.y
)
emptyGraph =: 3 : '(y,y)$0'
connect =: 4 : 0
    'u v'=.y
    x=.1 (<u,v)}x
    1 (<v,u)}x
)
edges =: 3 : 0
    result=.0$a:
    for_u. i.#y do.
        for_v. (u+1)+i.(#y)-u+1 do.
            if. (<u,v){y do. result=.result,<u,v end.
        end.
    end.
    result
)
degrees =: +/"1
distances =: 4 : 0
    d=.(#x)$_1
    d=.0 y}d
    queue=.,y
    at=.0
    while. at<#queue do.
        u=.at{queue
        at=.at+1
        for_v. i.#x do.
            if. ((<u,v){x)*.0>v{d do. d=.(1+u{d)v}d
                queue=.queue,v end.
        end.
    end.
    d
)
graphInfo =: 3 : 0
    n=.#y
    es=.edges y
    seen=.n$0
    sizes=.i.0
    ecc=.i.0
    shortest=.0
    bip=.1
    for_root. i.n do.
        d=.y distances root
        ecc=.ecc,>./d
        if. -.root{seen do. component=.I.d>:0
            sizes=.sizes,#component
            seen=.1 component}seen end.
        for_e. es do.
            'u v'=.>e
            if. ((u{d)>:0)*.((v{d)>:0)*.0=2|(u{d)-v{d do. bip=.0 end.
        end.
        depth=.n$_1
        parent=.n$_1
        depth=.0 root}depth
        queue=.,root
        at=.0
        while. at<#queue do.
            u=.at{queue
            at=.at+1
            for_v. i.n do.
                if. -. (<u,v){y do. continue. end.
                if. 0>v{depth do. depth=.(1+u{depth)v}depth
                    parent=.u v}parent
                    queue=.queue,v
                elseif. v~:u{parent do.
                    length=.1+(u{depth)+v{depth
                    if. (shortest=0)+.length<shortest do. shortest=.length end.
                end.
            end.
        end.
    end.
    triangles=.0
    for_e. es do.
        'u v'=.>e
        for_w. (v+1)+i.n-v+1 do. triangles=.triangles+((<u,w){y)*.(<v,w){y end.
    end.
    girth=.num shortest
    if. shortest=0 do. girth=.'none' end.
    diameter=.'INF'
    radius=.'INF'
    if. 1=#sizes do. diameter=.num >./ecc
        radius=.num <./ecc end.
    (<n),(<#es),(<\:~degrees y),(<triangles),(<\:~sizes),(<girth),(<diameter),(<radius),<yesno bip
)
lexLess =: 4 : 0
    for_i. i.(#x)<.#y do.
        if. (i{x)~:i{y do. (i{x)<i{y return. end.
    end.
    (#x)<#y
)
rankKeys =: 3 : 0
    unique=.~.y
    result=.i.0
    for_key. y do.
        count=.0
        for_other. unique do. count=.count+(>other)lexLess >key end.
        result=.result,count
    end.
    result
)
degreeColors =: 3 : 'rankKeys <"0 degrees y'
refine =: 4 : 0
    colors=.y
    rounds=.0
    while. 1 do.
        signatures=.0$a:
        for_v. i.#x do. signatures=.signatures,<(v{colors),/:~colors#~v{x end.
        next=.rankKeys signatures
        if. (#~.next)=#~.colors do. (<colors),<rounds return. end.
        colors=.next
        rounds=.rounds+1
    end.
)
stable =: 3 : 'y refine degreeColors y'
cells =: 3 : 0
    result=.0$a:
    for_color. i.1+>./y do. result=.result,<I.y=color end.
    result
)
individualize =: 4 : 'x+((x>:y{x)*.(i.#x)~:y)'
leafString =: 4 : 0
    inverse=./:y
    result=.''
    for_u. i.#x do.
        for_v. (u+1)+i.(#x)-u+1 do. result=.result,((< (u{inverse),v{inverse){x){'01' end.
    end.
    result
)
canonVisit =: 4 : 0
    if. (#~.y)=#x do.
        text=.x leafString y
        ( <1),(<1),(<text),(<y),<,<y return.
    end.
    chosen=.i.0
    for_cell. cells y do.
        cell=.>cell
        if. (#cell)>1 do.
            if. (0=#chosen)+.(#cell)<#chosen do. chosen=.cell end.
        end.
    end.
    nodes=.1
    leaves=.0
    text=.''
    labels=.i.0
    best=.0$a:
    for_v. chosen do.
        next=.0{::x refine y individualize v
        child=.x canonVisit next
        nodes=.nodes+0{::child
        leaves=.leaves+1{::child
        candidate=.2{::child
        if. (0=#best)+.(a.i.text)lexLess a.i.candidate do.
            text=.candidate
            labels=.3{::child
            best=.4{::child
        elseif. text-:candidate do. best=.best,4{::child end.
    end.
    (<nodes),(<leaves),(<text),(<labels),<best
)
canonical =: 3 : 'y canonVisit 0{::stable y'
cliqueVisit =: 4 : 0
    'chosen candidates'=.y
    best=.chosen
    for_v. candidates do.
        next=.candidates#~(candidates>v)*.candidates{v{x
        child=.x cliqueVisit (<chosen,v),<next
        if. (#child)>#best do. best=.child end.
    end.
    best
)
colorVisit =: 4 : 0
    'limit colors used'=.y
    v=.#colors
    if. v=#x do. <colors return. end.
    for_color. i.limit<.used+1 do.
        if. +./((#colors){.v{x)*.colors=color do. continue. end.
        answer=.x colorVisit (<limit),(<colors,color),<used>.color+1
        if. -.answer-:a: do. answer return. end.
    end.
    a:
)
invariantReport =: 4 : 0
    info=.graphInfo x
    emit 'invariants ',y
    emit 'degrees ',numbers 2{::info
    emit 'edges ',(num 1{::info),' triangles ',num 3{::info
    emit 'components ',(num #4{::info),' sizes ',numbers 4{::info
    emit 'girth ',(5{::info),' diameter ',(6{::info),' radius ',7{::info
    emit 'bipartite ',8{::info
    if. (#x)>:13 do. emit 'clique -'
        emit 'chromatic -' return. end.
    clique=.x cliqueVisit (<i.0),<i.#x
    emit 'clique ',(num #clique),' ',numbers clique
    for_limit. (#clique)+i.1+(#x)-#clique do.
        colors=.x colorVisit (<limit),(<i.0),<0
        if. -.colors-:a: do. emit 'chromatic ',(num limit),' ',numbers >colors return. end.
    end.
)
isoReport =: 4 : 0
    a=.graphInfo x
    b=.graphInfo y
    names=.;:'vertices edges degrees triangles components girth diameter radius bipartite'
    for_i. 0 1 2 3 4 5 6 8 do.
        left=.i{::a
        right=.i{::b
        if. i=4 do. left=.#left
            right=.#right end.
        if. -.left-:right do.
            text=.'not isomorphic ',i{::names
            if. i~:2 do.
                if. i<5 do. text=.text,' ',(num left),' ',num right
                else. text=.text,' ',left,' ',right end.
            end.
            emit text return.
        end.
    end.
    ar=.stable x
    br=.stable y
    if. (-.(1{::ar)-:1{::br)+.-.(#&>cells 0{::ar)-:#&>cells 0{::br do. emit 'not isomorphic refinement' return. end.
    ac=.canonical x
    bc=.canonical y
    if. -. (2{::ac)-:2{::bc do. emit 'not isomorphic canonical' return. end.
    inverse=./:3{::bc
    emit 'isomorphic'
    emit 'mapping ',numbers (3{::ac){inverse
)
automorphisms =: 3 : 0
    form=.canonical y
    inverse=./:3{::form
    result=.0$a:
    for_leaf. 4{::form do. result=.result,<(>leaf){inverse end.
    result
)
autReport =: 4 : 0
    permutations=.automorphisms x
    seen=.(#x)$0
    vorbits=.0$a:
    for_v. i.#x do.
        if. v{seen do. continue. end.
        orbit=./:~~.v&{&>permutations
        seen=.1 orbit}seen
        vorbits=.vorbits,<orbit
    end.
    es=.edges x
    seen=.(#es)$0
    eorbits=.0$a:
    for_i. i.#es do.
        if. i{seen do. continue. end.
        orbit=.0$a:
        for_p. permutations do. orbit=.orbit,</:~(i{::es){>p end.
        indices=.I.es e.orbit
        seen=.1 indices}seen
        eorbits=.eorbits,<indices{es
    end.
    emit 'aut ',y,' order ',num #permutations
    emit 'vertex orbits ',num #vorbits
    for_orbit. vorbits do. emit 'orbit ',numbers >orbit end.
    emit 'edge orbits ',num #eorbits
    for_orbit. eorbits do.
        words=.0$a:
        for_e. >orbit do. 'u v'=.>e
            words=.words,<(num u),'-',num v end.
        emit 'orbit ',' 'join words
    end.
    emit 'transitive vertex ',(yesno 1=#vorbits),' edge ',yesno 1=#eorbits
)
embeddingVisit =: 3 : 0
    'pattern target image'=.y
    v=.#image
    if. v=#pattern do.
        exact=.1
        for_u. i.#pattern do.
            for_w. (u+1)+i.(#pattern)-u+1 do.
                if. ((<u,w){pattern)~:(< (u{image),w{image){target do. exact=.0 end.
            end.
        end.
        record=.(<image),<exact
        shown=.,<record
        (<1),(<exact),<shown return.
    end.
    total=.0
    induced=.0
    shown=.0$a:
    for_w. i.#target do.
        if. w e.image do. continue. end.
        allowed=.1
        for_u. i.v do.
            if. ((<v,u){pattern)*.-.(<w,u{image){target do. allowed=.0 break. end.
        end.
        if. allowed do.
            child=.embeddingVisit (<pattern),(<target),<image,w
            total=.total+0{::child
            induced=.induced+1{::child
            combined=.shown,2{::child
            shown=.(5<.#combined){.combined
        end.
    end.
    (<total),(<induced),<shown
)
subisoReport =: 3 : 0
    'pattern target first second'=.y
    result=.embeddingVisit (<pattern),(<target),<i.0
    order=.#4{::canonical pattern
    emit 'subiso ',first,' ',second,' embeddings ',(num 0{::result),' induced ',num 1{::result
    emit 'copies ',(num order%~0{::result),' induced ',num order%~1{::result
    for_record. 2{::result do.
        'image exact'=.>record
        text=.'embedding ',numbers image
        if. exact do. text=.text,' induced' end.
        emit text
    end.
)
sizeCheck =: 3 : 0
    'n minimum maximum'=.y
    'bad value'check n>:minimum
    'too large'check n<:maximum
)
classify =: 3 : 0
    sizeCheck y,1 5
    pairs=.0$a:
    for_u. i.y do. for_v. (u+1)+i.y-u+1 do. pairs=.pairs,<u,v end. end.
    layers=.,<,<2{::canonical emptyGraph y
    for_m. i.#pairs do.
        next=.0$a:
        for_text. >{:layers do.
            text=.>text
            g=.emptyGraph y
            for_i. i.#pairs do. if. '1'=i{text do. g=.g connect i{::pairs end. end.
            for_i. i.#pairs do.
                if. '0'=i{text do. next=.next,<2{::canonical g connect i{::pairs end.
            end.
        end.
        layers=.layers,</:~~.next
    end.
    emit 'classify ',(num y),' total ',num +/#&>layers
    for_m. i.#layers do.
        strings=.m{::layers
        if. y=1 do. strings=.,<'-' end.
        emit 'edges ',(num m),' count ',(num #strings),' ',' 'join strings
    end.
)
validName =: 3 : 0
    if. ((#y)<1)+.(#y)>8 do. 0 return. end.
    (({.y)e.'abcdefghijklmnopqrstuvwxyz')*.*./y e.'abcdefghijklmnopqrstuvwxyz0123456789'
)
numberWord =: 3 : 0
    if. ((#y)<1)+.(#y)>3 do. 0 return. end.
    if. ((#y)>1)*.'0'={.y do. 0 return. end.
    *./y e.'0123456789'
)
edgeWord =: 3 : 0
    parts=.'-'split y
    if. 2~:#parts do. 0 return. end.
    *./numberWord&>parts
)
schema =: 3 : 0
    select. y
    case. 'GRAPH' do. ;:'name number edge*'
    case. 'CYCLE';'PATH';'COMPLETE';'STAR';'WHEEL';'HYPERCUBE' do. ;:'name number'
    case. 'BIPARTITE';'GRID' do. ;:'name number number'
    case. 'PETERSEN' do. ,<'name'
    case. 'CIRCULANT' do. ;:'name number number+'
    case. 'COMPLEMENT';'LINE';'CANONIZE' do. ;:'name graph'
    case. 'PRODUCT';'UNION' do. ;:'name graph graph'
    case. 'RELABEL' do. ;:'name graph number*'
    case. 'INDUCED' do. ;:'name graph number+'
    case. 'DELETE';'SHOW';'INVARIANTS';'CANON';'AUT' do. ,<'graph'
    case. 'REFINE' do. ;:'graph number*'
    case. 'ISO';'SUBISO' do. ;:'graph graph'
    case. 'CLASSIFY' do. ,<'number'
    case. do. 0$a:
    end.
)
getGraph =: 3 : '(Names i.<y){::Graphs'
arguments =: 4 : 0
    format=.schema x
    if. (0=#format)*.-.x-:'LIST' do. fail 'unknown command ',x end.
    repeated=.0
    if. #format do. repeated=.({:>{:format)e.'*+' end.
    fixed=.(#format)-repeated
    if. repeated do. minimum=.fixed+'+'={:>{:format
        'bad arguments'check (#y)>:minimum
    else. 'bad arguments'check (#y)=fixed end.
    for_i. i.#y do.
        if. i<fixed do. kind=.i{::format else. kind=.}:>{:format end.
        word=.i{::y
        select. kind
        case. 'name';'graph' do. valid=.validName word
        case. 'number' do. valid=.numberWord word
        case. do. valid=.edgeWord word
        end.
        'bad arguments'check valid
    end.
    for_i. i.fixed do.
        if. (i{::format)-:'graph' do. ('no graph ',i{::y)check (<i{::y)e.Names end.
    end.
)
buildGraph =: 4 : 0
    command=.x
    args=.y
    if. (<command)e.;:'GRAPH CYCLE PATH COMPLETE CIRCULANT' do.
        n=.0".1{::args
        minimum=.1+2*(<command)e.;:'CYCLE CIRCULANT'
        sizeCheck n,minimum,16
        g=.emptyGraph n
        select. command
        case. 'GRAPH' do.
            for_word. 2}.args do.
                word=.>word
                'u v'=.0".&>'-'split word
                ('bad edge ',word)check (u<n)*.(v<n)*.u~:v
                ('duplicate edge ',word)check -.(<u,v){g
                g=.g connect u,v
            end.
        case. 'CYCLE' do. for_u. i.n do. g=.g connect u,n|u+1 end.
        case. 'PATH' do. for_u. i.n-1 do. g=.g connect u,u+1 end.
        case. 'COMPLETE' do. for_u. i.n do. for_v. (u+1)+i.n-u+1 do. g=.g connect u,v end. end.
        case. do.
            jumps=.0".&>2}.args
            'bad value'check (*./jumps>0)*.(*./(2*jumps)<:n)*.*./(}:jumps)<}.jumps
            for_u. i.n do. for_j. jumps do. g=.g connect u,n|u+j end. end.
        end.
        g return.
    end.
    if. (<command)e.;:'BIPARTITE GRID' do.
        'a b'=.0".&>1}.args
        'bad value'check (a>0)*.b>0
        if. command-:'GRID' do. n=.a*b else. n=.a+b end.
        sizeCheck n,1 16
        g=.emptyGraph n
        if. command-:'BIPARTITE' do.
            for_u. i.a do. for_v. a+i.b do. g=.g connect u,v end. end.
        else.
            for_u. i.a do. for_v. i.b do.
                at=.b*u
                at=.at+v
                if. (v+1)<b do. g=.g connect at,at+1 end.
                if. (u+1)<a do. g=.g connect at,at+b end.
            end. end.
        end.
        g return.
    end.
    if. (<command)e.;:'STAR WHEEL' do.
        k=.0".1{::args
        sizeCheck k,(1+2*command-:'WHEEL'),15
        g=.emptyGraph k+1
        for_v. 1+i.k do. g=.g connect 0,v end.
        if. command-:'WHEEL' do. for_v. 1+i.k do. g=.g connect v,1+k|v end. end.
        g return.
    end.
    if. command-:'PETERSEN' do.
        g=.emptyGraph 10
        for_i. i.5 do. g=.g connect i,5|i+1
            g=.g connect i,i+5
            g=.g connect (i+5),5+5|i+2 end.
        g return.
    end.
    if. command-:'HYPERCUBE' do.
        d=.0".1{::args
        sizeCheck d,1 4
        n=.2^d
        g=.emptyGraph n
        for_u. i.n do. for_bit. i.d do.
            power=.2^bit
            if. 2|<.u%power do. v=.u-power else. v=.u+power end.
            g=.g connect u,v
        end. end.
        g return.
    end.
    source=.getGraph 1{::args
    n=.#source
    select. command
    case. 'COMPLEMENT' do. g=.(1-source)*.-.=i.n
    case. 'LINE' do.
        es=.edges source
        'no edges'check 0<#es
        sizeCheck (#es),1 16
        g=.emptyGraph #es
        for_i. i.#es do. for_j. (i+1)+i.(#es)-i+1 do.
            if. +./(i{::es)e.j{::es do. g=.g connect i,j end.
        end. end.
    case. 'PRODUCT';'UNION' do.
        other=.getGraph 2{::args
        m=.#other
        if. command-:'PRODUCT' do. size=.n*m else. size=.n+m end.
        sizeCheck size,1 16
        g=.emptyGraph size
        if. command-:'PRODUCT' do.
            for_e. edges source do. 'u v'=.>e
                for_w. i.m do. g=.g connect (m*u)+w,(m*v)+w end. end.
            for_e. edges other do. 'u v'=.>e
                for_w. i.n do. g=.g connect (m*w)+u,(m*w)+v end. end.
        else.
            for_e. edges source do. g=.g connect >e end.
            for_e. edges other do. g=.g connect n+>e end.
        end.
    case. 'RELABEL';'CANONIZE' do.
        if. command-:'CANONIZE' do. p=.3{::canonical source else. p=.0".&>2}.args end.
        'bad permutation'check (/:~p)-:i.n
        g=.emptyGraph n
        for_e. edges source do. g=.g connect (>e){p end.
    case. do.
        selected=.0".&>2}.args
        'bad vertices'check (*./selected<n)*.(#selected)=#~.selected
        g=.selected{"1 selected{source
    end.
    g
)
execute =: 3 : 0
    words=.' 'split y
    command=.0{::words
    args=.}.words
    command arguments args
    format=.schema command
    if. #format do.
        if. (0{::format)-:'name' do.
            graph=.command buildGraph args
            name=.0{::args
            at=.Names i.<name
            status=.'defined'
            if. at=#Names do. Names=:Names,<name
                Graphs=:Graphs,<graph
            else. status=.'redefined'
                Graphs=:(<graph)at}Graphs end.
            emit status,' ',name,' n ',(num #graph),' m ',num #edges graph return.
        end.
    end.
    select. command
    case. 'LIST' do.
        emit 'graphs ',num #Names
        for_name. /:~Names do. g=.getGraph >name
            emit (>name),' n ',(num #g),' m ',num #edges g end.
    case. 'CLASSIFY' do. classify 0".0{::args
    case. 'DELETE' do.
        name=.0{::args
        mask=.Names~:<name
        Names=:mask#Names
        Graphs=:mask#Graphs
        emit 'deleted ',name
    case. do.
        name=.0{::args
        g=.getGraph name
        select. command
        case. 'SHOW' do.
            emit 'graph ',name,' n ',(num #g),' m ',num #edges g
            for_v. i.#g do.
                neighbors=.I.v{g
                text=.(num v),':'
                if. #neighbors do. text=.text,' ',numbers neighbors end.
                emit text
            end.
        case. 'INVARIANTS' do. g invariantReport name
        case. 'CANON' do.
            form=.canonical g
            emit 'canon ',name,' nodes ',(num 0{::form),' leaves ',num 1{::form
            emit 'labels ',numbers 3{::form
            text=.2{::form
            if. 0=#text do. text=.'-' end.
            emit 'string ',text
        case. 'REFINE' do.
            selected=.0".&>}.args
            'bad vertices'check *./selected<#g
            result=.stable g
            for_v. selected do.
                colors=.0{::result
                ('singleton ',num v)check 1<+/colors=v{colors
                next=.g refine colors individualize v
                result=.(<0{::next),<(1{::result)+1{::next
            end.
            groups=.cells 0{::result
            emit 'refine ',name,' rounds ',(num 1{::result),' cells ',num #groups
            for_c. i.#groups do. emit (num c),': ',numbers c{::groups end.
        case. 'ISO' do. g isoReport getGraph 1{::args
        case. 'AUT' do. g autReport name
        case. 'SUBISO' do. subisoReport (<g),(<getGraph 1{::args),(<name),<1{::args
        end.
    end.
)
main =: 3 : 0
    Names=:Graphs=:0$a:
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    count=.0".0{::lines
    for_i. i.count do.
        Output=:0$a:
        try. execute (i+1){::lines
        catcht. Output=:,<'error: ',Reason end.
        if. #Output do. 1!:2&2 ;Output,&.><LF end.
    end.
)
main''
