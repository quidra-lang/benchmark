local dataset = require("dataset")
local numeric = require("numerics")
local estimator = require("estimators")
local tests = require("group_tests")
local cox = require("cox")
local plot = require("plot")
local Z = numeric.Z
local function number(value, digits)
    if value == nil then
        return "NA"
    end
    local result = string.format("%." .. (digits or 4) .. "f", value)
    if tonumber(result) == 0 then
        result = result:gsub("^-", "")
    end
    return result
end
local function integer(value)
    return value == nil and "NA" or string.format("%d", value)
end
local function append(destination, source)
    for _, value in ipairs(source) do
        destination[#destination + 1] = value
    end
end
local function select_subjects(subjects, predicate)
    local result = {}
    for _, subject in ipairs(subjects) do
        if predicate(subject) then
            result[#result + 1] = subject
        end
    end
    return result
end
local function event_count(subjects)
    local result = 0
    for _, subject in ipairs(subjects) do
        result = result + subject.event
    end
    return result
end
local function levels(subjects, variable)
    local seen, result = {}, {}
    for _, subject in ipairs(subjects) do
        local value = subject[variable]
        if not seen[value] then
            seen[value] = true
            result[#result + 1] = value
        end
    end
    table.sort(result)
    return result
end
local function percentile(rows, threshold, column)
    column = column or "survival"
    for _, row in ipairs(rows) do
        local value = row.survival == 0.0 and 0.0 or row[column]
        if value and value <= threshold then
            return row.time
        end
    end
end
local function restricted_mean(rows, tau)
    local selected, times, survival = {}, {0}, {1.0}
    for _, row in ipairs(rows) do
        if row.time <= tau then
            selected[#selected + 1] = row
            times[#times + 1] = row.time
            survival[#survival + 1] = row.survival
        end
    end
    times[#times + 1] = tau
    local tails = {}
    for index = #survival, 1, -1 do
        local rectangle = survival[index] * (times[index + 1] - times[index])
        tails[index] = index == #survival and rectangle or rectangle + tails[index + 1]
    end
    local variance = 0.0
    for index, row in ipairs(selected) do
        local tail = tails[index + 1]
        variance = variance + tail * tail * (row.events / (row.risk * (row.risk - row.events)))
    end
    local estimate, error = tails[1], math.sqrt(variance)
    return {estimate, error, estimate - Z * error, estimate + Z * error}
end
local function collection_summary(subjects, params)
    local rows = estimator.kaplan_meier(subjects)
    local life = estimator.life_table(subjects, params.width, params.intervals)
    local events, days, maximum, reverse = 0, 0, 0, {}
    for _, subject in ipairs(subjects) do
        events = events + subject.event
        days = days + subject.time
        maximum = math.max(maximum, subject.time)
        local copy = {}
        for key, value in pairs(subject) do
            copy[key] = value
        end
        copy.event = 1 - subject.event
        reverse[#reverse + 1] = copy
    end
    local rate = (1000 * events) / days
    local eta = Z / math.sqrt(events)
    local life_median, previous = nil, 1.0
    for _, row in ipairs(life) do
        if row.survival <= 0.5 then
            life_median = row.start + params.width * (previous - 0.5) / (previous - row.survival)
            break
        end
        previous = row.survival
    end
    local percentiles = {}
    for index, threshold in ipairs({0.75, 0.5, 0.25}) do
        percentiles[index] = {
            percentile = 25 * index, time = percentile(rows, threshold),
            lower = percentile(rows, threshold, "lower"), upper = percentile(rows, threshold, "upper")
        }
    end
    return {
        rows = rows, life = life, subjects = #subjects, events = events,
        censored = #subjects - events, maximum = maximum, person_days = days,
        rate = rate, rate_lower = math.exp(math.log(rate) - eta), rate_upper = math.exp(math.log(rate) + eta),
        followup = percentile(estimator.kaplan_meier(reverse), 0.5), life_median = life_median,
        percentiles = percentiles, rmst = restricted_mean(rows, params.tau)
    }
end
local function km_lines(name, subjects, summary, params)
    local lines = {
        "group " .. name .. " subjects " .. #subjects .. " events " .. summary.events .. " censored " .. summary.censored .. " max_time " .. summary.maximum,
        "person_days " .. summary.person_days .. " rate " .. number(summary.rate) .. " lower " .. number(summary.rate_lower) .. " upper " .. number(summary.rate_upper),
        "followup_median " .. integer(summary.followup),
        "life_table_median " .. number(summary.life_median)
    }
    for _, value in ipairs(summary.percentiles) do
        lines[#lines + 1] = "percentile " .. value.percentile .. " time " .. integer(value.time) .. " lower " .. integer(value.lower) .. " upper " .. integer(value.upper)
    end
    local rmst = summary.rmst
    lines[#lines + 1] = "rmst tau " .. params.tau .. " estimate " .. number(rmst[1]) .. " se " .. number(rmst[2]) .. " lower " .. number(rmst[3]) .. " upper " .. number(rmst[4])
    for _, moment in ipairs(params.report_times) do
        local row = estimator.row_at(summary.rows, moment)
        local risk, events = 0, 0
        for _, subject in ipairs(subjects) do
            if subject.time >= moment then
                risk = risk + 1
            end
            if subject.time <= moment then
                events = events + subject.event
            end
        end
        lines[#lines + 1] = "at " .. moment .. " at_risk " .. risk .. " events " .. events .. " survival " .. number(row.survival) .. " std_err " .. number(row.se) .. " lower " .. number(row.lower) .. " upper " .. number(row.upper) .. " cum_hazard " .. number(row.hazard) .. " hazard_se " .. number(row.hazard_se)
    end
    lines[#lines + 1] = "     time  at_risk   events censored survival  std_err    lower    upper  cum_haz   haz_se"
    for _, row in ipairs(summary.rows) do
        local values = {integer(row.time), integer(row.risk), integer(row.events), integer(row.censored),
            number(row.survival), number(row.se), number(row.lower), number(row.upper), number(row.hazard), number(row.hazard_se)}
        local fields = {}
        for _, value in ipairs(values) do
            fields[#fields + 1] = string.format("%9s", value)
        end
        lines[#lines + 1] = table.concat(fields)
    end
    return lines
end
local function life_lines(names, summaries)
    local lines = {"group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard"}
    for _, name in ipairs(names) do
        for _, row in ipairs(summaries[name].life) do
            lines[#lines + 1] = table.concat({name, row.start .. "-" .. row.finish, integer(row.risk), integer(row.events), integer(row.withdrawn),
                number(row.exposed, 1), number(row.q), number(row.survival), number(row.se), number(row.hazard)}, ",")
        end
    end
    return lines
end
local function baseline_line(name, subjects)
    local total, ages, males, stages = 0, {}, 0, {0, 0, 0, 0}
    for _, subject in ipairs(subjects) do
        total = total + subject.age
        ages[#ages + 1] = subject.age
        males = males + (subject.sex == "M" and 1 or 0)
        stages[subject.stage] = stages[subject.stage] + 1
    end
    local count, mean = #subjects, total / #subjects
    local variance = 0.0
    for _, subject in ipairs(subjects) do
        local difference = subject.age - mean
        variance = variance + difference * difference
    end
    table.sort(ages)
    local median = (ages[(count - 1) // 2 + 1] + ages[count // 2 + 1]) / 2.0
    return "  group " .. name .. " subjects " .. count .. " age_mean " .. number(mean) .. " age_sd " .. number(math.sqrt(variance / (count - 1))) .. " age_median " .. number(median, 1) .. " male " .. males .. " stage " .. table.concat(stages, " ")
end
local function kruskal(subjects, groups, collections)
    local ranked = numeric.copy(subjects)
    table.sort(ranked, function(a, b)
        if a.age ~= b.age then
            return a.age < b.age
        end
        return a.id < b.id
    end)
    local ranks, ties, position = {}, 0, 1
    while position <= #ranked do
        local finish = position
        while finish <= #ranked and ranked[finish].age == ranked[position].age do
            finish = finish + 1
        end
        local rank = (position + finish - 1) / 2.0
        for index = position, finish - 1 do
            ranks[ranked[index].id] = rank
        end
        local count = finish - position
        ties = ties + count * count * count - count
        position = finish
    end
    local weighted = 0.0
    for _, group in ipairs(groups) do
        local sum = 0.0
        for _, subject in ipairs(collections[group]) do
            sum = sum + ranks[subject.id]
        end
        weighted = weighted + sum * sum / #collections[group]
    end
    local count = #subjects
    local raw = 12 * weighted / (count * (count + 1)) - 3 * (count + 1)
    return raw / (1.0 - ties / (count * count * count - count))
end
local function contingency(subjects, groups, collections, variable)
    local values = levels(subjects, variable)
    local columns = {}
    for index, value in ipairs(values) do
        columns[index] = 0
        for _, subject in ipairs(subjects) do
            if subject[variable] == value then
                columns[index] = columns[index] + 1
            end
        end
    end
    local statistic = 0.0
    for _, group in ipairs(groups) do
        for index, value in ipairs(values) do
            local observed = 0
            for _, subject in ipairs(collections[group]) do
                if subject[variable] == value then
                    observed = observed + 1
                end
            end
            local expected = (#collections[group] * columns[index]) / #subjects
            statistic = statistic + (observed - expected) * (observed - expected) / expected
        end
    end
    return statistic, (#groups - 1) * (#values - 1)
end
local function baseline_lines(subjects, groups, names, collections)
    local lines = {"baseline"}
    for _, name in ipairs(names) do
        lines[#lines + 1] = baseline_line(name, collections[name])
    end
    local statistic, degrees = kruskal(subjects, groups, collections), #groups - 1
    lines[#lines + 1] = "  age kruskal_wallis chisq " .. number(statistic) .. " df " .. degrees .. " p " .. number(numeric.p(statistic, degrees))
    for _, variable in ipairs({"sex", "stage"}) do
        statistic, degrees = contingency(subjects, groups, collections, variable)
        lines[#lines + 1] = "  " .. variable .. " chisq " .. number(statistic) .. " df " .. degrees .. " p " .. number(numeric.p(statistic, degrees))
    end
    return lines
end
local function group_lines(result)
    local lines = {}
    for index, group in ipairs(result.groups) do
        local observed, expected = result.observed[index], result.expected[index]
        lines[#lines + 1] = "  group " .. group .. " events " .. integer(result.events[index]) .. " observed " .. number(observed) .. " expected " .. number(expected) .. " o_minus_e " .. number(observed - expected) .. " variance " .. number(result.covariance[index][index])
    end
    return lines
end
local function test_fields(result)
    return "chisq " .. number(result.statistic) .. " df " .. result.degrees .. " p " .. number(result.p)
end
local function overall_lines(subjects, groups)
    local lines, logrank = {}, nil
    for _, weight in ipairs(tests.weights) do
        local result = tests.test(subjects, groups, weight, #subjects)
        if weight == "logrank" then
            logrank = result
        end
        lines[#lines + 1] = "test " .. weight .. " " .. test_fields(result)
        append(lines, group_lines(result))
    end
    local trend, variance = 0.0, 0.0
    for g = 1, #groups do
        trend = trend + g * (logrank.observed[g] - logrank.expected[g])
        local inner = 0.0
        for h = 1, #groups do
            inner = inner + (g * h) * logrank.covariance[g][h]
        end
        variance = variance + inner
    end
    local statistic = trend * trend / variance
    lines[#lines + 1] = "test logrank_trend chisq " .. number(statistic) .. " df 1 p " .. number(numeric.p(statistic, 1))
    return lines
end
local function stratified_lines(subjects, groups, variable)
    local values, strata, lines = levels(subjects, variable), {}, {}
    for _, value in ipairs(values) do
        strata[#strata + 1] = select_subjects(subjects, function(s) return s[variable] == value end)
    end
    for _, weight in ipairs(tests.weights) do
        local results = {}
        for _, members in ipairs(strata) do
            results[#results + 1] = tests.test(members, groups, weight, #subjects)
        end
        local combined = tests.combine(results, groups)
        lines[#lines + 1] = "stratified " .. weight .. " by " .. variable .. " " .. test_fields(combined)
        for index, value in ipairs(values) do
            local result, members = results[index], strata[index]
            lines[#lines + 1] = "  stratum " .. value .. " subjects " .. #members .. " events " .. event_count(members) .. " chisq " .. number(result.statistic) .. " p " .. number(result.p)
        end
        append(lines, group_lines(combined))
    end
    return lines
end
local function landmark_lines(subjects, groups, landmark)
    local selected = select_subjects(subjects, function(s) return s.time > landmark end)
    local result = tests.test(selected, groups, "logrank", #subjects)
    local lines = {"landmark " .. landmark .. " subjects " .. #selected .. " " .. test_fields(result)}
    append(lines, group_lines(result))
    return lines
end
local function two_group(subjects, groups, population)
    local result = tests.test(subjects, groups, "logrank", population)
    local observed, expected = result.observed, result.expected
    result.ratio = (observed[2] / expected[2]) / (observed[1] / expected[1])
    result.variance = 1.0 / expected[1] + 1.0 / expected[2]
    result.log_ratio = math.log(result.ratio)
    result.lower = math.exp(result.log_ratio - Z * math.sqrt(result.variance))
    result.upper = math.exp(result.log_ratio + Z * math.sqrt(result.variance))
    return result
end
local function pairwise_lines(subjects, groups)
    local pairs, results, order, adjusted = {}, {}, {}, {}
    for a = 1, #groups - 1 do
        for b = a + 1, #groups do
            local pair = {groups[a], groups[b]}
            local members = select_subjects(subjects, function(s) return s.group == pair[1] or s.group == pair[2] end)
            pairs[#pairs + 1], results[#results + 1] = pair, two_group(members, pair, #subjects)
            order[#order + 1] = #pairs
        end
    end
    table.sort(order, function(a, b)
        if results[a].p ~= results[b].p then
            return results[a].p < results[b].p
        end
        return a < b
    end)
    local previous = 0.0
    for rank, index in ipairs(order) do
        previous = math.max(previous, math.min(1.0, (#pairs - rank + 1) * results[index].p))
        adjusted[index] = previous
    end
    local lines = {"pairwise logrank adjust holm"}
    for index, pair in ipairs(pairs) do
        local result = results[index]
        lines[#lines + 1] = "  " .. pair[1] .. " " .. pair[2] .. " chisq " .. number(result.statistic) .. " p " .. number(result.p) .. " p_holm " .. number(adjusted[index]) .. " hr " .. number(result.ratio) .. " lower " .. number(result.lower) .. " upper " .. number(result.upper)
    end
    return lines
end
local function subgroup_lines(subjects, groups, variables)
    local lines = {"subgroups reference " .. groups[1]}
    for _, variable in ipairs(variables) do
        local values = levels(subjects, variable)
        for b = 2, #groups do
            local results = {}
            for _, value in ipairs(values) do
                local members = select_subjects(subjects, function(s)
                    return s[variable] == value and (s.group == groups[1] or s.group == groups[b])
                end)
                local result = two_group(members, {groups[1], groups[b]}, #subjects)
                results[#results + 1] = result
                lines[#lines + 1] = "  " .. variable .. " " .. value .. " " .. groups[b] .. " subjects " .. #members .. " events " .. event_count(members) .. " hr " .. number(result.ratio) .. " lower " .. number(result.lower) .. " upper " .. number(result.upper) .. " p " .. number(result.p)
            end
            local numerator, denominator = 0.0, 0.0
            for _, result in ipairs(results) do
                local weight = 1.0 / result.variance
                numerator = numerator + weight * result.log_ratio
                denominator = denominator + weight
            end
            local mean, statistic = numerator / denominator, 0.0
            for _, result in ipairs(results) do
                statistic = statistic + (1.0 / result.variance) * (result.log_ratio - mean) * (result.log_ratio - mean)
            end
            local degrees = #values - 1
            lines[#lines + 1] = "  " .. variable .. " " .. groups[b] .. " heterogeneity chisq " .. number(statistic) .. " df " .. degrees .. " p " .. number(numeric.p(statistic, degrees))
        end
    end
    return lines
end
local function difference_fields(difference, error)
    local statistic = difference / error
    return "difference " .. number(difference) .. " se " .. number(error) .. " lower " .. number(difference - Z * error) .. " upper " .. number(difference + Z * error) .. " z " .. number(statistic) .. " p " .. number(numeric.p(statistic * statistic, 1))
end
local function rmst_lines(groups, summaries, tau)
    local lines = {"rmst_difference tau " .. tau .. " reference " .. groups[1]}
    local control = summaries[groups[1]].rmst
    for index = 2, #groups do
        local row = summaries[groups[index]].rmst
        lines[#lines + 1] = "  " .. groups[index] .. " " .. difference_fields(row[1] - control[1], math.sqrt(row[2] * row[2] + control[2] * control[2]))
    end
    return lines
end
local function rate_lines(groups, summaries)
    local lines = {"rate_ratio reference " .. groups[1]}
    local control = summaries[groups[1]]
    for index = 2, #groups do
        local row = summaries[groups[index]]
        local ratio = row.rate / control.rate
        local error = math.sqrt(1.0 / row.events + 1.0 / control.events)
        local logarithm = math.log(ratio)
        local statistic = logarithm / error
        lines[#lines + 1] = "  " .. groups[index] .. " ratio " .. number(ratio) .. " lower " .. number(math.exp(logarithm - Z * error)) .. " upper " .. number(math.exp(logarithm + Z * error)) .. " z " .. number(statistic) .. " p " .. number(numeric.p(statistic * statistic, 1))
    end
    return lines
end
local function survival_lines(groups, summaries, times)
    local lines = {"survival_difference reference " .. groups[1]}
    for _, moment in ipairs(times) do
        local control = estimator.row_at(summaries[groups[1]].rows, moment)
        for index = 2, #groups do
            local row = estimator.row_at(summaries[groups[index]].rows, moment)
            local difference = row.survival - control.survival
            local error = math.sqrt(row.se * row.se + control.se * control.se)
            lines[#lines + 1] = "  at " .. moment .. " " .. groups[index] .. " " .. difference_fields(difference, error)
        end
    end
    return lines
end
local function vectors_for(subjects, names)
    local vectors = {}
    for _, subject in ipairs(subjects) do
        local values = {}
        for _, name in ipairs(names) do
            local value
            if name == "age" or name == "stage" then
                value = subject[name]
            elseif name == "male" then
                value = subject.sex == "M" and 1 or 0
            else
                value = subject.group == name and 1 or 0
            end
            values[#values + 1] = value
        end
        vectors[#vectors + 1] = values
    end
    return vectors
end
local function is_group(name)
    return name ~= "age" and name ~= "male" and name ~= "stage"
end
local function coefficient_fields(coefficient, error)
    local statistic = coefficient / error
    return "coef " .. number(coefficient) .. " se " .. number(error) .. " z " .. number(statistic) .. " p " .. number(numeric.p(statistic * statistic, 1)) .. " hr " .. number(math.exp(coefficient)) .. " lower " .. number(math.exp(coefficient - Z * error)) .. " upper " .. number(math.exp(coefficient + Z * error))
end
local function coefficient_lines(names, beta, covariance)
    local lines = {}
    for index, name in ipairs(names) do
        lines[#lines + 1] = "term " .. name .. " " .. coefficient_fields(beta[index], math.sqrt(covariance[index][index]))
    end
    for a = 1, #names - 1 do
        if is_group(names[a]) then
            for b = a + 1, #names do
                if is_group(names[b]) then
                    local coefficient = beta[b] - beta[a]
                    local error = math.sqrt(covariance[b][b] + covariance[a][a] - 2.0 * covariance[a][b])
                    lines[#lines + 1] = "contrast " .. names[b] .. " vs " .. names[a] .. " " .. coefficient_fields(coefficient, error)
                end
            end
        end
    end
    return lines
end
local function cox_tests(subjects, vectors, names, model)
    local size, beta, final, null = #names, model.beta, model.final, model.null
    local likelihood_ratio = 2.0 * (final.loglik - null.loglik)
    local wald = 0.0
    for c = 1, size do
        local inner = 0.0
        for d = 1, size do
            inner = inner + final.information[c][d] * beta[d]
        end
        wald = wald + beta[c] * inner
    end
    local solution = numeric.solve(null.information, null.score)
    local score = 0.0
    for c = 1, size do
        score = score + null.score[c] * solution[c]
    end
    local lines = {}
    for _, item in ipairs({{"likelihood_ratio", likelihood_ratio}, {"wald", wald}, {"score", score}}) do
        lines[#lines + 1] = item[1] .. " chisq " .. number(item[2]) .. " df " .. size .. " p " .. number(numeric.p(item[2], size))
    end
    for omitted, name in ipairs(names) do
        local likelihood = null.loglik
        if size >= 2 then
            local reduced = {}
            for _, vector in ipairs(vectors) do
                local values = {}
                for c = 1, size do
                    if c ~= omitted then
                        values[#values + 1] = vector[c]
                    end
                end
                reduced[#reduced + 1] = values
            end
            likelihood = cox.fit(subjects, reduced).final.loglik
        end
        local statistic = 2.0 * (final.loglik - likelihood)
        lines[#lines + 1] = "drop " .. name .. " loglik " .. number(likelihood) .. " chisq " .. number(statistic) .. " df 1 p " .. number(numeric.p(statistic, 1))
    end
    return lines
end
local function concordance(subjects, vectors, predictors)
    local comparable, concordant, tied = 0, 0, 0
    for i, first in ipairs(subjects) do
        if first.event == 1 then
            for j, second in ipairs(subjects) do
                if i ~= j and (first.time < second.time or first.time == second.time and second.event == 0) then
                    comparable = comparable + 1
                    local equal = true
                    for c = 1, #vectors[i] do
                        if vectors[i][c] ~= vectors[j][c] then
                            equal = false
                            break
                        end
                    end
                    if equal then
                        tied = tied + 1
                    elseif predictors[i] > predictors[j] then
                        concordant = concordant + 1
                    end
                end
            end
        end
    end
    local value = (2 * concordant + tied) / (2 * comparable)
    return "concordance " .. number(value) .. " comparable " .. comparable .. " concordant " .. concordant .. " tied " .. tied
end
local function ph_lines(subjects, vectors, names, evaluation)
    local events, time_sum = {}, 0
    for index, subject in ipairs(subjects) do
        if subject.event == 1 then
            events[#events + 1] = index
            time_sum = time_sum + subject.time
        end
    end
    table.sort(events, function(a, b)
        if subjects[a].time ~= subjects[b].time then
            return subjects[a].time < subjects[b].time
        end
        return subjects[a].id < subjects[b].id
    end)
    local mean_time, lines = time_sum / #events, {}
    for c, name in ipairs(names) do
        local residuals, sum = {}, 0.0
        for _, index in ipairs(events) do
            local row = evaluation.event_sums[subjects[index].time]
            local residual = vectors[index][c] - row.s1[c] / row.s0
            residuals[#residuals + 1] = residual
            sum = sum + residual
        end
        local mean = sum / #events
        local sxy, sxx, syy = 0.0, 0.0, 0.0
        for position, index in ipairs(events) do
            local x, y = residuals[position] - mean, subjects[index].time - mean_time
            sxy, sxx, syy = sxy + x * y, sxx + x * x, syy + y * y
        end
        local correlation = sxy / math.sqrt(sxx * syy)
        local statistic = 0.5 * math.log((1.0 + correlation) / (1.0 - correlation)) * math.sqrt(#events - 3)
        lines[#lines + 1] = "ph_check " .. name .. " rho " .. number(correlation) .. " z " .. number(statistic) .. " p " .. number(numeric.p(statistic * statistic, 1))
    end
    return lines
end
local function baseline_hazard(evaluation)
    local times = {}
    for moment in pairs(evaluation.event_sums) do
        times[#times + 1] = moment
    end
    table.sort(times)
    local rows, cumulative = {}, 0.0
    for _, moment in ipairs(times) do
        local row = evaluation.event_sums[moment]
        cumulative = cumulative + row.events / row.s0
        rows[#rows + 1] = {time = moment, hazard = cumulative}
    end
    return rows
end
local function hazard_at(rows, moment)
    for index = #rows, 1, -1 do
        if rows[index].time <= moment then
            return rows[index].hazard
        end
    end
    return 0.0
end
local function residual_lines(subjects, evaluation, hazard, count)
    local residuals = {}
    for index, subject in ipairs(subjects) do
        local martingale = subject.event - hazard_at(hazard, subject.time) * math.exp(evaluation.predictors[index])
        local deviance
        if subject.event == 1 then
            deviance = math.sqrt(-2.0 * (martingale + math.log(1.0 - martingale)))
        else
            deviance = math.sqrt(-2.0 * martingale)
        end
        if martingale <= 0.0 then
            deviance = -deviance
        end
        residuals[#residuals + 1] = {subject = subject, martingale = martingale, deviance = deviance}
    end
    table.sort(residuals, function(a, b)
        if math.abs(a.deviance) ~= math.abs(b.deviance) then
            return math.abs(a.deviance) > math.abs(b.deviance)
        end
        return a.subject.id < b.subject.id
    end)
    local lines = {"residuals top " .. count}
    for index = 1, count do
        local row = residuals[index]
        local subject = row.subject
        lines[#lines + 1] = "  id " .. subject.id .. " group " .. subject.group .. " time " .. subject.time .. " event " .. subject.event .. " martingale " .. number(row.martingale) .. " deviance " .. number(row.deviance)
    end
    return lines
end
local function adjusted_lines(vectors, names, beta, groups, times, hazard)
    local means, fields, risks = {}, {}, {}
    for c, name in ipairs(names) do
        if not is_group(name) then
            local sum = 0
            for _, vector in ipairs(vectors) do
                sum = sum + vector[c]
            end
            means[name] = sum / #vectors
            fields[#fields + 1] = name .. " " .. number(means[name])
        end
    end
    if #fields == 0 then
        fields[1] = "none"
    end
    local lines = {"adjusted_survival mean " .. table.concat(fields, " ")}
    for _, group in ipairs(groups) do
        local predictor = 0.0
        for c, name in ipairs(names) do
            local value = means[name]
            if value == nil then
                value = name == group and 1 or 0
            end
            predictor = predictor + beta[c] * value
        end
        risks[group] = math.exp(predictor)
    end
    for _, moment in ipairs(times) do
        fields = {}
        local cumulative = hazard_at(hazard, moment)
        for _, group in ipairs(groups) do
            fields[#fields + 1] = group .. " " .. number(math.exp(-cumulative * risks[group]))
        end
        lines[#lines + 1] = "  at " .. moment .. " " .. table.concat(fields, " ")
    end
    fields = {}
    for _, group in ipairs(groups) do
        local median
        for _, row in ipairs(hazard) do
            if math.exp(-row.hazard * risks[group]) <= 0.5 then
                median = row.time
                break
            end
        end
        fields[#fields + 1] = group .. " " .. integer(median)
    end
    lines[#lines + 1] = "  median " .. table.concat(fields, " ")
    return lines
end
local function cox_lines(subjects, params)
    local names = params.covariates
    local vectors = vectors_for(subjects, names)
    local model = cox.fit(subjects, vectors)
    local final = model.final
    local covariance = numeric.inverse(final.information)
    local event_times = 0
    for _ in pairs(final.event_sums) do
        event_times = event_times + 1
    end
    local lines = {"cox covariates " .. table.concat(names, " ") .. " subjects " .. #subjects .. " events " .. event_count(subjects) .. " event_times " .. event_times}
    for _, iteration in ipairs(model.iterations) do
        local values = {}
        for _, value in ipairs(iteration.beta) do
            values[#values + 1] = number(value)
        end
        lines[#lines + 1] = "iter " .. iteration.iteration .. " loglik " .. number(iteration.loglik) .. " beta " .. table.concat(values, " ")
    end
    lines[#lines + 1] = "final loglik " .. number(final.loglik) .. " null_loglik " .. number(model.null.loglik)
    append(lines, coefficient_lines(names, model.beta, covariance))
    append(lines, cox_tests(subjects, vectors, names, model))
    lines[#lines + 1] = concordance(subjects, vectors, final.predictors)
    append(lines, ph_lines(subjects, vectors, names, final))
    local hazard = baseline_hazard(final)
    append(lines, residual_lines(subjects, final, hazard, params.residuals))
    append(lines, adjusted_lines(vectors, names, model.beta, params.groups, params.report_times, hazard))
    return lines
end
local function plot_lines(params, collections, summaries)
    local width, height, time_limit, divisions = table.unpack(params.plot)
    local legend, estimates = {}, {}
    for index, group in ipairs(params.groups) do
        legend[#legend + 1] = string.char(64 + index) .. " " .. group
        estimates[group] = summaries[group].rows
    end
    local lines = {"km_plot width " .. width .. " height " .. height .. " time " .. time_limit, "legend " .. table.concat(legend, " ")}
    append(lines, plot.curves(params.groups, collections, estimates, width, height, time_limit))
    lines[#lines + 1] = "time 0 to " .. time_limit .. " days, " .. time_limit // width .. " days per column"
    local times = {}
    for index = 0, divisions do
        times[#times + 1] = index * (time_limit // divisions)
    end
    lines[#lines + 1] = "at_risk " .. table.concat(times, " ")
    for _, group in ipairs(params.groups) do
        local counts = {}
        for _, moment in ipairs(times) do
            local count = 0
            for _, subject in ipairs(collections[group]) do
                if subject.time >= moment then
                    count = count + 1
                end
            end
            counts[#counts + 1] = count
        end
        lines[#lines + 1] = group .. " " .. table.concat(counts, " ")
    end
    return lines
end
local function join_sections(sections)
    local lines = {}
    for index, section in ipairs(sections) do
        if index > 1 then
            lines[#lines + 1] = ""
        end
        append(lines, section)
    end
    return lines
end
local function save(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do
        file:write(line, "\n")
    end
    file:close()
end
local subjects, params = dataset.read()
local names = numeric.copy(params.groups)
names[#names + 1] = "all"
local collections, summaries, tables = {}, {}, {}
for _, name in ipairs(names) do
    local members = name == "all" and subjects or select_subjects(subjects, function(s) return s.group == name end)
    collections[name] = members
    summaries[name] = collection_summary(members, params)
    tables[#tables + 1] = km_lines(name, members, summaries[name], params)
end
local comparisons = {
    baseline_lines(subjects, params.groups, names, collections), overall_lines(subjects, params.groups),
    stratified_lines(subjects, params.groups, params.strata), landmark_lines(subjects, params.groups, params.landmark),
    pairwise_lines(subjects, params.groups), subgroup_lines(subjects, params.groups, params.subgroups),
    rmst_lines(params.groups, summaries, params.tau), rate_lines(params.groups, summaries),
    survival_lines(params.groups, summaries, params.report_times)
}
os.execute("mkdir -p output")
save("km_tables.txt", join_sections(tables))
save("life_table.csv", life_lines(names, summaries))
save("tests.txt", join_sections(comparisons))
save("cox.txt", cox_lines(subjects, params))
save("km_plot.txt", plot_lines(params, collections, summaries))
