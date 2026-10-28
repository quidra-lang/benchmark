struct Factor
    name::String
    column::String
    power::Int
    categorical::Bool
end
function Factor(name)
    name = String(name)
    if startswith(name,"C(")
        Factor(name,name[3:end-1],1,true)
    elseif startswith(name,"I(")
        column,power = split(name[3:end-1],'^')
        Factor(name,String(column),parse(Int,power),false)
    else
        Factor(name,name,1,false)
    end
end
function parse_model(line)
    parts = split(line," weights=";limit=2)
    original = String(parts[1])
    weight = length(parts)==2 ? String(parts[2]) : nothing
    response,expressions = split(original," ~ ";limit=2)
    terms = NamedTuple[]
    seen = Set{Set{String}}()
    for expression in split(expressions," + ")
        factors = Factor.(split(expression,occursin('*',expression) ? '*' : ':'))
        if occursin('*',expression)
            subsets = [[i for i in eachindex(factors) if (mask>>(i-1))&1==1] for mask in 1:(1<<length(factors))-1]
            sort!(subsets;by=indices->(length(indices),Tuple(indices)))
            expanded = [factors[indices] for indices in subsets]
        else
            expanded = [factors]
        end
        for sequence in expanded
            names = Set(f.name for f in sequence)
            names in seen && continue
            push!(seen,names)
            push!(terms,(factors=sequence,name=join([f.name for f in sequence],":"),names=names))
        end
    end
    factor_columns = unique([f.column for term in terms for f in term.factors])
    categorical = unique([f.column for term in terms for f in term.factors if f.categorical])
    variables = vcat(factor_columns,[String(response)],isnothing(weight) ? String[] : [weight])
    (
        original=original,
        response=String(response),
        weight=weight,
        terms=terms,
        factor_columns=factor_columns,
        categorical=categorical,
        variables=variables
    )
end
contained(a,b) = length(a.names)<length(b.names) && issubset(a.names,b.names)
format_formula(model,indices) = model.response*" ~ "*(isempty(indices) ? "1" : join(
    [model.terms[i].name for i in sort(collect(indices))],
    " + "
))
removable(model,indices) = [i for i in indices if !any(contained(
    model.terms[i],
    model.terms[j]
) for j in indices)]
candidates(
    model,
    indices
) = [i for i in eachindex(model.terms) if !(i in indices) && all(j in indices for j in eachindex(model.terms) if contained(
    model.terms[j],
    model.terms[i]
))]
hierarchical(model,indices) = all(j in indices for i in indices for j in eachindex(model.terms) if contained(
    model.terms[j],
    model.terms[i]
))
function factor_value(factor,row,level)
    value = row[factor.column]
    factor.categorical && return value==level ? 1.0 : 0.0
    factor.power==2 && return value*value
    factor.power==3 && return value*value*value
    value
end
function column_value(column,row)
    isempty(column.components) && return 1.0
    value = factor_value(column.components[1].factor,row,column.components[1].level)
    for component in column.components[2:end]
        value *= factor_value(component.factor,row,component.level)
    end
    value
end
design_values(design,row) = [column_value(column,row) for column in design.columns]
function build_design(model,data)
    numbers = [i for i in eachindex(data.rows) if all(!isnothing(data.rows[i][name]) for name in model.variables)]
    rows = data.rows[numbers]
    levels = Dict(name=>sort(unique(String(row[name]) for row in rows)) for name in model.categorical)
    columns = NamedTuple[(term=0,name="(Intercept)",components=NamedTuple[])]
    for (i,term) in enumerate(model.terms)
        components = [[(
            factor=f,
            name=f.name*level,
            level=level
        ) for level in levels[f.column][2:end]] for f in term.factors if f.categorical]
        components = [f.categorical ? [(
            factor=f,
            name=f.name*level,
            level=level
        ) for level in levels[f.column][2:end]] : [(
            factor=f,
            name=f.name,
            level=nothing
        )] for f in term.factors]
        for choices in Iterators.product(components...)
            push!(columns,(term=i,name=join([c.name for c in choices],":"),components=collect(choices)))
        end
    end
    matrix = [column_value(column,row) for row in rows,column in columns]
    response = Float64[row[model.response] for row in rows]
    weights = isnothing(model.weight) ? ones(length(rows)) : Float64[row[model.weight] for row in rows]
    (
        model=model,
        numbers=numbers,
        rows=rows,
        levels=levels,
        columns=columns,
        matrix=matrix,
        response=response,
        weights=weights
    )
end
function subset_matrix(design,indices)
    columns = [j for j in eachindex(design.columns) if design.columns[j].term==0 || design.columns[j].term in indices]
    design.matrix[:,columns]
end
function predictable(design,row)
    all(!isnothing(row[name]) && (!haskey(
        design.levels,
        name
    ) || row[name] in design.levels[name]) for name in design.model.factor_columns)
end
