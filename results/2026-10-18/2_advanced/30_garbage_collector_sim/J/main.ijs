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
load 'heap.ijs'
load 'mutator.ijs'
load 'mark_sweep.ijs'
load 'copying.ijs'
load 'generational.ijs'
c_line =: 0&{::
c_kind =: 1&{::
c_pointers =: 2&{::
c_data =: 3&{::
c_slot =: 4&{::
c_field =: 5&{::
c_source =: 6&{::
c_count =: 7&{::
c_label =: 8&{::
root_value =: 3 : 0
    if. y<0 do.
        0
    else.
        y{Roots
    end.
)
reachable =: 3 : 0
    reached =. (#ObjSize)$0
    stack =. y#~y>0
    while. #stack do.
        ident =. ({:stack)-1
        stack =. }:stack
        if. ident{reached do.
            continue.
        end.
        reached =. 1 ident}reached
        fields =. ident{::ObjFields
        stack =. stack,fields#~fields>0
    end.
    reached
)
fragmentation =: 3 : 0
    total =. total_free y
    (total-largest_free y)pct total
)
state_check =: 3 : 0
    kind =. c_kind y
    depth =. #Roots
    if. (kind e.0 1 2)*.depth=64 do.
        'stack' return.
    end.
    if. (kind e.2 4 5)*.(c_slot y)>:depth do.
        'stack' return.
    end.
    if. (kind e.1 4 5)*.(c_source y)>:depth do.
        'stack' return.
    end.
    if. (kind=3)*.(c_count y)>depth do.
        'stack' return.
    end.
    if. kind e.2 4 do.
        target =. (c_slot y){Roots
        if. target=0 do.
            'null' return.
        end.
        if. (c_field y)>:#(target-1){::ObjFields do.
            'field' return.
        end.
    end.
    if. (kind=6)*.(<c_label y)e.CheckpointLabels do.
        'duplicate' return.
    end.
    ''
)
execute_reference =: 3 : 0
    select. c_kind y
    case. 0 do.
        number =. add_object (c_pointers y),(c_data y),0
        Births =: Births,AllocationClock
        Deaths =: Deaths,_1
        Lifetimes =: Lifetimes,_1
        AllocationClock =: AllocationClock+{:ObjSize
        Roots =: Roots,number
    case. 1 do.
        Roots =: Roots,root_value c_source y
    case. 2 do.
        fields =. (((c_slot y){Roots)-1){::ObjFields
        Roots =: Roots,(c_field y){fields
    case. 3 do.
        Roots =: (-c_count y)}.Roots
    case. 4 do.
        index =. ((c_slot y){Roots)-1
        fields =. index{::ObjFields
        fields =. (root_value c_source y)(c_field y)}fields
        ObjFields =: (<fields)index}ObjFields
    case. 5 do.
        Roots =: (root_value c_source y)(c_slot y)}Roots
    end.
    i.0
)
analyze_script =: 3 : 0
    raw =. read_lines y
    LineCount =: #raw
    reset_heap 0
    Roots =: Births =: Deaths =: Lifetimes =: i.0
    Commands =: ScriptErrors =: Checkpoints =: CheckpointLabels =: 0$a:
    CommandCounts =: 7$0
    AllocationClock =: 0
    Alive =: i.0
    Live =: Peak =: 0 0
    PeakLine =: _1
    phase_start =. 0
    for_index. i.LineCount do.
        'command reason' =. (index+1)parse_line index{::raw
        if. 0=#reason do.
            reason =. state_check command
        end.
        if. #reason do.
            ScriptErrors =: ScriptErrors,<(<index+1),<reason
            continue.
        end.
        Commands =: Commands,<command
        kind =. c_kind command
        CommandCounts =: (>:(kind{CommandCounts))kind}CommandCounts
        execute_reference command
        reached =. reachable Roots
        for_ident. I.Alive do.
            if. -.ident{reached do.
                Deaths =: (c_line command)ident}Deaths
                lifetime =. AllocationClock-(ident{Births)+ident{ObjSize
                Lifetimes =: lifetime ident}Lifetimes
            end.
        end.
        Alive =: reached
        Live =: pair_of I.reached
        if. (PeakLine<0)+.({:Live)>{:Peak do.
            Peak =: Live
            PeakLine =: c_line command
        end.
        if. kind=6 do.
            label =. c_label command
            CheckpointLabels =: CheckpointLabels,<label
            phase_ids =. phase_start+i.(#ObjSize)-phase_start
            phase =. pair_of phase_ids
            survivors =. pair_of phase_ids#~phase_ids{reached
            allocated =. (#ObjSize),AllocationClock
            checkpoint =. (<label),(<c_line command),(<#Roots),(<Live),(<allocated),(<phase),(<survivors),<reached
            Checkpoints =: Checkpoints,<checkpoint
            phase_start =. #ObjSize
        end.
    end.
    lines =. ,<line 'script';'lines';LineCount;'valid';(#Commands);'errors';#ScriptErrors
    for_error. ScriptErrors do.
        'number reason' =. >error
        lines =. lines,<line 'error';'line';number;reason
    end.
    counts =. 0$a:
    for_kind. i.7 do.
        counts =. counts,<line (kind{::command_names);kind{CommandCounts
    end.
    lines =. lines,<'commands ',' 'join counts
    lines =. lines,<line 'allocated';'objects';(#ObjSize);'words';(+/ObjSize);'sizes';class_table ObjSize
    lines =. lines,<line 'peak_live';'objects';({.Peak);'words';({:Peak);'line';PeakLine
    lines =. lines,<line 'end_live';'objects';({.Live);'words';({:Live);'stack';#Roots
    life_counts =. 6$0
    for_life. Lifetimes do.
        index =. 5
        if. life>:0 do.
            index =. +/life>63 255 1023 4095
        end.
        life_counts =. (>:(index{life_counts))index}life_counts
    end.
    lines =. lines,<line 'lifetimes';'0-63';(0{life_counts);'64-255';(1{life_counts);'256-1023';(2{life_counts);'1024-4095';(3{life_counts);'4096+';(4{life_counts);'live';5{life_counts
    for_checkpoint. Checkpoints do.
        'label number depth live allocated phase survivors reached' =. >checkpoint
        lines =. lines,<line 'checkpoint';label;'line';number;'stack';depth;'live';(integers live);'allocated';(integers allocated);'phase';(integers phase);'survivors';(integers survivors);'survival';({:survivors)pct {:phase
    end.
    ScriptReport =: lines
    i.0
)
on_cycle =: 4 : 0
    members =. x
    origin =. y
    visited =. (#ObjSize)$0
    fields =. origin{::ObjFields
    stack =. (fields#~fields>0)-1
    stack =. stack#~stack{members
    while. #stack do.
        current =. {:stack
        stack =. }:stack
        if. current=origin do.
            1 return.
        end.
        if. current{visited do.
            continue.
        end.
        visited =. 1 current}visited
        fields =. current{::ObjFields
        children =. (fields#~fields>0)-1
        stack =. stack,children#~children{members
    end.
    0
)
leak_report =: 4 : 0
    garbage =. y
    members =. 1 garbage}(#ObjSize)$0
    neighbors =. (#ObjSize)$<i.0
    for_ident. garbage do.
        fields =. ident{::ObjFields
        for_child. fields#~fields>0 do.
            other =. child-1
            if. other{members do.
                neighbors =. (<(ident{::neighbors),other)ident}neighbors
                neighbors =. (<(other{::neighbors),ident)other}neighbors
            end.
        end.
    end.
    grouped =. (#ObjSize)$0
    groups =. 0$a:
    for_ident. /:~garbage do.
        if. ident{grouped do.
            continue.
        end.
        grouped =. 1 ident}grouped
        stack =. ,ident
        group =. i.0
        while. #stack do.
            current =. {:stack
            stack =. }:stack
            group =. group,current
            for_other. current{::neighbors do.
                if. -.other{grouped do.
                    grouped =. 1 other}grouped
                    stack =. stack,other
                end.
            end.
        end.
        groups =. groups,</:~group
    end.
    lines =. ,<line x;'groups';(#groups);'objects';(#garbage);'words';+/garbage{ObjSize
    for_index. i.#groups do.
        group =. index{::groups
        ids =. 0$a:
        cycles =. died =. 0
        for_ident. group do.
            cyclic =. members on_cycle ident
            value =. ":ident+1
            if. cyclic do.
                value =. value,'*'
                cycles =. cycles+1 end.
            ids =. ids,<value
            died =. died>.ident{Deaths
        end.
        lines =. lines,<line 'group';(index+1);'objects';(#group);'words';(+/group{ObjSize);'cycle';cycles;'died';died;'ids';' 'join ids
    end.
    lines
)
retain =: 3 : 0
    if. (HeapKind-:'REFCOUNT')*.y>0 do.
        ident =. y-1
        ObjRC =: (>:(ident{ObjRC))ident}ObjRC
        Increments =: Increments+1
    end.
    i.0
)
release =: 3 : 0
    if. (-.HeapKind-:'REFCOUNT')+.y=0 do.
        i.0 return.
    end.
    ident =. y-1
    ObjRC =: (<:(ident{ObjRC))ident}ObjRC
    Decrements =: Decrements+1
    if. (ident{ObjRC)>0 do.
        i.0 return.
    end.
    pending =. ,ident
    while. #pending do.
        current =. {:pending
        pending =. }:pending
        ObjPresent =: 0 current}ObjPresent
        Released =: Released,current
        for_child. current{::ObjFields do.
            if. child=0 do.
                continue.
            end.
            other =. child-1
            Decrements =: Decrements+1
            ObjRC =: (<:(other{ObjRC))other}ObjRC
            if. 0=other{ObjRC do.
                pending =. pending,other
            end.
        end.
    end.
    i.0
)
push_root =: 3 : 0
    retain y
    Roots =: Roots,y
)
backup =: 3 : 0
    'number request' =. y
    new_record (<number),(<request),<'backup'
    mark_objects Roots
    garbage =. I.ObjPresent*.-.ObjMarked
    title =. line 'backup';(0{::CurrentRecord);'line';number
    LeakReports =: LeakReports,<title leak_report garbage
    sweep_objects 0
    for_ident. garbage do.
        for_child. ident{::ObjFields do.
            if. child>0 do.
                other =. child-1
                if. other{ObjMarked do.
                    ObjRC =: (<:(other{ObjRC))other}ObjRC
                    Decrements =: Decrements+1
                end.
            end.
        end.
    end.
    finish_record 0
)
allocate_address =: 3 : 0
    'number request' =. y
    if. HeapKind-:'GENERATIONAL' do.
        allocate_generation y return.
    end.
    if. (<HeapKind)e.'MARK_COMPACT';'COPYING' do.
        finish =. HeapSize
        if. HeapKind-:'COPYING' do.
            finish =. Base+Half
        end.
        if. (Top+request)>finish do.
            if. HeapKind-:'COPYING' do.
                collect_copy y
            else.
                collect_mark y
            end.
            finish =. HeapSize
            if. HeapKind-:'COPYING' do.
                finish =. Base+Half
            end.
        end.
        if. (Top+request)>finish do.
            _1 return.
        end.
        address =. Top
        Top =: Top+request
        address return.
    end.
    address =. (free_list 0)first_fit request
    if. address<0 do.
        if. HeapKind-:'REFCOUNT' do.
            backup y
        else.
            collect_mark y
        end.
        address =. (free_list 0)first_fit request
    end.
    address
)
timeline_add =: 4 : 0
    if. y=0 do.
        i.0 return.
    end.
    merge =. 0
    if. #TimelineFlags do.
        merge =. x={:TimelineFlags
    end.
    if. merge do.
        TimelineLengths =: (({:TimelineLengths)+y)(<:#TimelineLengths)}TimelineLengths
    else.
        TimelineStarts =: TimelineStarts,TimelineLength
        TimelineLengths =: TimelineLengths,y
        TimelineFlags =: TimelineFlags,x
        TimelineBefore =: TimelineBefore,MutatorUnits
    end.
    TimelineLength =: TimelineLength+y
    if. x do.
        MutatorUnits =: MutatorUnits+y
    end.
    i.0
)
mutator_until =: 3 : 0
    low =. 0
    high =. <:#TimelineStarts
    while. low<high do.
        middle =. (low+high+1)intdiv 2
        if. (middle{TimelineStarts)<:y do.
            low =. middle
        else.
            high =. middle-1
        end.
    end.
    result =. low{TimelineBefore
    if. low{TimelineFlags do.
        result =. result+y-low{TimelineStarts
    end.
    result
)
mmu =: 3 : 0
    if. y>TimelineLength do.
        '-' return.
    end.
    lowest =. y
    for_i. i.#TimelineStarts do.
        start =. i{TimelineStarts
        finish =. start+i{TimelineLengths
        for_begin. start,finish-y do.
            if. (begin>:0)*.begin<:TimelineLength-y do.
                count =. (mutator_until begin+y)-mutator_until begin
                lowest =. lowest<.count
            end.
        end.
    end.
    lowest pct y
)
observe =: 3 : 0
    checkpoint =. y
    reached =. 7{::checkpoint
    live_ids =. I.ObjPresent*.reached
    garbage_ids =. I.ObjPresent*.-.reached
    in_heap =. pair_of I.ObjPresent
    live =. pair_of live_ids
    garbage =. pair_of garbage_ids
    blocks =. free_list 0
    pointers =. forward =. backward =. distance =. 0
    for_ident. live_ids do.
        for_child. ident{::ObjFields do.
            if. child=0 do.
                continue.
            end.
            pointers =. pointers+1
            delta =. ((child-1){ObjAddr)-ident{ObjAddr
            forward =. forward+delta>0
            backward =. backward+delta<0
            distance =. distance+|delta
        end.
    end.
    mean =. '-'
    if. pointers>0 do.
        mean =. distance dec2 pointers
    end.
    lines =. (<line 'heap';'objects';(integers in_heap);'reachable';(integers live);'garbage';integers garbage),(<line 'free';'total';(total_free blocks);'largest';(largest_free blocks);'blocks';(#blocks);'sizes';(class_table 1{"1 blocks);'fragmentation';fragmentation blocks),<line 'locality';'pointers';pointers;'forward';forward;'backward';backward;'mean_distance';mean
    if. HeapKind-:'GENERATIONAL' do.
        young =. pair_of I.ObjPresent*.ObjAddr<Young
        old =. pair_of I.ObjPresent*.ObjAddr>:Young
        ages =. 4$0
        for_ident. I.ObjPresent*.ObjAddr<Young do.
            age =. 3<.ident{ObjAge
            ages =. (>:(age{ages))age}ages
        end.
        distribution =. '0:',(":0{ages),' 1:',(":1{ages),' 2:',(":2{ages),' 3+:',":3{ages
        lines =. lines,<line 'generations';'young';(integers young);'old';(integers old);'remembered';(+/ObjRemembered);'ages';distribution
    end.
    if. (0{checkpoint)e.MapLabels do.
        map =. heap_map reached
        for_start. MapWidth*i.HeapSize intdiv MapWidth do.
            prefix =. _4{.'0000',":start
            lines =. lines,<prefix,' ',MapWidth{.start}.map
        end.
    end.
    lines
)
execute_mutator =: 3 : 0
    select. c_kind y
    case. 1 do.
        push_root root_value c_source y
    case. 2 do.
        fields =. (((c_slot y){Roots)-1){::ObjFields
        push_root (c_field y){fields
    case. 3 do.
        for_i. i.c_count y do.
            previous =. {:Roots
            Roots =: }:Roots
            release previous
        end.
    case. 4 do.
        target =. (c_slot y){Roots
        value =. root_value c_source y
        if. HeapKind-:'GENERATIONAL' do.
            write_barrier target,value
        end.
        retain value
        fields =. (target-1){::ObjFields
        previous =. (c_field y){fields
        fields =. value(c_field y)}fields
        ObjFields =: (<fields)(target-1)}ObjFields
        release previous
    case. 5 do.
        value =. root_value c_source y
        retain value
        previous =. (c_slot y){Roots
        Roots =: value(c_slot y)}Roots
        release previous
    case. 6 do.
        Observations =: Observations,<observe (#Observations){::Checkpoints
    end.
    i.0
)
pause_events =: 3 : 0
    events =. 0$a:
    for_record. Records do.
        record =. >record
        events =. events,< (1{record),(9{record),(<{:5{::record),<1
    end.
    for_cascade. Cascades do.
        'number pair work' =. >cascade
        events =. events,<(<number),(<work),(<{:pair),<0
    end.
    events
)
pause_stats =: 3 : 0
    works =. i.0
    collections =. freed =. 0
    for_event. y do.
        'number work reclaimed collection' =. >event
        works =. works,work
        collections =. collections+collection
        freed =. freed+reclaimed
    end.
    works =. /:~works
    count =. #works
    maximum =. 0
    p50 =. p90 =. '-'
    if. count>0 do.
        maximum =. {:works
        p50 =. ":((((50*count)+99)intdiv 100)-1){works
        p90 =. ":((((90*count)+99)intdiv 100)-1){works
    end.
    (<count),(<collections),(<+/works),(<freed),(<maximum),(<p50),<p90
)
simulate_run =: 3 : 0
    'CollectorName HeapKind Young PromotionAge' =: y
    Half =: HeapSize intdiv 2
    if. HeapKind-:'GENERATIONAL' do.
        Half =: Young intdiv 2
    end.
    reset_heap 0
    Roots =: Released =: i.0
    Cascades =: LeakReports =: Observations =: 0$a:
    TimelineStarts =: TimelineLengths =: TimelineFlags =: TimelineBefore =: i.0
    TimelineLength =: MutatorUnits =: PeakUsed =: Increments =: Decrements =: 0
    FailedLine =: _1
    FailedSize =: 0
    for_command. Commands do.
        command =. >command
        previous =. #Records
        placed =. 1
        units =. 1
        if. 0=c_kind command do.
            units =. 1+(c_pointers command)+c_data command
            address =. allocate_address (c_line command),units
            placed =. address>:0
            if. placed do.
                number =. add_object (c_pointers command),(c_data command),address
                push_root number
                PeakUsed =: PeakUsed>.+/ObjPresent#ObjSize
            end.
        else.
            execute_mutator command
        end.
        for_record. previous}.Records do.
            0 timeline_add 9{::>record
        end.
        if. -.placed do.
            FailedLine =: c_line command
            FailedSize =: units
            break.
        end.
        1 timeline_add units
        if. #Released do.
            work =. +/1+#&>Released{ObjFields
            freed =. pair_of Released
            Cascades =: Cascades,<(<c_line command),(<freed),<work
            0 timeline_add work
            Released =: i.0
        end.
    end.
    if. (FailedLine<0)*.HeapKind-:'REFCOUNT' do.
        garbage =. I.ObjPresent*.-.Alive
        LeakReports =: LeakReports,<'end'leak_report garbage
    end.
    i.0
)
collection_lines =: 3 : 0
    lines =. ,<line 'collector';CollectorName;HeapKind
    for_record. Records do.
        'number source request kind live freed moved promoted stack work before after' =. >record
        lines =. lines,<line number;'line';source;'size';request;'kind';kind;'live';(integers live);'freed';(integers freed);'moved';(integers moved);'promoted';(integers promoted);'stack';stack;'work';work;'before';(integers before);'after';integers after
    end.
    pauses =. pause_events 0
    'count collections total freed maximum p50 p90' =. pause_stats pauses
    lines =. lines,<line 'totals';'collections';collections;'pauses';count;'work';total;'freed';freed;'pause';'p50';p50;'p90';p90;'max';maximum
    windows =. 0$a:
    for_width. Windows do.
        windows =. windows,<(":width),':',mmu width
    end.
    lines =. lines,<line 'utilization';(MutatorUnits pct TimelineLength);'mmu';' 'join windows
    if. HeapKind-:'GENERATIONAL' do.
        parts =. ,<'generational'
        promoted =. 0 0
        for_kind. 'minor';'major';'tenure';'full' do.
            count =. work =. 0
            for_record. Records do.
                record =. >record
                if. (>kind)-:3{::record do.
                    count =. count+1
                    work =. work+9{::record
                end.
            end.
            parts =. parts,<line (>kind);count;work
        end.
        for_record. Records do.
            promoted =. promoted+7{::>record
        end.
        parts =. parts,<line 'promoted';(integers promoted);'barrier';Barriers;'remembered';Remembers
        lines =. lines,<' 'join parts
    elseif. HeapKind-:'REFCOUNT' do.
        freed =. 0 0
        largest =. _1
        for_index. i.#Cascades do.
            cascade =. index{::Cascades
            freed =. freed+1{::cascade
            if. largest<0 do.
                largest =. index
            elseif. (2{::cascade)>2{::largest{::Cascades do.
                largest =. index
            end.
        end.
        maximum =. 'max_cascade 0 0 line -'
        if. largest>:0 do.
            'number pair work' =. largest{::Cascades
            maximum =. line 'max_cascade';({.pair);work;'line';number
        end.
        lines =. lines,<line 'refcount';'increments';Increments;'decrements';Decrements;'cascades';(#Cascades);'freed';(integers freed);maximum
    end.
    previous =. 0
    for_checkpoint. Checkpoints do.
        checkpoint =. >checkpoint
        label =. 0{::checkpoint
        source =. 1{::checkpoint
        if. (FailedLine>:0)*.FailedLine<source do.
            lines =. lines,<line 'phase';label;'out_of_memory'
        else.
            phase =. 0$a:
            for_pause. pauses do.
                value =. >pause
                number =. 0{::value
                if. (previous<number)*.number<:source do.
                    phase =. phase,pause
                end.
            end.
            'count collections total freed maximum p50 p90' =. pause_stats phase
            lines =. lines,<line 'phase';label;'collections';collections;'pauses';count;'work';total;'freed';freed;'max_pause';maximum
        end.
        previous =. source
    end.
    status =. 'status completed'
    if. FailedLine>:0 do.
        status =. line 'status';'out_of_memory';'line';FailedLine;'size';FailedSize
    end.
    lines,<status
)
summary_row =: 3 : 0
    'count collections total freed maximum p50 p90' =. pause_stats pause_events 0
    live =. moved =. 0
    for_record. Records do.
        record =. >record
        live =. live+{.4{::record
        moved =. moved+{.6{::record
    end.
    moves =. ObjMoves#~ObjMoves>0
    max_moves =. 0
    if. #moves do.
        max_moves =. >./moves
    end.
    status =. 'completed'
    if. FailedLine>:0 do.
        status =. 'out_of_memory'
    end.
    values =. CollectorName;HeapKind;status;(#Records);count;live;moved;(#moves);max_moves;freed;total;p50;p90;maximum;PeakUsed
    if. FailedLine>:0 do.
        values =. values,'-';'-';'-';'-'
    else.
        blocks =. free_list 0
        values =. values,(<+/ObjPresent#ObjSize),(<total_free blocks),(<largest_free blocks),<fragmentation blocks
    end.
    ','join text&.>values
)
leak_lines =: 3 : 0
    lines =. ,<'collector ',CollectorName
    for_report. LeakReports do.
        lines =. lines,>report
    end.
    if. FailedLine>:0 do.
        lines =. lines,<'status out_of_memory'
    end.
    lines
)
join_blocks =: 3 : 0
    lines =. 0$a:
    for_index. i.#y do.
        if. index>0 do.
            lines =. lines,<''
        end.
        lines =. lines,index{::y
    end.
    lines
)
write_lines =: 4 : 0
    text =. ''
    for_value. y do.
        text =. text,(>value),LF
    end.
    text 1!:2 <'output/',x
)
run =: 3 : 0
    read_config 'input/config.txt'
    analyze_script 'input/mutator.txt'
    RunResults =: 0$a:
    for_entry. CollectorEntries do.
        entry =. >entry
        simulate_run entry
        collections =. collection_lines 0
        summary =. summary_row 0
        leaks =. 0$a:
        if. HeapKind-:'REFCOUNT' do.
            leaks =. leak_lines 0
        end.
        RunResults =: RunResults,<(<entry),(<Observations),(<collections),(<summary),<leaks
    end.
    map_blocks =. 0$a:
    for_index. i.#Checkpoints do.
        checkpoint =. index{::Checkpoints
        for_result. RunResults do.
            'entry observations collections summary leaks' =. >result
            header =. line 'checkpoint';(0{::checkpoint);'line';(1{::checkpoint);'collector';0{::entry
            lines =. ,<header
            if. index<#observations do.
                lines =. lines,index{::observations
            else.
                lines =. lines,<'out_of_memory'
            end.
            map_blocks =. map_blocks,<lines
        end.
    end.
    collection_blocks =. leak_blocks =. 0$a:
    summaries =. ,<'collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,total_work,p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,fragmentation'
    for_result. RunResults do.
        'entry observations collections summary leaks' =. >result
        collection_blocks =. collection_blocks,<collections
        summaries =. summaries,<summary
        if. #leaks do.
            leak_blocks =. leak_blocks,<leaks
        end.
    end.
    leak_output =. ,<'none'
    if. #leak_blocks do.
        leak_output =. join_blocks leak_blocks
    end.
    try. 1!:5 <'output' catch. end.
    'mutator.txt'write_lines ScriptReport
    'heap_maps.txt'write_lines join_blocks map_blocks
    'collections.txt'write_lines join_blocks collection_blocks
    'summary.csv'write_lines summaries
    'leaks.txt'write_lines leak_output
    i.0
)
run 0
