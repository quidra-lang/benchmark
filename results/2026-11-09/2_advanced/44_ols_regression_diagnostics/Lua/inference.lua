local M = {}
function M.log_gamma(x)
    local coefficients = {76.18009172947146, -86.50532032941677, 24.01409824083091,
        -1.231739572450155, 0.001208650973866179, -0.000005395239384953}
    local t = x + 5.5
    local adjustment = t - (x + 0.5) * math.log(t)
    local series = 1.000000000190015
    for j, coefficient in ipairs(coefficients) do
        series = series + coefficient / (x + j)
    end
    return -adjustment + math.log(2.5066282746310005 * series / x)
end
local function replace_small(value)
    return math.abs(value) < 1e-300 and 1e-300 or value
end
function M.beta_fraction(a, b, x)
    local c = 1.0
    local d = 1.0 / replace_small(1.0 - (a + b) * x / (a + 1.0))
    local h = d
    for m = 1, 1000 do
        local q = m * (b - m) * x / ((a - 1.0 + 2 * m) * (a + 2 * m))
        d = 1.0 / replace_small(1.0 + q * d)
        c = replace_small(1.0 + q / c)
        h = h * (d * c)
        q = -(a + m) * (a + b + m) * x / ((a + 2 * m) * (a + 1.0 + 2 * m))
        d = 1.0 / replace_small(1.0 + q * d)
        c = replace_small(1.0 + q / c)
        local delta = d * c
        h = h * delta
        if math.abs(delta - 1.0) < 1e-15 then
            break
        end
    end
    return h
end
function M.incomplete_beta(x, a, b)
    if x <= 0.0 then
        return 0.0
    elseif x >= 1.0 then
        return 1.0
    end
    local factor = math.exp(M.log_gamma(a + b) - M.log_gamma(a) - M.log_gamma(b) + a * math.log(x) + b * math.log(1.0 - x))
    if x < (a + 1.0) / (a + b + 2.0) then
        return factor * M.beta_fraction(a, b, x) / a
    end
    return 1.0 - factor * M.beta_fraction(b, a, 1.0 - x) / b
end
function M.upper_gamma(a, x)
    if x <= 0.0 then
        return 1.0
    end
    local factor = math.exp(-x + a * math.log(x) - M.log_gamma(a))
    if x < a + 1.0 then
        local term, e = 1.0 / a, a
        local series = term
        for _ = 1, 1000 do
            e = e + 1.0
            term = term * (x / e)
            series = series + term
            if math.abs(term) < math.abs(series) * 1e-15 then
                break
            end
        end
        return 1.0 - series * factor
    end
    local beta, c = x + 1.0 - a, 1.0 / 1e-300
    local d = 1.0 / beta
    local h = d
    for i = 1, 1000 do
        local q = -i * (i - a)
        beta = beta + 2.0
        d = 1.0 / replace_small(q * d + beta)
        c = replace_small(beta + q / c)
        local delta = d * c
        h = h * delta
        if math.abs(delta - 1.0) < 1e-15 then
            break
        end
    end
    return factor * h
end
function M.t_pvalue(value, degrees)
    return M.incomplete_beta(degrees / (degrees + value * value), degrees / 2.0, 0.5)
end
function M.f_pvalue(statistic, numerator_df, denominator_df)
    return M.incomplete_beta(denominator_df / (denominator_df + numerator_df * statistic), denominator_df / 2.0, numerator_df / 2.0)
end
function M.chi_pvalue(statistic, degrees)
    return M.upper_gamma(degrees / 2.0, statistic / 2.0)
end
function M.t_quantile(confidence, degrees)
    local lo, hi = 0.0, 1000.0
    for _ = 1, 100 do
        local mid = (lo + hi) / 2.0
        if M.t_pvalue(mid, degrees) > 1.0 - confidence then
            lo = mid
        else
            hi = mid
        end
    end
    return (lo + hi) / 2.0
end
function M.significance(value)
    if value == nil then
        return ""
    elseif value < 0.001 then
        return "***"
    elseif value < 0.01 then
        return "**"
    elseif value < 0.05 then
        return "*"
    elseif value < 0.1 then
        return "."
    end
    return ""
end
function M.four(value)
    if value == nil then
        return "NA"
    end
    local text = string.format("%.4f", value)
    return text == "-0.0000" and "0.0000" or text
end
function M.probability(value)
    if value == nil then
        return "NA"
    end
    return value < 0.0001 and "<0.0001" or M.four(value)
end
return M
