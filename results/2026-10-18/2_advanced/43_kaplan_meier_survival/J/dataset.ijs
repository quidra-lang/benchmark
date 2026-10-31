read_lines =: 3 : '<;._2 (1!:1 <y)'
words =: 3 : '<;._1 '' '',y'
num =: 3 : '0".y'
read_inputs =: 3 : 0
    settings =. read_lines 'input/params.txt'
    Groups =: }.words 0{::settings
    ReportTimes =: num&>}.words 1{::settings
    Tau =: num 1{::words 2{::settings
    LifeWidth =: num 1{::words 3{::settings
    LifeIntervals =: num 2{::words 3{::settings
    Strata =: 1{::words 4{::settings
    Subgroups =: }.words 5{::settings
    Landmark =: num 1{::words 6{::settings
    Covariates =: }.words 7{::settings
    ResidualCount =: num 1{::words 8{::settings
    PlotSize =: num&>}.words 9{::settings
    subjects =. 0 7$0
    for_line. }.read_lines 'input/subjects.csv' do.
        fields =. <;._1 ',',>line
        row =. (num 0{::fields),(Groups i.1{fields),(num 2{::fields),(num 3{::fields),(num 4{::fields),((,'M')-:,5{::fields),num 6{::fields
        subjects =. subjects,row
    end.
    Subjects =: (/:0{"1 subjects){subjects
    0
)
