mutable struct Tableau
    row_names::Vector{String}
    column_names::Vector{String}
    values::Vector{Vector{Fraction}}
    rhs::Vector{Fraction}
    basic::Vector{Int}
end
function new_tableau(form)
    Tableau(form.row_names,form.column_names,deepcopy(form.matrix),copy(form.rhs),copy(form.initial))
end
function pivot!(tableau,row,column)
    divisor = tableau.values[row][column]
    tableau.values[row] ./= divisor
    tableau.rhs[row] /= divisor
    for other in eachindex(tableau.values)
        other == row && continue
        factor = tableau.values[other][column]
        tableau.values[other] .-= factor .* tableau.values[row]
        tableau.rhs[other] -= factor*tableau.rhs[row]
    end
    tableau.basic[row] = column
end
function reduced_costs(tableau,costs)
    [costs[column]-sum((costs[basic]*row[column] for (basic,row) in zip(tableau.basic,tableau.values));init=ZERO) for column in eachindex(costs)]
end
phase_value(tableau,costs) = sum((costs[basic]*rhs for (basic,rhs) in zip(tableau.basic,tableau.rhs));init=ZERO)
function tableau_display(tableau,heading,costs,objective)
    lines = ["TABLEAU $heading","COLUMNS " * join(tableau.column_names," ")]
    for (name,basic,row,rhs) in zip(tableau.row_names,tableau.basic,tableau.values,tableau.rhs)
        push!(lines,"ROW $name $(tableau.column_names[basic]) $(join(fraction_text.(row)," ")) | $(fraction_text(rhs))")
    end
    push!(lines,"COST $(join(fraction_text.(reduced_costs(tableau,costs))," ")) | $(fraction_text(objective(phase_value(tableau,costs))))")
    lines
end
