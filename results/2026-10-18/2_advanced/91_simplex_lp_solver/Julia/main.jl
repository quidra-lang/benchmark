include("rational.jl")
include("lp_parser.jl")
include("tableau.jl")
include("simplex.jl")
include("branch_bound.jl")
dot_exact(left,right) = sum((a*b for (a,b) in zip(left,right));init=ZERO)
function coefficients(terms,variables)
    values = Dict(name=>ZERO for name in variables)
    for (name,coefficient) in terms
        values[name] += coefficient
    end
    [values[name] for name in variables]
end
function content_check(parsed)
    parsed.error === nothing || return parsed
    variables = String[]
    expressions = [[parsed.objective];[row.terms for row in parsed.constraints]]
    for terms in expressions, (name,coefficient) in terms
        name in variables || push!(variables,name)
    end
    model = (name=parsed.name,error=nothing,direction=parsed.direction,variables=variables,constraints=parsed.constraints,
        costs=coefficients(parsed.objective,variables),matrix=[coefficients(row.terms,variables) for row in parsed.constraints],
        rhs=[row.rhs for row in parsed.constraints],comparisons=[row.comparison for row in parsed.constraints],
        lower=Union{Nothing,Fraction}[ZERO for _ in variables],upper=Union{Nothing,Fraction}[nothing for _ in variables],integer=falses(length(variables)))
    seen = Set{String}()
    for row in model.constraints
        row.name in seen && return merge(model,(error=(row.line,"duplicate constraint $(row.name)"),))
        push!(seen,row.name)
    end
    positions = Dict(name=>j for (j,name) in enumerate(variables))
    inconsistent(j) = model.lower[j] !== nothing && model.upper[j] !== nothing && model.lower[j] > model.upper[j]
    for bound in parsed.bounds
        haskey(positions,bound.name) || return merge(model,(error=(bound.line,"unknown variable $(bound.name)"),))
        j = positions[bound.name]
        bound.kind in ("lower","both") && (model.lower[j] = bound.lower)
        bound.kind in ("upper","both") && (model.upper[j] = bound.upper)
        inconsistent(j) && return merge(model,(error=(bound.line,"inconsistent bounds $(bound.name)"),))
    end
    for (line,names) in parsed.integers, name in names
        haskey(positions,name) || return merge(model,(error=(line,"unknown variable $name"),))
        j = positions[name]
        model.integer[j] = true
        model.lower[j] === nothing || (model.lower[j] = Fraction(ceil(Int64,model.lower[j])))
        model.upper[j] === nothing || (model.upper[j] = Fraction(floor(Int64,model.upper[j])))
        inconsistent(j) && return merge(model,(error=(line,"inconsistent bounds $name"),))
    end
    for (line,names) in parsed.binaries, name in names
        haskey(positions,name) || return merge(model,(error=(line,"unknown variable $name"),))
        j = positions[name]
        model.integer[j] = true
        model.lower[j],model.upper[j] = ZERO,Fraction(1)
    end
    model
end
mutable struct VariableMapping
    kind::String
    offset::Fraction
    columns::Vector{Int}
    directions::Vector{Int}
    upper_row::Union{Nothing,Int}
