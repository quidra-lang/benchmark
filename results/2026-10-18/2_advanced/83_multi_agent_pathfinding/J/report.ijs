cell_text =: 3 : '(integer GridWidth|y),'','',integer y intdiv GridWidth'
agent_name =: 3 : 'y{AgentNames'
action_string =: 3 : 0
    actions =. ''
    for_i. 1+i.(#y)-1 do.
        source =. (i-1){y
        destination =. i{y
        difference =. destination-source
        if. difference=0 do.
            action =. '.'
        elseif. difference=-GridWidth do.
            action =. 'N'
        elseif. difference=1 do.
            action =. 'E'
        elseif. difference=GridWidth do.
            action =. 'S'
        else.
            action =. 'W'
        end.
        actions =. actions,action
    end.
    actions
)
conflict_text =: 3 : 0
    'kind time first second source destination' =. y
    line =. (integer time),' ',(agent_name first),' ',agent_name second
    if. kind=0 do.
        'vertex t ',line,' at ',cell_text destination
    else.
        'edge t ',line,' from ',(cell_text source),' to ',cell_text destination
    end.
)
fraction =: 4 : 0
    divisor =. x+.y
    (integer x intdiv divisor),'/',integer y intdiv divisor
)
write_lines =: 4 : 0
    ((LF join y),LF)1!:2 <'output/',x
)
picture =: 3 : '<"1 (GridHeight,GridWidth)$y'
