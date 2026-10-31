local Data = require("data_io")
local Models = require("models")
local Integrator = require("integrator")
local Fitting = require("fitting")
local Report = require("report")
local fmt = Report.fmt
local function copy(values) local result = {}; for i, value in ipairs(values) do result[i] = value end; return result end
local function map(values, fn) local result = {}; for i, value in ipairs(values) do result[i] = fn(value, i) end; return result end
local function append(a, b) for _, value in ipairs(b) do a[#a + 1] = value end end
local function slice(values, first, last) local result = {}; for i = first, last do result[#result + 1] = values[i] end; return result end
local function repeated(value, count) local result = {}; for i = 1, count do result[i] = value end; return result end
local function sum(values, integers)
    local total = integers and 0 or 0.0
    for _, value in ipairs(values) do total = total + value end
    return total
end
local function range_sum(values, first, last, integers) return sum(slice(values, first, last), integers) end
local function peak(values)
    local chosen = 1
    for i = 2, #values do if values[i] > values[chosen] then chosen = i end end
    return chosen
end
local function squared_errors(series, coefficient, observations)
    local total = 0.0
    for i, value in ipairs(series) do local difference = coefficient * value - observations[i]; total = total + difference * difference end
    return total
end
local function multiplier_sequence(interventions, days)
    local result, index = {}, 1
    for day = 1, days do
        while index < #interventions and interventions[index + 1][1] <= day do index = index + 1 end
        result[day] = interventions[index][2]
    end
    return result
end
local function final_size(reproduction)
    if reproduction <= 1 then return 0.0 end
    local lo, hi = 1 - 1 / reproduction, 1.0
    for _ = 1, 20 do
        local mid = (lo + hi) / 2
        if 1 - mid - math.exp(-reproduction * mid) > 0 then lo = mid else hi = mid end
    end
    return (lo + hi) / 2
end
local function power_method(matrix)
    local vector, eigenvalue = repeated(1 / #matrix, #matrix), nil
    for _ = 1, 200 do
        local product = {}
        for g, row in ipairs(matrix) do
            local value = 0.0
            for h, entry in ipairs(row) do value = value + entry * vector[h] end
            product[g] = value
        end
        eigenvalue = sum(product)
        vector = map(product, function(value) return value / eigenvalue end)
    end
    return eigenvalue, vector
end
local S = {}
S.__index = S
function S.new(data)
    local self = setmetatable(data, S)
    self.days, self.group_count = #self.cases, #self.groups
    self.populations = map(self.groups, function(group) return group[2] end)
    self.fatalities = map(self.groups, function(group) return group[3] end)
    self.population, self.case_total, self.death_total = sum(self.populations, true), sum(self.cases, true), sum(self.deaths, true)
    self.fatality = sum(map(self.groups, function(group) return group[2] * group[3] end)) / self.population
    self.sigma, self.gamma0 = self.params.sigma, self.params.gamma
    local e, i = table.unpack(self.params.initial)
    self.initial = { self.population - e - i, e, i, 0.0, 0.0, 0.0 }
    self.sir_initial, self.age_initial, self.age_inflows = { self.population - e - i, e + i, 0.0, 0.0 }, {}, {}
    for g, population in ipairs(self.populations) do
        local eg, ig = e * population / self.population, i * population / self.population
        append(self.age_initial, { population - eg - ig, eg, ig, 0.0, 0.0, 0.0 })
        self.age_inflows[g] = 6 * g
    end
    self.multipliers, self.week_ranges = multiplier_sequence(self.interventions, self.days), {}
    for first = 1, self.days, 7 do self.week_ranges[#self.week_ranges + 1] = { first, math.min(first + 6, self.days) } end
    self.incidence_cache, self.fit_lines, self.reproduction_lines = {}, {}, {}
    return self
end
function S:fit(...) self.fit_lines[#self.fit_lines + 1] = table.concat({ ... }, " ") end
function S:rep(...) self.reproduction_lines[#self.reproduction_lines + 1] = table.concat({ ... }, " ") end
function S:rmse(error_value, count) return math.sqrt(error_value / (count or self.days)) end
function S:seird_states(beta, gamma, multipliers, initial, sigma)
    return Integrator.simulate(Models.seird(self.population, sigma or self.sigma, self.fatality, beta, gamma), initial or self.initial, multipliers or self.multipliers, { 6 })
end
function S:incidence_for(beta, gamma)
    if not self.incidence_cache[beta] then self.incidence_cache[beta] = {} end
    local row = self.incidence_cache[beta]
    if not row[gamma] then row[gamma] = map(self:seird_states(beta, gamma), function(state) return state[6] end) end
    return row[gamma]
end
function S:error_value(beta, gamma, rho) return squared_errors(self:incidence_for(beta, gamma), rho, self.cases) end
function S:golden_records(round, name, result, value, records)
    for i, row in ipairs(records) do
        self:fit("golden", round, name, i - 1, "a", fmt(row[1], 6), "b", fmt(row[2], 6), "c", fmt(row[3], 6), "d", fmt(row[4], 6), "rmse", fmt(self:rmse(row[5])), fmt(self:rmse(row[6])))
    end
    self:fit("golden_result", round, name, fmt(result, 6), "sse", fmt(value, 1))
end
function S:fit_model()
    local bmin, bmax, nb = table.unpack(self.params.beta_grid)
    local rmin, rmax, nr = table.unpack(self.params.rho_grid)
    local betas, rhos = {}, {}
    for i = 0, nb - 1 do betas[i + 1] = bmin + (bmax - bmin) * i / (nb - 1) end
    for j = 0, nr - 1 do rhos[j + 1] = rmin + (rmax - rmin) * j / (nr - 1) end
    self.delta_beta, self.delta_rho = (bmax - bmin) / (nb - 1), (rmax - rmin) / (nr - 1)
    self:fit("data days", self.days, "cases", self.case_total, "deaths", self.death_total, "population", self.population, "fatality", fmt(self.fatality, 6))
    self:fit("grid gamma", fmt(self.gamma0), "rho", table.concat(map(rhos, function(value) return fmt(value) end), " "))
    for _, beta in ipairs(betas) do
        local errors = {}
        for _, rho in ipairs(rhos) do
            local error_value = self:error_value(beta, self.gamma0, rho)
            errors[#errors + 1] = fmt(self:rmse(error_value), 2)
            if not self.sse_grid or error_value < self.sse_grid then self.sse_grid, self.beta_grid, self.rho_grid = error_value, beta, rho end
        end
        self:fit("grid beta", fmt(beta), "rmse", table.concat(errors, " "))
    end
    self:fit("grid_best beta", fmt(self.beta_grid), "rho", fmt(self.rho_grid), "sse", fmt(self.sse_grid, 1), "rmse", fmt(self:rmse(self.sse_grid)))
    local beta, rho = self.beta_grid, self.rho_grid
    local iterations, rounds = table.unpack(self.params.golden)
    for round = 1, rounds do
        local result, value, records = Fitting.golden(function(x) return self:error_value(x, self.gamma0, rho) end, beta - self.delta_beta, beta + self.delta_beta, iterations)
        self:golden_records(round, "beta", result, value, records)
        beta = result
        result, value, records = Fitting.golden(function(x) return self:error_value(beta, self.gamma0, x) end, rho - self.delta_rho, rho + self.delta_rho, iterations)
        self:golden_records(round, "rho", result, value, records)
        rho, self.sse_golden = result, value
    end
    self.beta_golden, self.rho = beta, rho
    local simplex, nm = self.params.simplex, self.params.nelder_mead
    local initial, records, final = Fitting.nelder_mead(function(b, g) return self:error_value(b, g, rho) end, beta, self.gamma0, simplex[1], simplex[2], nm[1], nm[2], nm[3], nm[4], nm[5])
    for _, vertex in ipairs(initial) do self:fit("simplex", vertex.number, "beta", fmt(vertex.beta, 6), "gamma", fmt(vertex.gamma, 6), "rmse", fmt(self:rmse(vertex.value))) end
    for i, record in ipairs(records) do local vertex = record[2]; self:fit("nelder_mead", i, record[1], "beta", fmt(vertex.beta, 6), "gamma", fmt(vertex.gamma, 6), "rmse", fmt(self:rmse(vertex.value))) end
    for i, vertex in ipairs(final) do self:fit("final_simplex", i, "beta", fmt(vertex.beta, 6), "gamma", fmt(vertex.gamma, 6), "rmse", fmt(self:rmse(vertex.value))) end
    self.beta, self.gamma, self.sse_nm = final[1].beta, final[1].gamma, final[1].value
    self.r0 = self.beta / self.gamma
    local mean = self.case_total / self.days
    local sst = sum(map(self.cases, function(value) local difference = value - mean; return difference * difference end))
    self:fit("fitted beta", fmt(self.beta, 6), "gamma", fmt(self.gamma, 6), "rho", fmt(self.rho, 6), "sigma", fmt(self.sigma, 6), "r0", fmt(self.r0))
    self:fit("sse grid", fmt(self.sse_grid, 1), "golden", fmt(self.sse_golden, 1), "nelder_mead", fmt(self.sse_nm, 1), "rmse", fmt(self:rmse(self.sse_nm)), "r2", fmt(1 - self.sse_nm / sst))
    for _, stage in ipairs({ { "grid", self.beta_grid, self.gamma0, self.rho_grid, self.sse_grid }, { "golden", self.beta_golden, self.gamma0, self.rho, self.sse_golden }, { "nelder_mead", self.beta, self.gamma, self.rho, self.sse_nm } }) do
        self:fit("stage", stage[1], "beta", fmt(stage[2], 6), "gamma", fmt(stage[3], 6), "rho", fmt(stage[4], 6), "r0", fmt(stage[2] / stage[3]), "rmse", fmt(self:rmse(stage[5])))
    end
end
function S:death_analysis()
    local numerator, denominator = 0.0, 0.0
    for i, value in ipairs(self.model_deaths) do numerator, denominator = numerator + value * self.deaths[i], denominator + value * value end
    local scale = numerator / denominator
    self:fit("deaths observed", self.death_total, "model", fmt(self.states[self.days][5], 1), "rmse", fmt(self:rmse(squared_errors(self.model_deaths, 1.0, self.deaths))), "scale", fmt(scale), "implied_fatality", fmt(self.fatality * scale, 6), "cfr", fmt(self.death_total / self.case_total))
    local correlations = {}
    for lag = 0, self.params.death_lag do
        local a, b, y = 0, 0, 0
        for d = 1, self.days - lag do a, b, y = a + self.cases[d] * self.deaths[d + lag], b + self.cases[d] * self.cases[d], y + self.deaths[d + lag] * self.deaths[d + lag] end
        local correlation = a / math.sqrt((b + 0.0) * (y + 0.0))
        correlations[#correlations + 1] = correlation
        self:fit("death_lag", lag, "correlation", fmt(correlation), "cfr", fmt(range_sum(self.deaths, lag + 1, self.days, true) / range_sum(self.cases, 1, self.days - lag, true)))
    end
    self:fit("death_best_lag", peak(correlations) - 1)
end
function S:fitted_diagnostics()
    self.states = self:seird_states(self.beta, self.gamma)
    self.states[0] = self.initial
    self.incidence = map(self.states, function(state) return state[6] end)
    self.reported = map(self.incidence, function(value) return self.rho * value end)
    self.residuals, self.model_deaths, self.rt, self.averages, self.cumulative_cases, self.cumulative_reported = {}, {}, {}, {}, {}, {}
    local observed_total, reported_total, runs, positive, u, difference_sum = 0, 0.0, 1, 0, 0.0, 0.0
    for d = 1, self.days do
        local residual = self.cases[d] - self.reported[d]
        self.residuals[d], self.model_deaths[d] = residual, self.states[d][5] - self.states[d - 1][5]
        self.rt[d] = self.r0 * self.multipliers[d] * self.states[d - 1][1] / self.population
        self.averages[d] = range_sum(self.cases, math.max(1, d - 6), d, true) / math.min(d, 7)
        observed_total, reported_total = observed_total + self.cases[d], reported_total + self.reported[d]
        self.cumulative_cases[d], self.cumulative_reported[d] = observed_total, reported_total
        u = u + residual * residual
        if residual > 0 then positive = positive + 1 end
        if d > 1 then
            local difference = residual - self.residuals[d - 1]
            difference_sum = difference_sum + difference * difference
            if (residual > 0) ~= (self.residuals[d - 1] > 0) then runs = runs + 1 end
        end
    end
    self.reported_total = reported_total
    local absolute = map(self.residuals, math.abs)
    local largest, correlations = peak(absolute), {}
    self:fit("residuals sum", fmt(sum(self.residuals), 1), "mae", fmt(sum(absolute) / self.days, 1), "max", fmt(self.residuals[largest], 1), "day", largest, "positive", positive, "runs", runs, "durbin_watson", fmt(difference_sum / u))
    for lag = 1, 7 do
        local value = 0.0
        for d = 1, self.days - lag do value = value + self.residuals[d] * self.residuals[d + lag] end
        correlations[lag] = fmt(value / u)
    end
    self:fit("autocorrelation", table.concat(correlations, " "))
    local outliers, factors = 0, {}
    for d, residual in ipairs(self.residuals) do
        local z = residual / math.sqrt(self.reported[d])
        if math.abs(z) > self.params.outlier then self:fit("outlier", d, "observed", self.cases[d], "fitted", fmt(self.reported[d], 1), "z", fmt(z)); outliers = outliers + 1 end
    end
    self:fit("outliers", outliers)
    for weekday = 1, 7 do
        local observed, fitted = 0, 0.0
        for d = weekday, self.days, 7 do observed, fitted = observed + self.cases[d], fitted + self.reported[d] end
        factors[weekday] = observed / fitted
        self:fit("weekday", weekday, "observed", observed, "fitted", fmt(fitted, 1), "factor", fmt(factors[weekday]))
    end
    local adjusted = map(self.reported, function(value, i) return value * factors[(i - 1) % 7 + 1] end)
    self:fit("weekday_adjusted rmse", fmt(self:rmse(squared_errors(adjusted, 1.0, self.cases))))
    local infections = sum(self.incidence)
    self:fit("burden infections", fmt(infections, 1), "ascertainment", fmt(self.case_total / infections), "deaths_per_infection", fmt(self.death_total / infections, 6))
    self:death_analysis()
    local previous
    for week, period in ipairs(self.week_ranges) do
        local first, last = table.unpack(period)
        local observed = range_sum(self.cases, first, last, true)
        self:fit("weekly", week, "days", first, last, "observed", observed, "fitted", fmt(range_sum(self.reported, first, last), 1), "deaths_observed", range_sum(self.deaths, first, last, true), "deaths_model", fmt(range_sum(self.model_deaths, first, last), 1), "growth", previous and fmt(observed / previous) or "-")
        previous = observed
    end
end
function S:profiles()
    local fitted, names, variance = { self.beta, self.gamma, self.rho }, { "beta", "gamma", "rho" }, self.sse_nm / (self.days - 3)
    self.standard_errors = {}
    for i, name in ipairs(names) do
        local value, errors = fitted[i], {}
        for offset = -5, 5 do
            local point, parameters = value * (1 + offset / 100), copy(fitted)
            parameters[i] = point
            errors[offset] = self:error_value(table.unpack(parameters))
            self:fit("profile", name, offset, "value", fmt(point, 6), "rmse", fmt(self:rmse(errors[offset])))
        end
        local h = value / 100
        local curvature = (errors[1] - 2 * errors[0] + errors[-1]) / (h * h)
        self.standard_errors[name] = math.sqrt(2 * variance / curvature)
        self:fit("profile_se", name, fmt(self.standard_errors[name], 6))
    end
end
function S:backtest()
    local holdout = self.params.holdout
    local count, iterations = self.days - holdout, self.params.golden[1]
    local multipliers, observations, cache = slice(self.multipliers, 1, count), slice(self.cases, 1, count), {}
    local function objective(beta, rho)
        if not cache[beta] then cache[beta] = map(self:seird_states(beta, self.gamma, multipliers), function(state) return state[6] end) end
        return squared_errors(cache[beta], rho, observations)
    end
    local beta = Fitting.golden(function(value) return objective(value, self.rho) end, self.beta - self.delta_beta, self.beta + self.delta_beta, iterations)
    local rho, error_value = Fitting.golden(function(value) return objective(beta, value) end, self.rho - self.delta_rho, self.rho + self.delta_rho, iterations)
    local forecasts = map(slice(self:incidence_for(beta, self.gamma), count + 1, self.days), function(value) return rho * value end)
    local actual = slice(self.cases, count + 1, self.days)
    self:fit("backtest train_days", count, "beta", fmt(beta, 6), "rho", fmt(rho, 6), "train_rmse", fmt(self:rmse(error_value, count)), "test_rmse", fmt(self:rmse(squared_errors(forecasts, 1.0, actual), holdout)), "full_fit_test_rmse", fmt(self:rmse(squared_errors(slice(self.reported, count + 1, self.days), 1.0, actual), holdout)))
    for i, forecast in ipairs(forecasts) do self:fit("backtest_day", count + i, "observed", actual[i], "forecast", fmt(forecast, 1), "error", fmt(actual[i] - forecast, 1)) end
end
function S:estimate_effects()
    local estimated, after, width = copy(self.interventions), self.sse_nm, self.params.effect_width
    for i = 2, #self.interventions do
        local day, given = table.unpack(self.interventions[i])
        local function objective(value)
            local changed = copy(estimated)
            changed[i] = { day, value }
            local incidence = map(self:seird_states(self.beta, self.gamma, multiplier_sequence(changed, self.days)), function(state) return state[6] end)
            return squared_errors(incidence, self.rho, self.cases)
        end
        local value
        value, after = Fitting.golden(objective, given - width, given + width, self.params.golden[1])
        estimated[i] = { day, value }
        self:fit("effect", i, "day", day, "given", fmt(given), "estimated", fmt(value, 6), "sse", fmt(after, 1))
    end
    self:fit("effect_sse before", fmt(self.sse_nm, 1), "after", fmt(after, 1), "rmse", fmt(self:rmse(after)))
end
function S:sensitivity()
    for i, name in ipairs({ "beta", "gamma", "sigma", "rho" }) do
        for _, factor in ipairs({ 0.9, 1.1 }) do
            local values = { self.beta, self.gamma, self.sigma, self.rho }
            values[i] = values[i] * factor
            local beta, gamma, sigma, rho = table.unpack(values)
            local states = self:seird_states(beta, gamma, nil, nil, sigma)
            local incidence = map(states, function(state) return state[6] end)
            local day = peak(incidence)
            self:fit("sensitivity", name, fmt(factor, 2), "r0", fmt(beta / gamma), "rmse", fmt(self:rmse(squared_errors(incidence, rho, self.cases))), "peak_day", day, "peak", fmt(rho * incidence[day], 1), "attack", fmt((self.population - states[#states][1]) / self.population))
        end
    end
end
function S:age_states_for(contacts, multipliers, initial)
    return Integrator.simulate(Models.age_seird(self.populations, self.fatalities, self.sigma, self.beta, self.gamma, contacts or self.normalized_contacts), initial or self.age_initial, multipliers or self.multipliers, self.age_inflows)
end
function S:next_generation(contacts)
    local matrix = {}
    for g, row in ipairs(contacts) do matrix[g] = {}; for h, value in ipairs(row) do matrix[g][h] = self.r0 * value * self.populations[g] / self.populations[h] end end
    return matrix
end
function S:analyze_age()
    local rows = map(self.contacts, function(row) return sum(row) end)
    self.kbar = sum(map(rows, function(value, g) return self.populations[g] * value end)) / self.population
    self.normalized_contacts = map(self.contacts, function(row) return map(row, function(value) return value / self.kbar end) end)
    local matrix = self:next_generation(self.normalized_contacts)
    local reproduction, eigenvector = power_method(matrix)
    self.age_lines = {}
    local function add(...) self.age_lines[#self.age_lines + 1] = table.concat({ ... }, " ") end
    for g, row in ipairs(matrix) do add("ngm", self.groups[g][1], table.concat(map(row, function(value) return fmt(value) end), " ")) end
    add("r0_age", fmt(reproduction), "ratio", fmt(reproduction / self.r0), "kbar", fmt(self.kbar), "eigenvector", table.concat(map(eigenvector, function(value) return fmt(value) end), " "))
    local final = repeated(1.0, self.group_count)
    for _ = 1, 100 do
        local changed = {}
        for g, row in ipairs(self.normalized_contacts) do
            local pressure = 0.0
            for h, value in ipairs(row) do pressure = pressure + self.r0 * value * final[h] end
            changed[g] = 1 - math.exp(-pressure)
        end
        final = changed
    end
    local long_states = self:age_states_for(nil, repeated(1.0, 730))
    local simulated = map(self.populations, function(population, g) return (population - long_states[#long_states][6 * (g - 1) + 1]) / population end)
    for g, group in ipairs(self.groups) do add("final_size_age", group[1], "equation", fmt(final[g]), "simulated", fmt(simulated[g])) end
    add("final_size_age total equation", fmt(sum(map(final, function(value, g) return self.populations[g] * value end)) / self.population), "simulated", fmt(sum(map(simulated, function(value, g) return self.populations[g] * value end)) / self.population))
    self.age_states = self:age_states_for()
    self.age_states[0] = self.age_initial
    self.age_incidence = map(self.age_states, function(state)
        local total = 0.0
        for _, i in ipairs(self.age_inflows) do total = total + state[i] end
        return total
    end)
    for day = 1, self.days, 7 do
        local previous, current = self.age_states[day - 1], {}
        for g, row in ipairs(self.normalized_contacts) do
            current[g] = {}
            for h, value in ipairs(row) do current[g][h] = self.multipliers[day] * self.r0 * value * previous[6 * (g - 1) + 1] / self.populations[h] end
        end
        local value = power_method(current)
        add("age_rt", day, fmt(value), "homogeneous", fmt(self.rt[day]))
    end
    for week, period in ipairs(self.week_ranges) do
        local first, last, totals = period[1], period[2], {}
        for g = 1, self.group_count do
            local total = 0.0
            for day = first, last do total = total + self.age_states[day][6 * g] end
            totals[g] = fmt(total, 1)
        end
        add("age_weekly", week, "days", first, last, table.concat(totals, " "))
    end
    local infections = {}
    for g = 1, self.group_count do
        local total = 0.0
        for day = 1, self.days do total = total + self.age_states[day][6 * g] end
        infections[g] = total
    end
    local infection_total = sum(infections)
    for g, group in ipairs(self.groups) do
        local incidence = map(self.age_states, function(state) return state[6 * g] end)
        local day = peak(incidence)
        local last = self.age_states[self.days]
        add("age", group[1], "attack", fmt((group[2] - last[6 * (g - 1) + 1]) / group[2]), "infections", fmt(infections[g], 1), "share", fmt(infections[g] / infection_total), "deaths", fmt(last[6 * (g - 1) + 5], 1), "peak_day", day, "peak", fmt(incidence[day], 1))
    end
    local group_numbers = {}
    for g, group in ipairs(self.groups) do group_numbers[group[1]] = g end
    for _, change in ipairs(self.params.contact_change) do
        local name, target, factor = table.unpack(change)
        local target_number, contacts = group_numbers[target], {}
        for g, row in ipairs(self.normalized_contacts) do
            contacts[g] = {}
            for h, value in ipairs(row) do contacts[g][h] = value * (g == target_number and factor or 1.0) * (h == target_number and factor or 1.0) end
        end
        local value = power_method(self:next_generation(contacts))
        local states = self:age_states_for(contacts)
        local incidence, deaths, attack = 0.0, 0.0, 0.0
        for _, state in ipairs(states) do
            local daily = 0.0
            for g = 1, self.group_count do daily = daily + state[6 * g] end
            incidence = incidence + daily
        end
        for g, population in ipairs(self.populations) do deaths, attack = deaths + states[self.days][6 * (g - 1) + 5], attack + (population - states[self.days][6 * (g - 1) + 1]) end
        add("contact_change", name, "group", target, "factor", fmt(factor), "r0_age", fmt(value), "infections", fmt(incidence, 1), "deaths", fmt(deaths, 1), "attack", fmt(attack / self.population))
    end
end
function S:sir_incidence(beta)
    local states = Integrator.simulate(Models.sir(self.population, beta, self.gamma), self.sir_initial, self.multipliers, { 4 })
    return map(states, function(state) return state[4] end)
end
function S:compare_models()
    for _, pair in ipairs({ { "sir", self:sir_incidence(self.beta) }, { "seir", self.incidence }, { "age", self.age_incidence } }) do
        local name, incidence = pair[1], pair[2]
        local numerator, denominator = 0.0, 0.0
        for d, value in ipairs(incidence) do numerator, denominator = numerator + self.cases[d] * value, denominator + value * value end
        local rho = numerator / denominator
        self:fit("model", name, "rmse", fmt(self:rmse(squared_errors(incidence, self.rho, self.cases))), "peak_day", peak(incidence), "rho_opt", fmt(rho, 6), "rmse_opt", fmt(self:rmse(squared_errors(incidence, rho, self.cases))))
    end
    local beta, value = Fitting.golden(function(x) return squared_errors(self:sir_incidence(x), self.rho, self.cases) end, self.params.beta_grid[1], self.params.beta_grid[2], self.params.golden[1])
    self:fit("model sir_fit beta", fmt(beta, 6), "rmse", fmt(self:rmse(value)), "peak_day", peak(self:sir_incidence(beta)))
end
function S:generation_interval()
    local length = self.params.generation
    local states = Integrator.simulate(Models.generation(self.sigma, self.gamma), { 1.0, 0.0, 0.0 }, repeated(1.0, length), { 3 })
    local amounts = map(states, function(state) return state[3] end)
    local coverage = sum(amounts)
    local weights = map(amounts, function(value) return value / coverage end)
    local mean = sum(map(weights, function(value, day) return (day - 0.5) * value end))
    self:rep("generation mean", fmt(mean), "theory", fmt(1 / self.sigma + 1 / self.gamma), "coverage", fmt(coverage))
    for day, weight in ipairs(weights) do self:rep("generation_weight", day, fmt(weight, 6)) end
    local pressures = {}
    for day = 1, self.days do
        local total = 0.0
        for lag = 1, math.min(length, day - 1) do total = total + weights[lag] * self.cases[day - lag] end
        pressures[day] = total
    end
    self.empirical_rt = {}
    for day = 1, self.days do
        self.empirical_rt[day] = day >= length + 7 and range_sum(self.cases, day - 6, day, true) / range_sum(pressures, day - 6, day) or false
    end
end
function S:epidemic_peaks()
    local day = peak(self.incidence)
    local infectious = map(self.states, function(state) return state[3] end)
    local infectious_day = peak(infectious)
    self:rep("peak model day", day, "incidence", fmt(self.incidence[day], 1), "reported", fmt(self.reported[day], 1), "infectious_day", infectious_day, "infectious", fmt(infectious[infectious_day], 1))
    local observed_day, average_day = peak(self.cases), peak(self.averages)
    self:rep("peak observed day", observed_day, "cases", self.cases[observed_day], "average7_day", average_day, "average7", fmt(self.averages[average_day], 2))
end
function S:periods_and_milestones()
    for i, intervention in ipairs(self.interventions) do
        local first, multiplier = table.unpack(intervention)
        local last = i < #self.interventions and self.interventions[i + 1][1] - 1 or self.days
        local residuals = slice(self.residuals, first, last)
        local error_value = sum(map(residuals, function(value) return value * value end))
        self:rep("period", i, "days", first, last, "multiplier", fmt(multiplier), "rt_start", fmt(self.rt[first]), "rt_end", fmt(self.rt[last]), "observed", range_sum(self.cases, first, last, true), "fitted", fmt(range_sum(self.reported, first, last), 1), "rmse", fmt(self:rmse(error_value, last - first + 1)), "bias", fmt(sum(residuals) / (last - first + 1), 1))
    end
    for _, target in ipairs(self.params.milestones) do
        local observed, fitted = "never", "never"
        for day = 1, self.days do if self.cumulative_cases[day] >= target then observed = day; break end end
        for day = 1, self.days do if self.cumulative_reported[day] >= target then fitted = day; break end end
        self:rep("milestone", target, "observed", observed, "fitted", fitted)
    end
end
function S:counterfactual_reported(interventions)
    return map(self:seird_states(self.beta, self.gamma, multiplier_sequence(interventions, self.days)), function(state) return self.rho * state[6] end)
end
function S:counterfactuals()
    local reported = self:counterfactual_reported({ self.interventions[1] })
    local total, day = sum(reported), peak(reported)
    self:rep("counterfactual none reported", fmt(total, 1), "peak_day", day, "peak", fmt(reported[day], 1), "averted", fmt(total - self.reported_total, 1))
    for i = 2, #self.interventions do
        local changed = {}
        for j, intervention in ipairs(self.interventions) do if j ~= i then changed[#changed + 1] = intervention end end
        local value = sum(self:counterfactual_reported(changed))
        self:rep("counterfactual without", i, "reported", fmt(value, 1), "averted", fmt(value - self.reported_total, 1))
    end
    for i = 2, #self.interventions do
        for _, shift in ipairs({ -7, 7 }) do
            local changed = copy(self.interventions)
            changed[i] = { changed[i][1] + shift, changed[i][2] }
            local value = sum(self:counterfactual_reported(changed))
            self:rep("timing", i, "shift", shift, "reported", fmt(value, 1), "change", fmt(value - self.reported_total, 1))
        end
    end
end
function S:analyze_reproduction()
    self:rep("r0", fmt(self.r0), "herd_immunity", fmt(1 - 1 / self.r0))
    local long_states = self:seird_states(self.beta, self.gamma, repeated(1.0, 730))
    self:rep("final_size equation", fmt(final_size(self.r0)), "simulated", fmt((self.population - long_states[#long_states][1]) / self.population))
    self:generation_interval(); self:epidemic_peaks(); self:periods_and_milestones(); self:counterfactuals()
    for day = 2, self.days do if (self.rt[day] < 1) ~= (self.rt[day - 1] < 1) then self:rep("rt_cross day", day, self.rt[day] < 1 and "down" or "up") end end
    for day = 1, self.days do self:rep("rt", day, "model", fmt(self.rt[day]), "empirical", self.empirical_rt[day] and fmt(self.empirical_rt[day]) or "-") end
    append(self.reproduction_lines, self.age_lines)
end
function S:scenario_projections()
    local horizon, threshold = self.params.horizon, self.params.threshold
    self.scenario_rows = { "scenario,day,incidence,reported" }
    local baseline
    for _, scenario in ipairs(self.params.scenario) do
        local name, multiplier = table.unpack(scenario)
        local future = repeated(multiplier, horizon)
        local states = self:seird_states(self.beta, self.gamma, future, self.states[self.days])
        local incidence = map(states, function(state) return state[6] end)
        local reported = map(incidence, function(value) return self.rho * value end)
        local below, above, total = "never", 0, sum(reported)
        for i, value in ipairs(reported) do
            self.scenario_rows[#self.scenario_rows + 1] = table.concat({ name, self.days + i, fmt(incidence[i], 1), fmt(value, 1) }, ",")
            if value < threshold and below == "never" then below = self.days + i end
            if value >= threshold then above = above + 1 end
        end
        if baseline == nil then baseline = total end
        local day = peak(reported)
        local reproduction = self.r0 * multiplier * self.states[self.days][1] / self.population
        self:rep("scenario", name, "multiplier", fmt(multiplier), "rt", fmt(reproduction), "reported", fmt(total, 1), "peak_day", self.days + day, "peak", fmt(reported[day], 1), "attack", fmt((self.population - states[horizon][1]) / self.population), "final_size", fmt(final_size(self.r0 * multiplier)), "averted", fmt(baseline - total, 1), "below", below, "days_above", above)
        local beta_low, beta_high = self.beta - 2 * self.standard_errors.beta, self.beta + 2 * self.standard_errors.beta
        local full_multipliers, band = copy(self.multipliers), {}
        append(full_multipliers, future)
        for i, beta in ipairs({ beta_low, beta_high }) do
            local full = self:seird_states(beta, self.gamma, full_multipliers)
            local value = 0.0
            for day_index = self.days + 1, #full do value = value + self.rho * full[day_index][6] end
            band[i] = value
        end
        self:rep("scenario_band", name, "beta_low", fmt(beta_low, 6), "reported_low", fmt(band[1], 1), "beta_high", fmt(beta_high, 6), "reported_high", fmt(band[2], 1))
        local age_states = self:age_states_for(nil, future, self.age_states[self.days])
        local attacks, deaths = {}, 0.0
        for g, population in ipairs(self.populations) do
            attacks[g] = fmt((population - age_states[horizon][6 * (g - 1) + 1]) / population)
            deaths = deaths + age_states[horizon][6 * (g - 1) + 5]
        end
        self:rep("scenario_age", name, "attack", table.concat(attacks, " "), "deaths", fmt(deaths, 1))
    end
end
function S:trajectories()
    local lines = { "day,S,E,I,R,D,incidence,reported,observed,average7,cumulative_observed,cumulative_reported" }
    for day = 1, self.days do
        local row = { tostring(day) }
        for _, value in ipairs(self.states[day]) do row[#row + 1] = fmt(value, 1) end
        append(row, { fmt(self.reported[day], 1), tostring(self.cases[day]), fmt(self.averages[day], 2), tostring(self.cumulative_cases[day]), fmt(self.cumulative_reported[day], 1) })
        lines[#lines + 1] = table.concat(row, ",")
    end
    return lines
end
local study = S.new(Data.read())
study:fit_model(); study:fitted_diagnostics(); study:profiles(); study:backtest(); study:estimate_effects(); study:sensitivity()
study:analyze_age(); study:compare_models(); study:analyze_reproduction(); study:scenario_projections()
Data.write({ ["fit.txt"] = study.fit_lines, ["trajectories.csv"] = study:trajectories(), ["scenarios.csv"] = study.scenario_rows,
    ["reproduction.txt"] = study.reproduction_lines, ["curve_plot.txt"] = Report.curve_plot(study.cases, study.reported) })
