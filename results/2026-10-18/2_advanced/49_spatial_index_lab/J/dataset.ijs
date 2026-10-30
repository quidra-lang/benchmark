intdiv =: 4 : '<.(x:x)%x:y'
read_lines =: 3 : '<;._2 (1!:1 <y)'
split_words =: 3 : '<;._1 '' '',y'
read_csv =: 3 : 0
    rows =. }.read_lines y
    width =. #<;._1 ',',>{.rows
    result =. 0,width$0x
    for_row. rows do.
        result =. result,".&><;._1 ',',>row
    end.
    result
)
read_data =: 3 : 0
    points =. read_csv 'input/points.csv'
    rectangles =. read_csv 'input/rects.csv'
    settings =. split_words&.>read_lines 'input/params.txt'
    world =. ".1{::0{::settings
    bucket =. ".1{::1{::settings
    limits =. ".&>}.2{::settings
    cell =. ".1{::3{::settings
    commands =. 0$a:
    for_line. read_lines 'input/queries.txt' do.
        fields =. split_words >line
        commands =. commands,<(<0{::fields),<".&>}.fields
    end.
    (<points),(<rectangles),(<world,bucket,limits,cell),<commands
)
