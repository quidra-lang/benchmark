run_phase =: 3 : 0
    'costs candidates phase' =. y
    iterations =. 0
    lines =. 0$a:
    candidates =. /:~candidates
    while. 1 do.
        reduced =. reduced_costs costs
        negative =. candidates#~(candidates{reduced)<0
        if. 0=#negative do. (<iterations),(<_1),<lines return. end.
        column =. {.negative
        choices =. 0 3$0x
        for_row. i.#TBeta do.
            coefficient =. (<row,column){TMatrix
            if. coefficient>0 do.
                choices =. choices,((row{TBeta)%coefficient),(row{TBasis),row
            end.
        end.
        if. 0=#choices do. (<iterations),(<column),<lines return. end.
        'ratio leaving row' =. ({./:choices){choices
        leaving =. <.leaving
        row =. <.row
        before =. column{reduced
        pivot row,column
        iterations =. iterations+1
        value =. phase display_value phase_value costs
        line =. 'PIVOT ',(integer iterations),' enter ',(column{::ColumnNames),' reduced ',fraction before
        line =. line,' leave ',(leaving{::ColumnNames),' row ',(row{::RowNames),' ratio ',fraction ratio
        lines =. lines,<line,' objective ',fraction value
    end.
)
