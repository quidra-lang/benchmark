read_workcenters =: 3 : 0
    Centers =: empty_table ''
    for_box. read_rows 'workcenters.csv' do.
        'line fields' =. >box
        'id minutetext efficiencytext description' =. fields
        minutes =. num minutetext
        efficiency =. num efficiencytext
        reason =. ''
        if. id has_key Centers do. reason =. 'duplicate center ',id
        elseif. (efficiency<50)+.efficiency>150 do. reason =. 'bad efficiency ',number efficiency end.
        if. #reason do. 'workcenters.csv' record_error (<line),<reason
        else.
            values =. (<id),(<minutes),(<efficiency),(<(minutes*efficiency) div 100),<description
            center =. 'id minutes efficiency available description' record values
            Centers =: ((<id),<center) put_key Centers
        end.
    end.
    CenterIds =: /:~table_keys Centers
    i.0
)
read_routings =: 3 : 0
    Routings =: empty_table ''
    for_box. ItemIds do. Routings =: (box,<0$a:) put_key Routings end.
    for_box. read_rows 'routings.csv' do.
        'line fields' =. >box
        'id numbertext center setuptext runtext' =. fields
        numbervalue =. num numbertext
        run =. num runtext
        reason =. ''
        if. -.id has_key Items do. reason =. 'unknown item ',id
        elseif. -.center has_key Centers do. reason =. 'unknown center ',center
        elseif. 0=#id get_key Children do. reason =. 'purchased item ',id
        elseif. run<1 do. reason =. 'bad run time ',number run
        else.
            for_operationbox. id get_key Routings do.
                if. numbervalue='number' get_key >operationbox do. reason =. 'duplicate ',id,' operation ',number numbervalue
                break. end.
            end.
        end.
        if. #reason do. 'routings.csv' record_error (<line),<reason
        else.
            operation =. 'item number center setup run' record (<id),(<numbervalue),(<center),(<num setuptext),<run
            operations =. (id get_key Routings),<operation
            numbers =. 0$0
            for_operationbox. operations do. numbers =. numbers,'number' get_key >operationbox end.
            Routings =: ((<id),<( /:numbers){operations) put_key Routings
        end.
    end.
    i.0
)
operation_week =: 3 : 0
    'receipt lead index count' =. y
    1>.(receipt-lead)+(index*lead) div count
)
operation_minutes =: 4 : '(''setup'' get_key x)+y*''run'' get_key x'
level_loads =: 4 : 0
    leveled =. (#y)$0
    carry =. 0
    for_week. |.>:i.(#y)-1 do.
        total =. (week{y)+carry
        used =. x<.total
        leveled =. used week}leveled
        carry =. total-used
    end.
    (({.y)+carry) 0}leveled
)
