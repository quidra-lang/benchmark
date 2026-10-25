module Capacity

using ..Bom: manufactured

struct Center
    id::String
    minutes::Int
    efficiency::Int
    available::Int
    description::String
end

struct Operation
    number::Int
    center::String
    setup::Int
    run::Int
end

minutes(operation, quantity) = operation.setup + quantity * operation.run
operationweek(receipt, lead, index, count) = max(receipt - lead + index * lead ÷ count, 1)

function centers(path, errors)
    result = Dict{String,Center}()
    for (number, line) in enumerate(readlines(path))
        number == 1 && continue
        fields = String.(split(line, ','))
        id, time, efficiency = fields[1], parse(Int, fields[2]), parse(Int, fields[3])
        message = haskey(result, id) ? "duplicate center $id" : !(50 <= efficiency <= 150) ? "bad efficiency $efficiency" : ""
        if isempty(message)
            result[id] = Center(id, time, efficiency, time * efficiency ÷ 100, fields[4])
        else
            push!(errors, "workcenters.csv line $number: $message")
        end
    end
    return result
end

function routings(path, items, centers, graph, errors)
    result = Dict(id => Operation[] for id in keys(items))
    for (number, line) in enumerate(readlines(path))
        number == 1 && continue
        fields = String.(split(line, ','))
        id, operation, center, setup, run = fields[1], parse(Int, fields[2]), fields[3], parse(Int, fields[4]), parse(Int, fields[5])
        message = !haskey(items, id) ? "unknown item $id" : !haskey(centers, center) ? "unknown center $center" : !manufactured(graph, id) ? "purchased item $id" : run < 1 ? "bad run time $run" : any(entry -> entry.number == operation, result[id]) ? "duplicate $id operation $operation" : ""
        if isempty(message)
            push!(result[id], Operation(operation, center, setup, run))
        else
            push!(errors, "routings.csv line $number: $message")
        end
    end
    for operations in values(result)
        sort!(operations; by=operation -> operation.number)
    end
    return result
end

function level(loads, available)
    result = zeros(Int, length(loads))
    carry = 0
    for week in length(loads):-1:2
        total = loads[week] + carry
        result[week] = min(total, available)
        carry = total - result[week]
    end
    result[1] = loads[1] + carry
    return result
end

end
