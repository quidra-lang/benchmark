ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
div =: 4 : '_1 x:<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
decimal =: 3 : 0
    sign =. 1
    if. '-'={.y do. sign =. _1
        y =. }.y end.
    parts =. '.' split y
    value =. num 0{::parts
    if. (#parts)>1 do.
        digits =. 1{::parts
        value =. value+(num digits)%10^#digits
    end.
    sign*value
)
number =: 3 : 0
    if. y<0 do. '-',number -y return. end.
    text =. ''
    while. y>0 do.
        text =. ((10|y){Digits),text
        y =. y div 10
    end.
    if. #text do. text else. '0' end.
)
split =: 4 : 0
    parts =. 0$a:
    while. 1 do.
        position =. y i.x
        parts =. parts,<position{.y
        if. position=#y do. parts return. end.
        y =. (position+1)}.y
    end.
)
join =: 4 : 0
    text =. ''
    for_index. i.#y do.
        if. index do. text =. text,x end.
        text =. text,index{::y
    end.
    text
)
text_line =: 3 : 0
    parts =. 0$a:
    for_box. y do.
        value =. >box
        if. 2~:3!:0 value do. value =. number value end.
        parts =. parts,<value
    end.
    ' ' join parts
)
ascii_order =: 3 : '/: > (a.&i.)&.> y'
ascii_sort =: 3 : '(ascii_order y){y'
ordered_sum =: 3 : 0
    total =. 0.0
    for_value. y do. total =. total+value end.
    total
)
load SourceDirectory,'graph_io.ijs'
load SourceDirectory,'components.ijs'
load SourceDirectory,'pagerank.ijs'
load SourceDirectory,'hits.ijs'
load SourceDirectory,'report.ijs'
Regions =: ;:'CORE IN OUT TUBE IN_TENDRIL OUT_TENDRIL OTHER'
Quantities =: ;:'in_degree pagerank cheirank authority hub trustrank harmonic'
ids =: 3 : 'y{PageIds'
numbers =: 3 : ''' '' join number&.><"0 y'
rank_order =: 3 : '/: (-scaled y),.i.#y'
positions =: 3 : '1+/:y'
prefix =: 4 : '(x<.#y){.y'
top_list =: 4 : 'x prefix (rank_order y)#~0<(rank_order y){scaled y'
ranked_counts =: 4 : 0
    nodes =. I.y>0
    x prefix nodes{~/: (-(nodes{y)),.nodes
)
join_blocks =: 3 : 0
    lines =. 0$a:
    for_block. y do.
        if. #lines do. lines =. lines,<'' end.
        lines =. lines,>block
    end.
    lines
)
distribution =: 3 : 0
    lines =. 0$a:
    for_value. /:~~.y do. lines =. lines,<text_line value;+/y=value end.
    lines
)
describe =: 4 : 0
    'rank node' =. x
    page =. node{::Pages
    text_line (<rank),(0{page),(<y),(1{page),2{page
)
rank_lines =: 4 : 0
    lines =. 0$a:
    for_position. i.#y do.
        node =. position{y
        lines =. lines,<((position+1),node) describe fixed node{x
    end.
    lines
)
build_graph =: 3 : 0
    Links =: 0 2$0
    Ignored =: 0$a:
    for_record. Records do.
        'line source target' =. record
        reason =. ''
        if. -. (source e.PageIds)*.target e.PageIds do. reason =. 'unknown'
        elseif. source=target do. reason =. 'self'
        else.
            edge =. PageIds i.source,target
            if. (<edge)e.<"1 Links do. reason =. 'duplicate'
            else. Links =: Links,edge end.
        end.
        if. #reason do. Ignored =: Ignored,<(<record),<reason end.
    end.
    Links =: (/:Links){Links
    Successors =: Predecessors =: PageCount$<0$0
    InterLinks =: 0 2$0
    for_edge. Links do.
        'source target' =. edge
        Successors =: (<(source{::Successors),target) source}Successors
        Predecessors =: (<(target{::Predecessors),source) target}Predecessors
        if. -. (source{::PageHosts)-:target{::PageHosts do. InterLinks =: InterLinks,edge end.
    end.
    InDegrees =: #&>Predecessors
    OutDegrees =: #&>Successors
    Forward =: Reverse =: 0$a:
    for_node. i.PageCount do.
        sources =. node{::Predecessors
        targets =. node{::Successors
        Forward =: Forward,<sources,.((#sources)$1)
        Reverse =: Reverse,<targets,.((#targets)$1)
    end.
    i.0
)
undirected_data =: 3 : 0
    Adjacent =: (PageCount,PageCount)$0
    for_edge. Links do.
        Adjacent =: 1 (<edge)}Adjacent
        Adjacent =: 1 (<|.edge)}Adjacent
    end.
    Neighbors =: <@I."1 Adjacent
    UndirectedEdges =: (+/#&>Neighbors)div 2
    Closed =: Possible =: Eligible =: 0
    localtotal =. 0.0
    for_group. Neighbors do.
        nodes =. >group
        degree =. #nodes
        if. degree<2 do. continue. end.
        own =. 0
        for_first. i.degree do.
            for_second. (first+1)+i.degree-(first+1) do.
                own =. own+(<(first{nodes),second{nodes){Adjacent
            end.
        end.
        choices =. (degree*degree-1)div 2
        Closed =: Closed+own
        Possible =: Possible+choices
        Eligible =: Eligible+1
        localtotal =. localtotal+own%choices
    end.
    AverageClustering =: localtotal%Eligible
    remaining =. #&>Neighbors
    removed =. PageCount$0
    KCore =: PageCount$0
    level =. 0
    left =. PageCount
    while. left do.
        candidates =. I.(-.removed)*.remaining<:level
        if. 0=#candidates do. level =. level+1 continue. end.
        node =. {.candidates
        removed =. 1 node}removed
        KCore =: level node}KCore
        left =. left-1
        for_child. node{::Neighbors do.
            if. -.child{removed do. remaining =. ((child{remaining)-1) child}remaining end.
        end.
    end.
    Degeneracy =: >./KCore
    labels =. weak_components Neighbors
    WeakCount =: 1+>./labels
    WeakLargest =: >./+/"1 (i.WeakCount)=/labels
    i.0
)
component_data =: 3 : 0
    groups =. /:~&.>strong_components Successors
    Groups =: (/:{.&>groups){groups
    ComponentCount =: #Groups
    ComponentLabels =: PageCount$0
    CoreComponent =: (#&>Groups)i.>./#&>Groups
    Singletons =: +/1=#&>Groups
    for_group. i.ComponentCount do. ComponentLabels =: group (group{::Groups)}ComponentLabels end.
    ComponentIncoming =: ComponentOutgoing =: ComponentCount$0
    edges =. 0 2$0
    for_edge. Links do.
        'first second' =. edge{ComponentLabels
        if. first=second do. continue. end.
        ComponentOutgoing =: (1+first{ComponentOutgoing) first}ComponentOutgoing
        ComponentIncoming =: (1+second{ComponentIncoming) second}ComponentIncoming
        edges =. edges,first,second
    end.
    edges =. ~.edges
    CondensationEdges =: #edges
    successors =. ComponentCount$<0$0
    pending =. lengths =. ComponentCount$0
    for_edge. edges do.
        'source target' =. edge
        successors =. (<(source{::successors),target) source}successors
        pending =. (1+target{pending) target}pending
    end.
    ready =. I.pending=0
    while. #ready do.
        node =. {:ready
        ready =. }:ready
        for_child. node{::successors do.
            lengths =. ((child{lengths)>.1+node{lengths) child}lengths
            pending =. ((child{pending)-1) child}pending
            if. 0=child{pending do. ready =. ready,child end.
        end.
    end.
    CondensationDepth =: >./lengths
    core =. CoreComponent{::Groups
    forward =. Successors reachable core
    backward =. Predecessors reachable core
    Bowtie =: PageCount$6
    Bowtie =: 2 (I.forward)}Bowtie
    Bowtie =: 1 (I.backward)}Bowtie
    Bowtie =: 0 core}Bowtie
    fromin =. Successors reachable I.Bowtie=1
    toout =. Predecessors reachable I.Bowtie=2
    for_node. I.Bowtie=6 do.
        if. (node{fromin)*.node{toout do. Bowtie =: 3 node}Bowtie
        elseif. node{fromin do. Bowtie =: 4 node}Bowtie
        elseif. node{toout do. Bowtie =: 5 node}Bowtie end.
    end.
    i.0
)
distance_data =: 3 : 0
    ReachablePairs =: DistanceTotal =: Diameter =: 0
    DiameterPair =: 0 0
    DistanceHistogram =: PageCount$0
    Harmonic =: PageCount$0.0
    for_source. i.PageCount do.
        distances =. Successors bfs_distances ,source
        for_target. i.PageCount do.
            steps =. target{distances
            if. (source=target)+.steps<0 do. continue. end.
            ReachablePairs =: ReachablePairs+1
            DistanceTotal =: DistanceTotal+steps
            DistanceHistogram =: (1+steps{DistanceHistogram) steps}DistanceHistogram
            Harmonic =: ((target{Harmonic)+%steps) target}Harmonic
            if. steps>Diameter do. Diameter =: steps
                DiameterPair =: source,target end.
        end.
    end.
    cumulative =. 0
    EffectiveDiameter =: Diameter
    for_steps. 1+i.Diameter do.
        cumulative =. cumulative+steps{DistanceHistogram
        if. (10*cumulative)>:9*ReachablePairs do. EffectiveDiameter =: steps break. end.
    end.
    i.0
)
kendall =: 4 : 0
    numerator =. 0
    count =. #x
    for_first. i.count do.
        for_second. (first+1)+i.count-(first+1) do.
            dx =. (first{x)-second{x
            dy =. (first{y)-second{y
            if. (dx=0)+.dy=0 do. continue. end.
            if. (dx>0)=dy>0 do. numerator =. numerator+1
            else. numerator =. numerator-1 end.
        end.
    end.
    numerator fraction (count*count-1)div 2
)
salsa =: 4 : 0
    degree =. x$0
    targets =. neighbors =. x$<0$0
    for_edge. y do.
        'source target' =. edge
        degree =. (1+target{degree) target}degree
        targets =. (<(source{::targets),target) source}targets
    end.
    for_group. targets do.
        group =. >group
        for_position. i.0>.((#group)-1) do.
            first =. position{group
            second =. (position+1){group
            neighbors =. (<(first{::neighbors),second) first}neighbors
            neighbors =. (<(second{::neighbors),first) second}neighbors
        end.
    end.
    labels =. weak_components neighbors
    side =. I.degree>0
    sizes =. mass =. x$0
    for_node. side do.
        label =. node{labels
        sizes =. (1+label{sizes) label}sizes
        mass =. ((label{mass)+node{degree) label}mass
    end.
    values =. x$0.0
    for_node. side do.
        label =. node{labels
        value =. ((label{sizes)*node{degree)%((#side)*label{mass)
        values =. value node}values
    end.
    values
)
run_pagerank =: 4 : 0
    'teleport damping' =. y
    x power_iteration (<teleport),(<damping),(<Iterations),<Tolerance
)
analyze =: 3 : 0
    build_graph ''
    undirected_data ''
    component_data ''
    distance_data ''
    trusted =. /:~PageIds i.Trusted
    PR =: Forward run_pagerank (<i.PageCount),<Damping
    CR =: Reverse run_pagerank (<i.PageCount),<Damping
    TR =: Forward run_pagerank (<trusted),<Damping
    Pagerank =: 0{::PR
    Cheirank =: 0{::CR
    Trustrank =: 0{::TR
    'Authority Hub' =: PageCount hits (<i.PageCount),(<InterLinks),<HitsIterations
    PageOrder =: rank_order Pagerank
    PageRank =: positions PageOrder
    CheirankRank =: positions rank_order Cheirank
    TrustRatio =: Trustrank%Pagerank
    TrustDistance =: Successors bfs_distances trusted
    examined =. SpamTop prefix PageOrder
    Suspects =: examined#~(((examined{4 scaled TrustRatio)%10000)<SpamThreshold)
    SuspectHosts =: ascii_sort ~.Suspects{PageHosts
    Demoted =: 0$a:
    RemovedLinks =: 0
    if. #Suspects do.
        kept =. PageCount$<0 2$0
        for_edge. Links do.
            'source target' =. edge
            if. ((source{::PageHosts)-:target{::PageHosts)*.(source{PageHosts)e.SuspectHosts do.
                RemovedLinks =: RemovedLinks+1
            else.
                kept =. (<(target{::kept),source,1) target}kept
            end.
        end.
        Demoted =: kept run_pagerank (<i.PageCount),<Damping
    end.
    Sweeps =: 0$a:
    for_damping. Sweep do. Sweeps =: Sweeps,<Forward run_pagerank (<i.PageCount),<damping end.
    QueryResults =: 0$a:
    for_query. Queries do. QueryResults =: QueryResults,<query_result >query end.
    host_data ''
    i.0
)
query_result =: 3 : 0
    query =. y
    'querynumber words seedids' =. query
    matches =. 0$0
    for_node. PageOrder do.
        titlewords =. 3{::node{::Pages
        accepted =. 1
        for_word. words do.
            word =. >word
            excluded =. '-'={.word
            if. excluded do. word =. }.word end.
            if. excluded=(<word)e.titlewords do. accepted =. 0 end.
        end.
        if. accepted do. matches =. matches,node end.
    end.
    root =. RootLimit prefix matches
    inbase =. PageCount$0
    for_node. root do.
        inbase =. 1 node}inbase
        inbase =. 1 (NeighborLimit prefix node{::Successors)}inbase
        inbase =. 1 (NeighborLimit prefix node{::Predecessors)}inbase
    end.
    base =. I.inbase
    links =. 0 2$0
    dropped =. 0
    for_edge. Links do.
        'source target' =. edge
        if. *./edge{inbase do.
            if. (source{::PageHosts)-:target{::PageHosts do. dropped =. dropped+1
            else. links =. links,edge end.
        end.
    end.
    seeds =. /:~PageIds i.seedids
    personalized =. Forward run_pagerank (<seeds),<Damping
    values =. 0{::personalized
    top =. TopK top_list values
    reach =. +/Successors reachable seeds
    seedmass =. ordered_sum seeds{values
    globaloverlap =. +/(top{PageRank)<:TopK
    sub =. 0$a:
    if. #links do.
        'authority hub' =. PageCount hits (<base),(<links),<HitsIterations
        sa =. PageCount salsa links
        sh =. PageCount salsa |."1 links
        at =. TopK top_list authority
        ht =. TopK top_list hub
        sat =. TopK top_list sa
        sht =. TopK top_list sh
        cited =. {.at
        citing =. {.ht
        cocitation =. coupling =. PageCount$0
        for_source. cited{::Predecessors do.
            for_target. source{::Successors do.
                if. target~:cited do. cocitation =. (1+target{cocitation) target}cocitation end.
            end.
        end.
        for_target. citing{::Successors do.
            for_source. target{::Predecessors do.
                if. source~:citing do. coupling =. (1+source{coupling) source}coupling end.
            end.
        end.
        related =. TopK ranked_counts cocitation
        similar =. TopK ranked_counts coupling
        sub =. (<authority),(<hub),(<sa),(<sh),(<at),(<ht),(<sat),(<sht),(<cited),(<citing),(<cocitation),(<coupling),(<related),<similar
    end.
    (<query),(<matches),(<root),(<base),(<links),(<dropped),(<personalized),(<top),(<reach),(<seedmass),(<globaloverlap),<sub
)
host_data =: 3 : 0
    HostNames =: ascii_sort ~.PageHosts
    HostCount =: #HostNames
    ofpage =. HostNames i.PageHosts
    HostMembers =: 0$a:
    for_host. i.HostCount do. HostMembers =: HostMembers,<I.ofpage=host end.
    HostWeights =: (HostCount,HostCount)$0
    HostInternal =: HostOutgoing =: HostIncoming =: HostCount$0
    for_edge. Links do.
        'first second' =. edge{ofpage
        if. first=second do. HostInternal =: (1+first{HostInternal) first}HostInternal
        else.
            HostWeights =: (1+(<first,second){HostWeights) (<first,second)}HostWeights
            HostOutgoing =: (1+first{HostOutgoing) first}HostOutgoing
            HostIncoming =: (1+second{HostIncoming) second}HostIncoming
        end.
    end.
    HostEdges =: 0 2$0
    neighbors =. HostCount$<0$0
    inedges =. HostCount$<0 2$0
    HostReciprocal =: 0
    for_first. i.HostCount do.
        for_second. i.HostCount do.
            weight =. (<first,second){HostWeights
            if. weight=0 do. continue. end.
            HostEdges =: HostEdges,first,second
            neighbors =. (<(first{::neighbors),second) first}neighbors
            inedges =. (<(second{::inedges),first,weight) second}inedges
            HostReciprocal =: HostReciprocal+0<(<second,first){HostWeights
        end.
    end.
    groups =. strong_components neighbors
    HostComponents =: #groups
    HostLargest =: >./#&>groups
    HostRun =: inedges run_pagerank (<i.HostCount),<Damping
    HostRank =: positions rank_order 0{::HostRun
    keys =. 0 3$0
    for_edge. HostEdges do. keys =. keys,(-(<edge){HostWeights),edge end.
    HeavyEdges =: (TopK<.#HostEdges){.( /:keys){HostEdges
    i.0
)
representative =: 3 : '(y{PageRank)i.<./y{PageRank'
representative_node =: 3 : '(representative y){y'
graph_stats =: 3 : 0
    lines =. (<text_line 'pages';PageCount),(<text_line 'hosts';HostCount),(<text_line 'link_rows';#Records),<text_line 'links';#Links
    reasons =. (1&{::)&.>Ignored
    for_reason. ;:'unknown self duplicate' do.
        reason =. >reason
        lines =. lines,<text_line ('ignored_',reason);+/ (<reason)e.~reasons
    end.
    for_box. Ignored do.
        'record reason' =. >box
        'lineno source target' =. record
        lines =. lines,<text_line 'ignored line';lineno;((number source),',',number target);reason
    end.
    reciprocal =. 0
    for_edge. Links do. reciprocal =. reciprocal+(<|.edge)e.<"1 Links end.
    lines =. lines,<text_line 'intra_host_links';(#Links)-#InterLinks
    lines =. lines,<text_line 'inter_host_links';#InterLinks
    lines =. lines,<text_line 'mean_degree';4 fixed (#Links)%PageCount
    lines =. lines,<text_line 'reciprocity';reciprocal fraction #Links
    dangling =. I.OutDegrees=0
    noins =. I.InDegrees=0
    own =. text_line 'dangling';#dangling
    if. #dangling do. own =. own,' ',numbers ids dangling end.
    lines =. lines,<own
    own =. text_line 'no_in_links';#noins
    if. #noins do. own =. own,' ',numbers ids noins end.
    lines =. lines,<own
    lines =. lines,<text_line 'max_in_degree';(>./InDegrees);'pages';numbers ids I.InDegrees=>./InDegrees
    lines =. lines,<text_line 'max_out_degree';(>./OutDegrees);'pages';numbers ids I.OutDegrees=>./OutDegrees
    lines =. lines,(<''),(< 'in_degree_distribution'),(distribution InDegrees),(<''),(< 'out_degree_distribution'),(distribution OutDegrees),<''
    lines =. lines,<text_line 'undirected_links';UndirectedEdges
    lines =. lines,<text_line 'transitivity';Closed fraction Possible
    lines =. lines,<text_line 'average_clustering';(4 fixed AverageClustering);'pages';Eligible
    lines =. lines,<text_line 'degeneracy';Degeneracy;'pages';+/KCore=Degeneracy
    lines =. lines,(<'core_distribution'),(distribution KCore),<''
    lines =. lines,<text_line 'strong_components';ComponentCount;'largest';(#CoreComponent{::Groups);'singletons';Singletons;'condensation_links';CondensationEdges
    lines =. lines,<text_line 'weak_components';WeakCount;'largest';WeakLargest
    lines =. lines,<text_line 'condensation_depth';CondensationDepth
    for_group. i.ComponentCount do.
        members =. group{::Groups
        if. (#members)<2 do. continue. end.
        own =. text_line 'scc';(group+1);'size';(#members);'min';({.ids members);'incoming';(group{ComponentIncoming);'outgoing';(group{ComponentOutgoing);'pagerank';fixed ordered_sum members{Pagerank
        if. 0=group{ComponentOutgoing do. own =. own,' sink' end.
        lines =. lines,<own
    end.
    lines =. lines,(<''),<text_line 'bowtie core_scc';CoreComponent+1
    for_region. i.7 do.
        members =. I.Bowtie=region
        own =. text_line (region{::Regions);(#members);'pagerank';fixed ordered_sum members{Pagerank
        if. #members do. own =. own,' top ',number {.ids representative_node members end.
        if. (0<#members)*.(#members)<:10 do. own =. own,' pages ',numbers ids members end.
        lines =. lines,<own
    end.
    counts =. 7 7$0
    for_edge. Links do.
        index =. <edge{Bowtie
        counts =. (1+index{counts) index}counts
    end.
    lines =. lines,<'region_links'
    for_first. i.7 do.
        for_second. i.7 do.
            count =. (<first,second){counts
            if. count do. lines =. lines,<text_line (first{::Regions);(second{::Regions);count end.
        end.
    end.
    'source target' =. DiameterPair
    lines =. lines,(<''),<'distances'
    lines =. lines,<text_line 'reachable_pairs';ReachablePairs
    lines =. lines,<text_line 'average';DistanceTotal fraction ReachablePairs
    lines =. lines,<text_line 'diameter';Diameter;'from';(source{PageIds);'to';target{PageIds
    lines =. lines,<text_line 'effective_diameter';EffectiveDiameter
    for_steps. 1+i.Diameter do. lines =. lines,<text_line steps;steps{DistanceHistogram end.
    lines
)
pagerank_csv =: 3 : 0
    lines =. <'id,in_degree,out_degree,scc,region,kcore,harmonic,pagerank,pagerank_rank,cheirank,cheirank_rank,authority,hub,trustrank,trust_ratio,trust_distance'
    for_node. i.PageCount do.
        fields =. (<number node{PageIds),(<number node{InDegrees),(<number node{OutDegrees),(<number 1+node{ComponentLabels),( (node{Bowtie){Regions),(<number node{KCore),(<fixed node{Harmonic),(<fixed node{Pagerank),(<number node{PageRank),(<fixed node{Cheirank),(<number node{CheirankRank),(<fixed node{Authority),(<fixed node{Hub),(<fixed node{Trustrank),(<4 fixed node{TrustRatio),<number node{TrustDistance
        lines =. lines,<',' join fields
    end.
    lines
)
contribution =: 3 : '(Damping*y{Pagerank)%y{OutDegrees'
rankings =: 3 : 0
    values =. Pagerank;Cheirank;Authority;Hub;Trustrank;Harmonic
    blocks =. 0$a:
    for_score. i.6 do.
        scores =. score{::values
        name =. (score+1){::Quantities
        top =. TopK top_list scores
        lines =. (<text_line name;'top';TopK),scores rank_lines top
        if. score=0 do.
            lines =. lines,<text_line 'dangling_mass';fixed ordered_sum (I.OutDegrees=0){Pagerank
            for_node. top do.
                sources =. node{::Predecessors
                keys =. (-scaled contribution sources),.sources
                contributors =. 3 prefix (/:keys){sources
                own =. text_line 'contributors';node{PageIds
                for_source. contributors do.
                    own =. own,' ',text_line (source{PageIds);fixed contribution source
                end.
                lines =. lines,<own
            end.
        end.
        blocks =. blocks,<lines
    end.
    series =. <InDegrees
    for_scores. values do. series =. series,<scaled >scores end.
    lines =. <'correlation'
    for_first. i.7 do.
        for_second. (first+1)+i.7-(first+1) do.
            lines =. lines,<text_line (first{::Quantities);(second{::Quantities);(first{::series)kendall second{::series
        end.
    end.
    blocks =. blocks,<lines
    lines =. <'damping_sweep'
    for_sweep. i.#Sweep do.
        run =. sweep{::Sweeps
        scores =. 0{::run
        order =. rank_order scores
        ranks =. positions order
        shifts =. |ranks-PageRank
        shift =. shifts i.>./shifts
        shared =. +/(ranks<:TopK)*.PageRank<:TopK
        lines =. lines,<text_line 'damping';(4 fixed sweep{Sweep);'overlap';shared;'footrule';(+/shifts);'kendall';((scaled Pagerank)kendall scaled scores);'largest_shift';(shift{PageIds);(shift{PageRank);shift{ranks
        lines =. lines,<text_line 'top';numbers ids TopK prefix order
    end.
    blocks =. blocks,<lines
    lines =. <text_line 'spam top';SpamTop;'threshold';4 fixed SpamThreshold
    for_node. Suspects do.
        lines =. lines,<text_line 'suspect';(node{PageIds);'rank';(node{PageRank);'pagerank';(fixed node{Pagerank);'trustrank';(fixed node{Trustrank);'trust_ratio';(4 fixed node{TrustRatio);'trust_distance';(node{TrustDistance);'kcore';(node{KCore);node{::PageHosts
    end.
    lines =. lines,(<text_line 'count';#Suspects),<'trust_by_distance'
    distances =. /:~~.TrustDistance#~TrustDistance>:0
    if. _1 e.TrustDistance do. distances =. distances,_1 end.
    for_distance. distances do.
        members =. I.TrustDistance=distance
        label =. number distance
        if. distance=_1 do. label =. 'unreachable' end.
        lines =. lines,<text_line label;'pages';(#members);'trustrank';(fixed ordered_sum members{Trustrank);'pagerank';fixed ordered_sum members{Pagerank
    end.
    blocks =. blocks,<lines
    lines =. <'demotion none'
    if. #Demoted do.
        scores =. 0{::Demoted
        ranks =. positions rank_order scores
        top =. TopK top_list scores
        lines =. <text_line 'demotion hosts';(' ' join SuspectHosts);'removed_links';RemovedLinks
        for_position. i.#top do.
            node =. position{top
            value =. text_line (fixed node{scores);'was';node{PageRank
            lines =. lines,<((position+1),node) describe value
        end.
        for_node. Suspects do.
            lines =. lines,<text_line 'suspect';(node{PageIds);'before';(node{PageRank);'after';node{ranks
        end.
    end.
    blocks =. blocks,<lines
    lines =. <text_line 'host_graph hosts';HostCount;'links';(#HostEdges);'reciprocal';HostReciprocal;'strong_components';HostComponents;'largest';HostLargest
    lines =. lines,<text_line 'host_links top';TopK
    for_edge. HeavyEdges do.
        'first second' =. edge
        lines =. lines,<text_line (first{::HostNames);(second{::HostNames);(<edge){HostWeights
    end.
    blocks =. blocks,<lines
    join_blocks blocks
)
convergence_block =: 4 : 0
    lines =. (<''),<x
    'values changes converged' =. y
    for_step. 10*1+i.(#changes)div 10 do.
        lines =. lines,<text_line 'iteration';step;'l1';10 fixed (step-1){changes
    end.
    text =. 'none'
    if. converged do. text =. number converged end.
    lines,<text_line 'converged_at';text
)
convergence_lines =: 3 : 0
    damping =. 4 fixed Damping
    lines =. <text_line 'iterations';Iterations;'tolerance';10 fixed Tolerance
    lines =. lines,('pagerank damping ',damping)convergence_block PR
    lines =. lines,('cheirank damping ',damping)convergence_block CR
    heading =. text_line 'trustrank damping';damping;'seeds';#Trusted
    lines =. lines,heading convergence_block TR
    for_sweep. i.#Sweep do.
        lines =. lines,('sweep damping ',4 fixed sweep{Sweep)convergence_block sweep{::Sweeps
    end.
    if. #Demoted do. lines =. lines,('demoted damping ',damping)convergence_block Demoted end.
    for_result. QueryResults do.
        result =. >result
        query =. 0{::result
        heading =. text_line 'personalized query';(0{::query);'damping';damping
        lines =. lines,heading convergence_block 6{::result
    end.
    heading =. text_line 'host_pagerank damping';damping;'hosts';HostCount
    lines,heading convergence_block HostRun
)
query_lines =: 3 : 0
    'query matches root base links dropped personalized top reach seedmass globaloverlap sub' =. y
    'querynumber words seedids' =. query
    lines =. <text_line 'query';querynumber;'words';(' ' join words);'seeds';numbers seedids
    lines =. lines,<text_line 'matched';(#matches);'root';(#root);'base';(#base);'links';(#links);'dropped_intra_host';dropped
    lines =. lines,<'results'
    lines =. lines,Pagerank rank_lines TopK prefix matches
    lines =. lines,<text_line 'personalized reach';reach;'seed_mass';fixed seedmass
    lines =. lines,(0{::personalized)rank_lines top
    lines =. lines,<text_line 'overlap_with_global';globaloverlap
    if. 0=#sub do. lines,<'hits none' return. end.
    'authority hub sa sh at ht sat sht cited citing cocitation coupling related similar' =. sub
    lines =. lines,(<'hits authorities'),(authority rank_lines at),(< 'hits hubs'),(hub rank_lines ht),(< 'salsa authorities'),(sa rank_lines sat),(< 'salsa hubs'),sh rank_lines sht
    lines =. lines,<text_line 'hits_salsa_overlap authorities';(+/at e.sat);'hubs';(+/ht e.sht);'authority_hosts';#~.at{PageHosts
    lines =. lines,<text_line 'related_to';(cited{PageIds);'citing';#cited{::Predecessors
    for_position. i.#related do.
        node =. position{related
        lines =. lines,<((position+1),node)describe number node{cocitation
    end.
    lines =. lines,<text_line 'coupled_to';(citing{PageIds);'cited';#citing{::Successors
    for_position. i.#similar do.
        node =. position{similar
        lines =. lines,<((position+1),node)describe number node{coupling
    end.
    lines
)
hosts_csv =: 3 : 0
    lines =. <'host,pages,core_pages,internal_links,internal_density,outgoing_links,incoming_links,dangling_pages,page_score_sum,top_page,score,rank'
    for_host. i.HostCount do.
        members =. host{::HostMembers
        count =. #members
        density =. 0.0
        if. count>:2 do. density =. (host{HostInternal)%(count*count-1) end.
        fields =. (host{HostNames),(<number count),(<number +/0=members{Bowtie),(<number host{HostInternal),(<4 fixed density),(<number host{HostOutgoing),(<number host{HostIncoming),(<number +/0=members{OutDegrees),(<fixed ordered_sum members{Pagerank),(<number PageIds{~representative_node members),(<fixed host{0{::HostRun),<number host{HostRank
        lines =. lines,<',' join fields
    end.
    lines
)
main =: 3 : 0
    read_input ''
    analyze ''
    1!:5 ::0: <'output'
    'graph_stats.txt' write_lines graph_stats ''
    'pagerank.csv' write_lines pagerank_csv ''
    'rankings.txt' write_lines rankings ''
    'convergence.txt' write_lines convergence_lines ''
    blocks =. 0$a:
    for_result. QueryResults do. blocks =. blocks,<query_lines >result end.
    'queries.txt' write_lines join_blocks blocks
    'hosts.csv' write_lines hosts_csv ''
    i.0
)
main ''
