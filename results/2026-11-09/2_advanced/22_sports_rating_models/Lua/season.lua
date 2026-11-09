local M = {}
local function split(text, separator)
    local parts, position = {}, 1
    while true do
        local ending = text:find(separator, position, true)
        if not ending then parts[#parts + 1] = text:sub(position) break end
        parts[#parts + 1], position = text:sub(position, ending - 1), ending + #separator
    end
    return parts
end

function M.matches_before(matches, round)
    local result = {}
    for _, match in ipairs(matches) do if match.round < round then result[#result + 1] = match end end
    return result
end

function M.load_season(folder)
    local teams, indices, matches, values = {}, {}, {}, {}
    local first = true
    for line in io.lines(folder .. "/teams.csv") do
        if first then first = false
        else local fields = split(line, ",") local index = #teams + 1 teams[index] = {index = index, code = fields[1], name = fields[2]} indices[fields[1]] = index end
    end
    first = true
    for line in io.lines(folder .. "/matches.csv") do
        if first then first = false
        else
            local fields = split(line, ",")
            local hs, as = tonumber(fields[4]), tonumber(fields[5])
            matches[#matches + 1] = {round = tonumber(fields[1]), home = indices[fields[2]], away = indices[fields[3]],
                home_score = hs, away_score = as, margin = hs - as, y2 = hs > as and 2 or hs == as and 1 or 0,
                y = hs > as and 1.0 or hs == as and 0.5 or 0.0, order = #matches + 1}
        end
    end
    table.sort(matches, function(a, b) return a.round < b.round or a.round == b.round and a.order < b.order end)
    for line in io.lines(folder .. "/params.txt") do
        local fields = split(line, " ")
        local args = {}
        for position = 2, #fields do args[#args + 1] = tonumber(fields[position]) end
        values[fields[1]] = args
    end
    local settings = {}
    local names = {WIN_POINTS = "win_points", DRAW_POINTS = "draw_points", FORM_LENGTH = "form_length", CLOSE_MARGIN = "close_margin",
        PYTHAGOREAN_EXPONENT = "pythagorean_exponent", ELO_K = "elo_k", ELO_HOME = "elo_home", ELO_INITIAL = "elo_initial",
        BT_ITERATIONS = "bt_iterations", OD_ITERATIONS = "od_iterations", LINK_ITERATIONS = "link_iterations", HOLDOUT_ROUND = "holdout_round",
        UPSETS = "upsets", CALIBRATION_BINS = "calibration_bins", SIMULATIONS = "simulations", SIM_SEED = "seed", TOP_POSITIONS = "top_positions", BOTTOM_POSITIONS = "bottom_positions"}
    for key, name in pairs(names) do settings[name] = values[key][1] end
    settings.grid_k, settings.grid_home = values.ELO_GRID_K, values.ELO_GRID_HOME
    return teams, matches, settings
end

return M
