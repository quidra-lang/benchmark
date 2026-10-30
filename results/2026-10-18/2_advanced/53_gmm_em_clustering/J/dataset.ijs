read_lines =: 3 : '<;._2 (1!:1 <y)'
split_words =: 3 : '<;._1 '' '',y'
read_inputs =: 3 : 0
    ids =. 0$a:
    points =. 0 2$0.0
    for_line. }.read_lines 'input/points.csv' do.
        fields =. <;._1 ',',>line
        ids =. ids,{.fields
        points =. points,".&>}.fields
    end.
    initial =. 5$<0 6$0.0
    count =. 0
    weights =. i.0
    for_line. read_lines 'input/init.txt' do.
        if. 0=#>line do.
            continue.
        end.
        fields =. split_words >line
        select. 0{::fields
        case. 'K' do.
            count =. ".1{::fields
        case. 'W' do.
            weights =. ".&>}.fields
        case. 'C' do.
            component =. <:".1{::fields
            row =. (component{weights),".&>2}.fields
            initial =. (<(count{::initial),row)count}initial
        end.
    end.
    parameters =. 0$a:
    for_line. read_lines 'input/params.txt' do.
        fields =. split_words >line
        if. 'TYPES'-:0{::fields do.
            parameters =. parameters,<}.fields
        else.
            parameters =. parameters,<".&>}.fields
        end.
    end.
    (<ids),(<points),(<initial),<parameters
)
