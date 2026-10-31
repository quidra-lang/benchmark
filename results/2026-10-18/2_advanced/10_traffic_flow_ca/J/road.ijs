ChangeKinds =: 'overtaking';'return';'avoidance'
segment_record =: 3 : 0
    'id start finish length lanes limit' =. y
    fields =. (<id),(<start),(<finish),(<length),(<lanes),(<limit),(<(lanes,length)$0),(<_1),(<0$0),<_1
    fields =. fields,10#<0
    fields =. fields,<3$0
    'id start finish length lanes limit cells junction turns stop entered vehicle_sum speed_sum max_vehicles green_steps queue_sum max_queue failures passed blocked changes' record fields
)
seg =: 4 : 'x get_key y{::Segments'
set_seg =: 3 : 0
    'index key value' =. y
    item =. ((<key),<value) put_key index{::Segments
    Segments =: (<item) index}Segments
    i.0
)
add_seg =: 3 : 0
    'index key value' =. y
    set_seg (<index),(<key),<value+key seg index
)
road_empty =: 3 : 0
    'segment lane cell' =. y
    0=(<lane,cell){'cells' seg segment
)
road_put =: 3 : 0
    'segment lane cell value' =. y
    cells =. value (<lane,cell)}'cells' seg segment
    set_seg (<segment),(<'cells'),<cells
)
road_free =: 3 : 0
    'segment lane cell limit' =. y
    count =. 0
    cells =. 'cells' seg segment
    length =. 'length' seg segment
    while. count<limit do.
        position =. cell+count+1
        if. position>:length do. break. end.
        if. 0~:(<lane,position){cells do. break. end.
        count =. count+1
    end.
    count
)
road_first =: 3 : 0
    'segment lane' =. y
    cells =. lane{'cells' seg segment
    occupied =. I.cells~:0
    if. #occupied do. {.occupied else. #cells end.
)
road_safe =: 3 : 0
    'segment lane cell' =. y
    first =. 0>.cell-'limit' seg segment
    *./0=((1+cell-first){.first}.lane{'cells' seg segment)
)
vehicle_numbers =: 3 : 0
    'segment lane' =. y
    cells =. lane{'cells' seg segment
    cells#~cells>0
)
cells_text =: 3 : 0
    'segment lane' =. y
    text =. ''
    for_value. lane{'cells' seg segment do.
        if. value=0 do. text =. text,'.'
        elseif. value=_1 do. text =. text,'#'
        else. text =. text,number 'speed' veh value end.
    end.
    text
)
incident_record =: 3 : '''segment lane cell start finish state active_start active_end'' record (<"0 y),( <''planned''),( <0),<0'
update_incident =: 4 : 0
    step =. x
    index =. y
    incident =. index{::Incidents
    segment =. 'segment' get_key incident
    lane =. 'lane' get_key incident
    cell =. 'cell' get_key incident
    state =. 'state' get_key incident
    finish =. 'finish' get_key incident
    event =. ''
    if. (state-:'active')*.step>finish do.
        state =. 'cleared'
        road_put segment,lane,cell,0
        event =. 'INCIDENT_END'
    elseif. (state-:'planned')*.step>finish do. state =. 'cancelled'
    elseif. (state-:'planned')*.step>:'start' get_key incident do.
        if. road_empty segment,lane,cell do.
            state =. 'active'
            road_put segment,lane,cell,_1
            incident =. ((<'active_start'),<step) put_key incident
            event =. 'INCIDENT_START'
        end.
    end.
    incident =. ((<'state'),<state) put_key incident
    if. state-:'active' do. incident =. ((<'active_end'),<step) put_key incident end.
    Incidents =: (<incident) index}Incidents
    event
)
