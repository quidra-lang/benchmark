function run_phase!(tableau,costs,candidates,objective)
    iterations,lines = 0,String[]
    candidates = sort(collect(candidates))
    while true
        reduced = reduced_costs(tableau,costs)
        entering = findfirst(column -> reduced[column] < 0,candidates)
        entering === nothing && return (;iterations,unbounded=nothing,lines)
        column = candidates[entering]
        ratios = [(tableau.rhs[row]/values[column],tableau.basic[row],row) for (row,values) in enumerate(tableau.values) if values[column] > 0]
        isempty(ratios) && return (;iterations,unbounded=column,lines)
        ratio,leaving,row = minimum(ratios)
        before = reduced[column]
        pivot!(tableau,row,column)
        iterations += 1
        value = objective(phase_value(tableau,costs))
        push!(lines,"PIVOT $iterations enter $(tableau.column_names[column]) reduced $(fraction_text(before)) leave $(tableau.column_names[leaving]) row $(tableau.row_names[row]) ratio $(fraction_text(ratio)) objective $(fraction_text(value))")
    end
end
