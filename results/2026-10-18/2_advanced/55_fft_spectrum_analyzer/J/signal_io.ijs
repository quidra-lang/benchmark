read_lines =: 3 : '<;._2 (1!:1 <y)'
split_words =: 3 : '<;._1 '' '',y'
read_inputs =: 3 : 0
    rows =. read_lines 'input/signal.csv'
    'sample_rate count' =. ".&><;._1 ',',0{::rows
    samples =. 0 2$0.0
    for_row. }.rows do.
        samples =. samples,".&><;._1 ',',>row
    end.
    parameters =. 0$a:
    for_row. read_lines 'input/params.txt' do.
        parameters =. parameters,<}.split_words >row
    end.
    (<sample_rate),(<0{"1 samples),(<1{"1 samples),<parameters
)
