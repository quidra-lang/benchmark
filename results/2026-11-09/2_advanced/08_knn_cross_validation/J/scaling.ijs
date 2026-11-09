real_sum =: 3 : 0
    total =. 0.0
    for_value. y do. total =. total+value end.
    total
)
compute_scaling =: 4 : 0
    centers =. scales =. 0$0.0
    count =. #y
    for_feature. i.#'values' get_key 0{::y do.
        values =. 0$0.0
        for_box. y do. values =. values,feature{'values' get_key >box end.
        if. x-:'standard' do.
            center =. (real_sum values)%real count
            scale =. 0.0
            if. count>1 do.
                differences =. values-center
                scale =. %:(real_sum differences*differences)%real count-1
            end.
        else.
            center =. <./values
            scale =. (>./values)-center
        end.
        centers =. centers,center
        scales =. scales,scale
    end.
    'centers scales' record (<centers),<scales
)
transform_values =: 3 : 0
    'scaling values features' =. y
    centers =. 'centers' get_key scaling
    scales =. 'scales' get_key scaling
    transformed =. 0$0.0
    for_feature. features do.
        value =. 0.0
        if. (feature{scales)>!.0 0 do. value =. ((feature{values)-feature{centers)%feature{scales end.
        transformed =. transformed,value
    end.
    transformed
)
