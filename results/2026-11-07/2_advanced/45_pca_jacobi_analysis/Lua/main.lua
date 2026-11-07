local dataset = require("dataset")
local matrix = require("matrix")
local eigen = require("eigen")
local pca = require("pca")
local plot = require("plot")
local function number(value, digits)
    local result = string.format("%." .. (digits or 4) .. "f", value)
    if tonumber(result) == 0 then
        result = result:gsub("^-", "")
    end
    return result
end
local function reals(values, separator)
    local fields = {}
    for _, value in ipairs(values) do
        fields[#fields + 1] = number(value)
    end
    return table.concat(fields, separator or " ")
end
local function append(destination, source)
    for _, value in ipairs(source) do
        destination[#destination + 1] = value
    end
end
local function sum(values)
    local result = 0.0
    for _, value in ipairs(values) do
        result = result + value
    end
    return result
end
local function argmax(values)
    local result = 1
    for index = 2, #values do
        if values[index] > values[result] then
            result = index
        end
    end
    return result
end
local function top_indices(values, count)
    local result = {}
    for index = 1, #values do
        result[index] = index
    end
    table.sort(result, function(first, second)
        if values[first] ~= values[second] then
            return values[first] > values[second]
        end
        return first < second
    end)
    local selected = {}
    for index = 1, math.min(count, #result) do
        selected[index] = result[index]
    end
    return selected
end
local function congruence(first, second)
    return matrix.dot(first, second) / math.sqrt(matrix.dot(first, first) * matrix.dot(second, second))
end
local function summarize(data)
    local summaries, incomplete = {}, {}
    for j = 1, #data.variables do
        local values, total = {}, 0.0
        for _, row in ipairs(data.rows) do
            if row[j] ~= false then
                values[#values + 1] = row[j]
                total = total + row[j]
            end
        end
        local mean, squares = total / #values, 0.0
        local minimum, maximum = values[1], values[1]
        for _, value in ipairs(values) do
            squares = squares + (value - mean) * (value - mean)
            minimum, maximum = math.min(minimum, value), math.max(maximum, value)
        end
        summaries[j] = {observed = #values, missing = #data.rows - #values, mean = mean,
            sd = math.sqrt(squares / (#values - 1)), minimum = minimum, maximum = maximum}
    end
    for index, row in ipairs(data.rows) do
        local missing = false
        for j = 1, #data.variables do
            missing = missing or row[j] == false
        end
        if missing then
            incomplete[#incomplete + 1] = data.ids[index]
        end
    end
    return summaries, incomplete
end
local function analysis_data(data, summaries, strategy)
    local ids, rows = {}, {}
    for index, row in ipairs(data.rows) do
        local complete, values = true, {}
        for j = 1, #data.variables do
            if row[j] == false then
                complete = false
                values[j] = summaries[j].mean
            else
                values[j] = row[j]
            end
        end
        if strategy == "mean" or complete then
            ids[#ids + 1], rows[#rows + 1] = data.ids[index], values
        end
    end
    return ids, rows
end
local function adequacy(correlation, n)
    local size = #correlation
    local inverse, determinant = matrix.inverse_determinant(correlation)
    local msa, rr_total, pp_total = {}, 0.0, 0.0
    for j = 1, size do
        local rr, pp = 0.0, 0.0
        for k = 1, size do
            if k ~= j then
                local partial = -inverse[j][k] / math.sqrt(inverse[j][j] * inverse[k][k])
                rr = rr + correlation[j][k] * correlation[j][k]
                pp = pp + partial * partial
            end
        end
        msa[j] = rr / (rr + pp)
        rr_total, pp_total = rr_total + rr, pp_total + pp
    end
    local kmo = rr_total / (rr_total + pp_total)
    local bartlett = -(n - 1 - (2 * size + 5) / 6.0) * math.log(determinant)
    return {msa = msa, determinant = determinant, kmo = kmo, bartlett = bartlett, degrees = size * (size - 1) // 2}
end
local function parallel_analysis(n, size, repetitions, seed)
    local totals, state = {}, seed
    for k = 1, size do
        totals[k] = 0.0
    end
    for _ = 1, repetitions do
        local rows = {}
        for i = 1, n do
            rows[i] = {}
            for j = 1, size do
                state = (48271 * state) % 2147483647
                rows[i][j] = state / 2147483647
            end
        end
        local prepared = pca.prepare(rows, "correlation")
        local result = eigen.jacobi(prepared.values)
        local total = sum(result.values)
        for k = 1, size do
            totals[k] = totals[k] + result.values[k] / total
        end
    end
    for k = 1, size do
        totals[k] = totals[k] / repetitions
    end
    return totals
end
local function retention(values, parallel, n, params)
    local size, total = #values, sum(values)
    local average, cumulative = total / size, 0.0
    local ratios, cumulatives, broken, standard_errors, separated = {}, {}, {}, {}, {}
    local criteria = {kaiser = 0, broken_stick = size, parallel = size, cumulative = size}
    local broken_found, parallel_found, cumulative_found = false, false, false
    for k = 1, size do
        local ratio = values[k] / total
        cumulative = k == 1 and ratio or cumulative + ratio
        ratios[k], cumulatives[k] = ratio, cumulative
        local value = 0.0
        for index = k, size do
            value = value + 1.0 / index
        end
        broken[k] = value / size
        standard_errors[k] = values[k] * math.sqrt(2.0 / n)
        local isolated = true
        for _, other in ipairs({k - 1, k + 1}) do
            if other >= 1 and other <= size and math.abs(values[k] - values[other]) <= standard_errors[k] then
                isolated = false
            end
        end
        separated[k] = isolated
        if values[k] > average then
            criteria.kaiser = criteria.kaiser + 1
        end
        if not broken_found and ratio <= broken[k] then
            criteria.broken_stick, broken_found = k - 1, true
        end
        if not parallel_found and ratio <= parallel[k] then
            criteria.parallel, parallel_found = k - 1, true
        end
        if not cumulative_found and cumulative >= params.cumulative then
            criteria.cumulative, cumulative_found = k, true
        end
    end
    local retained = tonumber(params.components) or criteria[params.components]
    retained = math.max(1, retained)
    return {total = total, average = average, ratios = ratios, cumulative = cumulatives, broken = broken,
        standard_errors = standard_errors, separated = separated, criteria = criteria, retained = retained}
end
local function loading_analysis(values, vectors, covariance, count)
    local loadings, communalities, correlations = {}, {}, {}
    for j = 1, #values do
        loadings[j], correlations[j] = {}, {}
        local communality = 0.0
        for k = 1, #values do
            local value = vectors[k][j] * math.sqrt(values[k])
            loadings[j][k] = value
            if k <= count then
                communality = communality + value * value
            end
            if k <= 2 then
                correlations[j][k] = value / math.sqrt(covariance[j][j])
            end
        end
        communalities[j] = communality / covariance[j][j]
    end
    return loadings, communalities, correlations
end
local function varimax_criterion(values, count)
    local result = 0.0
    for k = 1, count do
        local q4, q2 = 0.0, 0.0
        for j = 1, #values do
            local square = values[j][k] * values[j][k]
            q4, q2 = q4 + square * square, q2 + square
        end
        result = result + (q4 / #values - (q2 / #values) * (q2 / #values))
    end
    return result
end
local function varimax(loadings, count, cycles)
    local size, lengths, normalized = #loadings, {}, {}
    for j = 1, size do
        local squared = 0.0
        for k = 1, count do
            squared = squared + loadings[j][k] * loadings[j][k]
        end
        lengths[j], normalized[j] = math.sqrt(squared), {}
        for k = 1, count do
            normalized[j][k] = loadings[j][k] / lengths[j]
        end
    end
    local criteria = {varimax_criterion(normalized, count)}
    for _ = 1, cycles do
        for a = 1, count - 1 do
            for b = a + 1, count do
                local sa, sb, sc, sd = 0.0, 0.0, 0.0, 0.0
                for j = 1, size do
                    local first, second = normalized[j][a], normalized[j][b]
                    local phi, psi = first * first - second * second, 2.0 * first * second
                    sa, sb, sc, sd = sa + phi, sb + psi, sc + (phi * phi - psi * psi), sd + 2.0 * phi * psi
                end
                local numerator, denominator = sd - 2.0 * sa * sb / size, sc - (sa * sa - sb * sb) / size
                local omega = math.sqrt(numerator * numerator + denominator * denominator)
                if omega ~= 0.0 then
                    local cos4, sin4 = denominator / omega, numerator / omega
                    local cos2 = math.sqrt((1.0 + cos4) / 2.0)
                    local sin2 = cos2 == 0.0 and 1.0 or sin4 / (2.0 * cos2)
                    local cos1 = math.sqrt((1.0 + cos2) / 2.0)
                    local sin1 = sin2 / (2.0 * cos1)
                    for j = 1, size do
                        local first, second = normalized[j][a], normalized[j][b]
                        normalized[j][a], normalized[j][b] = cos1 * first + sin1 * second, -sin1 * first + cos1 * second
                    end
                end
            end
        end
        criteria[#criteria + 1] = varimax_criterion(normalized, count)
    end
    local columns, squares = {}, {}
    for k = 1, count do
        local column = {}
        for j = 1, size do
            column[j] = normalized[j][k] * lengths[j]
        end
        columns[k] = matrix.orient(column)
        squares[k] = matrix.dot(columns[k], columns[k])
    end
    local order = top_indices(squares, count)
    local rotated, ss, closest, congruences = {}, {}, {}, {}
    for j = 1, size do
        rotated[j] = {}
    end
    for k, source in ipairs(order) do
        ss[k] = squares[source]
        for j = 1, size do
            rotated[j][k] = columns[source][j]
        end
        local values = {}
        for component = 1, count do
            values[component] = math.abs(congruence(columns[source], matrix.column(loadings, component)))
        end
        closest[k] = argmax(values)
        congruences[k] = values[closest[k]]
    end
    return {loadings = rotated, squares = ss, criteria = criteria, closest = closest, congruences = congruences}
end
local function diagnose(standardized, scores, values, vectors, count, params, quality_needed)
    local result = {}
    for i, row in ipairs(standardized) do
        local residual = pca.residual(row, scores[i], vectors, count)
        local t2, spe = pca.t2(scores[i], values, count), matrix.dot(residual, residual)
        local represented = 0.0
        for k = 1, count do
            represented = represented + scores[i][k] * scores[i][k]
        end
        local quality = quality_needed and represented / matrix.dot(row, row) or 0.0
        local flag = (t2 > params.t2_limit and "T" or "") .. (spe > params.spe_limit and "Q" or "")
        if flag == "" then
            flag = "-"
        end
        local t2_contributions, spe_contributions = {}, {}
        for j, value in ipairs(row) do
            local weight = 0.0
            for k = 1, count do
                weight = weight + (scores[i][k] / values[k]) * vectors[k][j]
            end
            t2_contributions[j], spe_contributions[j] = value * weight, residual[j] * residual[j]
        end
        result[i] = {t2 = t2, spe = spe, quality = quality, flag = flag,
            t2_contributions = t2_contributions, spe_contributions = spe_contributions}
    end
    return result
end
local function supplementary_nearest(scores, reference, count)
    local result = {}
    for i, row in ipairs(scores) do
        local nearest, minimum = 1, nil
        for index, other in ipairs(reference) do
            local distance = 0.0
            for k = 1, count do
                distance = distance + (row[k] - other[k]) * (row[k] - other[k])
            end
            if minimum == nil or distance < minimum then
                nearest, minimum = index, distance
            end
        end
        result[i] = {index = nearest, distance = math.sqrt(minimum)}
    end
    return result
end
local function eigen_report(analysis)
    local data, params = analysis.data, analysis.data.params
    local prepared, result, retention = analysis.prepared, analysis.eigen, analysis.retention
    local count, size = retention.retained, #data.variables
    local lines = {"pca rows " .. #data.rows .. " used " .. #analysis.ids .. " variables " .. size .. " missing " .. params.missing .. " scaling " .. params.scaling}
    local incomplete = #analysis.incomplete == 0 and "-" or table.concat(analysis.incomplete, " ")
    append(lines, {"incomplete " .. #analysis.incomplete .. " " .. incomplete, "", "variable observed missing mean sd min max msa"})
    for j, variable in ipairs(data.variables) do
        local summary = analysis.summaries[j]
        lines[#lines + 1] = variable .. " " .. summary.observed .. " " .. summary.missing .. " " .. reals({summary.mean, summary.sd, summary.minimum, summary.maximum, analysis.adequacy.msa[j]})
    end
    local adequacy = analysis.adequacy
    append(lines, {"adequacy kmo " .. number(adequacy.kmo) .. " determinant " .. number(adequacy.determinant, 6) .. " bartlett " .. number(adequacy.bartlett) .. " df " .. adequacy.degrees, "", "matrix " .. params.scaling})
    for j, variable in ipairs(data.variables) do
        lines[#lines + 1] = variable .. " " .. reals(prepared.values[j])
    end
    local pairs, magnitudes = {}, {}
    for j = 1, size - 1 do
        for k = j + 1, size do
            pairs[#pairs + 1] = {j, k}
            magnitudes[#magnitudes + 1] = math.abs(prepared.correlation[j][k])
        end
    end
    local strongest = {}
    for _, index in ipairs(top_indices(magnitudes, params.top)) do
        local pair = pairs[index]
        strongest[#strongest + 1] = data.variables[pair[1]] .. ":" .. data.variables[pair[2]] .. ":" .. number(prepared.correlation[pair[1]][pair[2]])
    end
    append(lines, {"strongest " .. table.concat(strongest, " "), "", "jacobi sweeps " .. result.sweeps,
        "eigenvalues total " .. number(retention.total) .. " average " .. number(retention.average),
        "k eigenvalue ratio cumulative broken_stick parallel se separated"})
    for k = 1, size do
        lines[#lines + 1] = k .. " " .. reals({result.values[k], retention.ratios[k], retention.cumulative[k], retention.broken[k], analysis.parallel[k], retention.standard_errors[k]}) .. " " .. (retention.separated[k] and "yes" or "no")
    end
    local criteria = retention.criteria
    append(lines, {"retention kaiser " .. criteria.kaiser .. " broken_stick " .. criteria.broken_stick .. " parallel " .. criteria.parallel .. " cumulative " .. criteria.cumulative .. " target " .. number(params.cumulative),
        "components " .. count .. " rule " .. params.components, "", "eigenvectors"})
    local header = {"variable"}
    for k = 1, size do
        header[#header + 1] = "pc" .. k
    end
    lines[#lines + 1] = table.concat(header, " ")
    for j, variable in ipairs(data.variables) do
        local values = {}
        for k = 1, size do
            values[k] = result.vectors[k][j]
        end
        lines[#lines + 1] = variable .. " " .. reals(values)
    end
    append(lines, {"", "power_iteration iterations 1000", "k jacobi power agree_at match"})
    local matched = 0
    for k, powered in ipairs(analysis.power) do
        matched = matched + (powered.matched and 1 or 0)
        lines[#lines + 1] = k .. " " .. number(result.values[k]) .. " " .. number(powered.value) .. " " .. (powered.agreement or "-") .. " " .. (powered.matched and "yes" or "no")
    end
    append(lines, {"cross_check " .. matched .. "/" .. size, "", "scores", "component sd min min_id max max_id contributors"})
    for k = 1, count do
        local column = matrix.column(analysis.scores, k)
        local squared = 0.0
        local minimum, maximum, contributions = 1, 1, {}
        for i, value in ipairs(column) do
            squared = squared + value * value
            if value < column[minimum] then
                minimum = i
            end
            if value > column[maximum] then
                maximum = i
            end
            contributions[i] = value * value / ((#analysis.ids - 1) * result.values[k])
        end
        local fields = {}
        for _, i in ipairs(top_indices(contributions, params.top)) do
            fields[#fields + 1] = analysis.ids[i] .. ":" .. number(contributions[i])
        end
        lines[#lines + 1] = "pc" .. k .. " " .. number(math.sqrt(squared / (#analysis.ids - 1))) .. " " .. number(column[minimum]) .. " " .. analysis.ids[minimum] .. " " .. number(column[maximum]) .. " " .. analysis.ids[maximum] .. " " .. table.concat(fields, " ")
    end
    append(lines, {"", "varimax components " .. count .. " cycles " .. params.cycles})
    for index, value in ipairs(analysis.rotation.criteria) do
        lines[#lines + 1] = "cycle " .. index - 1 .. " criterion " .. number(value, 6)
    end
    for k = 1, count do
        lines[#lines + 1] = "rc" .. k .. " ss " .. number(analysis.rotation.squares[k]) .. " ratio " .. number(analysis.rotation.squares[k] / retention.total) .. " closest pc" .. analysis.rotation.closest[k] .. " congruence " .. number(analysis.rotation.congruences[k])
    end
    append(lines, {"", "sensitivity", "missing scaling rows sweeps eigenvalues cumulative congruence"})
    for _, combination in ipairs({{"listwise", "covariance"}, {"listwise", "correlation"}, {"mean", "covariance"}, {"mean", "correlation"}}) do
        local ids, rows = analysis_data(data, analysis.summaries, combination[1])
        local prepared_variant = pca.prepare(rows, combination[2])
        local variant = eigen.jacobi(prepared_variant.values)
        local total, cumulative = sum(variant.values), 0.0
        local values, agreements = {}, {}
        for k = 1, count do
            values[k] = variant.values[k]
            local ratio = variant.values[k] / total
            cumulative = k == 1 and ratio or cumulative + ratio
            agreements[k] = math.abs(matrix.dot(variant.vectors[k], result.vectors[k]))
        end
        lines[#lines + 1] = combination[1] .. " " .. combination[2] .. " " .. #ids .. " " .. variant.sweeps .. " " .. reals(values) .. " " .. number(cumulative) .. " " .. reals(agreements)
    end
    return lines
end
local function loadings_report(analysis)
    local count = analysis.retention.retained
    local header = {"variable"}
    for k = 1, count do
        header[#header + 1] = "pc" .. k
    end
    header[#header + 1] = "communality"
    for k = 1, count do
        header[#header + 1] = "rc" .. k
    end
    local lines = {table.concat(header, ",")}
    for j, variable in ipairs(analysis.data.variables) do
        local fields = {variable}
        for k = 1, count do
            fields[#fields + 1] = number(analysis.loadings[j][k])
        end
        fields[#fields + 1] = number(analysis.communalities[j])
        for k = 1, count do
            fields[#fields + 1] = number(analysis.rotation.loadings[j][k])
        end
        lines[#lines + 1] = table.concat(fields, ",")
    end
    return lines
end
local function scores_report(analysis)
    local count = analysis.retention.retained
    local header = {"id", "set"}
    for k = 1, count do
        header[#header + 1] = "pc" .. k
    end
    local lines = {table.concat(header, ",")}
    for _, collection in ipairs({{analysis.ids, analysis.scores, "data"}, {analysis.data.supplementary_ids, analysis.supplementary_scores, "supplementary"}}) do
        for index, id in ipairs(collection[1]) do
            local fields = {id, collection[3]}
            for k = 1, count do
                fields[#fields + 1] = number(collection[2][index][k])
            end
            lines[#lines + 1] = table.concat(fields, ",")
        end
    end
    return lines
end
local function outliers_report(analysis)
    local params, count = analysis.data.params, analysis.retention.retained
    local lines = {"diagnostics components " .. count .. " t2_limit " .. number(params.t2_limit) .. " spe_limit " .. number(params.spe_limit), "id t2 spe quality flag"}
    local flagged_t, flagged_q, both, any = 0, 0, 0, 0
    local t2_values, spe_values = {}, {}
    for index, row in ipairs(analysis.diagnostics) do
        lines[#lines + 1] = analysis.ids[index] .. " " .. reals({row.t2, row.spe, row.quality}) .. " " .. row.flag
        flagged_t = flagged_t + (row.flag:find("T", 1, true) and 1 or 0)
        flagged_q = flagged_q + (row.flag:find("Q", 1, true) and 1 or 0)
        both = both + (row.flag == "TQ" and 1 or 0)
        any = any + (row.flag ~= "-" and 1 or 0)
        t2_values[index], spe_values[index] = row.t2, row.spe
    end
    lines[#lines + 1] = "flagged t2 " .. flagged_t .. " spe " .. flagged_q .. " both " .. both .. " any " .. any
    for _, mode in ipairs({"t2", "spe"}) do
        append(lines, {"", "top " .. mode, "rank id " .. mode .. " variable contribution"})
        local values = mode == "t2" and t2_values or spe_values
        for rank, index in ipairs(top_indices(values, params.top)) do
            local contributions = analysis.diagnostics[index][mode .. "_contributions"]
            local variable = argmax(contributions)
            lines[#lines + 1] = rank .. " " .. analysis.ids[index] .. " " .. number(values[index]) .. " " .. analysis.data.variables[variable] .. " " .. number(contributions[variable])
        end
    end
    append(lines, {"", "reconstruction", "k mean_spe max_spe max_id"})
    for k = 1, #analysis.data.variables - 1 do
        local total, maximum, maximum_index = 0.0, nil, 1
        for i, row in ipairs(analysis.prepared.standardized) do
            local residual = pca.residual(row, analysis.scores[i], analysis.eigen.vectors, k)
            local spe = matrix.dot(residual, residual)
            total = total + spe
            if maximum == nil or spe > maximum then
                maximum, maximum_index = spe, i
            end
        end
        lines[#lines + 1] = k .. " " .. number(total / #analysis.ids) .. " " .. number(maximum) .. " " .. analysis.ids[maximum_index]
    end
    local header = {"id"}
    for k = 1, count do
        header[#header + 1] = "pc" .. k
    end
    append(header, {"t2", "spe", "flag", "nearest", "distance"})
    append(lines, {"", "supplementary", table.concat(header, " ")})
    for i, id in ipairs(analysis.data.supplementary_ids) do
        local fields = {id}
        for k = 1, count do
            fields[#fields + 1] = number(analysis.supplementary_scores[i][k])
        end
        local row, nearest = analysis.supplementary_diagnostics[i], analysis.nearest[i]
        append(fields, {number(row.t2), number(row.spe), row.flag, analysis.ids[nearest.index], number(nearest.distance)})
        lines[#lines + 1] = table.concat(fields, " ")
    end
    return lines
end
local function axes(grid, row, column)
    for index = 1, #grid[1] do
        grid[row][index] = "-"
    end
    for index = 1, #grid do
        grid[index][column] = "|"
    end
    grid[row][column] = "+"
end
local function draw_points(grid, cells)
    local counts = {}
    for row = 1, #grid do
        counts[row] = {}
    end
    for _, cell in ipairs(cells) do
        counts[cell.row][cell.column] = (counts[cell.row][cell.column] or 0) + 1
    end
    for row = 1, #grid do
        for column = 1, #grid[row] do
            local count = counts[row][column] or 0
            if count > 0 then
                grid[row][column] = count == 1 and "." or count <= 3 and "o" or "@"
            end
        end
    end
end
local function plots_report(analysis)
    local params, result, retained = analysis.data.params, analysis.eigen, analysis.retention
    local width = params.scree_width
    local kaiser = math.floor(retained.average / result.values[1] * width + 0.5)
    local lines = {"scree width " .. width .. " kaiser_column " .. kaiser}
    for k, value in ipairs(result.values) do
        local length = math.floor(value / result.values[1] * width + 0.5)
        local broken = math.floor(retained.broken[k] * retained.total / result.values[1] * width + 0.5)
        lines[#lines + 1] = "|" .. plot.scree(width, length, kaiser, broken) .. "| pc" .. k .. " " .. number(value)
    end
    width = params.biplot_width
    local height = params.biplot_height
    local maximum_x, maximum_y = 0.0, 0.0
    for _, scores in ipairs({analysis.scores, analysis.supplementary_scores}) do
        for _, row in ipairs(scores) do
            maximum_x, maximum_y = math.max(maximum_x, math.abs(row[1])), math.max(maximum_y, math.abs(row[2]))
        end
    end
    local largest_x, largest_y = 0.0, 0.0
    for _, row in ipairs(analysis.loadings) do
        largest_x, largest_y = math.max(largest_x, math.abs(row[1])), math.max(largest_y, math.abs(row[2]))
    end
    local arrow_scale = 0.9 * math.min(maximum_x / largest_x, maximum_y / largest_y)
    local grid = plot.grid(width, height)
    local origin_row, origin_column = plot.cell(0.0, 0.0, maximum_x, maximum_y, width, height)
    axes(grid, origin_row, origin_column)
    local tips = {}
    for j, row in ipairs(analysis.loadings) do
        local tip_row, tip_column = plot.cell(arrow_scale * row[1], arrow_scale * row[2], maximum_x, maximum_y, width, height)
        tips[j] = {row = tip_row, column = tip_column}
        for _, cell in ipairs(plot.shaft(origin_row, origin_column, tip_row, tip_column)) do
            grid[cell.row][cell.column] = cell.character
        end
    end
    local cells = {}
    for i, row in ipairs(analysis.scores) do
        local cell_row, column = plot.cell(row[1], row[2], maximum_x, maximum_y, width, height)
        cells[i] = {row = cell_row, column = column}
    end
    draw_points(grid, cells)
    for index, cell in ipairs(cells) do
        if analysis.diagnostics[index].flag ~= "-" then
            grid[cell.row][cell.column] = "X"
        end
    end
    for _, row in ipairs(analysis.supplementary_scores) do
        local cell_row, column = plot.cell(row[1], row[2], maximum_x, maximum_y, width, height)
        grid[cell_row][column] = "*"
    end
    for j, tip in ipairs(tips) do
        grid[tip.row][tip.column] = string.char(64 + j)
    end
    append(lines, {"", "biplot pc1 pc2 width " .. width .. " height " .. height,
        "x " .. number(-maximum_x) .. " " .. number(maximum_x) .. " y " .. number(-maximum_y) .. " " .. number(maximum_y) .. " arrow_scale " .. number(arrow_scale)})
    append(lines, plot.frame(grid))
    for j, variable in ipairs(analysis.data.variables) do
        lines[#lines + 1] = string.char(64 + j) .. " " .. variable .. " " .. reals({analysis.loadings[j][1], analysis.loadings[j][2]})
    end
    local radius = params.radius
    width, height = 2 * radius + 3, radius + 3
    local center_row, center_column = radius // 2 + 2, radius + 2
    grid = plot.grid(width, height)
    axes(grid, center_row, center_column)
    local function inside(row, column)
        return (column - center_column) * (column - center_column) + (2 * (row - center_row)) * (2 * (row - center_row)) <= radius * radius
    end
    for row = 1, height do
        for column = 1, width do
            if inside(row, column) and (not inside(row - 1, column) or not inside(row + 1, column) or not inside(row, column - 1) or not inside(row, column + 1)) then
                grid[row][column] = "."
            end
        end
    end
    for j, row in ipairs(analysis.correlations) do
        local cell_row = center_row - math.floor(row[2] * (radius // 2) + 0.5)
        local column = center_column + math.floor(row[1] * radius + 0.5)
        grid[cell_row][column] = string.char(64 + j)
    end
    append(lines, {"", "circle radius " .. radius})
    append(lines, plot.frame(grid))
    for j, variable in ipairs(analysis.data.variables) do
        local row = analysis.correlations[j]
        lines[#lines + 1] = string.char(64 + j) .. " " .. variable .. " " .. reals({row[1], row[2], row[1] * row[1] + row[2] * row[2]})
    end
    width, height = params.diagnostic_width, params.diagnostic_height
    local maximum_t2, maximum_spe = 2.0 * params.t2_limit, 2.0 * params.spe_limit
    grid = plot.grid(width, height)
    local limit_row, limit_column = plot.diagnostic_cell(params.t2_limit, params.spe_limit, maximum_t2, maximum_spe, width, height)
    axes(grid, limit_row, limit_column)
    cells = {}
    for index, row in ipairs(analysis.diagnostics) do
        local cell_row, column = plot.diagnostic_cell(row.t2, row.spe, maximum_t2, maximum_spe, width, height)
        cells[index] = {row = cell_row, column = column}
    end
    draw_points(grid, cells)
    for _, row in ipairs(analysis.supplementary_diagnostics) do
        local cell_row, column = plot.diagnostic_cell(row.t2, row.spe, maximum_t2, maximum_spe, width, height)
        grid[cell_row][column] = "*"
    end
    append(lines, {"", "diagnostic width " .. width .. " height " .. height .. " t2_max " .. number(maximum_t2) .. " spe_max " .. number(maximum_spe)})
    append(lines, plot.frame(grid))
    return lines
end
local function save(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do
        file:write(line, "\n")
    end
    file:close()
end
local data = dataset.read()
local summaries, incomplete = summarize(data)
local ids, rows = analysis_data(data, summaries, data.params.missing)
local prepared = pca.prepare(rows, data.params.scaling)
local result = eigen.jacobi(prepared.values)
local powered = eigen.power(prepared.values, result)
local parallel = parallel_analysis(#rows, #data.variables, data.params.repetitions, data.params.seed)
local retained = retention(result.values, parallel, #rows, data.params)
local loadings, communalities, correlations = loading_analysis(result.values, result.vectors, prepared.values, retained.retained)
local rotation = varimax(loadings, retained.retained, data.params.cycles)
local scores = pca.scores(prepared.standardized, result.vectors)
local diagnosed = diagnose(prepared.standardized, scores, result.values, result.vectors, retained.retained, data.params, true)
local supplementary = pca.standardize(data.supplementary, prepared.means, prepared.scales)
local supplementary_scores = pca.scores(supplementary, result.vectors)
local supplementary_diagnostics = diagnose(supplementary, supplementary_scores, result.values, result.vectors, retained.retained, data.params, false)
local analysis = {data = data, summaries = summaries, incomplete = incomplete, ids = ids, prepared = prepared,
    eigen = result, power = powered, parallel = parallel, retention = retained, loadings = loadings,
    communalities = communalities, correlations = correlations, rotation = rotation, scores = scores,
    diagnostics = diagnosed, supplementary_scores = supplementary_scores, supplementary_diagnostics = supplementary_diagnostics,
    nearest = supplementary_nearest(supplementary_scores, scores, retained.retained), adequacy = adequacy(prepared.correlation, #rows)}
os.execute("mkdir -p output")
save("eigen.txt", eigen_report(analysis))
save("loadings.csv", loadings_report(analysis))
save("scores.csv", scores_report(analysis))
save("outliers.txt", outliers_report(analysis))
save("plots.txt", plots_report(analysis))