end
function standard_form(model,lower,upper)
    column_names,owners,directions,mappings = String[],Int[],Int[],VariableMapping[]
    for (j,name) in enumerate(model.variables)
        first_column = length(column_names)+1
        if lower[j] !== nothing
            kind,offset = "shift",lower[j]
            columns,signs,names = [first_column],[1],[name]
        elseif upper[j] !== nothing
            kind,offset = "reflect",upper[j]
            columns,signs,names = [first_column],[-1],[name * "'"]
        else
            kind,offset = "split",ZERO
            columns,signs,names = [first_column,first_column+1],[1,-1],[name * "+",name * "-"]
        end
        append!(column_names,names)
        append!(owners,fill(j,length(columns)))
        append!(directions,signs)
        push!(mappings,VariableMapping(kind,offset,columns,signs,nothing))
    end
    offsets = [mapping.offset for mapping in mappings]
    row_names = [row.name for row in model.constraints]
    matrix = [[directions[k]*row[j] for (k,j) in enumerate(owners)] for row in model.matrix]
    rhs = [value-dot_exact(row,offsets) for (row,value) in zip(model.matrix,model.rhs)]
    comparisons = copy(model.comparisons)
    for (j,mapping) in enumerate(mappings)
        (mapping.kind != "shift" || upper[j] === nothing) && continue
        mapping.upper_row = length(row_names)+1
        push!(row_names,model.variables[j] * ".ub")
        row = fill(ZERO,length(column_names))
        row[mapping.columns[1]] = Fraction(1)
        push!(matrix,row)
        push!(rhs,upper[j]-lower[j])
        push!(comparisons,"<=")
    end
    signs = ones(Int,length(row_names))
    for i in eachindex(row_names)
        if rhs[i] < 0
            matrix[i] = -matrix[i]
            rhs[i] = -rhs[i]
            signs[i] = -1
            comparisons[i] = comparisons[i] == "<=" ? ">=" : comparisons[i] == ">=" ? "<=" : "="
        end
    end
    slack = zeros(Int,length(row_names))
    artificial = Set{Int}()
    initial = zeros(Int,length(row_names))
    for (i,comparison) in enumerate(comparisons)
        comparison == "=" && continue
        slack[i] = length(column_names)+1
        push!(column_names,"s:" * row_names[i])
        for (t,row) in enumerate(matrix)
            push!(row,Fraction(t == i ? (comparison == "<=" ? 1 : -1) : 0))
        end
        comparison == "<=" && (initial[i] = slack[i])
    end
    for (i,comparison) in enumerate(comparisons)
        comparison == "<=" && continue
        column = length(column_names)+1
        push!(artificial,column)
        initial[i] = column
        push!(column_names,"a:" * row_names[i])
        for (t,row) in enumerate(matrix)
            push!(row,Fraction(t == i ? 1 : 0))
        end
    end
    direction = model.direction == "minimize" ? 1 : -1
    phase2 = [direction*directions[k]*model.costs[j] for (k,j) in enumerate(owners)]
    append!(phase2,fill(ZERO,length(column_names)-length(phase2)))
    phase1 = [Fraction(k in artificial ? 1 : 0) for k in eachindex(column_names)]
    (;column_names,row_names,mappings,matrix,rhs,signs,slack,artificial,initial,phase1,phase2,constant=dot_exact(model.costs,offsets),direction)
end
function tableau_solution(form,tableau)
    values = fill(ZERO,length(form.column_names))
    for (basic,rhs) in zip(tableau.basic,tableau.rhs)
        values[basic] = rhs
    end
    [mapping.offset+sum((direction*values[column] for (column,direction) in zip(mapping.columns,mapping.directions));init=ZERO) for mapping in form.mappings]
end
function farkas_multipliers(result)
    form = result.form
    reduced = reduced_costs(result.tableau,form.phase1)
    [form.signs[i]*(form.phase1[column]-reduced[column]) for (i,column) in enumerate(form.initial)]
end
function unbounded_ray(model,result)
    tableau,form,column = result.tableau,result.form,result.unbounded
    delta = fill(ZERO,length(form.column_names))
    delta[column] = Fraction(1)
    for (row,basic) in enumerate(tableau.basic)
        delta[basic] = -tableau.values[row][column]
    end
    ray = [sum((direction*delta[k] for (k,direction) in zip(mapping.columns,mapping.directions));init=ZERO) for mapping in form.mappings]
    ray,dot_exact(model.costs,ray)
end
function mapping_lines(model,form,lower,upper)
    lines = String[]
    for (j,mapping) in enumerate(form.mappings)
        name = model.variables[j]
        if mapping.kind == "split"
            push!(lines,"MAP $name split")
        elseif mapping.kind == "reflect"
            push!(lines,"MAP $name reflect $(fraction_text(upper[j]))")
        else
            text = "MAP $name shift $(fraction_text(lower[j]))"
            upper[j] === nothing || (text *= " upper $(fraction_text(upper[j]))")
            push!(lines,text)
        end
    end
    for (name,sign) in zip(form.row_names,form.signs)
        sign == -1 && push!(lines,"FLIP $name")
    end
    lines
