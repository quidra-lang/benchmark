intdiv =: 4 : '<.(x:x)%x:y'
read_lines =: 3 : '<;._2 (1!:1 <y)'
split_words =: 3 : '<;._1 '' '',y'
read_inputs =: 3 : 0
    codes =. 0$a:
    coordinates =. 0 3$0x
    for_line. }.read_lines 'input/stations.csv' do.
        fields =. <;._1 ',',>line
        codes =. codes,{.fields
        coordinates =. coordinates,x:".&>}.fields
    end.
    rows =. read_lines 'input/waveforms.txt'
    starts =. i.0x
    samples =. 0$a:
    cursor =. 0
    for_station. i.#codes do.
        header =. split_words cursor{::rows
        start =. ".2{::header
        count =. ".3{::header
        cursor =. cursor+1
        values =. i.0x
        while. (#values)<count do.
            values =. values,x:".&>split_words cursor{::rows
            cursor =. cursor+1
        end.
        starts =. starts,start
        samples =. samples,<values
    end.
    params =. 0$a:
    for_line. read_lines 'input/params.txt' do.
        fields =. }.split_words >line
        values =. ".&>fields
        params =. params,<values
    end.
    (<codes),(<coordinates),(<starts),(<samples),<params
)
