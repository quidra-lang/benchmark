ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
div =: 4 : '_1 x:<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
signed_num =: 3 : 0
    if. '-'={.y do. -num }.y else. num y end.
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
read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
empty_table =: 3 : '0 2$a:'
table_keys =: 3 : '0{"1 y'
has_key =: 4 : '(<x)e.table_keys y'
get_key =: 4 : '((table_keys y)i.<x){::1{"1 y'
put_key =: 4 : 0
    'key value' =. x
    position =. (table_keys y)i.<key
    if. position<#y do. (<value) (<position,1)}y
    else. y,1 2$(<key),<value end.
)
record =: 4 : '('' '' split x),.y'
load SourceDirectory,'minstd.ijs'
load SourceDirectory,'road.ijs'
load SourceDirectory,'vehicles.ijs'
load SourceDirectory,'signals.ijs'
load SourceDirectory,'stats.ijs'
text_line =: 3 : 0
    fields =. 0$a:
    for_box. y do.
        value =. >box
        if. 2~:3!:0 value do. value =. number value end.
        fields =. fields,<value
    end.
    ' ' join fields
)
time_text =: 3 : '_4{.''0000'',number y'
range_text =: 3 : '(number {.y),''-'',number {:y'
flag_text =: 3 : 'y{::''N'';''Y'''
optional_step =: 3 : 0
    if. y=0 do. '-' else. number y end.
)
source_field =: 4 : 'x get_key y{::Sources'
set_source =: 3 : 0
    'index key value' =. y
    item =. ((<key),<value) put_key index{::Sources
    Sources =: (<item) index}Sources
    i.0
)
queue_size =: 3 : '(#''queue'' source_field y)-''head'' source_field y'
interval_field =: 3 : 'y get_key >{:Intervals'
add_interval =: 4 : 0
    item =. ((<x),<y+interval_field x) put_key >{:Intervals
    Intervals =: (<item) (<:#Intervals)}Intervals
    i.0
)
add_detector =: 3 : 0
    'key index value' =. y
    counts =. interval_field key
    counts =. (value+index{counts) index}counts
    item =. ((<key),<counts) put_key >{:Intervals
    Intervals =: (<item) (<:#Intervals)}Intervals
    i.0
)
new_interval =: 3 : '''arrivals insertions exits vehicle_steps speed_sum passing occupancy occupancy_speed'' record (5#<0),3#<y$0'
load_simulation =: 3 : 0
    Segments =: Junctions =: Incidents =: Stops =: Classes =: Sources =: Turns =: Detectors =: Diagrams =: Rings =: Vehicles =: Intervals =: Events =: Tracks =: SegmentIds =: Sinks =: 0$a:
    TrackNumbers =: 0$0
    for_filebox. 'network.txt';'demand.txt';'params.txt' do.
        for_linebox. read_lines >filebox do.
            tokens =. ' ' split >linebox
            kind =. 0{::tokens
            fields =. }.tokens
            select. kind
            case. 'SEGMENT' do.
                'id start finish' =. 3{.fields
                segment =. segment_record (<id),(<start),(<finish),<"0 num&>3}.fields
                SegmentIds =: SegmentIds,<id
                Segments =: Segments,<segment
            case. 'JUNCTION' do.
                node =. 0{::fields
                junction =. junction_record (<node),(<num 1{::fields),<2}.fields
                incoming =. 0$0
                for_index. i.#Segments do.
                    if. node-:'finish' seg index do.
                        incoming =. incoming,index
                        set_seg (<index),(<'junction'),<#Junctions
                    end.
                end.
                junction =. ((<'incoming'),<incoming) put_key junction
                Junctions =: Junctions,<junction
            case. 'INCIDENT' do.
                segment =. SegmentIds i.0{fields
                values =. segment,num&>}.fields
                values =. ((1{values)-1) 1}values
                Incidents =: Incidents,<incident_record values
            case. 'STOP' do.
                segment =. SegmentIds i.0{fields
                stop =. 'segment cell dwell buses' record (<segment),(<num 1{::fields),(<num 2{::fields),<0
                set_seg (<segment),(<'stop'),<#Stops
                Stops =: Stops,<stop
            case. 'CLASS' do.
                class =. class_record (0{fields),(<num 1{::fields),(<num 2{::fields),(<(3{::fields)-:'Y'),<(4{::fields)-:'Y'
                Classes =: Classes,<class
            case. 'SOURCE' do.
                node =. 0{::fields
                rates =. 0 2$0
                for_box. }.fields do. rates =. rates,num&>':' split >box end.
                entry =. _1
                for_index. i.#Segments do. if. node-:'start' seg index do. entry =. index break. end. end.
                source =. 'node rates segment queue head queue_start queue_max' record (<node),(<rates),(<entry),(<0$0),(<0),(<0),<0
                Sources =: Sources,<source
            case. 'SINK' do. Sinks =: Sinks,0{fields
            case. 'TURN' do.
                segment =. SegmentIds i.0{fields
                target =. SegmentIds i.1{fields
                turn =. 'target weight vehicles' record (<target),(<num 2{::fields),<0
                set_seg (<segment),(<'turns'),<('turns' seg segment),#Turns
                Turns =: Turns,<turn
            case. 'seed' do. Seed =: num 0{::fields
            case. 'steps' do. Steps =: num 0{::fields
            case. 'dawdle' do. 'Dawdle DawdleStopped' =: num&>fields
            case. 'interval' do. IntervalLength =: num 0{::fields
            case. 'bin' do. BinWidth =: num 0{::fields
            case. 'detector' do.
                detector =. 'name segment cell width' record (0{fields),(<SegmentIds i.1{fields),(<num 2{::fields),<num 3{::fields
                Detectors =: Detectors,<detector
            case. 'diagram' do.
                diagram =. 'segment lane start finish lines' record (<SegmentIds i.0{fields),(<(num 1{::fields)-1),(<num 2{::fields),(<num 3{::fields),<0$a:
                Diagrams =: Diagrams,<diagram
            case. 'track' do.
                TrackNumbers =: num&>fields
                Tracks =: (#TrackNumbers)#<0$a:
            case. 'ring' do.
                values =. num&>fields
                ring =. 'number length vmax warmup measure seed counts' record (<1+#Rings),(<0{values),(<1{values),(<2{values),(<3{values),(<4{values),<5}.values
                Rings =: Rings,<ring
            end.
        end.
    end.
    i.0
)
record_event =: 4 : 'Events =: Events,<(time_text x),'' '',y'
vehicles_on =: 3 : 0
    ids =. 0$0
    for_lane. i.'lanes' seg y do. ids =. ids,vehicle_numbers y,lane end.
    ids
)
enter_segment =: 3 : 0
    'number segment' =. y
    set_veh (<number),(<'route'),<('route' veh number),segment
    add_seg (<segment),(<'entered'),<1
    if. ('junction' seg segment)>:0 do.
        turns =. 'turns' seg segment
        weights =. 0$0
        for_turn. turns do. weights =. weights,'weight' get_key turn{::Turns end.
        set_veh (<number),(<'turn'),<(weights select_weighted draw ''){turns
    end.
    i.0
)
source_rate =: 4 : 0
    for_period. 'rates' source_field y do. if. x<:{:period do. {.period return. end. end.
    0
)
arrive =: 3 : 0
    weights =. 0$0
    for_box. Classes do. weights =. weights,'weight' get_key >box end.
    for_source. i.#Sources do.
        if. (1000|draw '')<y source_rate source do.
            class =. weights select_weighted draw ''
            number =. 1+#Vehicles
            Vehicles =: Vehicles,<vehicle_record number,class,source,y
            set_source (<source),(<'queue'),<('queue' source_field source),number
            'arrivals' add_interval 1
        end.
    end.
    i.0
)
insert_vehicles =: 3 : 0
    step =. y
    for_source. i.#Sources do.
        segment =. 'segment' source_field source
        while. queue_size source do.
            best =. _1
            best_first =. _1
            for_lane. i.'lanes' seg segment do.
                if. road_empty segment,lane,0 do.
                    first =. road_first segment,lane
                    if. first>best_first do. best =. lane
                        best_first =. first end.
                end.
            end.
            if. best<0 do. break. end.
            head =. 'head' source_field source
            number =. head{'queue' source_field source
            set_source (<source),(<'head'),<head+1
            place_vehicle number,segment,best,0
            set_veh (<number),(<'inserted'),<step
            enter_segment number,segment
            'insertions' add_interval 1
        end.
        size =. queue_size source
        start =. 'queue_start' source_field source
        if. (size>0)*.start=0 do.
            start =. step
            set_source (<source),(<'queue_start'),<start
            set_source (<source),(<'queue_max'),<0
        end.
        if. start>0 do.
            maximum =. size>.'queue_max' source_field source
            set_source (<source),(<'queue_max'),<maximum
            if. size=0 do.
                step record_event text_line (<'QUEUE'),(<'node' source_field source),(<'from'),(<start),(<'max'),<maximum
                set_source (<source),(<'queue_start'),<0
            end.
        end.
    end.
    i.0
)
desired_lane =: 3 : 0
    number =. y
    segment =. 'segment' veh number
    lane =. 'lane' veh number
    cell =. 'cell' veh number
    top =. max_speed number
    here =. road_free segment,lane,cell,top+1
    want =. top<.1+'speed' veh number
    ahead =. cell+here+1
    obstacle =. (here<top+1)*.ahead<'length' seg segment
    if. obstacle do. obstacle =. _1=(<lane,ahead){'cells' seg segment end.
    if. obstacle do.
        for_target. (lane+1),lane-1 do.
            if. (target>:0)*.target<'lanes' seg segment do.
                if. ((road_free segment,target,cell,top+1)>here)*.road_safe segment,target,cell do. target,2 return. end.
            end.
        end.
    end.
    if. heading_for_stop number do.
        if. lane>:1 do. if. road_safe segment,(lane-1),cell do. (lane-1),1 return. end. end.
        lane,_1 return.
    end.
    class =. ('class' veh number){::Classes
    if. ('overtakes' get_key class)*.((lane+1)<'lanes' seg segment)*.here<want do.
        if. ((road_free segment,(lane+1),cell,top+1)>here)*.road_safe segment,(lane+1),cell do. (lane+1),0 return. end.
    end.
    if. lane>:1 do.
        if. ((road_free segment,(lane-1),cell,top+1)>want)*.road_safe segment,(lane-1),cell do. (lane-1),1 return. end.
    end.
    lane,_1
)
change_lanes =: 3 : 0
    changes =. 0 3$0
    for_segment. i.#Segments do.
        lanes =. 'lanes' seg segment
        if. lanes<2 do. continue. end.
        reserved =. (lanes,'length' seg segment)$0
        for_lane. i.lanes do.
            for_number. vehicle_numbers segment,lane do.
                if. ('dwell' veh number)>0 do. continue. end.
                'target kind' =. desired_lane number
                cell =. 'cell' veh number
                if. (target~:lane)*.0=(<target,cell){reserved do.
                    reserved =. 1 (<target,cell)}reserved
                    changes =. changes,number,target,kind
                end.
            end.
        end.
    end.
    for_change. changes do.
        'number lane kind' =. change
        segment =. 'segment' veh number
        place_vehicle number,segment,lane,'cell' veh number
        add_veh (<number),(<'lane_changes'),<1
        counts =. 'changes' seg segment
        counts =. (1+kind{counts) kind}counts
        set_seg (<segment),(<'changes'),<counts
    end.
    i.0
)
processing_order =: 3 : 0
    moves =. 0 4$0
    for_segment. i.#Segments do.
        for_lane. i.'lanes' seg segment do.
            for_number. |.vehicle_numbers segment,lane do. moves =. moves,number,segment,('cell' veh number),0 end.
        end.
    end.
    moves
)
determine_speed =: 4 : 0
    step =. x
    number =. y
    segment =. 'segment' veh number
    lane =. 'lane' veh number
    cell =. 'cell' veh number
    previous =. 'speed' veh number
    accelerated =. (previous+1)<.max_speed number
    gap =. road_free segment,lane,cell,accelerated
    if. (gap<accelerated)*.(cell+gap)=('length' seg segment)-1 do.
        if. ('junction' seg segment)<0 do. gap =. accelerated
        elseif. segment is_green step do.
            turn =. ('turn' veh number){::Turns
            target =. 'target' get_key turn
            gap =. gap+road_free target,(lane<.('lanes' seg target)-1),_1,accelerated-gap
        end.
    end.
    if. heading_for_stop number do.
        stop =. ('stop' seg segment){::Stops
        gap =. gap<.('cell' get_key stop)-cell
    end.
    speed =. random_slowdown (accelerated<.gap),previous,(draw ''),Dawdle,DawdleStopped
    dwell =. 'dwell' veh number
    if. dwell>0 do.
        speed =. 0
        set_veh (<number),(<'dwell'),<dwell-1
    end.
    speed
)
move_vehicles =: 4 : 0
    step =. x
    moves =. y
    passing =. 0$0
    for_index. i.#moves do.
        'number segment cell speed' =. index{moves
        length =. 'length' seg segment
        if. (cell+speed)<length do. place_vehicle number,segment,('lane' veh number),cell+speed
        elseif. ('junction' seg segment)<0 do.
            leave_vehicle number
            set_veh (<number),(<'exited'),<step
            set_veh (<number),(<'sink'),<'finish' seg segment
            'exits' add_interval 1
        else. passing =. passing,index end.
    end.
    for_index. passing do.
        'number segment cell speed' =. index{moves
        turnindex =. 'turn' veh number
        turn =. turnindex{::Turns
        target =. 'target' get_key turn
        lane =. ('lane' veh number)<.('lanes' seg target)-1
        overshoot =. (cell+speed)-'length' seg segment
        position =. overshoot<.(road_first target,lane)-1
        if. position<overshoot do. add_seg (<segment),(<'blocked'),<1 end.
        if. position>:0 do.
            place_vehicle number,target,lane,position
            speed =. (('length' seg segment)-cell)+position
            add_seg (<segment),(<'passed'),<1
            turn =. ((<'vehicles'),<1+'vehicles' get_key turn) put_key turn
            Turns =: (<turn) turnindex}Turns
            enter_segment number,target
        else.
            place_vehicle number,segment,('lane' veh number),('length' seg segment)-1
            speed =. (('length' seg segment)-1)-cell
        end.
        moves =. speed (<index,3)}moves
    end.
    moves
)
aggregate_vehicle =: 4 : 0
    step =. x
    'number oldsegment oldcell speed' =. y
    previous =. 'speed' veh number
    add_veh (<number),(<'steps'),<1
    add_veh (<number),(<'distance'),<speed
    if. speed=0 do.
        add_veh (<number),(<'stopped_steps'),<1
        if. previous>0 do. add_veh (<number),(<'stop_count'),<1 end.
    end.
    set_veh (<number),(<'speed'),<speed
    'vehicle_steps' add_interval 1
    'speed_sum' add_interval speed
    if. heading_for_stop number do.
        segment =. 'segment' veh number
        stopindex =. 'stop' seg segment
        stop =. stopindex{::Stops
        if. (0='lane' veh number)*.('cell' veh number)='cell' get_key stop do.
            set_veh (<number),(<'completed_stops'),<('completed_stops' veh number),segment
            set_veh (<number),(<'dwell'),<'dwell' get_key stop
            stop =. ((<'buses'),<1+'buses' get_key stop) put_key stop
            Stops =: (<stop) stopindex}Stops
            step record_event text_line (<'BUS_STOP'),(<number),(<'id' seg segment),(<'cell'),<'cell' get_key stop
        end.
    end.
    track =. TrackNumbers i.number
    if. track<#TrackNumbers do.
        segment =. 'segment' veh number
        if. segment<0 do. text =. text_line (<time_text step),(<'EXIT'),<speed
        else. text =. text_line (<time_text step),(<'id' seg segment),(<1+'lane' veh number),(<'cell' veh number),<speed end.
        Tracks =: (<(track{::Tracks),<text) track}Tracks
    end.
    for_index. i.#Detectors do.
        detector =. index{::Detectors
        segment =. 'segment' get_key detector
        line =. 'cell' get_key detector
        if. (oldsegment=segment)*.oldcell<line do.
            if. (segment~:'segment' veh number)+.('cell' veh number)>:line do. add_detector (<'passing'),(<index),<1 end.
        end.
    end.
    i.0
)
aggregate_state =: 3 : 0
    step =. y
    for_index. i.#Detectors do.
        detector =. index{::Detectors
        segment =. 'segment' get_key detector
        first =. 'cell' get_key detector
        last =. first+'width' get_key detector
        for_number. vehicles_on segment do.
            cell =. 'cell' veh number
            if. (cell>:first)*.cell<last do.
                add_detector (<'occupancy'),(<index),<1
                add_detector (<'occupancy_speed'),(<index),<'speed' veh number
            end.
        end.
    end.
    for_segment. i.#Segments do.
        present =. vehicles_on segment
        speed_sum =. queue =. 0
        for_number. present do.
            speed_sum =. speed_sum+'speed' veh number
            queue =. queue+0='speed' veh number
        end.
        add_seg (<segment),(<'vehicle_sum'),<#present
        add_seg (<segment),(<'speed_sum'),<speed_sum
        set_seg (<segment),(<'max_vehicles'),<(#present)>.'max_vehicles' seg segment
        if. ('junction' seg segment)<0 do. continue. end.
        green =. segment is_green step
        if. green do. add_seg (<segment),(<'green_steps'),<1 end.
        add_seg (<segment),(<'queue_sum'),<queue
        set_seg (<segment),(<'max_queue'),<queue>.'max_queue' seg segment
        if. (step<Steps)*.(queue>0)*.green do.
            if. -.segment is_green step+1 do. add_seg (<segment),(<'failures'),<1 end.
        end.
    end.
    for_index. i.#Diagrams do.
        diagram =. index{::Diagrams
        if. (step>:'start' get_key diagram)*.step<:'finish' get_key diagram do.
            segment =. 'segment' get_key diagram
            signal =. 'E'
            if. ('junction' seg segment)>:0 do. signal =. (segment is_green step){::'R';'G' end.
            text =. (time_text step),' ',(cells_text segment,'lane' get_key diagram),' ',signal
            diagram =. ((<'lines'),<('lines' get_key diagram),<text) put_key diagram
            Diagrams =: (<diagram) index}Diagrams
        end.
    end.
    i.0
)
run_simulation =: 3 : 0
    RngState =: Seed
    for_step. 1+i.Steps do.
        for_index. i.#Incidents do.
            event =. step update_incident index
            if. #event do.
                incident =. index{::Incidents
                step record_event text_line (<event),(<'id' seg 'segment' get_key incident),(<'lane'),(<1+'lane' get_key incident),(<'cell'),<'cell' get_key incident
            end.
        end.
        if. 0=IntervalLength|step-1 do. Intervals =: Intervals,<new_interval #Detectors end.
        arrive step
        insert_vehicles step
        change_lanes ''
        moves =. processing_order ''
        for_index. i.#moves do. moves =. (step determine_speed (<index,0){moves) (<index,3)}moves end.
        moves =. step move_vehicles moves
        for_move. moves do. step aggregate_vehicle move end.
        aggregate_state step
    end.
    for_source. i.#Sources do.
        start =. 'queue_start' source_field source
        if. start>0 do. Steps record_event text_line (<'QUEUE'),(<'node' source_field source),(<'from'),(<start),(<'max'),(<'queue_max' source_field source),<'open' end.
    end.
    i.0
)
run_ring =: 4 : 0
    ring =. x
    count =. y
    length =. 'length' get_key ring
    vmax =. 'vmax' get_key ring
    warmup =. 'warmup' get_key ring
    measure =. 'measure' get_key ring
    state =. 'seed' get_key ring
    positions =. (length*i.count) div count
    speeds =. count$0
    total =. 0
    for_step. 1+i.warmup+measure do.
        order =. \:positions
        next =. count$0
        for_rank. i.count do.
            index =. rank{order
            ahead =. ((count|rank-1){order){positions
            gap =. length|(ahead-index{positions)-1
            speed =. ((index{speeds)+1)<.vmax<.gap
            state =. minstd_step state
            speed =. random_slowdown speed,(index{speeds),state,Dawdle,DawdleStopped
            next =. speed index}next
        end.
        positions =. length|positions+next
        speeds =. next
        if. step>warmup do. total =. total++/speeds end.
    end.
    total
)
enumerate_routes =: 3 : 0
    if. ('junction' seg y)<0 do. <'ids sink share' record (<,y),(<'finish' seg y),<1 fraction 1 return. end.
    turns =. 'turns' seg y
    total =. 0
    for_index. turns do. total =. total+'weight' get_key index{::Turns end.
    routes =. 0$a:
    for_index. turns do.
        turn =. index{::Turns
        share =. ('weight' get_key turn) fraction total
        for_box. enumerate_routes 'target' get_key turn do.
            route =. >box
            ids =. y,'ids' get_key route
            routes =. routes,<'ids sink share' record (<ids),(<'sink' get_key route),<share*'share' get_key route
        end.
    end.
    routes
)
vehicle_sum =: 4 : 0
    total =. 0
    for_id. y do. total =. total+x veh id end.
    total
)
travel_sum =: 3 : 0
    total =. 0
    for_id. y do. total =. total+travel_time id end.
    total
)
exited_vehicles =: 3 : 0
    ids =. 0$0
    for_id. y do. if. ('exited' veh id)>0 do. ids =. ids,id end. end.
    ids
)
class_vehicles =: 4 : 0
    ids =. 0$0
    for_id. y do. if. x='class' veh id do. ids =. ids,id end. end.
    ids
)
travel_block =: 4 : 0
    heading =. x
    count =. #y
    if. count=0 do. <heading,' exited 0' return. end.
    times =. 0$0
    for_id. y do. times =. times,travel_time id end.
    times =. /:~times
    fields =. (<heading),(<'exited'),(<count),(<'min'),(<{.times),(<'p50'),(<50 percentile times),(<'p90'),(<90 percentile times),(<'max'),(<{:times),(<'mean'),<dec (+/times),count,2
    (<text_line fields),BinWidth histogram_lines times
)
travel_report =: 3 : 0
    exited =. exited_vehicles 1+i.#Vehicles
    lines =. 0$a:
    for_index. i.#Classes do.
        class =. index{::Classes
        lines =. lines,('CLASS ','name' get_key class) travel_block index class_vehicles exited
    end.
    lines =. lines,'ALL' travel_block exited
    for_source. i.#Sources do.
        ids =. 0$0
        for_id. exited do. if. source='source' veh id do. ids =. ids,id end. end.
        count =. #ids
        routes =. enumerate_routes 'segment' source_field source
        lines =. lines,<text_line (<'SOURCE'),(<'node' source_field source),(<'exited'),<count
        for_box. routes do.
            route =. >box
            routeids =. 'ids' get_key route
            selected =. 0$0
            for_id. ids do. if. routeids-:'route' veh id do. selected =. selected,id end. end.
            names =. routeids{SegmentIds
            fields =. (<'  ROUTE'),(<',' join names),(<'expected'),(<share_text 'share' get_key route),(<'vehicles'),(<#selected),(<'share'),(<frac (#selected),count),(<'mean'),<dec (travel_sum selected),(#selected),2
            lines =. lines,<text_line fields
        end.
        for_sinkbox. Sinks do.
            sink =. >sinkbox
            expected =. 0 fraction 1
            exists =. 0
            for_box. routes do.
                route =. >box
                if. sink-:'sink' get_key route do. exists =. 1
                    expected =. expected+'share' get_key route end.
            end.
            if. -.exists do. continue. end.
            selected =. 0$0
            for_id. ids do. if. sink-:'sink' veh id do. selected =. selected,id end. end.
            fields =. (<'  SINK'),(<sink),(<'expected'),(<share_text expected),(<'vehicles'),(<#selected),(<'share'),(<frac (#selected),count),(<'mean'),<dec (travel_sum selected),(#selected),2
            lines =. lines,<text_line fields
        end.
    end.
    lines
)
class_block =: 4 : 0
    generated =. #y
    inserted =. 0
    for_id. y do. inserted =. inserted+('inserted' veh id)>0 end.
    exited =. exited_vehicles y
    count =. #exited
    steps =. 'steps' vehicle_sum y
    distance =. 'distance' vehicle_sum y
    delay =. ('inserted' vehicle_sum exited)-'arrival' vehicle_sum exited
    lines =. <x
    fields =. (<'  generated'),(<generated),(<'inserted'),(<inserted),(<'exited'),(<count),(<'in_network'),(<inserted-count),(<'queued'),<generated-inserted
    lines =. lines,<text_line fields
    fields =. (<'  vehicle_steps'),(<steps),(<'distance'),(<distance),(<'mean_speed'),(<frac distance,steps),(<'='),<dec distance,steps,3
    lines =. lines,<text_line fields
    fields =. (<'  travel'),(<dec (travel_sum exited),count,2),(<'entry_delay'),(<dec delay,count,2),(<'stopped'),(<dec ('stopped_steps' vehicle_sum exited),count,2),(<'stops'),(<dec ('stop_count' vehicle_sum exited),count,2),(<'lane_changes'),<dec ('lane_changes' vehicle_sum exited),count,2
    lines,<text_line fields
)
class_report =: 3 : 0
    lines =. 0$a:
    ids =. 1+i.#Vehicles
    for_index. i.#Classes do.
        class =. index{::Classes
        fields =. (<'CLASS'),(<'name' get_key class),(<'vmax'),(<'vmax' get_key class),(<'weight'),(<'weight' get_key class),(<'overtake'),(<flag_text 'overtakes' get_key class),(<'stops'),<flag_text 'stops' get_key class
        lines =. lines,(text_line fields) class_block index class_vehicles ids
    end.
    lines,'ALL' class_block ids
)
network_report =: 3 : 0
    lines =. 0$a:
    for_index. i.#Segments do.
        length =. 'length' seg index
        lanes =. 'lanes' seg index
        vehicle_sum =. 'vehicle_sum' seg index
        changes =. '/' join number&.><"0 'changes' seg index
        fields =. (<'SEGMENT'),(<'id' seg index),(<'start' seg index),(<'finish' seg index),(<'length'),(<length),(<'lanes'),(<lanes),(<'limit'),(<'limit' seg index),(<'entered'),(<'entered' seg index),(<'mean_vehicles'),(<dec vehicle_sum,Steps,3),(<'density'),(<dec vehicle_sum,(Steps*length*lanes),4),(<'mean_speed'),(<dec ('speed_sum' seg index),vehicle_sum,2),(<'max_vehicles'),(<'max_vehicles' seg index),(<'changes'),<changes
        lines =. lines,<text_line fields
    end.
    for_box. Junctions do.
        junction =. >box
        lines =. lines,plan_lines junction
        for_index. 'incoming' get_key junction do.
            fields =. (<'  IN'),(<'id' seg index),(<'green'),(<'green_steps' seg index),(<'passed'),(<'passed' seg index),(<'blocked'),(<'blocked' seg index),(<'max_queue'),(<'max_queue' seg index),(<'mean_queue'),(<dec ('queue_sum' seg index),Steps,3),(<'failures'),<'failures' seg index
            lines =. lines,<text_line fields
            for_turnindex. 'turns' seg index do.
                turn =. turnindex{::Turns
                lines =. lines,<text_line (<'    TURN'),(<'id' seg 'target' get_key turn),(<'weight'),(<'weight' get_key turn),(<'vehicles'),<'vehicles' get_key turn
            end.
        end.
    end.
    for_box. Stops do.
        stop =. >box
        lines =. lines,<text_line (<'STOP'),(<'id' seg 'segment' get_key stop),(<'cell'),(<'cell' get_key stop),(<'dwell'),(<'dwell' get_key stop),(<'buses'),<'buses' get_key stop
    end.
    for_box. Incidents do.
        incident =. >box
        active =. 'none'
        if. ('active_start' get_key incident)>0 do. active =. range_text ('active_start' get_key incident),'active_end' get_key incident end.
        planned =. range_text ('start' get_key incident),'finish' get_key incident
        lines =. lines,<text_line (<'INCIDENT'),(<'id' seg 'segment' get_key incident),(<'lane'),(<1+'lane' get_key incident),(<'cell'),(<'cell' get_key incident),(<'planned'),(<planned),(<'active'),<active
    end.
    lines
)
write_lines =: 4 : 0
    ((LF join y),LF#~0<#y) 1!:2 <'output/',x
    i.0
)
write_reports =: 3 : 0
    1!:5 <'output'
    lines =. 0$a:
    for_box. Diagrams do.
        diagram =. >box
        header =. text_line (<'DIAGRAM'),(<'id' seg 'segment' get_key diagram),(<'lane'),(<1+'lane' get_key diagram),(<'steps'),<range_text ('start' get_key diagram),'finish' get_key diagram
        lines =. lines,(<header),'lines' get_key diagram
    end.
    'spacetime.txt' write_lines lines
    lines =. <'detector,interval,flow,density,speed'
    for_index. i.#Detectors do.
        detector =. index{::Detectors
        segment =. 'segment' get_key detector
        size =. IntervalLength*('width' get_key detector)*'lanes' seg segment
        for_k. i.#Intervals do.
            interval =. k{::Intervals
            passing =. index{'passing' get_key interval
            occupancy =. index{'occupancy' get_key interval
            speed =. index{'occupancy_speed' get_key interval
            lines =. lines,<',' join (<'name' get_key detector),(<number k+1),(<number passing),(<dec occupancy,size,4),<dec speed,occupancy,2
        end.
    end.
    'detectors.csv' write_lines lines
    'travel_times.txt' write_lines travel_report ''
    'class_stats.txt' write_lines class_report ''
    'network_stats.txt' write_lines network_report ''
    lines =. <'interval,arrived,inserted,exited,in_network,queued,mean_speed'
    arrived =. inserted =. exited =. 0
    for_k. i.#Intervals do.
        interval =. k{::Intervals
        arrivals =. 'arrivals' get_key interval
        insertions =. 'insertions' get_key interval
        exits =. 'exits' get_key interval
        arrived =. arrived+arrivals
        inserted =. inserted+insertions
        exited =. exited+exits
        fields =. (<number k+1),(<number arrivals),(<number insertions),(<number exits),(<number inserted-exited),(<number arrived-inserted),<dec ('speed_sum' get_key interval),('vehicle_steps' get_key interval),2
        lines =. lines,<',' join fields
    end.
    'timeline.csv' write_lines lines
    lines =. 0$a:
    for_index. i.#TrackNumbers do.
        id =. index{TrackNumbers
        if. id>#Vehicles do. lines =. lines,<text_line (<'VEHICLE'),(<id),<'none'
            continue. end.
        class =. ('class' veh id){::Classes
        source =. 'source' veh id
        sink =. '-'
        if. ('exited' veh id)>0 do. sink =. 'sink' veh id end.
        fields =. (<'VEHICLE'),(<id),(<'class'),(<'name' get_key class),(<'source'),(<'node' source_field source),(<'arrival'),(<'arrival' veh id),(<'inserted'),(<optional_step 'inserted' veh id),(<'exited'),(<optional_step 'exited' veh id),(<'sink'),<sink
        route =. 'route' veh id
        routetext =. '-'
        if. #route do. routetext =. ' ' join route{SegmentIds end.
        lines =. lines,(<text_line fields),(<'ROUTE ',routetext),index{::Tracks
    end.
    'tracks.txt' write_lines lines
    lines =. <'ring,vehicles,density,flow,speed'
    for_box. Rings do.
        ring =. >box
        length =. 'length' get_key ring
        measure =. 'measure' get_key ring
        for_count. 'counts' get_key ring do.
            total =. ring run_ring count
            fields =. (<number 'number' get_key ring),(<number count),(<dec count,length,4),(<dec total,(length*measure),4),<dec total,(count*measure),3
            lines =. lines,<',' join fields
        end.
    end.
    'fundamental.csv' write_lines lines
    'events.txt' write_lines Events
    i.0
)
main =: 3 : 0
    load_simulation ''
    run_simulation ''
    write_reports ''
)
main ''
