join =: 4 : 0
    result =. ''
    for_index. i.#y do.
        if. index do.
            result =. result,x
        end.
        result =. result,index{::y
    end.
    result
)
text =: 3 : 0
    if. 2=3!:0 y do.
        y return.
    end.
    value =. ":y
    '-'(I.value='_')}value
)
line =: 3 : ''' ''join text&.>y'
fixed =: 3 : 0
    sign =. ''
    if. y<0 do.
        sign =. '-'
    end.
    magnitude =. |y
    fraction =. text 10000|magnitude
    sign,(text magnitude intdiv 10000),'.',((4-#fraction)#'0'),fraction
)
average =: 4 : 'fixed (10000*x)intdiv y'
cell_text =: 3 : '(text y intdiv Cols),'','',text Cols|y'
cells_text =: 3 : ''' ''join cell_text&.>y'
state_text =: 3 : 'cell_text y{States'
world_grid =: 4 : 0
    result =. 0$a:
    for_row. i.Rows do.
        fields =. 0$a:
        for_column. i.Cols do.
            cell =. (row*Cols)+column
            state =. cell{StateIndex
            if. state<0 do.
                fields =. fields,<,cell{Kinds
            else.
                fields =. fields,state{y
            end.
        end.
        result =. result,<x join fields
    end.
    result
)
value_grid =: 3 : ''' ''world_grid fixed&.>y'
policy_grid =: 3 : '''''world_grid <"0 y{''^>v<'''
q_rows =: 3 : 0
    'name values visits optimal' =. y
    result =. 0$a:
    for_state. i.#States do.
        position =. state{States
        for_action. i.4 do.
            count =. '-'
            if. -.optimal do.
                count =. text (<state,action){visits
            end.
            fields =. (<name),(<position intdiv Cols),(<Cols|position),(<,action{'NESW'),(<fixed (<state,action){values),<count
            result =. result,<','join text&.>fields
        end.
    end.
    result
)
join_parts =: 3 : 0
    result =. 0$a:
    for_index. i.#y do.
        if. index do.
            result =. result,<''
        end.
        result =. result,index{::y
    end.
    result
)
write_lines =: 4 : 0
    content =. ''
    for_row. y do.
        content =. content,(>row),LF
    end.
    content 1!:2 <'output/',x
)
