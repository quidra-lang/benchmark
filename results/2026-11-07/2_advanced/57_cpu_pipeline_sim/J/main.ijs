load 'trace_io.ijs'
load 'hazards.ijs'
load 'pipeline.ijs'
load 'predictors.ijs'
load 'report.ijs'
Classes =: ;:'ALU MUL LOAD STORE BRANCH JUMP NOP'
Causes =: ;:'control structural load_use raw'
Stages =: ;:'IF ID EX MEM WB'
MissKinds =: ;:'direction btb_miss wrong_target'
DistanceLabels =: ,&.>;:'1 2 3 4 5+'
control =: 3 : '(1{y)e.4 5'
cause_values =: 3 : 0
    result =. 0$a:
    for_i. i.4 do.
        result =. result,<(i{::Causes),' ',integer i{y
    end.
    ' 'join result
)
check_record =: 3 : 0
    fields =. split_words y
    if. (8~:#fields)+.(<,'')e.fields do.
        (<i.0),<'fields' return.
    end.
    pc =. parse_hex 0{::fields
    if. (pc<0)+.0~:4|pc do. (<i.0),<'pc' return. end.
    kind =. Classes i.<1{::fields
    if. kind=#Classes do. (<i.0),<'class' return. end.
    registers =. parse_register&>2 3 4{fields
    for_i. i.3 do.
        if. (_1=i{registers)*.-.(,'-')-:,(i+2){::fields do.
            (<i.0),<'register' return.
        end.
    end.
    usages =. kind{7 3$1 1 2 1 1 1 1 1 0 0 1 1 0 1 2 2 2 0 0 0 0
    if. +./((usages=1)*.registers<0)+.((usages=0)*.registers>:0) do.
        (<i.0),<'operands' return.
    end.
    outcome_text =. 5{::fields
    outcome =. _1
    if. (,'T')-:,outcome_text do. outcome =. 1 end.
    if. (,'N')-:,outcome_text do. outcome =. 0 end.
    invalid =. 0
    if. kind=4 do. invalid =. outcome<0
    elseif. kind=5 do. invalid =. outcome~:1
    else. invalid =. -.(,'-')-:,outcome_text
    end.
    if. invalid do. (<i.0),<'taken' return. end.
    target =. parse_hex 6{::fields
    if. kind e.4 5 do.
        invalid =. (target<0)+.(0~:4|target)+.target=pc+4
    else. invalid =. -.(,'-')-:,6{::fields
    end.
    if. invalid do. (<i.0),<'target' return. end.
    address =. parse_hex 7{::fields
    if. kind e.2 3 do.
        invalid =. (address<0)+.0~:4|address
    else. invalid =. -.(,'-')-:,7{::fields
    end.
    if. invalid do. (<i.0),<'address' return. end.
    next =. pc+4
    if. outcome=1 do. next =. target end.
    instruction =. pc,kind,registers,outcome,target,address,next
    previous_index =. ({."1 Instructions)i.pc
    if. previous_index<#Instructions do.
        previous =. previous_index{Instructions
        invalid =. -.((1+i.4){instruction)-:(1+i.4){previous
        if. (kind=4)+.((kind=5)*.0>1{registers) do.
            invalid =. invalid+.target~:6{previous
        end.
        if. invalid do. (<i.0),<'conflict' return. end.
    end.
    (<instruction),<''
)
validate_trace =: 3 : 0
    Instructions =: 0 9$0
    Rejected =: Gaps =: 0$a:
    InputLines =: #y
    for_i. i.#y do.
        'instruction reason' =. check_record i{::y
        if. #reason do.
            Rejected =: Rejected,<'reject line ',(integer i+1),' ',reason
        else.
            if. #Instructions do.
                previous =. 8{_1{Instructions
                if. previous~:{.instruction do.
                    Gaps =: Gaps,<'gap line ',(integer i+1),' expected ',(hexadecimal previous),' found ',hexadecimal {.instruction
                end.
            end.
            Instructions =: Instructions,instruction
        end.
    end.
    0
)
predict_trace =: 3 : 0
    definition =. y
    (BtbSize,RasDepth)initialize_predictor definition
    flags =. (#Instructions)$0
    details =. ((#Instructions),2)$_1
    statistics =. 15$0
    for_i. i.#Instructions do.
        instruction =. i{Instructions
        if. control instruction do.
            pc =. 0{instruction
            kind =. 1{instruction
            target =. 6{instruction
            taken =. 5{instruction
            candidate =. btb_lookup pc
            statistics =. statistics+0 0 0 0 0 0 0 0 0 1,(candidate>:0),0 0 0 0
            if. (kind=5)*.(0>2{instruction)*.31=3{instruction do.
                statistics =. (1+12{statistics)12}statistics
                address =. ras_pop ''
                if. address>:0 do.
                    candidate =. address
                    statistics =. (1+13{statistics)13}statistics
                    statistics =. ((14{statistics)+address=target)14}statistics
                end.
            end.
            if. (kind=5)*.31=2{instruction do.
                statistics =. (1+11{statistics)11}statistics
                ras_push pc+4
            end.
            predicted_taken =. 1
            if. kind=4 do. predicted_taken =. pc predict_direction target end.
            predicted =. pc+4
            if. 'PERFECT'-:1{::definition do.
                predicted =. 8{instruction
            elseif. predicted_taken*.candidate>:0 do.
                predicted =. candidate
            end.
            missed =. predicted~:8{instruction
            miss_kind =. _1
            if. missed do.
                miss_kind =. 2
                if. candidate<0 do. miss_kind =. 1 end.
                if. (kind=4)*.predicted_taken~:taken do. miss_kind =. 0 end.
                statistics =. (1+(6+miss_kind){statistics)(6+miss_kind)}statistics
                statistics =. (1+1{statistics)1}statistics
                slot =. 5-2*(kind=4)
                statistics =. (1+slot{statistics)slot}statistics
            end.
            flags =. missed i}flags
            details =. (predicted,miss_kind)i}details
            statistics =. (1+0{statistics)0}statistics
            slot =. 4-2*(kind=4)
            statistics =. (1+slot{statistics)slot}statistics
            if. kind=4 do. pc update_direction taken end.
            if. taken do. pc btb_insert target end.
        end.
    end.
    (<flags),(<details),(<statistics),<storage_bits ''
)
stall_totals =: 3 : 0
    totals =. 2 4$0
    for_record. y do.
        cause =. 0{record
        totals =. ((1{record)+(<0,cause){totals)(<0,cause)}totals
        totals =. (1+(<1,cause){totals)(<1,cause)}totals
    end.
    totals
)
all_combinations =: 3 : 0
    combinations =. 0$a:
    keys =. 0 3$a:
    for_v. i.#Variants do.
        variant =. v{::Variants
        for_p. i.#Definitions do.
            simulation =. variant simulate 0{::p{::Predictions
            totals =. stall_totals 1{::simulation
            record =. (<v),(<p),(<simulation),(<0{totals),<1{totals
            combinations =. combinations,<record
            keys =. keys,(<3{::simulation),(0{variant),0{p{::Definitions
        end.
    end.
    Combinations =: (/:keys){combinations
    Primary =: 0$a:
    for_combination. Combinations do.
        record =. >combination
        names =. (0{(0{::record){::Variants),0{(1{::record){::Definitions
        if. names-:PrimaryNames do. Primary =: record end.
    end.
    0
)
build_rows =: 3 : 0
    simulation =. 2{::Primary
    timings =. 0{::simulation
    prediction =. (1{::Primary){::Predictions
    flags =. 0{::prediction
    details =. 1{::prediction
    variant =. (0{::Primary){::Variants
    annotations =. (#Instructions)#<''
    for_record. 1{::simulation do.
        waiting =. 3{record
        if. waiting>:0 do.
            text =. (waiting{::annotations),' ',((0{record){::Causes),' ',integer 1{record
            annotations =. (<text)waiting}annotations
        end.
    end.
    rows =. 0$a:
    for_i. i.#Instructions do.
        instruction =. i{Instructions
        'f d x m w' =. i{timings
        annotation =. i{::annotations
        if. i{flags do.
            annotation =. annotation,' mispredict ',(1{i{details){::MissKinds
        end.
        characters =. 7 3$f,f,0,(f+1),(d-1),1,d,d,2,(d+1),(x-1),1,x,(m-1),3,m,m,4,w,w,5
        occupied =. 5 3$0,f,(d-1),1,d,(x-1),2,x,(m-1),3,m,m,4,w,w
        row =. (<i+1),(<0{instruction),((1{instruction){Classes),(<annotation),(<characters),<occupied
        rows =. rows,<row
        if. i{flags do.
            resolved =. (2{::variant)id_resolved instruction
            cancel =. x+-.resolved
            characters =. 3 3$d,d,0,(d+1),(x-1),1,cancel,cancel,6
            occupied =. 1 3$0,d,x-1
            if. -.resolved do.
                characters =. characters,x,x,2
                occupied =. occupied,1,x,x
            end.
            pc =. 0{i{details
            row =. (<_1),(<pc),(<'FLUSH'),(<''),(<characters),<occupied
            rows =. rows,<row
            if. -.resolved do.
                characters =. 2 3$x,x,0,(x+1),(x+1),6
                occupied =. 1 3$0,x,x
                row =. (<_1),(<pc+4),(<'FLUSH'),(<''),(<characters),<occupied
                rows =. rows,<row
            end.
        end.
    end.
    rows
)
pipeline_lines =: 3 : 0
    'first last' =. Window
    width =. 1+last-first
    lines =. (<'pipeline variant=',(0{::PrimaryNames),' predictor=',(1{::PrimaryNames),' cycles ',(integer first),'-',integer last),<cycle_heading Window
    contents =. (width,5)$<,'.'
    visible =. stalled =. flushed =. 0
    for_row. Rows do.
        'number pc kind annotation spans occupied' =. >row
        characters =. width$'.'
        for_span. spans do.
            'begin finish symbol' =. span
            start =. first>.begin
            count =. 0>.1+(last<.finish)-start
            characters =. (symbol{'F*DXMWx')((start-first)+i.count)}characters
        end.
        if. +./characters~:'.' do.
            visible =. visible+1
            stalled =. stalled++/'*'=characters
            flushed =. flushed++/'x'=characters
            left =. (<number),(<pc),(<kind),<annotation
            lines =. lines,<left diagram_row characters
        end.
        text =. ,'w'
        if. number>:0 do. text =. integer number end.
        for_span. occupied do.
            'stage begin finish' =. span
            start =. first>.begin
            count =. 0>.1+(last<.finish)-start
            for_cycle. start+i.count do.
                contents =. (<text)(<(cycle-first),stage)}contents
            end.
        end.
    end.
    timing =. 0{::2{::Primary
    completed =. +/(first<:4{"1 timing)*.last>:4{"1 timing
    lines =. lines,(<'rows ',(integer visible),' completed ',(integer completed),' stall_cells ',(integer stalled),' flushed ',integer flushed),(<' '),((<'stages'),<'cycle IF ID EX MEM WB')
    lines =. (<'')((#lines)-3)}lines
    for_cycle. first+i.width do.
        lines =. lines,<(integer cycle),' ',' 'join (cycle-first){contents
    end.
    lines
)
accuracy =: 4 : 0
    statistics =. 2{::y
    ((x{statistics)-(x+1){statistics)percentage x{statistics
)
aggregate_stalls =: 3 : 0
    class_stalls =. 7$0
    by_pc =. ((#PCs),4)$0
    pairs =. 0 5$0
    for_record. 1{::2{::Primary do.
        'cause cycles responsible waiting producer' =. record
        instruction =. responsible{Instructions
        kind =. 1{instruction
        class_stalls =. (cycles+kind{class_stalls)kind}class_stalls
        index =. PCs i.0{instruction
        by_pc =. (cycles+(<index,cause){by_pc)(<index,cause)}by_pc
        if. cause>:2 do.
            key =. (0{producer{Instructions),(0{waiting{Instructions),cause
            keys =. 0 1 2{"1 pairs
            matches =. I.*./"1 keys="1 key
            if. #matches do.
                index =. {.matches
            else.
                index =. #pairs
                pairs =. pairs,key,0 0
            end.
            pairs =. (cycles+(<index,3){pairs)(<index,3)}pairs
            pairs =. (1+(<index,4){pairs)(<index,4)}pairs
        end.
    end.
    keys =. (-3{"1 pairs),.(0 1 2{"1 pairs)
    pairs =. (/:keys){pairs
    (<class_stalls),(<by_pc),<pairs
)
statistics_lines =: 3 : 0
    n =. #Instructions
    simulation =. 2{::Primary
    'timings records delays cycles' =. simulation
    variant =. (0{::Primary){::Variants
    'variant_name forwarding stage latency' =. variant
    stalls =. 3{::Primary
    events =. 4{::Primary
    total_stalls =. +/stalls
    input_part =. (<'input lines ',(integer InputLines),' accepted ',(integer n),' rejected ',(integer #Rejected),' gaps ',integer #Gaps),Rejected,Gaps
    kinds =. 1{"1 Instructions
    counts =. +/"1 (i.7)=/kinds
    mix =. 0$a:
    for_i. i.7 do. mix =. mix,<(i{::Classes),' ',integer i{counts end.
    branches =. I.kinds=4
    jumps =. I.kinds=5
    distance =. 5$0
    source_count =. 0
    for_i. i.n do.
        source_count =. source_count+#i{::Sources
        for_source. i{::Sources do.
            if. (1{source)>:0 do.
                slot =. _1+5<.i-1{source
                distance =. (1+slot{distance)slot}distance
            end.
        end.
    end.
    distances =. 0$a:
    for_i. i.5 do. distances =. distances,<(i{::DistanceLabels),' ',integer i{distance end.
    static_kinds =. 1{"1 StaticInstructions
    memory =. Instructions#~kinds e.2 3
    trace_part =. (<'trace'),(<'instructions ',integer n),(<'static_instructions ',integer #PCs),(<'mix ',' 'join mix)
    trace_part =. trace_part,<'branches ',(integer #branches),' taken ',(integer +/1=5{"1 branches{Instructions),' backward ',integer +/(6{"1 branches{Instructions)<0{"1 branches{Instructions
    trace_part =. trace_part,<'jumps ',(integer #jumps),' indirect ',(integer +/0<:3{"1 jumps{Instructions),' link ',integer +/0<:2{"1 jumps{Instructions
    trace_part =. trace_part,<'static_control branches ',(integer +/static_kinds=4),' jumps ',integer +/static_kinds=5
    trace_part =. trace_part,<'memory loads ',(integer 2{counts),' stores ',(integer 3{counts),' distinct_addresses ',integer #~.7{"1 memory
    trace_part =. trace_part,<'operands ',(integer source_count),' with_producer ',(integer +/distance),' distance ',' 'join distances
    prediction_part =. <'prediction'
    for_p. i.#Definitions do.
        'name scheme parameters' =. p{::Definitions
        prediction =. p{::Predictions
        s =. 2{::prediction
        prediction_part =. prediction_part,<name,' ',scheme,' bits ',(integer 3{::prediction),' control ',(integer 0{s),' mispredicted ',(integer 1{s),' accuracy ',(0 accuracy prediction),' branches ',(2 accuracy prediction),' jumps ',(4 accuracy prediction),' direction ',(integer 6{s),' btb_miss ',(integer 7{s),' wrong_target ',integer 8{s
    end.
    s =. 2{::0{::Predictions
    prediction_part =. prediction_part,<'btb entries ',(integer BtbSize),' lookups ',(integer 9{s),' hits ',(integer 10{s),' misses ',integer (9{s)-10{s
    prediction_part =. prediction_part,<'ras depth ',(integer RasDepth),' calls ',(integer 11{s),' returns ',(integer 12{s),' predicted ',(integer 13{s),' correct ',integer 14{s
    lengths =. 5$0
    for_delay. delays do.
        if. delay>0 do.
            slot =. _1+5<.delay
            lengths =. (1+slot{lengths)slot}lengths
        end.
    end.
    finish =. i.0
    for_i. i.n do.
        start =. 0
        for_source. i{::Sources do.
            if. (1{source)>:0 do. start =. start>.(1{source){finish end.
        end.
        cost =. 1
        if. (i{kinds)=2 do. cost =. 2 elseif. (i{kinds)=1 do. cost =. latency end.
        finish =. finish,start+cost
    end.
    height =. >./finish
    flushed =. 0
    for_row. Rows do.
        flushed =. flushed+0>0{::>row
    end.
    cpi_causes =. length_parts =. 0$a:
    for_i. i.4 do. cpi_causes =. cpi_causes,<(i{::Causes),' ',(i{stalls)decimal n end.
    for_i. i.5 do. length_parts =. length_parts,<(i{::DistanceLabels),' ',integer i{lengths end.
    forward_name =. 'off'
    if. forwarding do. forward_name =. 'on' end.
    timing_part =. (<'timing variant=',variant_name,' predictor=',1{::PrimaryNames),(<'forwarding ',forward_name,' branch_stage ',stage,' mul_latency ',integer latency),(<'cycles ',integer cycles),(<'cpi ',(cycles fraction n),' ',cycles decimal n),(<'ipc ',n decimal cycles)
    timing_part =. timing_part,(<'stall_cycles total ',(integer total_stalls),' ',cause_values stalls),(<'stall_events ',cause_values events),(<'flushed ',integer flushed),(<'cycle_check ',(integer n),' + 4 + ',(integer total_stalls),' = ',integer n+4+total_stalls),(<'cpi_stack base 1.0000 fill ',(4 decimal n),' ',' 'join cpi_causes),(<'stall_lengths ',' 'join length_parts),<'dataflow height ',(integer height),' ilp ',n decimal height
    whatif =. <'whatif'
    flags =. 0{::(1{::Primary){::Predictions
    for_change. i.4 do.
        modified =. variant
        missed =. flags
        name =. 'perfect_prediction'
        select. change
        case. 0 do. missed =. n$0
        case. 1 do. name =. 'single_cycle_mul'
            modified =. (<1)3}modified
        case. 2 do.
            forward_name =. 'off'
            if. -.forwarding do. forward_name =. 'on' end.
            name =. 'forwarding_',forward_name
            modified =. (<-.forwarding)1}modified
        case. 3 do.
            modified_stage =. 'ID'
            if. 'ID'-:stage do. modified_stage =. 'EX' end.
            name =. 'branch_stage_',modified_stage
            modified =. (<modified_stage)2}modified
        end.
        count =. 3{::modified simulate missed
        whatif =. whatif,<name,' cycles ',(integer count),' saved ',(integer cycles-count),' speedup ',cycles decimal count
    end.
    'class_stalls by_pc pairs' =. aggregate_stalls ''
    class_part =. <'classes'
    for_i. i.7 do.
        per_instruction =. ,'-'
        if. i{counts do. per_instruction =. (i{class_stalls)decimal i{counts end.
        class_part =. class_part,<(i{::Classes),' count ',(integer i{counts),' stall_cycles ',(integer i{class_stalls),' per_instruction ',per_instruction
    end.
    paths =. 3$0
    for_i. i.n do.
        for_source. i{::Sources do.
            producer_time =. i.0
            if. (1{source)>:0 do. producer_time =. (1{source){timings end.
            slot =. variant forwarding_path (<i{Instructions),(<producer_time),<i{timings
            paths =. (1+slot{paths)slot}paths
        end.
    end.
    forwarding_part =. <'forwarding regfile ',(integer 0{paths),' ex_mem ',(integer 1{paths),' mem_wb ',integer 2{paths
    occupancy =. 5 2$0
    for_row. Rows do.
        row =. >row
        slot =. 0>0{::row
        for_span. 5{::row do.
            stage_index =. 0{span
            count =. 1+(2{span)-1{span
            occupancy =. (count+(<stage_index,slot){occupancy)(<stage_index,slot)}occupancy
        end.
    end.
    occupancy_part =. <'occupancy cycles ',integer cycles
    for_i. i.5 do.
        'a b' =. i{occupancy
        occupancy_part =. occupancy_part,<(i{::Stages),' correct ',(integer a),' wrong ',(integer b),' idle ',(integer cycles-(a+b)),' busy ',(a+b)percentage cycles
    end.
    pc_totals =. +/"1 by_pc
    ranked =. I.pc_totals>0
    ranked =. (/: (-ranked{pc_totals),.ranked{PCs){ranked
    hotspots =. <'hotspots'
    for_rank. i.Top<.#ranked do.
        index =. rank{ranked
        pc =. index{PCs
        kind =. 1{index{StaticInstructions
        hotspots =. hotspots,<(integer rank+1),' ',(hexadecimal pc),' ',(kind{::Classes),' stall_cycles ',(integer index{pc_totals),' ',cause_values index{by_pc
    end.
    dependency_part =. <'dependencies total ',integer #pairs
    for_rank. i.Top<.#pairs do.
        'producer waiting cause count event_count' =. rank{pairs
        producer_kind =. 1{(PCs i.producer){StaticInstructions
        waiting_kind =. 1{(PCs i.waiting){StaticInstructions
        dependency_part =. dependency_part,<(integer rank+1),' ',(hexadecimal producer),' ',(producer_kind{::Classes),' -> ',(hexadecimal waiting),' ',(waiting_kind{::Classes),' ',(cause{::Causes),' stall_cycles ',(integer count),' events ',integer event_count
    end.
    intervals =. <'intervals size ',integer Interval
    for_first. Interval*i.>.(x:n)%x:Interval do.
        last =. _1+n<.first+Interval
        previous =. 0
        if. first do. previous =. 4{(first-1){timings end.
        count =. (4{last{timings)-previous
        intervals =. intervals,<(integer first+1),'-',(integer last+1),' cycles ',(integer count),' cpi ',count decimal 1+last-first
    end.
    cycle_table =. <'cycles_table ',' 'join 0{&.>Definitions
    for_v. i.#Variants do.
        values =. i.0
        for_p. i.#Definitions do.
            for_combination. Combinations do.
                record =. >combination
                if. (v=0{::record)*.p=1{::record do. values =. values,3{::2{::record end.
            end.
        end.
        cycle_table =. cycle_table,<(0{::v{::Variants),' ',words values
    end.
    join_parts (<input_part),(<trace_part),(<prediction_part),(<timing_part),(<whatif),(<class_part),(<forwarding_part),(<occupancy_part),(<hotspots),(<dependency_part),(<intervals),<cycle_table
)
branch_lines =: 3 : 0
    lines =. <'predictor,pc,class,executions,taken,mispredictions,accuracy'
    for_p. i.#Definitions do.
        flags =. 0{::p{::Predictions
        name =. 0{::p{::Definitions
        for_k. i.#PCs do.
            indices =. k{::Groups
            instruction =. ({.indices){Instructions
            if. control instruction do.
                taken =. +/1=5{"1 indices{Instructions
                missed =. +/indices{flags
                values =. (<name),(<hexadecimal k{PCs),((1{instruction){Classes),(<integer #indices),(<integer taken),(<integer missed),<((#indices)-missed)percentage #indices
                lines =. lines,<','join values
            end.
        end.
    end.
    lines
)
comparison_lines =: 3 : 0
    lines =. <'rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw'
    cycles =. 3{::2{::Primary
    for_rank. i.#Combinations do.
        'v p simulation stalls events' =. rank{::Combinations
        count =. 3{::simulation
        prediction =. p{::Predictions
        values =. (<integer rank+1),(0{v{::Variants),(0{p{::Definitions),(<integer count),(<count decimal #Instructions),(<cycles decimal count),(<0 accuracy prediction),(<integer 1{2{::prediction),integer&.>stalls
        lines =. lines,<','join values
    end.
    lines
)
profile_lines =: 3 : 0
    branches =. <'branches'
    loops =. <'loops'
    indirect =. <'indirect'
    static =. <'instructions'
    timings =. 0{::2{::Primary
    'class_stalls by_pc pairs' =. aggregate_stalls ''
    for_k. i.#PCs do.
        pc =. k{PCs
        indices =. k{::Groups
        instruction =. ({.indices){Instructions
        count =. #indices
        if. 4=1{instruction do.
            outcomes =. 5{"1 indices{Instructions
            transitions =. +/(}.outcomes)~:}:outcomes
            longest =. 2$0
            previous =. _1
            length =. trip_length =. 0
            trips =. i.0
            for_outcome. outcomes do.
                if. previous=outcome do. length =. length+1 else. length =. 1 end.
                longest =. (length>.outcome{longest)outcome}longest
                previous =. outcome
                trip_length =. trip_length+1
                if. outcome=0 do.
                    trips =. trips,trip_length
                    trip_length =. 0
                end.
            end.
            if. trip_length do. trips =. trips,trip_length end.
            best =. _1
            best_misses =. 0
            for_p. i.#Definitions do.
                if. -.'PERFECT'-:1{::p{::Definitions do.
                    missed =. +/indices{0{::p{::Predictions
                    if. (best<0)+.missed<best_misses do. best =. p
                        best_misses =. missed
                    end.
                end.
            end.
            direction =. 'forward'
            if. (6{instruction)<pc do. direction =. 'backward' end.
            branches =. branches,<(hexadecimal pc),' ',direction,' executions ',(integer count),' taken ',(integer +/outcomes),' transitions ',(integer transitions),' longest_taken ',(integer 1{longest),' longest_not_taken ',(integer 0{longest),' best ',(0{::best{::Definitions),' ',integer best_misses
            if. (6{instruction)<pc do.
                body =. 1+(pc-6{instruction)floor_div 4
                loops =. loops,<(hexadecimal 6{instruction),'-',(hexadecimal pc),' body ',(integer body),' entries ',(integer #trips),' iterations ',(integer count),' avg_trip ',(count decimal #trips),' max_trip ',integer >./trips
            end.
        elseif. (5=1{instruction)*.0<:3{instruction do.
            targets =. ~.6{"1 indices{Instructions
            counts =. +/"1 targets=/6{"1 indices{Instructions
            order =. /:(-counts),.targets
            values =. 0$a:
            for_index. order do.
                values =. values,<(hexadecimal index{targets),':',integer index{counts
            end.
            indirect =. indirect,<(hexadecimal pc),' executions ',(integer count),' distinct ',(integer #targets),' targets ',' 'join values
        end.
        registers =. ' 'join register_text&.>2 3 4{instruction
        static =. static,<(hexadecimal pc),' ',((1{instruction){::Classes),' ',registers,' executions ',(integer count),' stall_cycles ',integer +/k{by_pc
    end.
    segment_pcs =. i.0
    segment_values =. 0 3$0
    first =. 0
    for_last. i.#Instructions do.
        if. (control last{Instructions)+.last=(#Instructions)-1 do.
            pc =. 0{first{Instructions
            index =. segment_pcs i.pc
            if. index=#segment_pcs do.
                segment_pcs =. segment_pcs,pc
                segment_values =. segment_values,0 0 0
            end.
            previous =. 0
            if. first do. previous =. 4{(first-1){timings end.
            change =. 1,(1+last-first),(4{last{timings)-previous
            segment_values =. ((index{segment_values)+change)index}segment_values
            first =. last+1
        end.
    end.
    order =. /:(-2{"1 segment_values),.segment_pcs
    segments =. <'segments total ',integer #segment_pcs
    for_rank. i.Top<.#order do.
        index =. rank{order
        'instances instruction_count cycles' =. index{segment_values
        segments =. segments,<(integer rank+1),' ',(hexadecimal index{segment_pcs),' instances ',(integer instances),' instructions ',(integer instruction_count),' cycles ',(integer cycles),' cpi ',cycles decimal instruction_count
    end.
    join_parts (<branches),(<loops),(<segments),(<indirect),<static
)
run =: 3 : 0
    'trace config' =. read_inputs ''
    'BtbSize RasDepth Definitions Variants PrimaryNames Window Top Interval' =: config
    validate_trace trace
    Sources =: dependencies Instructions
    Predictions =: predict_trace&.>Definitions
    all_combinations ''
    PCs =: /:~~.{."1 Instructions
    Groups =: 0$a:
    StaticInstructions =: 0 9$0
    for_pc. PCs do.
        indices =. I.pc={."1 Instructions
        Groups =: Groups,<indices
        StaticInstructions =: StaticInstructions,({.indices){Instructions
    end.
    Rows =: build_rows ''
    'pipeline.txt'write_lines pipeline_lines ''
    'stats.txt'write_lines statistics_lines ''
    'branches.csv'write_lines branch_lines ''
    'comparison.csv'write_lines comparison_lines ''
    'profile.txt'write_lines profile_lines ''
    0
)
run ''
