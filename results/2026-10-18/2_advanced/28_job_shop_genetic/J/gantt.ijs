chart_scale =: 4 : 0
    magnitude =. 1
    while. 1 do.
        for_step. 1 2 5 do.
            quantum =. step*magnitude
            columns =. (x+quantum-1)intdiv quantum
            if. columns<:y do. quantum,columns return. end.
        end.
        magnitude =. magnitude*10
    end.
)
time_row =: 4 : 0
    row =. 'time'
    for_column. 10*i.(y+9)intdiv 10 do.
        row =. row,((0>.6+column-#row)#' '),":column*x
    end.
    row
)
rule_row =: 3 : '(6#'' ''),''-+''{~0=10|i.y'
framed =: 4 : 'x,((0>.4-#x)#'' ''),'' |'',y,''|'''
chart_row =: 3 : 0
    'label intervals quantum columns' =. y
    marks =. ''
    for_column. i.columns do.
        widest =. 0
        earliest =. 2147483647
        mark =. '.'
        for_interval. intervals do.
            'start finish symbol' =. >interval
            overlap =. (finish<.(column+1)*quantum)-start>.column*quantum
            if. (overlap>widest)+.((overlap=widest)*.(overlap>0)*.start<earliest) do.
                widest =. overlap
                earliest =. start
                mark =. symbol
            end.
        end.
        marks =. marks,mark
    end.
    label framed marks
)
busy_row =: 3 : 0
    'machines quantum columns' =. y
    marks =. ''
    for_column. i.columns do.
        time =. column*quantum
        busy =. 0
        for_intervals. machines do.
            for_interval. >intervals do.
                'start finish symbol' =. >interval
                if. (start<:time)*.time<finish do. busy =. busy+1 break. end.
            end.
        end.
        marks =. marks,busy{'0123456789X'
    end.
    'busy'framed marks
)
