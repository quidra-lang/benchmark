standard_costs =: 3 : 0
    Costs =: empty_table ''
    for_idbox. |.PlanningOrder do.
        id =. >idbox
        item =. id get_key Items
        material =. 'material' get_key item
        labor =. 'labor' get_key item
        for_box. id get_key Children do.
            row =. >box
            child =. ('child' get_key row) get_key Costs
            multiplier =. ('qty_per' get_key row)*100+'scrap' get_key row
            material =. material+((multiplier*'material' get_key child)+50) div 100
            labor =. labor+((multiplier*'labor' get_key child)+50) div 100
        end.
        cost =. 'material labor total' record (<material),(<labor),<material+labor
        Costs =: ((<id),<cost) put_key Costs
    end.
    i.0
)
abc_classes =: 3 : 0
    values =. 0$0
    for_box. ItemIds do. values =. values,(>box) get_key y end.
    total =. +/values
    order =. /:(-values),.i.#values
    classes =. empty_table ''
    before =. 0
    for_index. order do.
        value =. index{values
        if. value=0 do. class =. 'C'
        elseif. (100*before)<80*total do. class =. 'A'
        elseif. (100*before)<95*total do. class =. 'B'
        else. class =. 'C' end.
        classes =. ((index{ItemIds),<class) put_key classes
        before =. before+value
    end.
    classes
)
