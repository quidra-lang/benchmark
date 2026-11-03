read_points =: 3 : 0
    result =. 0 3$0
    for_line. }.<;._2 (1!:1 <'input/points.csv') do.
        result =. result,num&>','split >line
    end.
    result /:0{\"1 result
)
read_params =: 3 : 0
    rows =. 0$a:
    for_line. <;._2 (1!:1 <'input/params.txt') do.
        rows =. rows,<' 'split >line
    end.
    Eps =: num&>}.0{::rows
    MinPts =: num 1{::1{::rows
    MaxEps =: num 1{::2{::rows
    ExtractEps =: num&>}.3{::rows
    XiText =: 1{::4{::rows
    'XiU XiV' =: num&>'/'split XiText
    XiMinSize =: num 1{::5{::rows
    'MapWidth MapHeight' =: num&>}.6{::rows
    'KWidth KHeight' =: num&>}.7{::rows
    PlotWidth =: num 1{::8{::rows
    i.0
)
