class_record =: 3 : '''name vmax weight overtakes stops'' record y'
vehicle_record =: 3 : 0
    'number class source arrival' =. y
    fields =. (<number),(<class),(<source),(<arrival),(<0),(<0),( <''),(<_1),(<0),(<0),(<0),(<_1),<0$0
    fields =. fields,(6#<0),<0$0
    'number class source arrival inserted exited sink segment lane cell speed turn route steps distance stopped_steps stop_count lane_changes dwell completed_stops' record fields
)
veh =: 4 : 'x get_key (y-1){::Vehicles'
set_veh =: 3 : 0
    'number key value' =. y
    item =. ((<key),<value) put_key (number-1){::Vehicles
    Vehicles =: (<item) (number-1)}Vehicles
    i.0
)
add_veh =: 3 : 0
    'number key value' =. y
    set_veh (<number),(<key),<value+key veh number
)
max_speed =: 3 : 0
    class =. 'class' veh y
    ('vmax' get_key class{::Classes)<.'limit' seg 'segment' veh y
)
place_vehicle =: 3 : 0
    'number segment lane cell' =. y
    old =. 'segment' veh number
    if. old>:0 do. road_put old,('lane' veh number),('cell' veh number),0 end.
    road_put segment,lane,cell,number
    set_veh (<number),(<'segment'),<segment
    set_veh (<number),(<'lane'),<lane
    set_veh (<number),(<'cell'),<cell
)
leave_vehicle =: 3 : 0
    road_put ('segment' veh y),('lane' veh y),('cell' veh y),0
    set_veh (<y),(<'segment'),<_1
)
heading_for_stop =: 3 : 0
    segment =. 'segment' veh y
    if. segment<0 do. 0 return. end.
    class =. ('class' veh y){::Classes
    if. -.'stops' get_key class do. 0 return. end.
    stop =. 'stop' seg segment
    if. stop<0 do. 0 return. end.
    if. segment e.'completed_stops' veh y do. 0 return. end.
    ('cell' veh y)<:'cell' get_key stop{::Stops
)
travel_time =: 3 : '1+(''exited'' veh y)-''inserted'' veh y'
random_slowdown =: 3 : 0
    'speed previous value moving stopped' =. y
    probability =. moving
    if. previous=0 do. probability =. stopped end.
    speed-((speed>0)*.(1000|value)<probability)
)
