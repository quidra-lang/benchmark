rail_number =: 4 : 0
    cycle =. (2*x)-2
    offset =. cycle|y
    offset<.cycle-offset
)
rail_fence =: 4 : 0
    'key decrypt' =. x
    rails =. num key
    positions =. i.#y
    order =. /:(rails rail_number positions),.positions
    if. decrypt do. y order}(#y)#' ' else. order{y end.
)
column_order =: 3 : '/:(a.i.y),.i.#y'
rank_string =: 3 : '(>:/:column_order y){Digits'
columnar =: 4 : 0
    'key decrypt' =. x
    width =. #key
    positions =. i.#y
    order =. 0$0
    for_column. column_order key do.
        order =. order,I.column=width|positions
    end.
    if. decrypt do. y order}(#y)#' ' else. order{y end.
)
