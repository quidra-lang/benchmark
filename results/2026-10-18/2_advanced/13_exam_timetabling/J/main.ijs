ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
div =: 4 : '_1 x:<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
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
ascii_order =: 3 : '/: > (a.&i.)&.> y'
ascii_sort =: 3 : '(ascii_order y){y'
read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
load SourceDirectory,'enrolment.ijs'
load SourceDirectory,'conflict_graph.ijs'
load SourceDirectory,'coloring.ijs'
load SourceDirectory,'rooms.ijs'
load SourceDirectory,'report.ijs'
Relations =: 'back_to_back';'same_day';'overnight'
ExchangeVerdicts =: 'fixed';'invalid';'worse';'applied'
SwapVerdicts =: 'fixed';'invalid';'rooms';'worse';'applied'
ceil_div =: 4 : '((x+y)-1) div y'
by_size =: 3 : 'y{~/: (-y{Sizes),.y'
by_degree =: 3 : 'y{~/: (-y{Degrees),.y'
slot_day =: 3 : '1+(y-1) div Periods'
slot_name =: 3 : '''D'',(number slot_day y),''P'',number 1+Periods|y-1'
slot_length =: 3 : '(Periods|y-1){Lengths'
slot_at =: 3 : 0
    'day period' =. num&>y
    if. (day<1)+.(day>Days)+.(period<1)+.period>Periods do. 0 return. end.
    ((day-1)*Periods)+period
)
relation =: 3 : 0
    low =. <./y
    high =. >./y
    if. (slot_day low)=slot_day high do.
        if. (high-low)=1 do. 0 return. end.
        if. (high-low)>:2 do. 1 return. end.
    elseif. (high-low)=1 do. 2 return.
    end.
    _1
)
load_calendar =: 3 : 0
    lines =. y
    settings =. 0$a:
    for_line. 6{.lines do. settings =. settings,<num&>}. ' ' split >line end.
    Days =: 0{::settings
    Days =: {.Days
    Lengths =: 1{::settings
    Periods =: #Lengths
    Limit =: {.2{::settings
    Weights =: 3{::settings
    'FrontCount Deadline' =: 4{::settings
    Ratio =: {.5{::settings
    SlotCount =: Days*Periods
    Slots =: 1+i.SlotCount
    Closed =: 0$0
    Unavailable =: (StudentCount,SlotCount)$0
    Fixed =: CourseCount$0
    Orders =: 0 2$0
    i.0
)
blocked_students =: 4 : 0
    blocked =. 0$0
    for_student. x{::Rosters do.
        if. (<student,y-1){Unavailable do. blocked =. blocked,student end.
    end.
    blocked
)
suitable =: 4 : 0
    if. (slot_length y)<x{Durations do. 0 return. end.
    0=#x blocked_students y
)
packs =: 3 : '-. _1-:pack y'
courses_at =: 4 : 'I.y=x'
outside =: 3 : '''slot | | outside calendar'' format y'
accept_closed =: 3 : 0
    slot =. slot_at y
    if. slot=0 do. outside y return. end.
    if. slot e.Closed do. 'duplicate closed ',slot_name slot return. end.
    Closed =: Closed,slot
    ''
)
accept_unavailable =: 3 : 0
    student =. StudentIds i.0{y
    if. student=StudentCount do. 'unknown student ',0{::y return. end.
    slot =. slot_at }.y
    if. slot=0 do. outside }.y return. end.
    if. (<student,slot-1){Unavailable do.
        'duplicate unavailable | |' format (0{y),<slot_name slot return.
    end.
    Unavailable =: 1 (<student,slot-1)}Unavailable
    ''
)
accept_fixed =: 3 : 0
    id =. 0{::y
    course =. CourseIds i.<id
    if. course=CourseCount do. 'unknown course ',id return. end.
    if. -.course e.Schedulable do. 'course ',id,' not schedulable' return. end.
    slot =. slot_at }.y
    if. slot=0 do. outside }.y return. end.
    name =. slot_name slot
    if. slot e.Closed do. 'slot ',name,' closed' return. end.
    if. -.course suitable slot do. 'slot | unsuitable for |' format (<name),<id return. end.
    if. course{Fixed do. 'duplicate fixed ',id return. end.
    group =. slot courses_at Fixed
    clashes =. group#~group e.neighbours course
    if. #clashes do. 'conflict | |' format (<id),(<./clashes){CourseIds return. end.
    if. -.packs group,course do. 'rooms full ',name return. end.
    Fixed =: slot course}Fixed
    ''
)
accept_after =: 3 : 0
    'later earlier' =. CourseIds i.y
    for_index. i.2 do.
        if. CourseCount=index{later,earlier do. 'unknown course ',index{::y return. end.
    end.
    for_index. i.2 do.
        if. -. (index{later,earlier)e.Schedulable do. 'course ',(index{::y),' not schedulable' return. end.
    end.
    if. later=earlier do. 'bad order | |' format y return. end.
    if. (<later,earlier)e.<"1 Orders do. 'duplicate order | |' format y return. end.
    if. earlier reachable later do. 'cycle | |' format y return. end.
    if. ((later{Fixed)>0)*.(earlier{Fixed)>0 do.
        if. (later{Fixed)<:earlier{Fixed do. 'fixed order | |' format y return. end.
    end.
    Orders =: Orders,later,earlier
    ''
)
validate_calendar =: 3 : 0
    for_index. i.0>. (#y)-6 do.
        fields =. ' ' split (index+6){::y
        kind =. 0{::fields
        select. kind
        case. 'closed' do. message =. accept_closed }.fields
        case. 'unavailable' do. message =. accept_unavailable }.fields
        case. 'fixed' do. message =. accept_fixed }.fields
        case. 'after' do. message =. accept_after }.fields
        end.
        if. #message do. Errors =: Errors,<'calendar.txt line |: |' format (<index+7),<message end.
    end.
    OpenSlots =: Slots#~-.Slots e.Closed
    FixedSlots =: ~.Fixed#~Fixed>0
    i.0
)
order_conflicts =: 4 : 0
    'course slot' =. x
    conflicts =. 0$0
    for_pair. Orders do.
        'later earlier' =. pair
        if. (later=course)*.(earlier{y)>0 do.
            if. slot<:earlier{y do. conflicts =. conflicts,earlier end.
        elseif. (earlier=course)*.(later{y)>0 do.
            if. slot>:later{y do. conflicts =. conflicts,later end.
        end.
    end.
    conflicts
)
orders_satisfied =: 3 : 0
    for_pair. Orders do.
        'later earlier' =. pair
        if. ((later{y)>0)*.(earlier{y)>0 do.
            if. (later{y)<:earlier{y do. 0 return. end.
        end.
    end.
    1
)
candidate_slots =: 4 : 0
    course =. x
    candidates =. 0$0
    for_slot. OpenSlots do.
        if. -.course suitable slot do. continue. end.
        if. slot e.(neighbours course){y do. continue. end.
        if. # (course,slot) order_conflicts y do. continue. end.
        if. packs (slot courses_at y),course do. candidates =. candidates,slot end.
    end.
    candidates
)
build_timetable =: 3 : 0
    Excluded =: 0$0
    Attempts =: 0 3$0
    while. 1 do.
        Pending =: Schedulable#~(0=Schedulable{Fixed)*.-.Schedulable e.Excluded
        Assignment =: Fixed
        DeadEnds =: 0
        DeadEndCourse =: _1
        Aborted =: 0
        Chosen =: 0 2$0
        succeeded =. search ''
        if. succeeded do. failed =. _1 else. failed =. DeadEndCourse end.
        Attempts =: Attempts,(#Pending),DeadEnds,failed
        if. succeeded do.
            courses =. 0{"1 Chosen
            AssignmentOrder =: courses,.(courses{Assignment),.1{"1 Chosen
            break.
        end.
        Excluded =: Excluded,failed
    end.
    i.0
)
penalty_pairs =: 3 : 0
    pairs =. 0 4$0
    for_edge. Edges do.
        'first second shared' =. edge
        if. ((first{y)>0)*.(second{y)>0 do.
            kind =. relation (first,second){y
            if. kind>:0 do. pairs =. pairs,first,second,kind,shared end.
        end.
    end.
    pairs
)
late_courses =: 3 : 'FrontLoad#~(FrontLoad{y)>Deadline'
breakdown =: 3 : 0
    counts =. 3$0
    for_pair. penalty_pairs y do.
        kind =. 2{pair
        counts =. ((kind{counts)+3{pair) kind}counts
    end.
    late =. #late_courses y
    total =. (+/counts*3{.Weights)+(3{Weights)*late
    counts,late,total
)
breakdown_text =: 3 : '''back_to_back | same_day | overnight | front_load | penalty |'' format <"0 y'
contributions =: 3 : 0
    result =. CourseCount$0
    for_pair. penalty_pairs Assignment do.
        'first second kind shared' =. pair
        amount =. shared*kind{Weights
        result =. ((first{result)+amount) first}result
        result =. ((second{result)+amount) second}result
    end.
    for_course. late_courses Assignment do. result =. ((course{result)+3{Weights) course}result end.
    result
)
blocking_reason =: 4 : 0
    course =. x
    slot =. y
    if. slot e.Closed do. 'closed' return. end.
    if. (slot_length slot)<course{Durations do. 'too_short' return. end.
    blocked =. course blocked_students slot
    if. #blocked do. 'unavailable ',(<./blocked){::StudentIds return. end.
    adjacent =. neighbours course
    clashes =. adjacent#~slot=adjacent{Assignment
    if. #clashes do.
        weights =. clashes{course{Shared
        other =. {.clashes{~/: (-weights),.clashes
        'conflict | shared |' format (other{CourseIds),<(<course,other){Shared return.
    end.
    conflicts =. (course,slot) order_conflicts Assignment
    if. #conflicts do. 'order ',(<./conflicts){::CourseIds return. end.
    'rooms'
)
insert_excluded =: 3 : 0
    Insertions =: 0 3$0
    Reasons =: CourseCount$<0$a:
    for_course. /:~Excluded do.
        candidates =. course candidate_slots Assignment
        if. 0=#candidates do.
            reasons =. 0$a:
            for_slot. Slots do. reasons =. reasons,<course blocking_reason slot end.
            Reasons =: (<reasons) course}Reasons
            continue.
        end.
        before =. {:breakdown Assignment
        totals =. 0$0
        for_slot. candidates do. totals =. totals,{:breakdown slot course}Assignment end.
        index =. {. /:totals,.candidates
        best =. index{candidates
        Assignment =: best course}Assignment
        Insertions =: Insertions,course,best,(index{totals)-before
    end.
    Initial =: breakdown Assignment
    Penalty =: {:Initial
    i.0
)
unscheduled =: 3 : '/:~(Excluded#~0=Excluded{Assignment),Oversized'
valid_trial =: 4 : 0
    for_course. x do. if. -.course suitable course{y do. 0 return. end. end.
    orders_satisfied y
)
moved_courses =: 3 : 'I.(y>0)*.y~:Assignment'
verdict_counts =: 4 : 0
    fields =. 0$a:
    for_index. i.#x do. fields =. fields,(index{x),<index{y end.
    text_line fields
)
exchange_trial =: 3 : 0
    'home target' =. y
    if. +./y e.FixedSlots do. (<'fixed'),(<0$0),<0 return. end.
    trial =. target (I.Assignment=home)}Assignment
    trial =. home (I.Assignment=target)}trial
    if. -. (moved_courses trial) valid_trial trial do. (<'invalid'),(<0$0),<0 return. end.
    total =. {:breakdown trial
    if. total>:Penalty do. (<'worse'),(<0$0),<0 return. end.
    (<'applied'),(<trial),<total
)
exchange_slots =: 3 : 0
    ExchangeLog =: 0$a:
    round =. serial =. 0
    while. 1 do.
        round =. round+1
        tally =. 4$0
        records =. 0$a:
        pairs =. 0
        for_home. OpenSlots do.
            for_target. OpenSlots#~OpenSlots>home do.
                pairs =. pairs+1
                'verdict trial total' =. exchange_trial home,target
                index =. ExchangeVerdicts i.<verdict
                tally =. (1+index{tally) index}tally
                if. verdict-:'applied' do.
                    serial =. serial+1
                    records =. records,<'EXCHANGE | | | penalty | -> |' format (<serial),(<slot_name home),(<slot_name target),(<Penalty),<total
                    Assignment =: trial
                    Penalty =: total
                end.
            end.
        end.
        ExchangeLog =: ExchangeLog,(<'ROUND | pairs | |' format (<round),(<pairs),<ExchangeVerdicts verdict_counts tally),records
        if. 0=3{tally do. break. end.
    end.
    Exchanged =: breakdown Assignment
    i.0
)
swap_trial =: 3 : 0
    'course home target' =. y
    chain =. y kempe_chain Assignment
    if. +./0<chain{Fixed do. (<'fixed'),(<0$0),<0 return. end.
    values =. home+(target-home)*(chain{Assignment)=home
    trial =. values chain}Assignment
    if. -.chain valid_trial trial do. (<'invalid'),(<0$0),<0 return. end.
    if. (-.packs home courses_at trial)+.-.packs target courses_at trial do. (<'rooms'),(<0$0),<0 return. end.
    total =. {:breakdown trial
    if. total>:Penalty do. (<'worse'),(<0$0),<0 return. end.
    (<'applied'),(<trial),<total
)
swap_chains =: 3 : 0
    SwapLog =: 0$a:
    pass =. serial =. 0
    while. 1 do.
        pass =. pass+1
        tally =. 5$0
        records =. 0$a:
        candidates =. 0
        movable =. I.(Assignment>0)*.Fixed=0
        for_course. movable do.
            home =. course{Assignment
            for_target. OpenSlots#~OpenSlots~:home do.
                candidates =. candidates+1
                'verdict trial total' =. swap_trial course,home,target
                index =. SwapVerdicts i.<verdict
                tally =. (1+index{tally) index}tally
                if. -.verdict-:'applied' do. continue. end.
                serial =. serial+1
                chain =. moved_courses trial
                records =. records,<'SWAP | | | | chain | penalty | -> |' format (<serial),(course{CourseIds),(<slot_name home),(<slot_name target),(<#chain),(<Penalty),<total
                for_member. chain do.
                    records =. records,<'  MOVE | | -> |' format (member{CourseIds),(<slot_name member{Assignment),<slot_name member{trial
                end.
                Assignment =: trial
                Penalty =: total
                break.
            end.
        end.
        SwapLog =: SwapLog,(<'PASS | candidates | |' format (<pass),(<candidates),<SwapVerdicts verdict_counts tally),records
        if. 0=4{tally do. break. end.
    end.
    i.0
)
assign_rooms =: 3 : 0
    Placements =: 0 5$0
    for_slot. OpenSlots do.
        placed =. pack slot courses_at Assignment
        Placements =: Placements,((#placed)#slot),.placed
    end.
    i.0
)
slot_placements =: 3 : 'Placements#~y=0{"1 Placements'
room_groups =: 3 : 0
    placed =. slot_placements y
    groups =. 0$a:
    for_room. i.RoomCount do.
        group =. placed#~room=2{"1 placed
        if. #group do. groups =. groups,<group end.
    end.
    groups
)
invigilators =: 3 : 0
    result =. 0
    for_box. room_groups y do.
        group =. >box
        count =. +/(1{"1 group){Sizes
        result =. result+count ceil_div Ratio
    end.
    result
)
slot_load =: 3 : 0
    courses =. y courses_at Assignment
    (#courses),+/courses{Sizes
)
assigned_courses =: 3 : 0
    courses =. y{::StudentCourses
    courses =. courses#~0<courses{Assignment
    courses{~/: (courses{Assignment),.courses
)
student_pairs =: 3 : 0
    courses =. assigned_courses y
    pairs =. 0 5$0
    for_index. i.#courses do.
        first =. index{courses
        low =. first{Assignment
        for_second. (index+1)}.courses do.
            high =. second{Assignment
            kind =. relation low,high
            if. kind>:0 do. pairs =. pairs,kind,low,first,high,second end.
        end.
    end.
    pairs
)
student_penalty =: 3 : 0
    counts =. 3$0
    for_pair. student_pairs y do.
        kind =. 0{pair
        counts =. (1+kind{counts) kind}counts
    end.
    counts,+/counts*3{.Weights
)
timetable_lines =: 3 : 0
    lines =. <'TIMETABLE days | periods | open | courses | scheduled | unscheduled | empty |' format (<Days),(<Periods),(<#OpenSlots),(<CourseCount),(<+/Assignment>0),(<#unscheduled ''),<#Empty
    header =. 0$a:
    for_period. 1+i.Periods do. header =. header,<'P',number period end.
    lines =. lines,<((<'DAY'),(<4),<10) fixed_width_line header,<'TOTAL'
    for_day. 1+i.Days do.
        cells =. 0$a:
        total =. 0 0
        for_period. 1+i.Periods do.
            slot =. ((day-1)*Periods)+period
            if. slot e.Closed do. cells =. cells,<'closed'
            else.
                load =. slot_load slot
                cells =. cells,<(number 0{load),'/',number 1{load
                total =. total+load
            end.
        end.
        cells =. cells,<(number 0{total),'/',number 1{total
        label =. 'D',number day
        lines =. lines,<((<label),(<4),<10) fixed_width_line cells
    end.
    for_slot. Slots do.
        prefix =. 'SLOT | | minutes |' format (<slot),(<slot_name slot),<slot_length slot
        if. slot e.Closed do. lines =. lines,<prefix,' closed' continue. end.
        load =. slot_load slot
        groups =. room_groups slot
        seats =. 0
        for_box. groups do. seats =. seats+(2{ {. >box){Capacities end.
        suffix =. ' exams | students | rooms | seats | invigilators |' format (<0{load),(<1{load),(<#groups),(<seats),<invigilators slot
        lines =. lines,<prefix,suffix
        for_placement. slot_placements slot do.
            'ignored course room first last' =. placement
            marker =. ''
            if. course{Fixed do. marker =. ' fixed' end.
            lines =. lines,<'  | |min students | room | seats |-| |' format (course{CourseIds),(<course{Durations),(<course{Sizes),(room{RoomIds),(<first),(<(number last),marker),course{CourseNames
        end.
    end.
    for_room. i.RoomCount do.
        placed =. Placements#~room=2{"1 Placements
        used =. #~.0{"1 placed
        exams =. #placed
        seated =. +/(1{"1 placed){Sizes
        utilization =. seated rounded_percent (room{Capacities)*#OpenSlots
        lines =. lines,<'ROOM | capacity | slots | exams | seated | utilization |' format (room{RoomIds),(<room{Capacities),(<used),(<exams),(<seated),<utilization
    end.
    total =. 0
    for_slot. OpenSlots do. total =. total+invigilators slot end.
    lines,<'INVIGILATORS total | ratio |' format (<total),<Ratio
)
room_lines =: 3 : 0
    lines =. <'slot,room,course,students,first_seat,last_seat'
    for_slot. OpenSlots do.
        for_box. room_groups slot do.
            for_placement. >box do.
                'ignored course room first last' =. placement
                lines =. lines,<'|,|,|,|,|,|' format (<slot_name slot),(room{RoomIds),(course{CourseIds),(<course{Sizes),(<first),<last
            end.
        end.
    end.
    lines
)
student_statistics =: 3 : 0
    histogram =. gaps =. dayloads =. 0$0
    ranking =. 0 5$0
    for_student. i.StudentCount do.
        value =. student_penalty student
        penalty =. {:value
        histogram =. histogram,penalty
        ranking =. ranking,student,value
        assigned =. (assigned_courses student){Assignment
        gaps =. gaps,(}.assigned)-}:assigned
        if. #assigned do.
            days =. slot_day assigned
            loads =. 0$0
            for_day. 1+i.Days do. loads =. loads,+/days=day end.
            dayloads =. dayloads,>./loads
        end.
    end.
    lines =. 0$a:
    kinds =. 'HISTOGRAM';'GAP';'DAYLOAD'
    values =. (<histogram),(<gaps),<dayloads
    for_index. i.3 do.
        data =. index{::values
        for_value. /:~~.data do.
            lines =. lines,<'| | |' format (index{kinds),(<value),<+/data=value
        end.
    end.
    order =. /:(-4{"1 ranking),.0{"1 ranking
    for_row. (5<.#ranking){.order{ranking do.
        'student back same overnight penalty' =. row
        if. penalty>0 do.
            lines =. lines,<'WORST | penalty | back_to_back | same_day | overnight |' format (student{StudentIds),(<penalty),(<back),(<same),<overnight
        end.
    end.
    lines
)
penalty_lines =: 3 : 0
    final =. breakdown Assignment
    lines =. <'WEIGHTS back_to_back | same_day | overnight | front_load |' format <"0 Weights
    lines =. lines,<'FRONT_LOAD courses | last_slot |' format (<#FrontLoad),<slot_name Deadline
    lines =. lines,<'INITIAL ',breakdown_text Initial
    lines =. lines,ExchangeLog,<'EXCHANGED ',breakdown_text Exchanged
    lines =. lines,SwapLog,<'FINAL ',breakdown_text final
    lines =. lines,<'SAVED ',number ({:Initial)-{:final
    daily =. (Days,3)$0
    for_pair. penalty_pairs Assignment do.
        'first second kind shared' =. pair
        day =. (slot_day <./(first,second){Assignment)-1
        daily =. (shared+(<day,kind){daily) (<day,kind)}daily
    end.
    for_day. 1+i.Days do.
        lines =. lines,<'DAY D| back_to_back | same_day | overnight |' format (<day),<"0 (day-1){daily
    end.
    for_course. late_courses Assignment do.
        lines =. lines,<'LATE | | students |' format (course{CourseIds),(<slot_name course{Assignment),<course{Sizes
    end.
    values =. contributions ''
    assigned =. I.Assignment>0
    ranked =. assigned{~/: (-assigned{values),.assigned
    for_course. (10<.#ranked){.ranked do.
        if. (course{values)>0 do.
            lines =. lines,<'COURSE | | penalty |' format (course{CourseIds),(<slot_name course{Assignment),<course{values
        end.
    end.
    lines,student_statistics ''
)
schedule_lines =: 3 : 0
    lines =. 0$a:
    for_idbox. y do.
        id =. >idbox
        student =. StudentIds i.<id
        if. student=StudentCount do. lines =. lines,<'STUDENT ',id,' not found' continue. end.
        courses =. student{::StudentCourses
        assigned =. assigned_courses student
        lines =. lines,<'STUDENT | exams | scheduled | penalty |' format (<id),(<#courses),(<#assigned),<{:student_penalty student
        for_course. assigned do.
            placement =. {.Placements#~course=1{"1 Placements
            'slot ignored room first last' =. placement
            seat =. first+(course{::Rosters)i.student
            lines =. lines,<'  | | room | seat | |' format (<slot_name slot),(course{CourseIds),(room{RoomIds),(<seat),course{CourseNames
        end.
        for_course. courses#~0=courses{Assignment do.
            lines =. lines,<'  UNSCHEDULED | |' format (course{CourseIds),course{CourseNames
        end.
        for_pair. student_pairs student do.
            'kind low first high second' =. pair
            lines =. lines,<'  | | | | |' format (<toupper kind{::Relations),(<slot_name low),(first{CourseIds),(<slot_name high),second{CourseIds
        end.
        for_slot. 1+I.student{Unavailable do. lines =. lines,<'  UNAVAILABLE ',slot_name slot end.
    end.
    lines
)
status_lines =: 3 : 0
    values =. contributions ''
    lines =. <'course,status,slot,students,minutes,degree,penalty'
    for_course. i.CourseCount do.
        if. course{Fixed do. status =. 'fixed'
        elseif. course{Assignment do. status =. 'scheduled'
        elseif. course e.Oversized do. status =. 'too_large'
        elseif. course e.Empty do. status =. 'empty'
        else. status =. 'no_slot' end.
        slot =. '-'
        if. course{Assignment do. slot =. slot_name course{Assignment end.
        lines =. lines,<'|,|,|,|,|,|,|' format (course{CourseIds),(<status),(<slot),(<course{Sizes),(<course{Durations),(<course{Degrees),<course{values
    end.
    lines
)
graph_lines =: 3 : 0
    vertices =. #Vertices
    edges =. #Edges
    shared =. +/2{"1 Edges
    density =. 0
    if. vertices>:2 do. density =. (2000*edges) div vertices*vertices-1 end.
    lines =. <'GRAPH courses | edges | shared | density |' format (<vertices),(<edges),(<shared),<density
    for_course. (5<.#Vertices){.by_degree Vertices do.
        lines =. lines,<'DEGREE | neighbours | shared | students |' format (course{CourseIds),(<course{Degrees),(<+/course{Shared),<course{Sizes
    end.
    groups =. graph_components ''
    lines =. lines,<'COMPONENTS ',number #groups
    for_index. i.#groups do.
        group =. index{::groups
        lines =. lines,<'COMPONENT | size | first |' format (<index+1),(<#group),({.group){CourseIds
    end.
    clique =. greedy_clique Schedulable
    fields =. (<'CLIQUE'),(<'size'),(<#clique),clique{CourseIds
    lines,<text_line fields
)
capacity_lines =: 3 : 0
    loads =. #&>StudentCourses
    most =. >./loads
    demand =. +/Schedulable{Sizes
    capacity =. +/Capacities
    lines =. <'LOAD max_exams | students |' format (<most),<+/loads=most
    lines =. lines,<'SEATS demand | capacity | min_slots |' format (<demand),(<capacity),<demand ceil_div capacity
    lines =. lines,<'HEURISTIC largest_degree slots ',number greedy_numbering by_degree Schedulable
    lines =. lines,<'HEURISTIC largest_enrolment slots ',number greedy_numbering by_size Schedulable
    table =. (8<.#Vertices){.by_size Vertices
    lines =. lines,<((<'MATRIX'),(<9),<9) fixed_width_line table{CourseIds
    for_row. table do.
        cells =. 0$a:
        for_column. table do.
            if. row=column do. value =. '-' else. value =. number (<row,column){Shared end.
            cells =. cells,<value
        end.
        lines =. lines,<((row{CourseIds),(<9),<9) fixed_width_line cells
    end.
    lines
)
report_lines =: 3 : 0
    lines =. <'INPUT courses | enrolments | rooms | students | errors |' format (<CourseCount),(<+/#&>StudentCourses),(<RoomCount),(<StudentCount),<#Errors
    for_error. Errors do. lines =. lines,<'ERROR ',>error end.
    lines =. lines,(graph_lines ''),capacity_lines ''
    for_course. Empty do. lines =. lines,<'EMPTY ',course{::CourseIds end.
    for_course. Oversized do.
        lines =. lines,<'TOO_LARGE | students | largest_room |' format (course{CourseIds),(<course{Sizes),<LargestRoom
    end.
    for_slot. /:~Closed do. lines =. lines,<'CLOSED ',slot_name slot end.
    for_course. I.Fixed>0 do.
        lines =. lines,<'FIXED | |' format (course{CourseIds),<slot_name course{Fixed
    end.
    for_pair. Orders do. lines =. lines,<'AFTER | |' format pair{CourseIds end.
    for_index. i.#Attempts do.
        'count dead failed' =. index{Attempts
        if. failed=_1 do. result =. 'success' else. result =. 'failed ',failed{::CourseIds end.
        lines =. lines,<'ATTEMPT | courses | backtracks | |' format (<index+1),(<count),(<dead),<result
    end.
    for_index. i.#AssignmentOrder do.
        'course slot saturation' =. index{AssignmentOrder
        lines =. lines,<'ORDER | | | saturation | degree |' format (<index+1),(course{CourseIds),(<slot_name slot),(<saturation),<course{Degrees
    end.
    for_record. Insertions do.
        'course slot increase' =. record
        lines =. lines,<'INSERTED | | penalty |' format (course{CourseIds),(<slot_name slot),<increase
    end.
    for_course. unscheduled '' do.
        if. course e.Oversized do. reason =. 'too_large' else. reason =. 'no_slot' end.
        lines =. lines,<'UNSCHEDULED | reason | students |' format (course{CourseIds),(<reason),<course{Sizes
        reasons =. course{::Reasons
        for_index. i.#reasons do.
            lines =. lines,<'  | |' format (<slot_name index+1),index{reasons
        end.
    end.
    used =. #~.Assignment#~Assignment>0
    lines,<'SUMMARY scheduled | unscheduled | slots_used | penalty |' format (<+/Assignment>0),(<#unscheduled ''),(<used),<Penalty
)
main =: 3 : 0
    Errors =: 0$a:
    load_courses ''
    load_enrolments ''
    load_rooms ''
    LargestRoom =: >./Capacities
    Empty =: I.Sizes=0
    Oversized =: I.Sizes>LargestRoom
    Schedulable =: I.(Sizes>0)*.Sizes<:LargestRoom
    build_graph ''
    calendar =. read_lines 'calendar.txt'
    load_calendar calendar
    FrontLoad =: (FrontCount<.#Schedulable){.by_size Schedulable
    validate_calendar calendar
    build_timetable ''
    insert_excluded ''
    exchange_slots ''
    swap_chains ''
    assign_rooms ''
    files =. <(<'timetable.txt'),<timetable_lines ''
    files =. files,<(<'rooms.csv'),<room_lines ''
    files =. files,<(<'penalties.txt'),<penalty_lines ''
    files =. files,<(<'student_schedules.txt'),<schedule_lines read_lines 'queries.txt'
    files =. files,<(<'course_status.csv'),<status_lines ''
    files =. files,<(<'report.txt'),<report_lines ''
    write_files files
    i.0
)
main ''
