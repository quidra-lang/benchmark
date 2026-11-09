local qr = require("qr_solver")
local inference = require("inference")
local M = {}
function M.rows(fitted, params)
    local n, rank = fitted.n, fitted.rank
    local degrees = n - rank
    local sigma = math.sqrt(fitted.rss / degrees)
    local leverage_limit = params.LEVERAGE * rank / n
    local cook_limit = params.COOK / n
    local dffits_limit = params.DFFITS * math.sqrt(rank / n)
    local result = {}
    for i = 1, n do
        local h, residual = fitted.leverage[i], fitted.weighted_residual[i]
        local z = residual / (sigma * math.sqrt(1.0 - h))
        local studentized = z * math.sqrt((degrees - 1) / (degrees - z * z))
        local cooks = z * z * h / (rank * (1.0 - h))
        local dffits = studentized * math.sqrt(h / (1.0 - h))
        local flags = ""
        if h > leverage_limit then
            flags = flags .. "H"
        end
        if math.abs(studentized) > params.STUDENTIZED then
            flags = flags .. "O"
        end
        if cooks > cook_limit then
            flags = flags .. "C"
        end
        if math.abs(dffits) > dffits_limit then
            flags = flags .. "F"
        end
        local deleted_sigma = sigma * math.sqrt((degrees - z * z) / (degrees - 1))
        local dfbetas = {}
        for k = 1, rank do
            dfbetas[k] = fitted.g[i][k] * residual / (1.0 - h) / (deleted_sigma * math.sqrt(fitted.variance[k]))
        end
        result[i] = {standardized = z, studentized = studentized, cooks = cooks, dffits = dffits,
            flags = flags == "" and "-" or flags, dfbetas = dfbetas}
    end
    return result
end
function M.durbin_watson(fitted)
    local numerator = 0.0
    for i = 2, fitted.n do
        local difference = fitted.weighted_residual[i] - fitted.weighted_residual[i - 1]
        numerator = numerator + difference * difference
    end
    return numerator / fitted.rss
end
function M.breusch_pagan(fitted, tolerance)
    local squared, matrix, ones, sum = {}, {}, {}, 0.0
    for i = 1, fitted.n do
        squared[i] = fitted.weighted_residual[i] * fitted.weighted_residual[i]
        sum = sum + squared[i]
        ones[i], matrix[i] = 1.0, {}
        for _, column in ipairs(fitted.accepted) do
            matrix[i][#matrix[i] + 1] = fitted.matrix[i][column]
        end
    end
    local auxiliary = qr.fit(matrix, squared, ones, tolerance)
    local mean, tss = sum / fitted.n, 0.0
    for _, value in ipairs(squared) do
        tss = tss + (value - mean) * (value - mean)
    end
    local statistic, degrees = fitted.n * (1.0 - auxiliary.rss / tss), auxiliary.rank - 1
    return {statistic, degrees, inference.chi_pvalue(statistic, degrees)}
end
function M.jarque_bera(fitted)
    local sum = 0.0
    for _, value in ipairs(fitted.weighted_residual) do
        sum = sum + value
    end
    local mean, m2, m3, m4 = sum / fitted.n, 0.0, 0.0, 0.0
    for _, value in ipairs(fitted.weighted_residual) do
        local delta = value - mean
        m2, m3, m4 = m2 + delta * delta, m3 + delta * delta * delta, m4 + delta * delta * delta * delta
    end
    m2, m3, m4 = m2 / fitted.n, m3 / fitted.n, m4 / fitted.n
    local skewness, kurtosis = m3 / (m2 * math.sqrt(m2)), m4 / (m2 * m2)
    local statistic = fitted.n / 6.0 * (skewness * skewness + (kurtosis - 3.0) * (kurtosis - 3.0) / 4.0)
    return {statistic, inference.chi_pvalue(statistic, 2), skewness, kurtosis}
end
function M.calculate(fitted, params)
    return {rows = M.rows(fitted, params), dw = M.durbin_watson(fitted),
        bp = M.breusch_pagan(fitted, params.RANK_TOL), jb = M.jarque_bera(fitted)}
end
return M
