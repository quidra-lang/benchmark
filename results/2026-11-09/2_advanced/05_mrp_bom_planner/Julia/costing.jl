module Costing

struct Cost
    material::Int
    labor::Int
    total::Int
end

function rollup(items, graph, order)
    costs = Dict{String,Cost}()
    for id in reverse(order)
        material, labor = items[id].material, items[id].labor
        for edge in graph.children[id]
            child = costs[edge.child]
            material += (edge.quantity * (100 + edge.scrap) * child.material + 50) ÷ 100
            labor += (edge.quantity * (100 + edge.scrap) * child.labor + 50) ÷ 100
        end
        costs[id] = Cost(material, labor, material + labor)
    end
    return costs
end

function abc(values)
    order = sort!(collect(keys(values)); by=id -> (-values[id], id))
    total, before = sum(Base.values(values)), 0
    result = Dict{String,String}()
    for id in order
        result[id] = values[id] == 0 ? "C" : 100 * before < 80 * total ? "A" : 100 * before < 95 * total ? "B" : "C"
        before += values[id]
    end
    return result
end

end
