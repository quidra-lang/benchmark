load 'grid_map.ijs'
load 'low_level.ijs'
load 'cbs.ijs'
load 'prioritized.ijs'
load 'report.ijs'

Classes =: ;:'cardinal semi_cardinal non_cardinal'
intdiv =: 4 : '<.(x:x)%x:y'
integer =: 3 : 0
    text =. ,":y
    '-'(I.text='_')}text
)
parse_integer =: 3 : 0
    text =. '_'(I.y='-')}y
    ".text
)
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do.
            result =. result,x
        end.
        result =. result,i{::y
    end.
    result
)
numbers =: 3 : ''' ''join integer&.>y'
read_lines =: 3 : '<;._2 (1!:1 <y)'
split_words =: 3 : '<;._1 '' '',y'
read_parameters =: 3 : 0
    Orders =: ,<i.NumberAgents
    RunDefinitions =: 0$a:
    Delays =: 0 3$0
    for_line. read_lines 'input/params.txt' do.
        fields =. split_words >line
        select. 0{::fields
        case. 'HORIZON' do. Horizon =: parse_integer 1{::fields
        case. 'HL_BUDGET' do. HighBudget =: parse_integer 1{::fields
        case. 'LL_BUDGET' do. LowBudget =: parse_integer 1{::fields
        case. 'WINDOW' do. 'WindowSize WindowStep' =: parse_integer ' 'join }.fields
        case. 'ORDER' do. Orders =: Orders,<parse_integer ' 'join }.fields
        case. 'RUN' do.
            'solver cost' =. }.fields
            RunDefinitions =: RunDefinitions,<(<solver,'-',cost),(<solver),<cost
        case. 'ANIMATE' do.
            AnimateName =: 1{::fields
            Frames =: parse_integer 2{::fields
        case. 'DELAY' do. Delays =: Delays,parse_integer ' 'join }.fields
        end.
    end.
)
mdd_layers =: 3 : 0
    'agent length restrictions' =. y
    distance =. agent{Distances
    layers =. ((length+1),NumberCells)$0
    layers =. 1(<0,agent{Starts)}layers
    for_time. 1+i.length do.
        for_cell. I.(time-1){layers do.
            for_destination. cell{::Destinations do.
                d =. destination{distance
                if. (d~:_1)*.(time+d)<:length do.
                    if. restrictions action_allowed cell,destination,time do.
                        layers =. 1(<time,destination)}layers
                    end.
                end.
            end.
        end.
    end.
    valid =. ((length+1),NumberCells)$0
    valid =. 1(<length,agent{Goals)}valid
    for_time. |.i.length do.
        for_cell. I.time{layers do.
            for_destination. cell{::Destinations do.
                if. (<(time+1),destination){valid do.
                    if. restrictions action_allowed cell,destination,time+1 do.
                        valid =. 1(<time,cell)}valid
                        break.
                    end.
                end.
            end.
        end.
    end.
    valid
)
initialize_classification =: 4 : 0
    ClassPaths =: x
    ClassRestrictions =: y
    ClassCache =: NumberAgents$<0$a:
)
conflict_class =: 3 : 0
    'kind time first second source destination' =. y
    fixed =. 0
    for_agent. first,second do.
        layers =. agent{::ClassCache
        if. 0=#layers do.
            length =. (#agent{::ClassPaths)-1
            arguments =. (<agent),(<length),<agent{::ClassRestrictions
            layers =. mdd_layers arguments
            ClassCache =: (<layers)agent}ClassCache
        end.
        length =. (#layers)-1
        if. time>length do.
            forced =. 1
        elseif. kind=0 do.
            forced =. 1=+/time{layers
        else.
            forced =. (1=+/(time-1){layers)*.1=+/time{layers
        end.
        fixed =. fixed+forced
    end.
    2-fixed
)
conflict_groups =: 3 : 0
    adjacent =. (NumberAgents,NumberAgents)$0
    for_conflict. y do.
        first =. 2{conflict
        second =. 3{conflict
        adjacent =. 1(<first,second)}adjacent
        adjacent =. 1(<second,first)}adjacent
    end.
    seen =. NumberAgents$0
    groups =. 0$a:
    for_start. i.NumberAgents do.
        if. (start{seen)+.-.+./start{adjacent do.
            continue.
        end.
        queue =. ,start
        seen =. 1 start}seen
        front =. 0
        while. front<#queue do.
            current =. front{queue
            front =. front+1
            for_other. I.current{adjacent do.
                if. -.other{seen do.
                    seen =. 1 other}seen
                    queue =. queue,other
                end.
            end.
        end.
        groups =. groups,<(/:~queue){AgentNames
    end.
    groups
)
prepare_instance =: 3 : 0
    Shortest =: i.0
    MddStates =: i.0
    MddWidths =: i.0
    empty =. empty_prohibitions ''
    BaselinePaths =: 0$a:
    LLSearches =: 0
    LLExpansions =: 0
    LLLimit =: _1
    for_agent. i.NumberAgents do.
        shortest =. (<agent,agent{Starts){Distances
        Shortest =: Shortest,shortest
        arguments =. (<agent),(<agent{Starts),(<0),(<empty),(<Horizon),<0
        'status path expanded' =. low_search arguments
        BaselinePaths =: BaselinePaths,<path
        layers =. mdd_layers(<agent),(<shortest),<empty
        widths =. +/"1 layers
        MddStates =: MddStates,+/widths
        MddWidths =: MddWidths,>./widths
    end.
    LowerSoc =: +/Shortest
    LowerSpan =: >./Shortest
    BaselineConflicts =: plan_conflicts BaselinePaths
    restrictions =. NumberAgents$<empty_prohibitions ''
    BaselinePaths initialize_classification restrictions
    BaselineClasses =: conflict_class"1 BaselineConflicts
    ConflictGroups =: conflict_groups BaselineConflicts
    DegreeCounts =: (+/0=FreeCells{Degrees),(+/1=FreeCells{Degrees),(+/2=FreeCells{Degrees),+/3<:FreeCells{Degrees
    remaining =. IsFree
    components =. 0
    for_seed. FreeCells do.
        if. -.seed{remaining do.
            continue.
        end.
        components =. components+1
        queue =. ,seed
        remaining =. 0 seed}remaining
        front =. 0
        while. front<#queue do.
            cell =. front{queue
            front =. front+1
            for_neighbor. map_neighbors cell do.
                if. neighbor{remaining do.
                    remaining =. 0 neighbor}remaining
                    queue =. queue,neighbor
                end.
            end.
        end.
    end.
    Components =: components
)
start_run =: 3 : 0
    'RName Solver CostFunction' =: y
    CostId =: CostFunction-:'MAKESPAN'
    RStatus =: 0
    RReason =: ''
    RPaths =: 0$a:
    RHigh =: 0
    RGenerated =: _1
    RSpecific =: 0$a:
    RTrace =: 0$a:
    REnd =: ''
    LLSearches =: 0
    LLExpansions =: 0
    LLLimit =: LowBudget
)
solve_pp =: 3 : 0
    for_order_number. 1+i.#Orders do.
        order =. (order_number-1){::Orders
        RHigh =: RHigh+1
        before =. LLExpansions
        'paths attempts failure' =. try_order order
        for_attempt. attempts do.
            'agent status path expanded' =. >attempt
            line =. 'order ',(integer order_number),' agent ',agent_name agent
            if. status=0 do.
                line =. line,' failed expansions ',integer expanded
            else.
                line =. line,' cost ',(integer (#path)-1),' expansions ',integer expanded
            end.
            RTrace =: RTrace,<line
        end.
        if. failure=_2 do.
            RReason =: 'll_budget'
            break.
        end.
        planned =. #attempts
        if. failure~:_1 do.
            planned =. planned-1
        end.
        line =. 'order ',(integer order_number),' ',(order{AgentNames),' planned ',integer planned
        line =. line,' expansions ',integer LLExpansions-before
        if. failure=_1 do.
            RSpecific =: RSpecific,<line,' ok'
            RPaths =: paths
            RStatus =: 1
            REnd =: 'end OK order ',integer order_number
            break.
        else.
            RSpecific =: RSpecific,<line,' failed ',agent_name failure
        end.
    end.
    if. -.RStatus do.
        if. 0=#RReason do.
            RReason =: 'orders'
        end.
        REnd =: 'end FAIL ',RReason
    end.
)
apply_constraint =: 4 : 0
    'agent kind source destination time' =. y
    restrictions =. x
    'states moves permanent' =. agent{::restrictions
    if. kind=0 do.
        states =. ~.states,destination,time
    else.
        moves =. ~.moves,source,destination,time
    end.
    changed =. (<states),(<moves),<permanent
    (<changed)agent}restrictions
)
choose_split =: 3 : 0
    conflicts =. 5{::y
    if. Solver-:'CBS' do.
        ( <0{conflicts),<_1 return.
    end.
    (0{::y)initialize_classification 1{::y
    categories =. conflict_class"1 conflicts
    index =. categories i.<./categories
    (<index{conflicts),<index{categories
)
constraint_lines =: 3 : 0
    rows =. 0 9$0
    for_agent. i.NumberAgents do.
        'states moves permanent' =. agent{::y
        for_state. states do.
            'cell time' =. state
            xx =. GridWidth|cell
            yy =. cell intdiv GridWidth
            rows =. rows,agent,time,0,xx,yy,xx,yy,cell,cell
        end.
        for_move. moves do.
            'source destination time' =. move
            coordinates =. (GridWidth|source),(source intdiv GridWidth)
            coordinates =. coordinates,(GridWidth|destination),destination intdiv GridWidth
            rows =. rows,agent,time,1,coordinates,source,destination
        end.
    end.
    rows =. (/:rows){rows
    lines =. 0$a:
    for_row. rows do.
        'agent time kind sx sy dx dy source destination' =. row
        line =. 'constraint ',agent_name agent
        if. kind=0 do.
            line =. line,' vertex ',cell_text destination
        else.
            line =. line,' edge ',(cell_text source),' ',cell_text destination
        end.
        lines =. lines,<line,' t ',integer time
    end.
    lines
)

cbs_summary =: 3 : 0
    'expanded generated pruned open classifications' =. y
    RHigh =: expanded
    RGenerated =: generated
    line =. 'search expanded ',(integer expanded),' generated ',(integer generated),' pruned ',integer pruned
    RSpecific =: RSpecific,<line,' open ',integer open
    if. Solver-:'ICBS' do.
        line =. 'classes cardinal ',(integer 0{classifications),' semi_cardinal ',integer 1{classifications
        RSpecific =: RSpecific,<line,' non_cardinal ',integer 2{classifications
    end.
)
solve_cbs =: 3 : 0
    empty =. NumberAgents$<empty_prohibitions ''
    paths =. 0$a:
    for_agent. i.NumberAgents do.
        arguments =. (<agent),(<agent{Starts),(<0),(agent{empty),(<Horizon),<0
        'status path expanded' =. low_search arguments
        if. status~:1 do.
            RReason =: 'exhausted'
            if. status=_1 do.
                RReason =: 'll_budget'
            end.
            cbs_summary(<0),(<0),(<0),(<0),<0 0 0
            REnd =: 'end FAIL ',RReason
            i.0 return.
        end.
        paths =. paths,<path
    end.
    root =. 0 0 _1 new_node(<paths),(<empty),<CostId
    nodes =. ,<root
    heap =. ,:node_key root
    generated =. 1
    expanded =. 0
    pruned =. 0
    classifications =. 3$0
    reason =. 'exhausted'
    answer =. 0$a:
    while. #heap do.
        'entry heap' =. heap_pop heap
        number =. 3{entry
        node =. number{::nodes
        conflicts =. 5{::node
        if. 0=#conflicts do.
            answer =. node
            reason =. ''
            break.
        end.
        if. expanded=HighBudget do.
            reason =. 'hl_budget'
            break.
        end.
        expanded =. expanded+1
        'conflict category' =. choose_split node
        if. category~:_1 do.
            classifications =. ((category{classifications)+1)category}classifications
        end.
        children =. 0$a:
        aborted =. 0
        for_branch. split_constraints conflict do.
            affected =. 0{branch
            restrictions =. (1{::node)apply_constraint branch
            arguments =. (<affected),(<affected{Starts),(<0),(affected{restrictions),(<Horizon),<0
            'status child_path count' =. low_search arguments
            if. status=_1 do.
                aborted =. 1
                break.
            elseif. status=0 do.
                pruned =. pruned+1
                children =. children,<'-'
                continue.
            end.
            new_paths =. (<child_path)affected}0{::node
            metadata =. generated,(1+3{::node),2{::node
            child =. metadata new_node(<new_paths),(<restrictions),<CostId
            nodes =. nodes,<child
            heap =. heap heap_push node_key child
            children =. children,<integer generated
            generated =. generated+1
        end.
        if. aborted do.
            reason =. 'll_budget'
            break.
        end.
        parent =. '-'
        if. _1~:4{::node do.
            parent =. integer 4{::node
        end.
        line =. 'expand ',(integer expanded),' node ',(integer number),' parent ',parent,' depth ',integer 3{::node
        line =. line,' cost ',(integer 6{::node),' conflicts ',(integer #conflicts),' split ',conflict_text conflict
        if. category~:_1 do.
            line =. line,' class ',category{::Classes
        end.
        RTrace =: RTrace,<line,' children ',' 'join children
    end.
    cbs_summary(<expanded),(<generated),(<pruned),(<#heap),<classifications
    if. 0=#answer do.
        RReason =: reason
        REnd =: 'end FAIL ',reason
    else.
        RStatus =: 1
        RPaths =: 0{::answer
        line =. 'solution node ',(integer 2{::answer),' depth ',integer 3{::answer
        RSpecific =: RSpecific,(<line),constraint_lines 1{::answer
        REnd =: 'end OK node ',(integer 2{::answer),' cost ',integer 6{::answer
    end.
)
solve_whca =: 3 : 0
    current =. Starts
    executed =. <"0 Starts
    time =. 0
    rounds =. 0
    reason =. ''
    while. -.current-:Goals do.
        if. time>:Horizon do.
            reason =. 'timeout'
            break.
        end.
        rounds =. rounds+1
        restrictions =. empty_prohibitions ''
        order =. (I.current~:Goals),I.current=Goals
        plans =. NumberAgents$<i.0
        failed =. 0
        for_agent. order do.
            arguments =. (<agent),(<agent{current),(<time),(<restrictions),(<time+WindowSize),<1
            'status path expanded' =. low_search arguments
            if. status=_1 do.
                reason =. 'll_budget'
                failed =. 1
                break.
            end.
            line =. 'round ',(integer rounds),' time ',(integer time),' agent ',agent_name agent
            if. status=0 do.
                RTrace =: RTrace,<line,' blocked expansions ',integer expanded
                reason =. 'blocked'
                failed =. 1
                break.
            end.
            path =. path,((1+WindowSize)-#path)${:path
            plans =. (<path)agent}plans
            RTrace =: RTrace,<line,' moves ',(action_string path),' expansions ',integer expanded
            restrictions =. restrictions reserve_path(<path),(<time),<0
        end.
        if. failed do.
            break.
        end.
        for_agent. i.NumberAgents do.
            plan =. agent{::plans
            path =. (agent{::executed),WindowStep{.}.plan
            executed =. (<path)agent}executed
            current =. (WindowStep{plan)agent}current
        end.
        time =. time+WindowStep
    end.
    RHigh =: rounds
    RSpecific =: ,<'window ',(integer WindowSize),' step ',(integer WindowStep),' rounds ',integer rounds
    if. #reason do.
        RReason =: reason
        REnd =: 'end FAIL ',reason
    else.
        RStatus =: 1
        RPaths =: 0$a:
        for_agent. i.NumberAgents do.
            path =. agent{::executed
            goal =. agent{Goals
            while. 1<#path do.
                if. (({:path)=goal)*.(_2{path)=goal do.
                    path =. }:path
                else.
                    break.
                end.
            end.
            RPaths =: RPaths,<path
        end.
        REnd =: 'end OK rounds ',integer rounds
    end.
)

validate_plan =: 3 : 0
    paths =. y
    start =. 0
    goal =. 0
    moves =. 0
    for_agent. i.NumberAgents do.
        path =. agent{::paths
        start =. start+({.path)~:agent{Starts
        goal =. goal+({:path)~:agent{Goals
        for_i. 1+i.(#path)-1 do.
            source =. (i-1){path
            destination =. i{path
            moves =. moves+-.destination e.source{::Destinations
        end.
    end.
    conflicts =. plan_conflicts paths
    vertex =. +/0=0{"1 conflicts
    edge =. (#conflicts)-vertex
    horizon =. >./(#&>paths)-1
    follows =. 0
    for_time. 1+i.horizon do.
        for_first. i.NumberAgents do.
            path_a =. first{::paths
            past_a =. (time-1)path_position path_a
            next_a =. time path_position path_a
            if. next_a=past_a do.
                continue.
            end.
            for_second. (i.NumberAgents)-.first do.
                path_b =. second{::paths
                past_b =. (time-1)path_position path_b
                next_b =. time path_position path_b
                follows =. follows+(next_a=past_b)*.next_b~:past_a
            end.
        end.
    end.
    counts =. start,goal,moves,vertex,edge,follows
    valid =. 0=+/5{.counts
    (<valid),(<counts),<conflicts
)
plan_statistics =: 4 : 0
    paths =. y
    lengths =. (#&>paths)-1
    soc =. +/lengths
    span =. >./lengths
    cost =. soc
    lower =. LowerSoc
    if. x do.
        cost =. span
        lower =. LowerSpan
    end.
    per_agent =. 0 6$0
    actions =. 0$a:
    traffic =. NumberCells$0
    cell_waits =. NumberCells$0
    for_agent. i.NumberAgents do.
        path =. agent{::paths
        length =. ( #path)-1
        differences =. (}.path)-}:path
        waits =. +/differences=0
        moves =. differences#~differences~:0
        turns =. 0
        if. 1<#moves do.
            turns =. +/(}.moves)~:}:moves
        end.
        goal =. agent{Goals
        arrive =. path i.goal
        leaves =. +/((}:path)=goal)*.(}.path)~:goal
        extra =. length-agent{Shortest
        per_agent =. per_agent,length,extra,waits,turns,arrive,leaves
        actions =. actions,<action_string path
        cells =. ~.path
        traffic =. (1+cells{traffic)cells}traffic
        for_i. I.differences=0 do.
            cell =. i{path
            cell_waits =. ((cell{cell_waits)+1)cell}cell_waits
        end.
    end.
    arrivals =. i.0
    for_time. i.span+1 do.
        arrivals =. arrivals,+/lengths<:time
    end.
    cells =. I.traffic>0
    keys =. (-cells{traffic),.cells
    hotspots =. (5<.#cells){.( /:keys){cells
    sum_extra =. +/1{"1 per_agent
    max_extra =. >./1{"1 per_agent
    total_waits =. +/2{"1 per_agent
    total_turns =. +/3{"1 per_agent
    result =. (<soc),(<span),(<cost),(<cost fraction lower),(<per_agent),(<actions),(<arrivals)
    result,(<traffic),(<cell_waits),(<hotspots),(<sum_extra),(<max_extra),(<total_waits),<total_turns
)
delayed_execution =: 3 : 0
    paths =. y
    steps =. 0$a:
    for_path. paths do.
        path =. >path
        entries =. ,:0,{.path
        for_time. 1+i.(#path)-1 do.
            if. (time{path)~:(time-1){path do.
                entries =. entries,time,time{path
            end.
        end.
        steps =. steps,<entries
    end.
    prerequisites =. 0$a:
    for_agent. i.NumberAgents do.
        entries =. agent{::steps
        requested =. ,<0 2$0
        for_index. 1+i.(#entries)-1 do.
            'scheduled cell' =. index{entries
            required =. 0 2$0
            for_other. (i.NumberAgents)-.agent do.
                earlier =. other{::steps
                for_k. i.#earlier do.
                    'time other_cell' =. k{earlier
                    if. (other_cell=cell)*.time<scheduled do.
                        required =. required,other,k
                    end.
                end.
            end.
            requested =. requested,<required
        end.
        prerequisites =. prerequisites,<requested
    end.
    maxima =. (#&>steps)-1
    progress =. NumberAgents$0
    finish =. NumberAgents$_1
    holds =. 0
    time =. 0
    while. +./progress<maxima do.
        advancing =. i.0
        stopped =. 0
        for_agent. I.progress<maxima do.
            delayed =. +/(agent=0{"1 Delays)*.(time>:1{"1 Delays)*.time<(1{"1 Delays)+2{"1 Delays
            if. delayed do.
                stopped =. stopped+1
                continue.
            end.
            index =. 1+agent{progress
            required =. index{::agent{::prerequisites
            allowed =. 1
            for_requirement. required do.
                'other step' =. requirement
                if. (other{progress)<:step do.
                    allowed =. 0
                    break.
                end.
            end.
            if. allowed do.
                advancing =. advancing,agent
            else.
                holds =. holds+1
            end.
        end.
        if. (0=#advancing)*.stopped=0 do.
            (<time),(<holds),(<finish),(<_1),<_1 return.
        end.
        for_agent. advancing do.
            progress =. (1+agent{progress)agent}progress
            if. (agent{progress)=agent{maxima do.
                finish =. (time+1)agent}finish
            end.
        end.
        time =. time+1
    end.
    (<_1),(<holds),(<finish),(<+/finish),<>./finish
)
run_solvers =: 3 : 0
    Results =: 0$a:
    for_definition. RunDefinitions do.
        start_run >definition
        select. Solver
        case. 'PP' do. solve_pp ''
        case. 'CBS';'ICBS' do. solve_cbs ''
        case. 'WHCA' do. solve_whca ''
        end.
        metrics =. 0$a:
        validation =. 0$a:
        execution =. 0$a:
        if. RStatus do.
            metrics =. CostId plan_statistics RPaths
            validation =. validate_plan RPaths
            execution =. delayed_execution RPaths
        end.
        result =. (<RName),(<Solver),(<CostFunction),(<RStatus),(<RReason),(<RPaths)
        result =. result,(<RHigh),(<RGenerated),(<LLSearches),(<LLExpansions),(<RSpecific),(<RTrace),(<REnd)
        Results =: Results,<result,(<metrics),(<validation),<execution
    end.
)
instance_lines =: 3 : 0
    line =. 'instance width ',(integer GridWidth),' height ',(integer GridHeight)
    lines =. <line,' free ',(integer #FreeCells),' agents ',integer NumberAgents
    line =. 'map isolated ',(integer 0{DegreeCounts),' dead_ends ',integer 1{DegreeCounts
    line =. line,' corridors ',(integer 2{DegreeCounts),' junctions ',integer 3{DegreeCounts
    lines =. lines,<line,' components ',integer Components
    for_agent. i.NumberAgents do.
        line =. 'agent ',(agent_name agent),' start ',cell_text agent{Starts
        line =. line,' goal ',(cell_text agent{Goals),' distance ',integer agent{Shortest
        lines =. lines,<line,' mdd ',(integer agent{MddStates),' width ',integer agent{MddWidths
    end.
    lines =. lines,<'lower_bound soc ',(integer LowerSoc),' makespan ',integer LowerSpan
    vertices =. +/0=0{"1 BaselineConflicts
    line =. 'independent conflicts ',(integer #BaselineConflicts),' vertex ',integer vertices
    line =. line,' edge ',(integer (#BaselineConflicts)-vertices)
    for_class. i.3 do.
        line =. line,' ',(class{::Classes),' ',integer +/BaselineClasses=class
    end.
    lines =. lines,<line
    groups =. '-'
    if. #ConflictGroups do.
        groups =. ' 'join ConflictGroups
    end.
    lines,<'groups ',groups
)
successful_run_lines =: 3 : 0
    metrics =. 13{::y
    line =. 'run ',(0{::y),' solver ',(1{::y),' cost_function ',(2{::y),' result OK'
    line =. line,' cost ',(integer 2{::metrics),' soc ',integer 0{::metrics
    lines =. <line,' makespan ',(integer 1{::metrics),' ratio ',3{::metrics
    lines =. lines,10{::y
    per_agent =. 4{::metrics
    actions =. 5{::metrics
    for_agent. i.NumberAgents do.
        'cost extra waits turns arrive leave' =. agent{per_agent
        line =. 'agent ',(agent_name agent),' cost ',(integer cost),' extra ',integer extra
        line =. line,' waits ',(integer waits),' turns ',(integer turns),' arrive ',integer arrive
        lines =. lines,<line,' leave ',(integer leave),' moves ',agent{::actions
    end.
    lines =. lines,<'arrivals ',numbers 6{::metrics
    traffic =. 7{::metrics
    entries =. 0$a:
    for_cell. 9{::metrics do.
        entries =. entries,<(cell_text cell),':',integer cell{traffic
    end.
    lines =. lines,<'hotspots ',' 'join entries
    execution =. 15{::y
    if. _1=0{::execution do.
        line =. 'execution soc ',(integer 3{::execution),' makespan ',integer 4{::execution
        lines =. lines,<line,' blocked ',(integer 1{::execution),' finish ',numbers 2{::execution
    else.
        lines =. lines,<'execution deadlock time ',integer 0{::execution
    end.
    lines
)
solution_lines =: 3 : 0
    lines =. instance_lines ''
    successful =. i.0
    for_i. i.#Results do.
        result =. i{::Results
        lines =. lines,<''
        if. 3{::result do.
            lines =. lines,successful_run_lines result
            successful =. successful,i
        else.
            line =. 'run ',(0{::result),' solver ',(1{::result),' cost_function ',2{::result
            lines =. lines,<line,' result FAIL reason ',4{::result
            lines =. lines,10{::result
        end.
    end.
    lines =. lines,<''
    lines =. lines,<'summary ok ',(integer #successful),' failed ',integer (#Results)-#successful
    if. 0=#successful do.
        lines return.
    end.
    costs =. 0 3$0
    for_i. successful do.
        metrics =. 13{::i{::Results
        costs =. costs,(0{::metrics),(1{::metrics),i
    end.
    for_column. i.2 do.
        values =. column{"1 costs
        best =. <./values
        selected =. successful#~values=best
        names =. 0$a:
        for_i. selected do.
            names =. names,<0{::i{::Results
        end.
        label =. 'best_soc'
        if. column do.
            label =. 'best_makespan'
        end.
        lines =. lines,<label,' ',(integer best),' ',' 'join names
    end.
    names =. 0$a:
    for_i. (/:costs){successful do.
        names =. names,<0{::i{::Results
    end.
    lines,<'ranking ',' 'join names
)
stats_lines =: 3 : 0
    line =. 'run,solver,cost_function,result,reason,cost,soc,makespan,sum_extra,max_extra,waits,turns'
    lines =. <line,',exec_soc,exec_makespan,high_level,generated,searches,expansions'
    for_result. Results do.
        result =. >result
        fields =. 3{.result
        if. 3{::result do.
            fields =. fields,'OK';'-'
            metrics =. 13{::result
            values =. (2{::metrics),(0{::metrics),(1{::metrics),(10{::metrics),(11{::metrics)
            values =. values,(12{::metrics),13{::metrics
            fields =. fields,integer&.>values
            execution =. 15{::result
            if. _1=0{::execution do.
                fields =. fields,integer&.>(3{::execution),4{::execution
            else.
                fields =. fields,'-';'-'
            end.
        else.
            fields =. fields,(<'FAIL'),(<4{::result),9$<'-'
        end.
        fields =. fields,<integer 6{::result
        generated =. '-'
        if. _1~:7{::result do.
            generated =. integer 7{::result
        end.
        fields =. fields,(<generated),integer&.>(8{::result),9{::result
        lines =. lines,<','join fields
    end.
    lines
)
validation_block =: 4 : 0
    'name independent' =. x
    'valid counts conflicts' =. y
    verdict =. 'INVALID'
    if. valid do.
        verdict =. 'VALID'
    end.
    line =. 'plan ',name,' verdict ',verdict
    labels =. ;:'start goal moves vertex edge follows'
    for_i. i.6 do.
        line =. line,' ',(i{::labels),' ',integer i{counts
    end.
    lines =. <line
    for_i. i.#conflicts do.
        line =. '  ',conflict_text i{conflicts
        if. independent do.
            line =. line,' ',(i{BaselineClasses){::Classes
        end.
        lines =. lines,<line
    end.
    lines
)
validation_lines =: 3 : 0
    lines =. ('INDEPENDENT';1)validation_block validate_plan BaselinePaths
    for_result. Results do.
        result =. >result
        if. 3{::result do.
            lines =. lines,((<0{::result),<0)validation_block 14{::result
        else.
            lines =. lines,<'plan ',(0{::result),' verdict NONE'
        end.
    end.
    lines
)
trace_lines =: 3 : 0
    lines =. 0$a:
    for_i. i.#Results do.
        result =. i{::Results
        if. i do.
            lines =. lines,<''
        end.
        lines =. lines,<'run ',0{::result
        lines =. lines,11{::result
        lines =. lines,<12{::result
    end.
    lines
)
animation_lines =: 3 : 0
    names =. 0$a:
    for_result. Results do.
        names =. names,<0{::>result
    end.
    selected =. (names i.<AnimateName){::Results
    if. -.3{::selected do.
        ,<'run ',AnimateName,' FAIL' return.
    end.
    paths =. 5{::selected
    lengths =. (#&>paths)-1
    lines =. <'run ',AnimateName,' frames ',integer Frames
    for_time. i.Frames do.
        done =. +/time>:lengths
        moving =. 0
        cells =. GridCells
        for_agent. i.NumberAgents do.
            cells =. (a.{~97+agent)(agent{Goals)}cells
        end.
        for_agent. i.NumberAgents do.
            path =. agent{::paths
            cell =. time path_position path
            cells =. (agent_name agent)cell}cells
            if. (time<agent{lengths)*.time>:1 do.
                moving =. moving+cell~:(time-1)path_position path
            end.
        end.
        waiting =. NumberAgents-(done+moving)
        line =. 'frame ',(integer time),' done ',(integer done),' moving ',integer moving
        lines =. lines,(<''),(<line,' waiting ',integer waiting),picture cells
    end.
    metrics =. 13{::selected
    for_column. 7 8 do.
        label =. 'traffic'
        if. column=8 do.
            label =. 'waits'
        end.
        cells =. GridCells
        counts =. column{::metrics
        for_cell. FreeCells do.
            count =. cell{counts
            symbol =. '.'
            if. count>:10 do.
                symbol =. '+'
            elseif. count>0 do.
                symbol =. a.{~48+count
            end.
            cells =. symbol cell}cells
        end.
        lines =. lines,(<''),(<label),picture cells
    end.
    lines
)
run =: 3 : 0
    read_grid_agents ''
    read_parameters ''
    prepare_instance ''
    run_solvers ''
    try.
        1!:5 <'output'
    catch.
    end.
    'solutions.txt'write_lines solution_lines ''
    'stats.csv'write_lines stats_lines ''
    'validation.txt'write_lines validation_lines ''
    'trace.txt'write_lines trace_lines ''
    'frames.txt'write_lines animation_lines ''
)
run ''
