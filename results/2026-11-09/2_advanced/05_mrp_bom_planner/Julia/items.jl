module Items

struct Item
    id::String
    lead::Int
    rule::String
    first::Int
    second::Int
    safety::Int
    onhand::Int
    material::Int
    labor::Int
    description::String
end

function lotvalues(rule, text)
    values = parse.(Int, split(text, '/'))
    valid = rule == "LFL" ? length(values) == 1 && values[1] == 0 : rule == "MIN" ? length(values) == 2 && all(>=(1), values) : length(values) == 1 && values[1] >= 1
    return valid ? values : nothing
end

function load(path, errors)
    items = Dict{String,Item}()
    for (number, line) in enumerate(readlines(path))
        number == 1 && continue
        fields = String.(split(line, ','))
        id, rule, parameter = fields[1], fields[3], fields[4]
        message = haskey(items, id) ? "duplicate item $id" : rule ∉ ("LFL", "FOQ", "POQ", "MIN") ? "unknown lot rule $rule" : isnothing(lotvalues(rule, parameter)) ? "bad lot parameter $parameter for $rule" : ""
        if !isempty(message)
            push!(errors, "items.csv line $number: $message")
            continue
        end
        lot = lotvalues(rule, parameter)
        items[id] = Item(id, parse(Int, fields[2]), rule, lot[1], length(lot) == 2 ? lot[2] : 0, parse(Int, fields[5]), parse(Int, fields[6]), parse(Int, fields[7]), parse(Int, fields[8]), fields[9])
    end
    return items
end

label(item) = item.rule == "MIN" ? "MIN $(item.first)/$(item.second)" : item.rule == "LFL" ? "LFL" : "$(item.rule) $(item.first)"

end
