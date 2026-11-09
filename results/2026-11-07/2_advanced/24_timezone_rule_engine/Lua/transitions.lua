local day_rules = require("day_rules")
local M = {}
function M.instance_sequence(rules)
    local instances = {}
    for _, rule in ipairs(rules) do
        for year = rule.from_year, rule.to_year do instances[#instances + 1] = {rule = rule, nominal = rule.day:value(year, rule.month) * 86400 + rule.at} end
    end
    table.sort(instances, function(a, b) return a.nominal < b.nominal or a.nominal == b.nominal and a.rule.number < b.rule.number end)
    return instances
end
function M.adjustment(time_type, stdoff, save)
    if time_type == "u" then return 0 end
    return time_type == "s" and stdoff or stdoff + save
end
function M.run_instances(instances, stdoff, start, until_value)
    local run, save = {pre_start = {}, applied = {}, ending = day_rules.POS_INFINITY}, 0
    for _, instance in ipairs(instances) do
        local rule = instance.rule
        local time = instance.nominal - M.adjustment(rule.at_type, stdoff, save)
        if until_value and time >= until_value.value - M.adjustment(until_value.time_type, stdoff, save) then break end
        if time <= start then run.pre_start[#run.pre_start + 1] = rule else run.applied[#run.applied + 1] = {time = time, rule = rule} end
        save = rule.save
    end
    if until_value then run.ending = until_value.value - M.adjustment(until_value.time_type, stdoff, save) end
    return run
end
function M.abbreviation(format_text, save, letter)
    local separator = format_text:find("/", 1, true)
    if separator then return save == 0 and format_text:sub(1, separator - 1) or format_text:sub(separator + 1) end
    return (format_text:gsub("%%s", function() return letter end))
end
return M
