const NO_EXPORT_COMMUNITY = (65535, 65281)
parse_community(text) = text == "NO_EXPORT" ? NO_EXPORT_COMMUNITY : Tuple(parse.(Int, split(text, ':')))
parse_communities(values) = Tuple(sort!(unique(parse_community.(values))))
community_text(value) = value == NO_EXPORT_COMMUNITY ? "NO_EXPORT" : "$(value[1]):$(value[2])"
communities_text(values) = isempty(values) ? "-" : join(community_text.(values), ",")

mutable struct BGPRule
    name::String
    active::Bool
    owner::Int
    direction::String
    target::String
    conditions::Vector{Tuple{String,Any}}
    actions::Vector{Tuple{String,Any}}
    settings::Dict{String,Any}
    hits::Int
end

function edit_communities(communities, rule)
    edited = Set{Tuple{Int,Int}}(communities)
    for (action, value) in rule.actions
        action == "ADD" && push!(edited, value)
        action == "REMOVE" && delete!(edited, value)
    end
    return Tuple(sort!(collect(edited)))
end

function read_policies()
    lists, rules = Dict{String,Vector{Any}}(), BGPRule[]
    for line in readlines("input/policies.txt")
        fields = String.(split(line, ' '))
        if fields[1] == "PLIST"
            prefix = parse_prefix(fields[4])
            bounds = Dict(fields[index] => parse(Int, fields[index + 1]) for index in 5:2:length(fields))
            low = get(bounds, "GE", prefix[2])
            high = get(bounds, "LE", haskey(bounds, "GE") ? 32 : prefix[2])
            push!(get!(lists, fields[2], Any[]), (fields[3] == "PERMIT", prefix, low, high))
            continue
        end
        separator = findfirst(==("THEN"), fields)
        conditions, actions = Tuple{String,Any}[], Tuple{String,Any}[]
        for index in 7:2:separator - 1
            condition, token = fields[index:index + 1]
            value = condition in (
                "CONTAINS",
                "ORIGINAS"
            ) ? parse(Int, token) : condition == "LENGTH" ? Tuple(parse.(
                Int,
                split(token, '-')
            )) : condition == "COMMUNITY" ? parse_community(token) : token
            push!(conditions, (condition, value))
        end
        index = separator + 1
        while index <= length(fields)
            action = fields[index]
            index += 1
            value = nothing
            if !(action in ("DENY", "ALLOW"))
                value = action in ("ADD", "REMOVE") ? parse_community(fields[index]) : parse(
                    Int,
                    fields[index]
                )
                index += 1
            end
            push!(actions, (action, value))
        end
        push!(
            rules,
            BGPRule(
                fields[2],
                fields[3] == "ON",
                parse(Int, fields[4]),
                fields[5],
                fields[6],
                conditions,
                actions,
                Dict(actions),
                0
            )
        )
    end
    return (lists=lists, rules=rules, by_name=Dict(rule.name => rule for rule in rules))
end

function prefix_permitted(policies, name, prefix)
    for (permit, base, low, high) in policies.lists[name]
        low <= prefix[2] <= high && prefix_contains(base, prefix[1]) && return permit
    end
    return false
end

function rule_matches(policies, rule, owner, link, prefix, path, communities)
    (!rule.active || rule.owner != owner) && return false
    rule.target in ("*", string(other_end(link, owner)), link.name) || return false
    for (condition, value) in rule.conditions
        condition == "PREFIX" && !prefix_permitted(policies, value, prefix) && return false
        condition == "CONTAINS" && !(value in path) && return false
        condition == "ORIGINAS" && (isempty(path) ? owner : path[end]) != value && return false
        condition == "LENGTH" && !(value[1] <= length(path) <= value[2]) && return false
        condition == "COMMUNITY" && !(value in communities) && return false
    end
    return true
end

function applied_rule(policies, direction, owner, link, prefix, path, communities)
    for rule in policies.rules
        rule.direction == direction && rule_matches(
            policies,
            rule,
            owner,
            link,
            prefix,
            path,
            communities
        ) && return rule
    end
    return nothing
end
