struct Rule
    number::Int
    fields::Vector{String}
    name::String
    from_year::Int
    to_year::Int
    month::Int
    day::DaySpec
    at::Int
    at_type::Char
    save::Int
    letter::String
end
struct RuleInstance
    rule::Int
    nominal::Int
end
struct LineRun
    last_pre_start::Union{Nothing,Int}
    applied::Vector{Tuple{Int,Int}}
    end_time::Int
end
function instance_sequence(rules::Vector{Rule}, indices::Vector{Int})
    instances = RuleInstance[]
    for index in indices
        rule = rules[index]
        for year in rule.from_year:rule.to_year
            push!(instances, RuleInstance(index, day_value(rule.day, year, rule.month) * SECONDS_PER_DAY + rule.at))
        end
    end
    sort!(instances; by = instance -> (instance.nominal, rules[instance.rule].number))
end
adjustment(kind::Char, stdoff::Int, save::Int) = kind == 'u' ? 0 : (kind == 's' ? stdoff : stdoff + save)
function run_instances(instances::Vector{RuleInstance}, rules::Vector{Rule}, stdoff::Int, start::Int, until::Union{Nothing,Until})
    last_pre_start = nothing
    applied = Tuple{Int,Int}[]
    save = 0
    for instance in instances
        rule = rules[instance.rule]
        time = instance.nominal - adjustment(rule.at_type, stdoff, save)
        until !== nothing && time >= until.value - adjustment(until.time_type, stdoff, save) && break
        if time <= start
            last_pre_start = instance.rule
        else
            push!(applied, (time, instance.rule))
        end
        save = rule.save
    end
    end_time = until === nothing ? POS_INFINITY : until.value - adjustment(until.time_type, stdoff, save)
    LineRun(last_pre_start, applied, end_time)
end
function abbreviation(format::String, save::Int, letter::String)
    if occursin('/', format)
        fields = split(format, '/'; limit = 2)
        return String(save == 0 ? fields[1] : fields[2])
    end
    replace(format, "%s" => letter)
end
