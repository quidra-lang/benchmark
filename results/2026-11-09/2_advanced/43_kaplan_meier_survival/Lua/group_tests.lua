local numeric = require("numerics")
local estimator = require("estimators")
local M = {weights = {"logrank", "gehan_wilcoxon", "tarone_ware"}}
function M.empty(groups)
    return {groups = groups, events = numeric.zeros(#groups), observed = numeric.zeros(#groups),
        expected = numeric.zeros(#groups), covariance = numeric.matrix(#groups, #groups)}
end
function M.totals(subjects, groups, weight, population_size)
    local result, collections = M.empty(groups), {}
    for index, group in ipairs(groups) do
        collections[index] = {}
        for _, subject in ipairs(subjects) do
            if subject.group == group then
                collections[index][#collections[index] + 1] = subject
            end
        end
    end
    for _, row in ipairs(estimator.risk_sets(subjects)) do
        if row.events > 0 then
            local risks, deaths, n, d = {}, {}, 0, 0
            for index, members in ipairs(collections) do
                local risk, events = 0, 0
                for _, subject in ipairs(members) do
                    if subject.time >= row.time then
                        risk = risk + 1
                    end
                    if subject.time == row.time then
                        events = events + subject.event
                    end
                end
                risks[index], deaths[index] = risk, events
                n, d = n + risk, d + events
            end
            local value = 1.0
            if weight == "gehan_wilcoxon" then
                value = n / population_size
            elseif weight == "tarone_ware" then
                value = math.sqrt(n / population_size)
            end
            for h = 1, #groups do
                result.events[h] = result.events[h] + deaths[h]
                result.observed[h] = result.observed[h] + value * deaths[h]
                result.expected[h] = result.expected[h] + value * ((d * risks[h]) / n)
                if n >= 2 then
                    local factor = value * value * ((d * (n - d)) / ((n - 1) * n * n))
                    for other = 1, #groups do
                        local multiple = -(risks[h] * risks[other])
                        if h == other then
                            multiple = risks[h] * (n - risks[h])
                        end
                        result.covariance[h][other] = result.covariance[h][other] + factor * multiple
                    end
                end
            end
        end
    end
    return result
end
function M.finish(result)
    local degrees, difference, matrix = #result.groups - 1, {}, {}
    for row = 1, degrees do
        difference[row] = result.observed[row] - result.expected[row]
        matrix[row] = {}
        for column = 1, degrees do
            matrix[row][column] = result.covariance[row][column]
        end
    end
    local solution = numeric.solve(matrix, difference)
    local statistic = 0.0
    for index = 1, degrees do
        statistic = statistic + difference[index] * solution[index]
    end
    result.statistic, result.degrees, result.p = statistic, degrees, numeric.p(statistic, degrees)
    return result
end
function M.test(subjects, groups, weight, population_size)
    return M.finish(M.totals(subjects, groups, weight, population_size))
end
function M.combine(strata, groups)
    local result = M.empty(groups)
    for _, stratum in ipairs(strata) do
        for h = 1, #groups do
            result.events[h] = result.events[h] + stratum.events[h]
            result.observed[h] = result.observed[h] + stratum.observed[h]
            result.expected[h] = result.expected[h] + stratum.expected[h]
            for other = 1, #groups do
                result.covariance[h][other] = result.covariance[h][other] + stratum.covariance[h][other]
            end
        end
    end
    return M.finish(result)
end
return M