end
function solve_lp(model,lower,upper,number,level)
    form = standard_form(model,lower,upper)
    tableau = new_tableau(form)
    lines = String[]
    emit(required,text) = level >= required && push!(lines,text)
    function display(heading,costs,objective)
        level >= 2 && append!(lines,tableau_display(tableau,heading,costs,objective))
    end
    phase2_value(value) = form.constant+form.direction*value
    emit(0,"SOLVE node $number rows $(length(form.row_names)) columns $(length(form.column_names)) artificials $(length(form.artificial))")
    foreach(line -> emit(1,line),mapping_lines(model,form,lower,upper))
    phase1_count,phase2_count,drives,redundant = 0,0,0,0
    infeasibility,status,unbounded = ZERO,"OPTIMAL",nothing
    if !isempty(form.artificial)
        emit(1,"PHASE 1")
        display("phase 1 start",form.phase1,identity)
        phase = run_phase!(tableau,form.phase1,eachindex(form.column_names),identity)
        phase1_count = phase.iterations
        foreach(line -> emit(1,line),phase.lines)
        infeasibility = phase_value(tableau,form.phase1)
        emit(1,"PHASE 1 END objective $(fraction_text(infeasibility)) iterations $phase1_count")
        if infeasibility > 0
            status = "INFEASIBLE"
            display("final",form.phase1,identity)
        else
            for row in eachindex(tableau.basic)
                basic = tableau.basic[row]
                basic in form.artificial || continue
                entering = findfirst(k -> !(k in form.artificial) && tableau.values[row][k] != 0,eachindex(form.column_names))
                if entering === nothing
                    redundant += 1
                    emit(1,"REDUNDANT row $(form.row_names[row])")
                else
                    leaving = form.column_names[basic]
                    pivot!(tableau,row,entering)
                    drives += 1
                    emit(1,"DRIVE row $(form.row_names[row]) enter $(form.column_names[entering]) leave $leaving")
                end
            end
        end
    end
    if status != "INFEASIBLE"
        emit(1,"PHASE 2")
        display("phase 2 start",form.phase2,phase2_value)
        candidates = [k for k in eachindex(form.column_names) if !(k in form.artificial)]
        phase = run_phase!(tableau,form.phase2,candidates,phase2_value)
        phase2_count = phase.iterations
        foreach(line -> emit(1,line),phase.lines)
        unbounded = phase.unbounded
        if unbounded !== nothing
            status = "UNBOUNDED"
            emit(1,"UNBOUNDED enter $(form.column_names[unbounded])")
        end
        value = phase2_value(phase_value(tableau,form.phase2))
        emit(1,"PHASE 2 END objective $(fraction_text(value)) iterations $phase2_count")
        display("final",form.phase2,phase2_value)
    end
    objective = status == "OPTIMAL" ? phase2_value(phase_value(tableau,form.phase2)) : nothing
    emit(0,"RESULT $status objective $(shown(objective)) phase1 $phase1_count phase2 $phase2_count drives $drives redundant $redundant")
    (;status,objective,solution=tableau_solution(form,tableau),form,tableau,unbounded,infeasibility,phase1=phase1_count,phase2=phase2_count,drives,redundant,pivots=phase1_count+phase2_count+drives,lines)
end
function statistics_line(model)
    matrix = [value for row in model.matrix for value in row if value != 0]
    objective = filter(!iszero,model.costs)
    rhs = filter(!iszero,model.rhs)
    bounds = [value for value in [model.lower;model.upper] if value !== nothing && value != 0]
    parts = ["STATS nonzeros $(length(matrix))"]
    for (name,values) in [("matrix",matrix),("objective",objective),("rhs",rhs),("bounds",bounds)]
        if isempty(values)
            push!(parts,"$name - -")
        else
            magnitudes = abs.(values)
            push!(parts,"$name $(fraction_text(minimum(magnitudes))) $(fraction_text(maximum(magnitudes)))")
        end
    end
    join(parts," ")
end
function range_endpoints(origin,coefficients,numerators)
    lower = [value/coefficient for (value,coefficient) in zip(numerators,coefficients) if coefficient > 0]
    upper = [value/coefficient for (value,coefficient) in zip(numerators,coefficients) if coefficient < 0]
    (isempty(lower) ? nothing : origin+maximum(lower),isempty(upper) ? nothing : origin+minimum(upper))
end
function objective_range(model,result,variable,reduced,nonbasic)
    form,tableau = result.form,result.tableau
    h = fill(ZERO,length(form.column_names))
    mapping = form.mappings[variable]
    for (column,direction) in zip(mapping.columns,mapping.directions)
        h[column] = Fraction(form.direction*direction)
    end
    eta = [h[column]-sum((h[basic]*tableau.values[row][column] for (row,basic) in enumerate(tableau.basic));init=ZERO) for column in nonbasic]
    range_endpoints(model.costs[variable],eta,[-reduced[column] for column in nonbasic])
