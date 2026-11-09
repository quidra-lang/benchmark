struct PrologClause
    head::PrologTerm
    body::Union{Nothing,PrologTerm}
    file::String
    line::Int
end
struct PrologDatabase
    predicates::Dict{PredicateIndicator,Vector{PrologClause}}
    order::Vector{PredicateIndicator}
end
PrologDatabase() = PrologDatabase(Dict{PredicateIndicator,Vector{PrologClause}}(),PredicateIndicator[])
function add_clause!(database,clause)
    key = indicator(clause.head)
    if !haskey(database.predicates,key)
        database.predicates[key] = PrologClause[]
        push!(database.order,key)
    end
    push!(database.predicates[key],clause)
end
function candidate_clauses(database,goal)
    key = indicator(goal)
    clauses = database.predicates[key]
    key[2] == 0 && return copy(clauses)
    filter(clause->same_kind(goal.arguments[1],clause.head.arguments[1]),clauses)
end
copy_clause(clause) = copy_terms(clause.head,clause.body)
