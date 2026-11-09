restore_tableau =: 3 : 0
    'TMatrix TBeta TBasis' =: y
)
pivot =: 3 : 0
    'row column' =. y
    divisor =. (<row,column){TMatrix
    pivot_row =. (row{TMatrix)%divisor
    pivot_rhs =. (row{TBeta)%divisor
    TMatrix =: pivot_row row}TMatrix
    TBeta =: pivot_rhs row}TBeta
    for_other. i.#TBeta do.
        if. other=row do. continue. end.
        factor =. (<other,column){TMatrix
        TMatrix =: ((other{TMatrix)-factor*pivot_row)other}TMatrix
        TBeta =: ((other{TBeta)-factor*pivot_rhs)other}TBeta
    end.
    TBasis =: column row}TBasis
)
reduced_costs =: 3 : 0
    result =. y
    for_i. i.#TBeta do.
        result =. result-((i{TBasis){y)*i{TMatrix
    end.
    result
)
phase_value =: 3 : '+/(TBasis{y)*TBeta'
tableau_display =: 4 : 0
    'costs phase' =. y
    lines =. (<'TABLEAU ',x),<'COLUMNS ',' 'join ColumnNames
    for_i. i.#TBeta do.
        coefficients =. ' 'join fraction&.>i{TMatrix
        line =. 'ROW ',(i{::RowNames),' ',((i{TBasis){::ColumnNames),' ',coefficients
        lines =. lines,<line,' | ',fraction i{TBeta
    end.
    line =. 'COST ',(' 'join fraction&.>reduced_costs costs),' | '
    lines,<line,fraction phase display_value phase_value costs
)