end
function rhs_range(model,result,constraint)
    form,tableau = result.form,result.tableau
    rho = [form.signs[constraint]*row[form.initial[constraint]] for row in tableau.values]
    any(value != 0 && basic in form.artificial for (value,basic) in zip(rho,tableau.basic)) && return (model.rhs[constraint],model.rhs[constraint])
    range_endpoints(model.rhs[constraint],rho,-tableau.rhs)
end
function variable_status(form,basic,variable)
    mapping = form.mappings[variable]
    mapping.kind == "split" && return any(column in basic for column in mapping.columns) ? "basic" : "zero"
    mapping.kind == "reflect" && return mapping.columns[1] in basic ? "basic" : "upper"
    mapping.columns[1] in basic || return "lower"
    mapping.upper_row !== nothing && !(form.slack[mapping.upper_row] in basic) ? "upper" : "basic"
end
function sensitivity_lines(model,result)
    form,tableau = result.form,result.tableau
    reduced = reduced_costs(tableau,form.phase2)
    basic = Set(tableau.basic)
    nonbasic = [k for k in eachindex(form.column_names) if !(k in basic) && !(k in form.artificial)]
    dual = [-form.direction*form.signs[i]*reduced[form.initial[i]] for i in eachindex(model.constraints)]
    variable_reduced = [cost-dot_exact(dual,[row[j] for row in model.matrix]) for (j,cost) in enumerate(model.costs)]
    primal_degeneracy = count(pair -> !(pair[1] in form.artificial) && pair[2] == 0,zip(tableau.basic,tableau.rhs))
    dual_degeneracy = count(column -> reduced[column] == 0,nonbasic)
    dual_objective = dot_exact(dual,model.rhs)+dot_exact(variable_reduced,result.solution)
    kind = any(model.integer) ? "relaxation" : "lp"
    lines = ["MODEL $(model.name) $kind objective $(fraction_text(result.objective))","BASIS " * join(form.column_names[tableau.basic]," "),
        "DEGENERACY primal $primal_degeneracy dual $dual_degeneracy","DUAL objective $(fraction_text(dual_objective))"]
    for (i,constraint) in enumerate(model.constraints)
        lower,upper = rhs_range(model,result,i)
        push!(lines,"CONSTRAINT $(constraint.name) price $(fraction_text(dual[i])) rhs $(fraction_text(model.rhs[i])) range $(endpoint(lower,true)) $(endpoint(upper,false))")
    end
    for (j,name) in enumerate(model.variables)
        lower,upper = objective_range(model,result,j,reduced,nonbasic)
        status = variable_status(form,basic,j)
        push!(lines,"VARIABLE $name $status value $(fraction_text(result.solution[j])) reduced $(fraction_text(variable_reduced[j])) cost $(fraction_text(model.costs[j])) range $(endpoint(lower,true)) $(endpoint(upper,false))")
    end
    lines
end
function solve_model(model,level,limit)
    solve(lower,upper,number) = solve_lp(model,lower,upper,number,level)
    any(model.integer) && return branch_search(model,limit,solve)
    result = solve(model.lower,model.upper,1)
    (;status=result.status,objective=result.objective,solution=result.status == "OPTIMAL" ? result.solution : nothing,solves=[result],root=result,nodes=1,lines=String[])
