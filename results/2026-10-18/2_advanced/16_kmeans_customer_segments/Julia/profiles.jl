struct NamingCondition
    feature::Int
    greater::Bool
    threshold::Float64
end

struct NamingRule
    name::String
    conditions::Vector{NamingCondition}
end

function read_rules(path)
    rules = NamingRule[]
    for line in readlines(path)
        fields = split(line)
        conditions = [NamingCondition(findfirst(==(fields[index]), FEATURE_NAMES), fields[index + 1] == ">", parse(Float64, fields[index + 2])) for index in 2:3:length(fields)]
        push!(rules, NamingRule(fields[1], conditions))
    end
    rules
end

rule_number(rules, center) = findfirst(rule -> all(condition.greater ? center[condition.feature] > condition.threshold : center[condition.feature] < condition.threshold for condition in rule.conditions), rules)

function original_scale(center, means, sds)
    result = Float64[]
    for (index, component) in enumerate(center)
        value = means[index] + sds[index] * component
        push!(result, SQRT_FEATURES[index] ? value * value : value)
    end
    result
end
