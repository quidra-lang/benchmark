local Z = require("numerics").Z
local M = {}
function M.risk_sets(subjects)
    local counts, events, times = {}, {}, {}
    for _, subject in ipairs(subjects) do
        local moment = subject.time
        if not counts[moment] then
            counts[moment], events[moment] = 0, 0
            times[#times + 1] = moment
        end
        counts[moment] = counts[moment] + 1
        events[moment] = events[moment] + subject.event
    end
    table.sort(times)
    local result, risk = {}, #subjects
    for _, moment in ipairs(times) do
        result[#result + 1] = {time = moment, risk = risk, events = events[moment], censored = counts[moment] - events[moment]}
        risk = risk - counts[moment]
    end
    return result
end
function M.kaplan_meier(subjects)
    local risk_rows, event_times = M.risk_sets(subjects), {}
    for _, row in ipairs(risk_rows) do
        if row.events > 0 then
            event_times[#event_times + 1] = row.time
        end
    end
    local result = {}
    local survival, greenwood, hazard, variance = 1.0, 0.0, 0.0, 0.0
    for _, row in ipairs(risk_rows) do
        if row.events > 0 then
            local n, d = row.risk, row.events
            survival = survival * ((n - d) / n)
            if n == d then
                greenwood = nil
            elseif greenwood then
                greenwood = greenwood + d / (n * (n - d))
            end
            local error, lower, upper
            if survival ~= 0.0 then
                error = survival * math.sqrt(greenwood)
                local logarithm = math.log(survival)
                local omega = Z * math.sqrt(greenwood) / (-logarithm)
                lower = math.exp(logarithm * math.exp(omega))
                upper = math.exp(logarithm * math.exp(-omega))
            end
            hazard = hazard + d / n
            variance = variance + d / (n * n)
            local following = event_times[#result + 2]
            local censored = 0
            for _, subject in ipairs(subjects) do
                if subject.event == 0 and subject.time >= row.time and (not following or subject.time < following) then
                    censored = censored + 1
                end
            end
            result[#result + 1] = {
                time = row.time, risk = n, events = d, censored = censored,
                survival = survival, se = error, lower = lower, upper = upper,
                hazard = hazard, hazard_se = math.sqrt(variance)
            }
        end
    end
    return result
end
function M.row_at(rows, moment)
    for index = #rows, 1, -1 do
        if rows[index].time <= moment then
            return rows[index]
        end
    end
    return {survival = 1.0, se = 0.0, hazard = 0.0, hazard_se = 0.0}
end
function M.life_table(subjects, width, count)
    local result, survival, variance = {}, 1.0, 0.0
    for interval = 0, count - 1 do
        local first, last = interval * width, (interval + 1) * width
        local n, d, c = 0, 0, 0
        for _, subject in ipairs(subjects) do
            if subject.time >= first then
                n = n + 1
                if subject.time < last then
                    d = d + subject.event
                    c = c + 1 - subject.event
                end
            end
        end
        local exposed = 2 * n - c
        survival = survival * ((exposed - 2 * d) / exposed)
        variance = variance + (4 * d) / (exposed * (exposed - 2 * d))
        result[#result + 1] = {
            start = first, finish = last, risk = n, events = d, withdrawn = c,
            exposed = exposed / 2.0, q = (2 * d) / exposed, survival = survival,
            se = survival * math.sqrt(variance), hazard = (2000 * d) / (width * (exposed - d))
        }
    end
    return result
end
return M
