read_lines =: 3 : '<;._2 (1!:1 <y)'
split =: 4 : '<;._1 x,y'
num =: 3 : '0".y'
hundredths =: 3 : 'num y#~y~:''.'''
read_dataset =: 3 : 0
    names =. 0$a:
    series =. 0$a:
    for_box. }.read_lines 'input/series.csv' do.
        row =. ','split >box
        name =. 0{::row
        index =. names i.<name
        if. index=#names do.
            names =. names,<name
            series =. series,<0 2$0
        end.
        point =. (hundredths 1{::row),hundredths 2{::row
        series =. (<(index{::series),point)index}series
    end.
    for_index. i.#series do.
        points =. index{::series
        points =. (/:0{"1 points){points
        series =. (<points)index}series
    end.
    requests =. 0$a:
    for_box. }.read_lines 'input/test_points.csv' do.
        row =. ','split >box
        requests =. requests,<(<0{::row),<hundredths 1{::row
    end.
    rows =. 0$a:
    for_box. read_lines 'input/params.txt' do.
        rows =. rows,<}.' 'split >box
    end.
    Windows =: 0{::rows
    Kernels =: 1{::rows
    Bandwidths =: 2{::rows
    Degrees =: 3{::rows
    Spans =: 4{::rows
    RobustIterations =: num 0{::5{::rows
    Lambdas =: 6{::rows
    Folds =: num 0{::7{::rows
    IsotonicModes =: 8{::rows
    GridPoints =: num 0{::9{::rows
    BandZ =: num 0{::10{::rows
    BandMethods =: 11{::rows
    Threshold =: num 0{::12{::rows
    'Bootstrap Trim Seed' =: num&>13{::rows
    PlotSeries =: 14{::rows
    PlotMethods =: 15{::rows
    'PlotWidth PlotHeight' =: num&>16{::rows
    (<names),(<series),<requests
)
