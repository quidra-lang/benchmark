local source_dir = arg[0]:match("^(.*[/\\])") or "./"
package.path = source_dir .. "?.lua;" .. package.path

local dataset = require("dataset")
local Minstd = require("minstd")
local rs = require("resampling")
local tests = require("tests")
local report = require("report")
local real, p_value, format = report.real, report.p_value, string.format
local GROUP_NAMES = {"mean", "median", "trimmed_mean", "sd"}
local PAIR_NAMES = {"mean_diff", "median_ratio", "hodges_lehmann", "cohen_d"}
local TEST_NAMES = {"mean", "median", "ranksum", "absdev"}

local function append(target, values)
    for _, value in ipairs(values) do target[#target + 1] = value end
end

local function copy(values)
    local result = {}
    append(result, values)
    return result
end

local function slice(values, first, last)
    local result = {}
    for index = first, last do result[#result + 1] = values[index] end
    return result
end

local function select_values(values, indices)
    local result = {}
    for _, index in ipairs(indices) do result[#result + 1] = values[index] end
    return result
end

local function columns()
    return {{}, {}, {}, {}}
end

local function append_statistics(target, values)
    for index, value in ipairs(values) do target[index][#target[index] + 1] = value end
end

local function bootstrap_samples(sample, indices)
    local result = {samples = {}, values = columns(), indices = indices}
    for _, chosen in ipairs(indices) do
        local values = select_values(sample, chosen)
        result.samples[#result.samples + 1] = values
        append_statistics(result.values, rs.statistics(values))
    end
    return result
end

local function summary(estimate, values, confidence)
    local average, se = rs.mean_and_se(values)
    local ordered = rs.sorted(values)
    local low_rank = (#values + 1) * (100 - confidence) // 200
    local high_rank = #values + 1 - low_rank
    local low, high = ordered[low_rank], ordered[high_rank]
    return {estimate = estimate, values = values, ordered = ordered, average = average, se = se,
        bias = average - estimate, low = low, high = high, basic_low = 2 * estimate - high,
        basic_high = 2 * estimate - low, low_rank = low_rank, high_rank = high_rank}
end

local function summary_text(value)
    return format("se %s bias %s percentile %s %s basic %s %s", real(value.se), real(value.bias),
        real(value.low), real(value.high), real(value.basic_low), real(value.basic_high))
end

local function jackknife_summary(values, estimate)
    local average, squares = rs.float_sum(values) / #values, 0.0
    for _, value in ipairs(values) do
        local e = value - average
        squares = squares + e * e
    end
    local variance = (#values - 1) * squares / #values
    return {average = average, variance = variance, bias = (#values - 1) * (average - estimate), se = math.sqrt(variance)}
end

local function describe(kind, name, sample, low, high, stems)
    local ordered, count, center = rs.sorted(sample), #sample, rs.mean(sample)
    local moment, wins = rs.moments(sample), rs.winsorized(sample)
    local q1, q3 = rs.quantile_numerator(sample, 25), rs.quantile_numerator(sample, 75)
    local outliers, inside = {}, {}
    for index, value in ipairs(sample) do
        if 200 * value < 5 * q1 - 3 * q3 or 200 * value > 5 * q3 - 3 * q1 then outliers[#outliers + 1] = index
        else inside[#inside + 1] = value end
    end
    local w1, w2 = math.min(table.unpack(inside)), math.max(table.unpack(inside))
    local delta = 100 * (high - low)
    local function position(value) return (120 * (value - 100 * low) + delta) // (2 * delta) + 1 end
    local band = {}
    for index = 1, 61 do band[index] = "." end
    for index = position(100 * w1), position(100 * w2) do band[index] = "-" end
    for index = position(q1), position(q3) do band[index] = "=" end
    band[position(rs.quantile_numerator(sample, 50))] = "|"
    for _, index in ipairs(outliers) do band[position(100 * sample[index])] = "o" end
    local lines = {kind .. " " .. name, "n " .. count, "mean " .. real(center), "median " .. real(rs.median(sample)),
        format("trimmed_mean %s trim %d", real(rs.trimmed_mean(sample)), count // 10),
        format("winsorized_mean %s winsorized_sd %s", real(rs.mean(wins)), real(rs.sd(wins))),
        "sd " .. real(moment.sd), "se_mean " .. real(moment.sd / math.sqrt(count)), "cv " .. real(moment.sd / center),
        "skewness " .. real(moment.m3 / (moment.m2 * math.sqrt(moment.m2))),
        "kurtosis " .. real(moment.m4 / (moment.m2 * moment.m2) - 3), "mad " .. real(rs.mad(sample)),
        "min " .. real(ordered[1] / 100), "q1 " .. real(q1 / 10000), "q3 " .. real(q3 / 10000),
        "iqr " .. real((q3 - q1) / 10000), "max " .. real(ordered[#ordered] / 100),
        format("percentiles p05 %s p10 %s p90 %s p95 %s", real(rs.quantile_numerator(sample, 5) / 10000),
            real(rs.quantile_numerator(sample, 10) / 10000), real(rs.quantile_numerator(sample, 90) / 10000), real(rs.quantile_numerator(sample, 95) / 10000)),
        format("whiskers %s %s", real(w1 / 100), real(w2 / 100)), "outliers " .. report.number_list(outliers), "box " .. table.concat(band)}
    if stems then
        for stem = ordered[1] // 100, ordered[#ordered] // 100 do
            local leaves = {}
            for _, value in ipairs(ordered) do
                if value // 100 == stem then leaves[#leaves + 1] = value % 100 // 10 end
            end
            lines[#lines + 1] = "stem " .. stem .. (#leaves > 0 and " " .. table.concat(leaves) or "")
        end
    end
    return lines
end

local function tally_counts(size)
    local result = {}
    for index = 1, size do result[index] = {extreme = 0, greater = 0} end
    return result
end

local function count_comparisons(observed, trial, counts)
    for index, value in ipairs(observed) do
        if math.abs(trial[index]) >= math.abs(value) then counts[index].extreme = counts[index].extreme + 1 end
        if trial[index] >= value then counts[index].greater = counts[index].greater + 1 end
    end
end

local function result_text(count, trials, offset)
    offset = offset or 1
    return format("extreme %d greater %d p_two %s p_greater %s", count.extreme, count.greater,
        p_value(count.extreme + offset, trials + offset), p_value(count.greater + offset, trials + offset))
end

local function ranked_sample(values)
    local ranks, result = tests.doubled_ranks(values), {}
    for index, value in ipairs(values) do result[index] = {value = value, rank = ranks[index]} end
    return result
end

local function permutation_statistics(items, size)
    local x, y, rank_total = {}, {}, 0
    for index, item in ipairs(items) do
        if index <= size then x[#x + 1] = item.value; rank_total = rank_total + item.rank
        else y[#y + 1] = item.value end
    end
    local mx, my = rs.doubled_median(x), rs.doubled_median(y)
    local ax, ay = 0, 0
    for _, value in ipairs(x) do ax = ax + math.abs(2 * value - mx) end
    for _, value in ipairs(y) do ay = ay + math.abs(2 * value - my) end
    return {values = {tests.contrast(x, y), mx - my, rank_total - size * (#items + 1), #y * ax - #x * ay},
        w = rank_total / 2, u = (rank_total - size * (size + 1)) / 2}
end

local Study = {}
Study.__index = Study

function Study.new(data)
    local self = setmetatable({data = data, groups = data.groups, pairs = data.pairs, settings = data.settings}, Study)
    self.generator = Minstd.new(self.settings.seed)
    self.z_low = rs.phi_inverse((100 - self.settings.confidence) / 200)
    return self
end

function Study:prepare_bootstraps()
    local count, confidence = self.settings.bootstrap, self.settings.confidence
    for _, group in ipairs(self.groups) do
        group.estimates = rs.statistics(group.sample)
        group.ordinary = bootstrap_samples(group.sample, rs.ordinary_indices(self.generator, #group.sample, count))
        group.summaries = {}
        for statistic = 1, 4 do group.summaries[statistic] = summary(group.estimates[statistic], group.ordinary.values[statistic], confidence) end
    end
    for _, group in ipairs(self.groups) do
        local balanced = bootstrap_samples(group.sample, rs.balanced_indices(self.generator, #group.sample, count))
        group.balanced_summaries = {}
        for statistic = 1, 4 do group.balanced_summaries[statistic] = summary(group.estimates[statistic], balanced.values[statistic], confidence) end
    end
    local differences, correlations = {}, {}
    for _ = 1, count do
        local indices = rs.resample_indices(self.generator, #self.data.before)
        differences[#differences + 1] = rs.mean(select_values(self.data.differences, indices))
        correlations[#correlations + 1] = rs.correlation(select_values(self.data.before, indices), select_values(self.data.after, indices))
    end
    self.paired_mean = summary(rs.mean(self.data.differences), differences, confidence)
    self.paired_correlation = summary(rs.correlation(self.data.before, self.data.after), correlations, confidence)
    for _, pair in ipairs(self.pairs) do
        pair.estimates, pair.values, pair.summaries = rs.pair_statistics(pair.first.sample, pair.second.sample), columns(), {}
        for replicate = 1, count do append_statistics(pair.values, rs.pair_statistics(pair.first.ordinary.samples[replicate], pair.second.ordinary.samples[replicate])) end
        for statistic = 1, 4 do pair.summaries[statistic] = summary(pair.estimates[statistic], pair.values[statistic], confidence) end
    end
end

function Study:descriptive_lines()
    local values = {}
    for _, group in ipairs(self.groups) do append(values, group.sample) end
    local low, high = math.min(table.unpack(values)), math.max(table.unpack(values))
    local lines = {format("groups %d observations %d", #self.groups, #values)}
    for _, group in ipairs(self.groups) do append(lines, describe("group", group.name, group.sample, low, high, true)) end
    lines[#lines + 1] = "paired subjects " .. #self.data.before
    local together = copy(self.data.before)
    append(together, self.data.after)
    low, high = math.min(table.unpack(together)), math.max(table.unpack(together))
    append(lines, describe("series", "before", self.data.before, low, high, false))
    append(lines, describe("series", "after", self.data.after, low, high, false))
    values = self.data.differences
    append(lines, describe("series", "diff", values, math.min(table.unpack(values)), math.max(table.unpack(values)), false))
    return lines
end

function Study:bootstrap_lines()
    local lines = {"group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi"}
    local function row(name, statistic, value)
        lines[#lines + 1] = table.concat({name, statistic, real(value.estimate), real(value.se), real(value.bias),
            real(value.low), real(value.high), real(value.basic_low), real(value.basic_high)}, ",")
    end
    for _, group in ipairs(self.groups) do
        for statistic, name in ipairs(GROUP_NAMES) do row(group.name, name, group.summaries[statistic]) end
        for statistic, name in ipairs(GROUP_NAMES) do row(group.name, "balanced_" .. name, group.balanced_summaries[statistic]) end
    end
    for _, pair in ipairs(self.pairs) do
        for statistic, name in ipairs(PAIR_NAMES) do row(pair.name, name, pair.summaries[statistic]) end
    end
    return lines
end

function Study:histogram(name, statistic, value)
    local bins, low, high = self.settings.bins, value.ordered[1], value.ordered[#value.ordered]
    local counts, marks = {}, {}
    for index = 1, bins do counts[index], marks[index] = 0, {} end
    for _, replicate in ipairs(value.values) do
        local index = report.bin_number(replicate, low, high, bins)
        counts[index] = counts[index] + 1
    end
    local top, estimate_bin = math.max(table.unpack(counts)), "none"
    local lower_bin, upper_bin = report.bin_number(value.low, low, high, bins), report.bin_number(value.high, low, high, bins)
    marks[lower_bin][#marks[lower_bin] + 1] = "L"
    if value.estimate >= low and value.estimate <= high then
        estimate_bin = report.bin_number(value.estimate, low, high, bins)
        marks[estimate_bin][#marks[estimate_bin] + 1] = "E"
    end
    marks[upper_bin][#marks[upper_bin] + 1] = "H"
    local convergence = {}
    for quarter = 1, 4 do
        local size = quarter * self.settings.bootstrap // 4
        local _, se = rs.mean_and_se(slice(value.values, 1, size))
        convergence[#convergence + 1] = size .. ":" .. real(se)
    end
    local lines = {format("histogram %s %s min %s max %s width %s top %d estimate_bin %s", name, statistic,
        real(low), real(high), real((high - low) / bins), top, tostring(estimate_bin)), "convergence " .. table.concat(convergence, " ")}
    for index = 1, bins do
        local parts = {"bin", index, real(low + (high - low) * (index - 1) / bins), counts[index]}
        if counts[index] > 0 then parts[#parts + 1] = report.bar(counts[index], top) end
        append(parts, marks[index])
        lines[#lines + 1] = table.concat(parts, " ")
    end
    return lines
end

function Study:histogram_lines()
    local lines = {}
    for _, group in ipairs(self.groups) do
        for statistic, name in ipairs(GROUP_NAMES) do append(lines, self:histogram(group.name, name, group.summaries[statistic])) end
    end
    for _, pair in ipairs(self.pairs) do
        for statistic, name in ipairs(PAIR_NAMES) do append(lines, self:histogram(pair.name, name, pair.summaries[statistic])) end
    end
    return lines
end

function Study:group_jackknife(group)
    local sample, values = group.sample, columns()
    for index = 1, #sample do append_statistics(values, rs.statistics(rs.without(sample, index))) end
    local moments, lines = {}, {format("group %s n %d", group.name, #sample)}
    for statistic, name in ipairs(GROUP_NAMES) do
        local moment = jackknife_summary(values[statistic], group.estimates[statistic])
        moments[statistic] = moment
        lines[#lines + 1] = format("jackknife %s estimate %s average %s bias %s se %s", name, real(group.estimates[statistic]), real(moment.average), real(moment.bias), real(moment.se))
    end
    for statistic, name in ipairs(GROUP_NAMES) do
        local value, below = group.summaries[statistic], 0
        for _, replicate in ipairs(value.values) do if replicate < value.estimate then below = below + 1 end end
        local z0, v2, v3 = rs.phi_inverse(below / #value.values), 0.0, 0.0
        for _, deleted in ipairs(values[statistic]) do
            local u = moments[statistic].average - deleted
            v2, v3 = v2 + u * u, v3 + u * u * u
        end
        local acceleration = v3 / (6 * v2 * math.sqrt(v2))
        local function alpha(z) return rs.phi(z0 + (z0 + z) / (1 - acceleration * (z0 + z))) end
        local b = #value.values
        local first = math.max(1, math.min(b, math.floor((b + 1) * alpha(self.z_low))))
        local second = math.max(1, math.min(b, b + 1 - math.floor((b + 1) * (1 - alpha(-self.z_low)))))
        lines[#lines + 1] = format("bca %s below %d z0 %s acceleration %s ranks %d %d interval %s %s", name,
            below, real(z0), real(acceleration), first, second, real(value.ordered[first]), real(value.ordered[second]))
    end
    local omitted, errors = {}, columns()
    for index = 1, #sample do omitted[index] = {} end
    for replicate, indices in ipairs(group.ordinary.indices) do
        local chosen = {}
        for _, index in ipairs(indices) do chosen[index] = true end
        for index = 1, #sample do if not chosen[index] then omitted[index][#omitted[index] + 1] = replicate end end
    end
    for statistic, name in ipairs(GROUP_NAMES) do
        for index, indices in ipairs(omitted) do
            local _, se = rs.mean_and_se(select_values(group.ordinary.values[statistic], indices))
            errors[statistic][index] = se
        end
        local moment = jackknife_summary(errors[statistic], 0)
        lines[#lines + 1] = format("after_bootstrap %s se %s average %s se_of_se %s", name,
            real(group.summaries[statistic].se), real(moment.average), real(moment.se))
    end
    local sizes, order = {}, {}
    for index, indices in ipairs(omitted) do sizes[index], order[index] = #indices, index end
    lines[#lines + 1] = format("without min %d max %d", math.min(table.unpack(sizes)), math.max(table.unpack(sizes)))
    local total = rs.sum(sample)
    table.sort(order, function(a, b)
        local first, second = math.abs(#sample * sample[a] - total), math.abs(#sample * sample[b] - total)
        if first ~= second then return first > second end
        return a < b
    end)
    for rank = 1, 5 do
        local index, shifted = order[rank], {}
        for _, replicate in ipairs(omitted[index]) do shifted[#shifted + 1] = group.ordinary.values[1][replicate] - group.estimates[1] end
        table.sort(shifted)
        local function quantile(p) return shifted[(p * #shifted + 99) // 100] end
        local influence = (#sample - 1) * (moments[1].average - values[1][index])
        lines[#lines + 1] = format("influence %d obs %d value %s l %s without %d se %s q05 %s q50 %s q95 %s", rank, index,
            real(sample[index] / 100), real(influence), sizes[index], real(errors[1][index]), real(quantile(5)), real(quantile(50)), real(quantile(95)))
    end
    return lines
end

function Study:pair_jackknife(pair)
    local x, y, first, second = pair.first.sample, pair.second.sample, columns(), columns()
    for index = 1, #x do append_statistics(first, rs.pair_statistics(rs.without(x, index), y)) end
    for index = 1, #y do append_statistics(second, rs.pair_statistics(x, rs.without(y, index))) end
    local lines = {}
    for statistic, name in ipairs(PAIR_NAMES) do
        local bias, variance = 0.0, 0.0
        for _, part in ipairs({first, second}) do
            local moment = jackknife_summary(part[statistic], pair.estimates[statistic])
            bias, variance = bias + moment.bias, variance + moment.variance
        end
        lines[#lines + 1] = format("pair %s %s estimate %s bias %s se %s", pair.name, name, real(pair.estimates[statistic]), real(bias), real(math.sqrt(variance)))
    end
    return lines
end

function Study:jackknife_lines()
    local lines = {}
    for _, group in ipairs(self.groups) do append(lines, self:group_jackknife(group)) end
    for _, pair in ipairs(self.pairs) do append(lines, self:pair_jackknife(pair)) end
    return lines
end

function Study:permutation_lines(pair)
    local x, y = pair.first.sample, pair.second.sample
    local combined = copy(x)
    append(combined, y)
    local items = ranked_sample(combined)
    local observed, counts = permutation_statistics(items, #x), tally_counts(4)
    for _ = 1, self.settings.permutations do
        local trial = permutation_statistics(self.generator:shuffle(copy(items)), #x)
        count_comparisons(observed.values, trial.values, counts)
    end
    pair.extremes = {}
    for index = 1, 4 do pair.extremes[index] = counts[index].extreme end
    local r = self.settings.permutations
    return {format("compare %s %s", pair.first.name, pair.second.name), format("permutation n %d %d perms %d", #x, #y, r),
        "mean diff " .. real(pair.estimates[1]) .. " " .. result_text(counts[1], r),
        "median diff " .. real(observed.values[2] / 200) .. " " .. result_text(counts[2], r),
        format("ranksum w %s u %s %s", real(observed.w), real(observed.u), result_text(counts[3], r)),
        "absdev diff " .. real(observed.values[4] / (200 * #x * #y)) .. " " .. result_text(counts[4], r)}
end

function Study:power_line(pair)
    local x, y, settings = pair.first.sample, pair.second.sample, self.settings
    local rejections = 0
    for _ = 1, settings.power_sims do
        local first = select_values(x, rs.resample_indices(self.generator, #x))
        local second = select_values(y, rs.resample_indices(self.generator, #y))
        local combined = copy(first)
        append(combined, second)
        local observed, extreme = math.abs(tests.contrast(first, second)), 0
        for _ = 1, settings.power_perms do
            local shuffled = self.generator:shuffle(copy(combined))
            if math.abs(tests.contrast(slice(shuffled, 1, #x), slice(shuffled, #x + 1, #shuffled))) >= observed then extreme = extreme + 1 end
        end
        if 100 * (extreme + 1) <= (100 - settings.confidence) * (settings.power_perms + 1) then rejections = rejections + 1 end
    end
    local power = rejections / settings.power_sims
    return format("power sims %d perms %d rejections %d power %s se %s", settings.power_sims, settings.power_perms,
        rejections, real(power), real(math.sqrt(power * (1 - power) / settings.power_sims)))
end

function Study:exact_lines(pair)
    local size = self.settings.pilot
    local x, y = slice(pair.first.sample, 1, size), slice(pair.second.sample, 1, size)
    local combined = copy(x)
    append(combined, y)
    local ranks, total = tests.doubled_ranks(combined), rs.sum(combined)
    local rank_total = rs.sum(slice(ranks, 1, size))
    local observed, counts = {tests.contrast(x, y), rank_total - size * (2 * size + 1)}, tally_counts(2)
    local frequencies, splits = {}, 0
    for choice in tests.position_choices(2 * size, size) do
        local chosen, rank_sum = 0, 0
        for _, index in ipairs(choice) do chosen, rank_sum = chosen + combined[index], rank_sum + ranks[index] end
        local contrast = size * chosen - size * (total - chosen)
        count_comparisons(observed, {contrast, rank_sum - size * (2 * size + 1)}, counts)
        local absolute = math.abs(contrast)
        frequencies[absolute], splits = (frequencies[absolute] or 0) + 1, splits + 1
    end
    local order = {}
    for value in pairs(frequencies) do order[#order + 1] = value end
    table.sort(order, function(a, b) return a > b end)
    local cumulative, critical, attained = 0
    for _, value in ipairs(order) do
        cumulative = cumulative + frequencies[value]
        if 100 * cumulative > (100 - self.settings.confidence) * splits then break end
        critical, attained = value, cumulative
    end
    local critical_line = "critical diff none attained none"
    if critical then critical_line = format("critical diff %s attained %s", real(critical / (100 * size * size)), p_value(attained, splits)) end
    return {format("exact size %d splits %d", size, splits), "mean diff " .. real(rs.mean_difference(x, y)) .. " " .. result_text(counts[1], splits, 0),
        format("ranksum w %s u %s %s", real(rank_total / 2), real((rank_total - size * (size + 1)) / 2), result_text(counts[2], splits, 0)), critical_line}
end

function Study:studentized_lines(pair)
    local x, y = pair.first.sample, pair.second.sample
    local k, m, sx, sy = #x, #y, rs.sd(x), rs.sd(y)
    local vx, vy = sx * sx / k, sy * sy / m
    local se0, estimate = math.sqrt(vx + vy), pair.estimates[1]
    local statistic, values, extreme = estimate / se0, {}, 0
    for replicate = 1, self.settings.bootstrap do
        local first, second = pair.first.ordinary.values[4][replicate], pair.second.ordinary.values[4][replicate]
        local value = (pair.values[1][replicate] - estimate) / math.sqrt(first * first / k + second * second / m)
        values[#values + 1] = value
        if math.abs(value) >= math.abs(statistic) then extreme = extreme + 1 end
    end
    table.sort(values)
    local low = estimate - values[pair.summaries[1].high_rank] * se0
    local high = estimate - values[pair.summaries[1].low_rank] * se0
    local df = (vx + vy) * (vx + vy) / (vx * vx / (k - 1) + vy * vy / (m - 1))
    local greater, equal = 0, 0
    for _, first in ipairs(x) do
        for _, second in ipairs(y) do
            if first > second then greater = greater + 1 end
            if first == second then equal = equal + 1 end
        end
    end
    local d = pair.estimates[4]
    return {format("bootstrap_t t %s df %s extreme %d p %s interval %s %s", real(statistic), real(df), extreme,
        p_value(extreme + 1, self.settings.bootstrap + 1), real(low), real(high)),
        format("effect pooled_sd %s cohen_d %s hedges_g %s cles %s", real(rs.pooled_sd(x, y)), real(d),
            real(d * (1 - 3 / (4 * (k + m - 2) - 1))), real((2 * greater + equal) / (2 * k * m)))}
end

function Study:holm_lines()
    local lines, denominator = {}, self.settings.permutations + 1
    for statistic, name in ipairs(TEST_NAMES) do
        local order = copy(self.pairs)
        table.sort(order, function(a, b)
            if a.extremes[statistic] ~= b.extremes[statistic] then return a.extremes[statistic] < b.extremes[statistic] end
            return a.number < b.number
        end)
        local adjusted = 0
        for rank, pair in ipairs(order) do
            local numerator = pair.extremes[statistic] + 1
            adjusted = math.max(adjusted, math.min(denominator, (#order - rank + 1) * numerator))
            local decision = 100 * adjusted <= (100 - self.settings.confidence) * denominator and "reject" or "retain"
            lines[#lines + 1] = format("holm %s rank %d %s %s p %s adjusted %s %s", name, rank,
                pair.first.name, pair.second.name, p_value(numerator, denominator), p_value(adjusted, denominator), decision)
        end
    end
    return lines
end

function Study:paired_lines()
    local d, count = self.data.differences, #self.data.differences
    local positive, negative, zero = 0, 0, 0
    local magnitudes = {}
    for _, value in ipairs(d) do
        if value > 0 then positive = positive + 1 elseif value < 0 then negative = negative + 1 else zero = zero + 1 end
        if value ~= 0 then magnitudes[#magnitudes + 1] = math.abs(value) end
    end
    local ranks, signed, cursor, positive_ranks = tests.doubled_ranks(magnitudes), {}, 1, 0
    for index, value in ipairs(d) do
        if value == 0 then signed[index] = 0
        else
            signed[index] = value > 0 and ranks[cursor] or -ranks[cursor]
            if value > 0 then positive_ranks = positive_ranks + ranks[cursor] end
            cursor = cursor + 1
        end
    end
    local center, deviation, r = rs.mean(d), rs.sd(d), self.paired_correlation.estimate
    local z, half = 0.5 * math.log((1 + r) / (1 - r)), -self.z_low / math.sqrt(count - 3)
    local function tanh(value)
        local exponential = math.exp(2 * value)
        return (exponential - 1) / (exponential + 1)
    end
    local lines = {format("paired subjects %d positive %d negative %d zero %d", count, positive, negative, zero),
        format("paired before %s after %s diff %s sd_diff %s t %s dz %s", real(rs.mean(self.data.before)), real(rs.mean(self.data.after)),
            real(center), real(deviation), real(center / (deviation / math.sqrt(count))), real(center / deviation)),
        "paired_bootstrap " .. summary_text(self.paired_mean),
        format("correlation r %s %s fisher %s %s", real(r), summary_text(self.paired_correlation), real(tanh(z - half)), real(tanh(z + half)))}
    local observed, counts = {rs.sum(d), rs.sum(signed)}, tally_counts(2)
    for _ = 1, self.settings.permutations do
        local total, rank_total = 0, 0
        for index, value in ipairs(d) do
            local sign = self.generator:draw() % 2 == 1 and -1 or 1
            total, rank_total = total + sign * value, rank_total + sign * signed[index]
        end
        count_comparisons(observed, {total, rank_total}, counts)
    end
    lines[#lines + 1] = "signflip flips " .. self.settings.permutations
    lines[#lines + 1] = "mean diff " .. real(center) .. " " .. result_text(counts[1], self.settings.permutations)
    lines[#lines + 1] = "signedrank w_plus " .. real(positive_ranks / 2) .. " " .. result_text(counts[2], self.settings.permutations)
    return lines
end

function Study:anova_lines()
    local samples, sizes, combined = {}, {}, {}
    for _, group in ipairs(self.groups) do
        samples[#samples + 1], sizes[#sizes + 1] = group.sample, #group.sample
        append(combined, group.sample)
    end
    local original, group_count, count = tests.anova(samples), #samples, #combined
    local msw = original.ssw / (count - group_count)
    local eta = original.ssb / (original.ssb + original.ssw)
    local omega = (original.ssb - (group_count - 1) * msw) / (original.ssb + original.ssw + msw)
    local eta_values = {}
    for replicate = 1, self.settings.bootstrap do
        local values = {}
        for _, group in ipairs(self.groups) do values[#values + 1] = group.ordinary.samples[replicate] end
        local result = tests.anova(values)
        eta_values[#eta_values + 1] = result.ssb / (result.ssb + result.ssw)
    end
    local weights = {}
    for _, sample in ipairs(samples) do
        local deviation = rs.sd(sample)
        weights[#weights + 1] = #sample / (deviation * deviation)
    end
    local total_weight, weighted = rs.float_sum(weights), 0.0
    for index, weight in ipairs(weights) do weighted = weighted + weight * original.means[index] end
    local center, spread, lambda = weighted / total_weight, 0.0, 0.0
    for index, weight in ipairs(weights) do
        local difference, share = original.means[index] - center, 1 - weight / total_weight
        spread = spread + weight * (difference * difference)
        lambda = lambda + share * share / (sizes[index] - 1)
    end
    local aw = spread / (group_count - 1)
    local welch = aw / (1 + 2 * (group_count - 2) * lambda / (group_count * group_count - 1))
    local df2 = (group_count * group_count - 1) / (3 * lambda)
    local tie_groups, tie_total = 0, 0
    for _, item in ipairs(tests.value_counts(combined)) do
        if item[2] >= 2 then tie_groups, tie_total = tie_groups + 1, tie_total + item[2] * item[2] * item[2] - item[2] end
    end
    local correction = 1 - tie_total / (count * count * count - count)
    local ranks = tests.doubled_ranks(combined)
    local h = tests.kruskal(tests.split_list(ranks, sizes), correction)
    local lines = {format("anova groups %d observations %d ssb %s ssw %s df %d %d f %s eta_squared %s omega_squared %s", group_count,
        count, real(original.ssb), real(original.ssw), group_count - 1, count - group_count, real(original.f), real(eta), real(omega)),
        "eta_bootstrap " .. summary_text(summary(eta, eta_values, self.settings.confidence)),
        format("welch f %s df %d %s", real(welch), group_count - 1, real(df2)), format("kruskal h %s tie_groups %d", real(h), tie_groups)}
    local pairs_list = {}
    for first = 1, group_count do
        for second = first + 1, group_count do
            pairs_list[#pairs_list + 1] = {first = first, second = second, numerator = math.abs(tests.contrast(samples[first], samples[second])),
                denominator = sizes[first] * sizes[second], extreme = 0, maximum = 0}
        end
    end
    local function at_least(a, b) return a.numerator * b.denominator >= b.numerator * a.denominator end
    local f_extreme, h_extreme = 0, 0
    local items = ranked_sample(combined)
    for _ = 1, self.settings.permutations do
        local parts = tests.split_list(self.generator:shuffle(copy(items)), sizes)
        local trial_samples, rank_groups = {}, {}
        for index, part in ipairs(parts) do
            trial_samples[index], rank_groups[index] = {}, {}
            for _, item in ipairs(part) do
                trial_samples[index][#trial_samples[index] + 1] = item.value
                rank_groups[index][#rank_groups[index] + 1] = item.rank
            end
        end
        local result, trial_h = tests.anova(trial_samples), tests.kruskal(rank_groups, correction)
        if result.f >= original.f - 0.000000001 * original.f then f_extreme = f_extreme + 1 end
        if trial_h >= h - 0.000000001 * h then h_extreme = h_extreme + 1 end
        local deltas, maximum = {}
        for index, pair in ipairs(pairs_list) do
            local value = {numerator = math.abs(tests.contrast(trial_samples[pair.first], trial_samples[pair.second])), denominator = pair.denominator}
            deltas[index] = value
            if not maximum or not at_least(maximum, value) then maximum = value end
        end
        for index, pair in ipairs(pairs_list) do
            if at_least(deltas[index], pair) then pair.extreme = pair.extreme + 1 end
            if at_least(maximum, pair) then pair.maximum = pair.maximum + 1 end
        end
    end
    lines[#lines + 1] = format("anova_permutation perms %d f_extreme %d f_p %s h_extreme %d h_p %s", self.settings.permutations,
        f_extreme, p_value(f_extreme + 1, self.settings.permutations + 1), h_extreme, p_value(h_extreme + 1, self.settings.permutations + 1))
    for _, pair in ipairs(pairs_list) do
        lines[#lines + 1] = format("pairwise %s %s diff %s extreme %d p %s maxt %d adjusted %s", self.groups[pair.first].name, self.groups[pair.second].name,
            real(rs.mean_difference(samples[pair.first], samples[pair.second])), pair.extreme, p_value(pair.extreme + 1, self.settings.permutations + 1),
            pair.maximum, p_value(pair.maximum + 1, self.settings.permutations + 1))
    end
    return lines
end

function Study:run()
    self:prepare_bootstraps()
    local lines = {}
    for _, pair in ipairs(self.pairs) do
        append(lines, self:permutation_lines(pair))
        lines[#lines + 1] = self:power_line(pair)
        append(lines, self:exact_lines(pair))
        append(lines, self:studentized_lines(pair))
    end
    append(lines, self:holm_lines())
    append(lines, self:paired_lines())
    append(lines, self:anova_lines())
    return {{"descriptives.txt", self:descriptive_lines()}, {"bootstrap.csv", self:bootstrap_lines()},
        {"jackknife.txt", self:jackknife_lines()}, {"tests.txt", lines}, {"histograms.txt", self:histogram_lines()}}
end

report.write_files(Study.new(dataset.load("input")):run())
