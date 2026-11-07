split =: 4 : '<;._1 x,y'
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
num =: 3 : 'x: 0".y'
intdiv =: 4 : '<.(x: x)%x: y'
text =: 3 : 0
    if. 2=3!:0 y do.
        y return.
    end.
    value =. ":y
    '-'(I.value='_')}value
)
line =: 3 : ''' ''join text&.>y'
integers =: 3 : ''' ''join text&.><"0 y'
percentage =: 4 : 0
    tenths =. ((2000*x)+y)intdiv 2*y
    (":tenths intdiv 10),'.',(":10|tenths),'%'
)
machine_name =: 3 : '''M'',":y'
load 'instance.ijs'
load 'minstd.ijs'
load 'dispatch_rules.ijs'
load 'genetic.ijs'
load 'gantt.ijs'
s_starts =: 0&{::
s_completions =: 1&{::
s_makespan =: 2&{::
s_order =: 3&{::
s_prev =: 4&{::
s_next =: 5&{::
makespan =: 4 : '>./x+y'
order_starts =: 4 : 0
    order =. y
    starts =. Count$_1
    completions =. Count$0
    positions =. MachineCount$0
    placed =. 0
    while. placed<Count do.
        for_machine. i.MachineCount do.
            sequence =. machine{::order
            while. (machine{positions)<#sequence do.
                position =. machine{positions
                ident =. position{sequence
                previous =. (<ident,7){Operations
                if. previous>:0 do.
                    if. (previous{starts)<0 do.
                        break.
                    end.
                end.
                ready =. free =. 0
                if. previous>:0 do.
                    ready =. previous{completions
                end.
                if. position>0 do.
                    free =. ((position-1){sequence){completions
                end.
                start =. ready>.free
                starts =. start ident}starts
                completions =. (start+ident{x)ident}completions
                positions =. (position+1)machine}positions
                placed =. placed+1
            end.
        end.
    end.
    starts
)
make_schedule =: 3 : 0
    starts =. y
    completions =. starts+Durations
    value =. >./completions
    order =. MachineCount$<i.0
    previous =. following =. Count$_1
    for_ident. /:starts do.
        machine =. _1+(<ident,3){Operations
        sequence =. machine{::order
        if. #sequence do.
            before =. {:sequence
            previous =. before ident}previous
            following =. ident before}following
        end.
        order =. (<sequence,ident)machine}order
    end.
    (<starts),(<completions),(<value),(<order),(<previous),<following
)
schedule_order =: 3 : 'make_schedule Durations order_starts y'
by_start =: /:@s_starts
chromosome =: 3 : '1{"1 (by_start y){Operations'
critical_path =: 3 : 0
    starts =. s_starts y
    completions =. s_completions y
    previous =. s_prev y
    current =. completions i.s_makespan y
    reverse =. i.0
    while. 1 do.
        reverse =. reverse,current
        if. 0=current{starts do.
            break.
        end.
        before =. current{previous
        if. before>:0 do.
            if. (before{completions)=current{starts do.
                current =. before continue.
            end.
        end.
        current =. (<current,7){Operations
    end.
    |.reverse
)
path_blocks =: 3 : 0
    result =. 0$a:
    for_ident. y do.
        machine =. (<ident,3){Operations
        same =. 0
        if. #result do.
            last =. {:> {:result
            same =. machine=(<last,3){Operations
        end.
        if. same do.
            result =. (<(>{:result),ident)(<:#result)}result
        else.
            result =. result,<,ident
        end.
    end.
    result
)
moves =: 3 : 0
    result =. 0 2$0
    for_block. path_blocks critical_path y do.
        block =. >block
        for_i. i.<:#block do.
            result =. result,(i,i+1){block
        end.
    end.
    result
)
path_count =: 3 : 0
    ways =. Count$0
    starts =. s_starts y
    completions =. s_completions y
    previous =. s_prev y
    for_ident. by_start y do.
        value =. 0
        if. 0=ident{starts do.
            value =. 1
        else.
            sources =. ((<ident,7){Operations),ident{previous
            for_source. sources do.
                if. source>:0 do.
                    if. (source{completions)=ident{starts do.
                        value =. value+source{ways
                    end.
                end.
            end.
        end.
        ways =. value ident}ways
    end.
    +/ways#~completions=s_makespan y
)
left_shift =: 4 : 0
    ident =. y
    starts =. s_starts x
    completions =. s_completions x
    machine =. _1+(<ident,3){Operations
    sequence =. machine{::s_order x
    position =. sequence i.ident
    if. position=0 do.
        _1 _1 return.
    end.
    previous =. (<ident,7){Operations
    ready =. 0
    if. previous>:0 do.
        ready =. previous{completions
    end.
    for_insertion. i.position do.
        begin =. 0
        if. insertion>0 do.
            begin =. ((insertion-1){sequence){completions
        end.
        start =. begin>.ready
        if. (start+ident{Durations)<:(insertion{sequence){starts do.
            start,insertion return.
        end.
    end.
    _1 _1
)
shiftable_count =: 3 : 0
    count =. 0
    for_ident. i.Count do.
        count =. count+0<:{.y left_shift ident
    end.
    count
)
slacks =: 3 : 0
    latest =. slack =. free =. Count$0
    starts =. s_starts y
    completions =. s_completions y
    following =. s_next y
    for_ident. |.by_start y do.
        latest_limit =. start_limit =. s_makespan y
        successors =. ((<ident,8){Operations),ident{following
        for_successor. successors#~successors>:0 do.
            latest_limit =. latest_limit<.successor{latest
            start_limit =. start_limit<.successor{starts
        end.
        value =. latest_limit-ident{Durations
        latest =. value ident}latest
        slack =. (value-ident{starts)ident}slack
        free =. (start_limit-ident{completions)ident}free
    end.
    (<slack),<free
)
path_counts =: 3 : '+/"1 (1+i.MachineCount)=/3{"1 y{Operations'
bottleneck =: 3 : 0
    counts =. path_counts y
    counts i.>./counts
)
flow_time =: 3 : 0
    total =. 0
    completions =. s_completions y
    for_job. JobNumbers do.
        total =. total+({:job{::JobOps){completions
    end.
    total
)
total_idle =: 3 : '(MachineCount*s_makespan y)-+/Durations'
letters =: 4 : ';job_letter&.>1{"1 (x{::s_order y){Operations'
apply_move =: 4 : 0
    'first second' =. y
    machine =. _1+(<first,3){Operations
    sequence =. machine{::x
    position =. sequence i.first
    sequence =. (second,first)(position,position+1)}sequence
    (<sequence)machine}x
)
distances =: 4 : 0
    result =. i.0
    for_machine. i.MachineCount do.
        first =. machine{::s_order x
        second =. machine{::s_order y
        rank =. second i.first
        count =. 0
        for_low. i.#rank do.
            count =. count++/(low{rank)>(low+1)}.rank
        end.
        result =. result,count
    end.
    result
)
jackson_bound =: 3 : 0
    ids =. y
    remaining =. ids{Durations
    time =. bound =. 0
    while. +./remaining>0 do.
        pending =. I.remaining>0
        time =. time>.<./5{"1 (pending{ids){Operations
        released =. pending#~time>:5{"1 (pending{ids){Operations
        chosen =. {.released
        for_position. }.released do.
            row =. (position{ids){Operations
            old =. (chosen{ids){Operations
            if. ((6{row)>6{old)+.(((6{row)=6{old)*.(1{row)<1{old) do.
                chosen =. position
            end.
        end.
        step =. chosen{remaining
        later =. (5{"1 ids{Operations)#~time<5{"1 ids{Operations
        if. #later do.
            step =. step<.(<./later)-time
        end.
        time =. time+step
        remaining =. ((chosen{remaining)-step)chosen}remaining
        if. 0=chosen{remaining do.
            bound =. bound>.time+(<(chosen{ids),6){Operations
        end.
    end.
    bound
)
tabu_search =: 3 : 0
    current =. best_order =. y
    start =. best =. s_makespan schedule_order y
    found =. 0
    records =. 0$a:
    reason =. 'limit'
    expiry_keys =. 0 2$0
    expiries =. i.0
    for_iteration. 1+i.TabuIterations do.
        candidates =. moves schedule_order current
        if. 0=#candidates do.
            reason =. 'no_moves' break.
        end.
        values =. i.0
        blocked =. i.0
        chosen =. _1
        tabu_count =. 0
        for_position. i.#candidates do.
            move =. position{candidates
            value =. s_makespan schedule_order current apply_move move
            values =. values,value
            index =. expiry_keys i.move
            forbidden =. 0
            if. index<#expiries do.
                forbidden =. (index{expiries)>:iteration
            end.
            blocked =. blocked,forbidden
            tabu_count =. tabu_count+forbidden
            if. (-.forbidden)+.value<best do.
                if. chosen<0 do.
                    chosen =. position
                elseif. value<chosen{values do.
                    chosen =. position
                end.
            end.
        end.
        if. chosen<0 do.
            reason =. 'all_tabu' break.
        end.
        selected =. chosen{candidates
        current =. current apply_move selected
        reversed =. |.selected
        index =. expiry_keys i.reversed
        expiry =. iteration+TabuTenure
        if. index=#expiries do.
            expiry_keys =. expiry_keys,reversed
            expiries =. expiries,expiry
        else.
            expiries =. expiry index}expiries
        end.
        value =. chosen{values
        if. value<best do.
            best_order =. current
            best =. value
            found =. iteration end.
        records =. records,<(<iteration),(<#candidates),(<tabu_count),(<selected),(<chosen{blocked),(<value),<best
    end.
    (<start),(<best_order),(<best),(<found),(<records),<reason
)
activate =: 3 : 0
    current =. y
    shifts =. 0 3$0
    while. 1 do.
        schedule =. schedule_order current
        selected =. _1
        for_ident. by_start schedule do.
            'start insertion' =. schedule left_shift ident
            if. start>:0 do.
                selected =. ident break.
            end.
        end.
        if. selected<0 do.
            (<current),<shifts return.
        end.
        machine =. _1+(<selected,3){Operations
        remaining =. machine{::current
        remaining =. remaining-.selected
        sequence =. (insertion{.remaining),selected,insertion}.remaining
        current =. (<sequence)machine}current
        shifts =. shifts,selected,(selected{s_starts schedule),start
    end.
)
mutate =: 3 : 0
    child =. y
    if. chance SwapProbability do.
        Swaps =: Swaps+1
        child =. swap_mutation child end.
    if. chance InsertProbability do.
        Inserts =: Inserts+1
        child =. insert_mutation child end.
    child
)
run_ga =: 3 : 0
    RngState =: Seed
    Population =: chromosome&.>Baselines
    basic =. i.0
    for_job. JobNumbers do.
        basic =. basic,(#job{::JobOps)#job
    end.
    while. (#Population)<PopulationSize do.
        Population =: Population,<shuffle basic
    end.
    Crossovers =: Swaps =: Inserts =: 0
    GARecords =: 0 3$0
    Progress =: ,<'generation,best,mean,worst,distinct'
    previous_best =. 2147483647
    for_generation. i.Generations+1 do.
        Values =: >./"1 Durations +"1 decode&>Population
        Ranked =: /:Values
        best =. {.Ranked
        value =. best{Values
        if. value<previous_best do.
            GARecords =: GARecords,generation,value,best+1
        end.
        previous_best =. value
        if. generation e.Checkpoints do.
            total =. +/Values
            divisor =. total+.#Values
            mean =. (":total intdiv divisor),'/',":(#Values)intdiv divisor
            fields =. generation;value;mean;(>./Values);#~.Population
            Progress =: Progress,<','join text&.>fields
        end.
        if. generation=Generations do.
            break.
        end.
        offspring =. (Elitism{.Ranked){Population
        for_pair. i.(PopulationSize-Elitism)intdiv 2 do.
            first =. (Values tournament TournamentSize){::Population
            second =. (Values tournament TournamentSize){::Population
            if. chance CrossoverProbability do.
                Crossovers =: Crossovers+1
                'first second' =. first crossover second
            end.
            first =. mutate first
            second =. mutate second
            offspring =. offspring,(<first),<second
        end.
        Population =: offspring
    end.
    i.0
)
load_parameters =: 3 : 0
    rows =. 0$a:
    for_row. <;._2 (1!:1 <y) do.
        rows =. rows,<' 'split >row
    end.
    Seed =: num 1{::0{::rows
    PopulationSize =: num 1{::1{::rows
    Generations =: num 1{::2{::rows
    TournamentSize =: num 1{::3{::rows
    CrossoverProbability =: num&>'/'split 1{::4{::rows
    SwapProbability =: num&>'/'split 1{::5{::rows
    InsertProbability =: num&>'/'split 1{::6{::rows
    Elitism =: num 1{::7{::rows
    Checkpoints =: num&>}.8{::rows
    TabuIterations =: num 1{::9{::rows
    TabuTenure =: num 1{::10{::rows
    GanttWidth =: num 1{::11{::rows
    i.0
)
write_lines =: 4 : 0
    result =. ''
    for_value. y do.
        result =. result,(>value),LF
    end.
    result 1!:2 <'output/',x
)
build_reports =: 3 : 0
    ga =. GASchedule
    final =. Final
    starts =. s_starts final
    completions =. s_completions final
    value =. s_makespan final
    path =. critical_path final
    blocks =. path_blocks path
    'slack free' =. slacks final
    baseline_lines =. ,<line 'INSTANCE';'jobs';(#JobNumbers);'machines';MachineCount;'operations';Count;'work';(+/Durations);'errors';#Errors
    baseline_lines =. baseline_lines,('ERROR '&,)&.>Errors
    for_position. i.#JobNumbers do.
        job =. position{JobNumbers
        operations =. job{::JobOps
        route =. ' 'join machine_name&.>3{"1 operations{Operations
        baseline_lines =. baseline_lines,<line ('JOB J',":job);'operations';(#operations);'work';(position{JobWork);'route';route
    end.
    for_machine. i.MachineCount do.
        baseline_lines =. baseline_lines,<line ('MACHINE M',":machine+1);'operations';(#machine{::MachineOps);'load';(machine{Loads);'head';(machine{Heads);'tail';(machine{Tails);'bound';(machine{Bounds);'jackson';machine{Jacksons
    end.
    baseline_lines =. baseline_lines,(<line 'BOUND';'job';(JobBound{JobWork);'J',":JobBound{JobNumbers),(<line 'BOUND';'machine';(MachineBound{Bounds);'M',":MachineBound+1),(<line 'BOUND';'jackson';(JacksonMachine{Jacksons);'M',":JacksonMachine+1),<line 'BOUND';'lower';Lower
    best_baseline =. 0
    for_index. i.4 do.
        schedule =. index{::Baselines
        rule =. index{::Rules
        previous =. index{::BaselineSearches
        'old best_order best found records reason' =. previous
        baseline_path =. critical_path schedule
        'decisions ties' =. index{::DispatchCounts
        gap =. ((s_makespan schedule)-Lower)percentage Lower
        baseline_lines =. baseline_lines,<line 'RULE';rule;'makespan';(s_makespan schedule);'gap';gap;'flow';(flow_time schedule);'idle';(total_idle schedule);'decisions';decisions;'ties';ties
        baseline_lines =. baseline_lines,<line 'PATH';rule;'operations';(#baseline_path);'blocks';(#path_blocks baseline_path);'critical_paths';(path_count schedule);'bottleneck';'M',":1+bottleneck baseline_path
        baseline_lines =. baseline_lines,<line 'TABU';rule;'makespan';(s_makespan schedule);'->';best;'found';found;'iterations';(#records);'stop';reason
        if. (s_makespan schedule)<s_makespan best_baseline{::Baselines do.
            best_baseline =. index
        end.
    end.
    baseline_lines =. baseline_lines,<line 'BEST';(best_baseline{::Rules);'makespan';s_makespan best_baseline{::Baselines
    for_machine. i.MachineCount do.
        parts =. ,<'UTILIZATION M',":machine+1
        for_index. i.4 do.
            parts =. parts,< (index{::Rules),' ',(machine{Loads)percentage s_makespan index{::Baselines
        end.
        baseline_lines =. baseline_lines,<' 'join parts
    end.
    schedule_lines =. ,<line 'GA';'best';(s_makespan ga);'generation';((<(<:#GARecords),0){GARecords);'crossovers';Crossovers;'swaps';Swaps;'inserts';Inserts
    for_record. GARecords do.
        'generation record_value individual' =. record
        schedule_lines =. schedule_lines,<line 'RECORD';'generation';generation;'makespan';record_value;'individual';individual
    end.
    seen =. 0$a:
    top =. 0
    for_index. Ranked do.
        individual =. index{Population
        if. individual e.seen do.
            continue.
        end.
        seen =. seen,individual
        top =. top+1
        other =. make_schedule decode >individual
        schedule_lines =. schedule_lines,<line 'TOP';top;'individual';(index+1);'makespan';(index{Values);'distance';+/other distances ga
        if. top=5 do.
            break.
        end.
    end.
    schedule_lines =. schedule_lines,<'GA_CHROMOSOME ',integers BestChromosome
    schedule_lines =. schedule_lines,<line 'ACTIVE_DECODE';'makespan';ActiveValue;'decisions';ActiveDecisions
    for_index. i.#Shifts do.
        'ident old new' =. index{Shifts
        machine =. (<ident,3){Operations
        schedule_lines =. schedule_lines,<line 'SHIFT';(index+1);(operation_code ident);('M',":machine);'start';old;'->';new
    end.
    schedule_lines =. schedule_lines,<line 'ACTIVATED';'makespan';(s_makespan ga);'->';ActivatedValue;'shifts';#Shifts
    schedule_lines =. schedule_lines,<line 'SCHEDULE';'makespan';value;'lower_bound';Lower;'gap';((value-Lower)percentage Lower);'improvement';((s_makespan ga)-value);'shiftable';shiftable_count final
    schedule_lines =. schedule_lines,<'CHROMOSOME ',integers chromosome final
    legend =. 0$a:
    for_job. JobNumbers do.
        legend =. legend,<(job_letter job),'=J',":job
    end.
    schedule_lines =. schedule_lines,<'LEGEND ',' 'join legend
    'quantum columns' =. value chart_scale GanttWidth
    schedule_lines =. schedule_lines,(<line 'GANTT';'scale';quantum;'columns';columns),(<quantum time_row columns),<rule_row columns
    machine_intervals =. MachineCount$<0$a:
    for_ident. i.Count do.
        machine =. _1+(<ident,3){Operations
        mark =. job_letter (<ident,1){Operations
        if. ident e.path do.
            mark =. (32+a.i.mark){a.
        end.
        interval =. (<ident{starts),(<ident{completions),<mark
        machine_intervals =. (<(machine{::machine_intervals),<interval)machine}machine_intervals
    end.
    for_machine. i.MachineCount do.
        schedule_lines =. schedule_lines,<chart_row (<'M',":machine+1),(machine{machine_intervals),(<quantum),<columns
    end.
    schedule_lines =. schedule_lines,<busy_row (<machine_intervals),(<quantum),<columns
    for_job. JobNumbers do.
        intervals =. 0$a:
        for_ident. job{::JobOps do.
            mark =. ":10|(<ident,3){Operations
            intervals =. intervals,<(<ident{starts),(<ident{completions),<mark
        end.
        schedule_lines =. schedule_lines,<chart_row (<'J',":job),(<intervals),(<quantum),<columns
    end.
    for_machine. i.MachineCount do.
        parts =. ,<('ORDER M',(":machine+1),' FINAL ',machine letters final)
        for_index. i.4 do.
            parts =. parts,<(index{::Rules),' ',machine letters index{::Baselines
        end.
        schedule_lines =. schedule_lines,<' 'join parts
    end.
    for_machine. i.MachineCount do.
        sequence =. machine{::s_order final
        intervals =. description =. 0$a:
        gaps =. longest =. previous =. 0
        for_position. i.#sequence do.
            ident =. position{sequence
            start =. ident{starts
            completion =. ident{completions
            if. start>previous do.
                intervals =. intervals,<(":previous),'-',":start
                if. position>0 do.
                    gaps =. gaps+1
                    longest =. longest>.start-previous end.
            end.
            description =. description,<('J',(": (<ident,1){Operations)),':',(":start),'-',":completion
            previous =. completion
        end.
        if. previous<value do.
            intervals =. intervals,<(":previous),'-',":value
        end.
        schedule_lines =. schedule_lines,<line ('MACHINE M',":machine+1);'load';(machine{Loads);'idle';(value-machine{Loads);'utilization';((machine{Loads)percentage value);'gaps';gaps;'longest_gap';longest;'sequence';' 'join description
        idle =. 'none'
        if. #intervals do.
            idle =. ' 'join intervals
        end.
        schedule_lines =. schedule_lines,<line ('IDLE M',":machine+1);idle
    end.
    total_waiting =. 0
    for_position. i.#JobNumbers do.
        job =. position{JobNumbers
        operations =. job{::JobOps
        completion =. ({:operations){completions
        waiting =. completion-position{JobWork
        total_waiting =. total_waiting+waiting
        schedule_lines =. schedule_lines,<line ('JOB J',":job);'operations';(#operations);'work';(position{JobWork);'start';(({.operations){starts);'completion';completion;'waiting';waiting
    end.
    schedule_lines =. schedule_lines,<line 'TOTAL';'flow';(flow_time final);'waiting';total_waiting;'idle';total_idle final
    others =. Baselines,<ga
    labels =. Rules,<'GA'
    all_distances =. 0$a:
    for_other. others do.
        all_distances =. all_distances,<final distances >other
    end.
    totals =. 5$0
    total_pairs =. 0
    for_machine. i.MachineCount do.
        count =. #machine{::MachineOps
        pairs =. (count*count-1)intdiv 2
        total_pairs =. total_pairs+pairs
        parts =. ,<line ('DISTANCE M',":machine+1);'pairs';pairs
        for_index. i.5 do.
            distance =. machine{index{::all_distances
            parts =. parts,<(index{::labels),' ',":distance
            totals =. ((index{totals)+distance)index}totals
        end.
        schedule_lines =. schedule_lines,<' 'join parts
    end.
    parts =. ,<line 'DISTANCE';'total';'pairs';total_pairs
    for_index. i.5 do.
        parts =. parts,<(index{::labels),' ',":index{totals
    end.
    schedule_lines =. schedule_lines,<' 'join parts
    'search_start search_order search_best search_found search_records search_reason' =. Search
    critical_lines =. ,<line 'SEARCH';'start';search_start;'iterations';TabuIterations;'tenure';TabuTenure
    for_record. search_records do.
        'iteration move_count tabu_count move aspiration evaluation best' =. >record
        'first second' =. move
        kind =. 'free'
        if. aspiration do.
            kind =. 'aspiration'
        end.
        critical_lines =. critical_lines,<line 'ITER';iteration;'moves';move_count;'tabu';tabu_count;'swap';('M',":(<first,3){Operations);(operation_code first);(operation_code second);kind;'makespan';evaluation;'best';best
    end.
    critical_lines =. critical_lines,<line 'STOP';'iterations';(#search_records);'reason';search_reason;'best';search_best;'found';search_found
    critical_lines =. critical_lines,<line 'PATH';'operations';(#path);'blocks';(#blocks);'makespan';value;'critical_paths';path_count final
    for_position. i.#path do.
        ident =. position{path
        link =. 'start'
        if. position do.
            link =. 'job'
            if. (ident{s_prev final)=(position-1){path do.
                link =. 'machine'
            end.
        end.
        interval =. (":ident{starts),'-',":ident{completions
        critical_lines =. critical_lines,<line 'NODE';(position+1);(operation_code ident);('M',":(<ident,3){Operations);interval;link
    end.
    for_index. i.#blocks do.
        block =. index{::blocks
        interval =. (":({.block){starts),'-',":({:block){completions
        names =. ' 'join operation_code&.>block
        critical_lines =. critical_lines,<line 'BLOCK';(index+1);('M',":(<({.block),3){Operations);interval;names
    end.
    neighbours =. moves final
    for_index. i.#neighbours do.
        move =. index{neighbours
        'first second' =. move
        evaluation =. s_makespan schedule_order (s_order final)apply_move move
        critical_lines =. critical_lines,<line 'NEIGHBOUR';(index+1);('M',":(<first,3){Operations);(operation_code first);(operation_code second);'makespan';evaluation
    end.
    critical_lines =. critical_lines,<line 'CRITICAL';'operations';(+/slack=0);'total';Count
    for_job. JobNumbers do.
        critical_lines =. critical_lines,<('SLACK J',(":job),' ',integers (job{::JobOps){slack)
    end.
    for_job. JobNumbers do.
        critical_lines =. critical_lines,<('FREE J',(":job),' ',integers (job{::JobOps){free)
    end.
    counts =. path_counts path
    for_machine. i.MachineCount do.
        identifiers =. machine{::MachineOps
        critical =. +/0=identifiers{slack
        durations =. Durations
        increased =. (identifiers{durations)+(9+identifiers{durations)intdiv 10
        durations =. increased identifiers}durations
        sensitivity =. >./durations+durations order_starts s_order final
        critical_lines =. critical_lines,<line ('MACHINE M',":machine+1);'critical';critical;'path';(machine{counts);'sensitivity';sensitivity;'delta';sensitivity-value
    end.
    machine =. bottleneck path
    critical_lines =. critical_lines,<line ('BOTTLENECK M',":machine+1);'path';machine{counts
    try. 1!:5 <'output' catch. end.
    'baselines.txt'write_lines baseline_lines
    'ga_progress.csv'write_lines Progress
    'best_schedule.txt'write_lines schedule_lines
    'critical_path.txt'write_lines critical_lines
    i.0
)
run =: 3 : 0
    read_instance 'input/instance.txt'
    load_parameters 'input/ga_params.txt'
    Rules =: 'SPT';'LPT';'MWKR';'FIFO'
    Jacksons =: jackson_bound&>MachineOps
    JobBound =: JobWork i.>./JobWork
    MachineBound =: Bounds i.>./Bounds
    JacksonMachine =: Jacksons i.>./Jacksons
    Lower =: >./(JobBound{JobWork),(MachineBound{Bounds),JacksonMachine{Jacksons
    Baselines =: DispatchCounts =: BaselineSearches =: 0$a:
    for_rule. Rules do.
        'starts decisions ties' =. (>rule)giffler_thompson i.0
        schedule =. make_schedule starts
        Baselines =: Baselines,<schedule
        DispatchCounts =: DispatchCounts,<decisions,ties
        BaselineSearches =: BaselineSearches,<tabu_search s_order schedule
    end.
    run_ga 0
    BestChromosome =: ({.Ranked){::Population
    GASchedule =: make_schedule decode BestChromosome
    gene_ids =. gene_operations BestChromosome
    positions =. (1+i.Count)gene_ids}Count$0
    'active_starts ActiveDecisions active_ties' =: 'GENES'giffler_thompson positions
    ActiveValue =: Durations makespan active_starts
    'activated Shifts' =: activate s_order GASchedule
    ActivatedValue =: s_makespan schedule_order activated
    Search =: tabu_search activated
    Final =: schedule_order 1{::Search
    build_reports 0
)
run 0
