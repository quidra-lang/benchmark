read_lines =: 3 : '<;._2 (1!:1 <y)'
words =: 3 : '<;._1 '' '',y'
decimal =: 3 : 0
    text =. y
    text =. '_'(I.text='-')}text
    0.0+0".text
)
read_table =: 3 : 0
    lines =. read_lines y
    variables =. }.<;._1 ',',0{::lines
    ids =. 0$a:
    rows =. (0,#variables)$a:
    for_line. }.lines do.
        fields =. <;._1 ',',>line
        ids =. ids,0{fields
        rows =. rows,}.fields
    end.
    (<variables),(<ids),<rows
)
read_inputs =: 3 : 0
    'Variables IDs RawRows' =: read_table 'input/data.csv'
    'SupplementaryVariables SupplementaryIDs SupplementaryRows' =: read_table 'input/supplementary.csv'
    settings =. words&.>read_lines 'input/params.txt'
    MissingStrategy =: 1{::0{::settings
    Scaling =: 1{::1{::settings
    ComponentRule =: 1{::2{::settings
    CumulativeTarget =: decimal 1{::3{::settings
    ParallelCount =: <.decimal 1{::4{::settings
    RandomSeed =: <.decimal 2{::4{::settings
    T2Limit =: decimal 1{::5{::settings
    SpeLimit =: decimal 1{::6{::settings
    RotationCycles =: <.decimal 1{::7{::settings
    TopCount =: <.decimal 1{::8{::settings
    ScreeWidth =: <.decimal 1{::9{::settings
    BiplotSize =: <.decimal&>}.10{::settings
    Radius =: <.decimal 1{::11{::settings
    DiagnosticSize =: <.decimal&>}.12{::settings
    0
)