end
function solution_lines(model,result)
    root = result.root
    integer_count = count(model.integer)
    lines = ["MODEL $(model.name) $(model.direction) variables $(length(model.variables)) constraints $(length(model.constraints)) integers $integer_count",statistics_line(model),"STATUS $(result.status)"]
    result.solution === nothing || push!(lines,"OBJECTIVE $(fraction_text(result.objective)) approx $(approximate(result.objective))")
    integer_count > 0 && root.status == "OPTIMAL" && push!(lines,"RELAXATION $(fraction_text(root.objective)) approx $(approximate(root.objective))")
    if root.status == "INFEASIBLE"
        push!(lines,"INFEASIBILITY $(fraction_text(root.infeasibility))")
        for (name,value) in zip(root.form.row_names,farkas_multipliers(root))
            push!(lines,"FARKAS $name $(fraction_text(value))")
        end
    end
    values = result.status == "UNBOUNDED" ? root.solution : result.solution
    if values !== nothing
        for (name,value) in zip(model.variables,values)
            push!(lines,"VALUE $name $(fraction_text(value))")
        end
    end
    if result.status == "UNBOUNDED"
        ray,rate = unbounded_ray(model,root)
        for (name,value) in zip(model.variables,ray)
            push!(lines,"RAY $name $(fraction_text(value))")
        end
        push!(lines,"RATE $(fraction_text(rate))")
    end
    if result.solution !== nothing
        for (i,constraint) in enumerate(model.constraints)
            value = dot_exact(model.matrix[i],result.solution)
            margin = model.comparisons[i] == "<=" ? model.rhs[i]-value : value-model.rhs[i]
            push!(lines,"ROW $(constraint.name) $(fraction_text(value)) $(fraction_text(margin))")
        end
    end
    integer_count > 0 && push!(lines,"NODES $(result.nodes)")
    push!(lines,"PIVOTS $(sum(lp.pivots for lp in result.solves))")
    lines
end
function main()
    settings = read_settings()
    iterations,solutions,sensitivity,tree = String[],String[],String[],String[]
    summary = ["model,status,objective,approx,relaxation,nodes,pivots"]
    statuses = Dict(status=>0 for status in ("OPTIMAL","INFEASIBLE","UNBOUNDED","NODE_LIMIT","ERROR"))
    solves,phase1,phase2,drives,analyzed,integer_models,integer_nodes,limited_models = 0,0,0,0,0,0,0,0
    for parsed in read_models()
        model = content_check(parsed)
        if model.error !== nothing
            line,message = model.error
            statuses["ERROR"] += 1
            push!(iterations,"MODEL $(model.name) error")
            append!(solutions,["MODEL $(model.name)","STATUS ERROR line $line $message"])
            push!(sensitivity,"MODEL $(model.name) skipped ERROR")
            push!(summary,"$(model.name),ERROR,-,-,-,0,0")
            continue
        end
        level,limit = get(settings.logs,model.name,settings.level),get(settings.limits,model.name,settings.limit)
        result = solve_model(model,level,limit)
        statuses[result.status] += 1
        push!(iterations,"MODEL $(model.name) level $level")
        for lp in result.solves
            append!(iterations,lp.lines)
            solves += 1
            phase1 += lp.phase1
            phase2 += lp.phase2
            drives += lp.drives
        end
        append!(solutions,solution_lines(model,result))
        if result.root.status == "OPTIMAL"
            analyzed += 1
            append!(sensitivity,sensitivity_lines(model,result.root))
        else
            push!(sensitivity,"MODEL $(model.name) skipped $(result.root.status)")
        end
        if any(model.integer)
            integer_models += 1
            integer_nodes += result.nodes
            limited_models += result.status == "NODE_LIMIT"
            push!(tree,"MODEL $(model.name) $(model.direction) integers $(count(model.integer)) node_limit $limit")
            append!(tree,result.lines)
        end
        objective = shown(result.objective)
        approx = result.objective === nothing ? "-" : approximate(result.objective)
        relaxation = shown(result.root.objective)
        pivots = sum(lp.pivots for lp in result.solves)
        push!(summary,"$(model.name),$(result.status),$objective,$approx,$relaxation,$(length(result.solves)),$pivots")
    end
    models = sum(values(statuses))
    pivots = phase1+phase2+drives
    push!(iterations,"TOTAL solves $solves phase1 $phase1 phase2 $phase2 drives $drives pivots $pivots")
    push!(solutions,"SUMMARY models $models optimal $(statuses["OPTIMAL"]) infeasible $(statuses["INFEASIBLE"]) unbounded $(statuses["UNBOUNDED"]) node_limit $(statuses["NODE_LIMIT"]) error $(statuses["ERROR"])")
    push!(sensitivity,"SUMMARY analyzed $analyzed skipped $(models-analyzed)")
    push!(tree,"SUMMARY models $integer_models nodes $integer_nodes node_limit $limited_models")
    mkpath("output")
    for (name,lines) in [("iterations.txt",iterations),("solutions.txt",solutions),("sensitivity.txt",sensitivity),("bnb_tree.txt",tree),("summary.csv",summary)]
        write(joinpath("output",name),join(lines,"\n") * "\n")
    end
end
main()
