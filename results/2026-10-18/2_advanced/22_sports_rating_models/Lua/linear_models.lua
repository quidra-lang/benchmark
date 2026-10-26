local M = {}
local function matrix(size)
    local result = {}
    for row = 1, size do result[row] = {} for column = 1, size do result[row][column] = 0.0 end end
    return result
end

function M.cholesky_solve(a, vector)
    local size, lower = #vector, matrix(#vector)
    for i = 1, size do
        for j = 1, i do
            local total = 0.0
            for k = 1, j - 1 do total = total + lower[i][k] * lower[j][k] end
            if j < i then lower[i][j] = (a[i][j] - total) / lower[j][j]
            else lower[i][i] = math.sqrt(a[i][i] - total) end
        end
    end
    local forward, solution = {}, {}
    for i = 1, size do
        local total = 0.0
        for k = 1, i - 1 do total = total + lower[i][k] * forward[k] end
        forward[i] = (vector[i] - total) / lower[i][i]
    end
    for i = size, 1, -1 do
        local total = 0.0
        for k = i + 1, size do total = total + lower[k][i] * solution[k] end
        solution[i] = (forward[i] - total) / lower[i][i]
    end
    return solution
end

function M.gaussian_solve(a, vector)
    local size = #vector
    for k = 1, size do
        local pivot = k
        for row = k + 1, size do if math.abs(a[row][k]) > math.abs(a[pivot][k]) then pivot = row end end
        a[k], a[pivot], vector[k], vector[pivot] = a[pivot], a[k], vector[pivot], vector[k]
        for i = k + 1, size do
            local factor = a[i][k] / a[k][k]
            for j = k, size do a[i][j] = a[i][j] - factor * a[k][j] end
            vector[i] = vector[i] - factor * vector[k]
        end
    end
    local solution = {}
    for i = size, 1, -1 do
        local total = 0.0
        for j = i + 1, size do total = total + a[i][j] * solution[j] end
        solution[i] = (vector[i] - total) / a[i][i]
    end
    return solution
end

function M.colley_ratings(team_count, matches)
    local a, balance, vector = matrix(team_count), {}, {}
    for team = 1, team_count do a[team][team], balance[team] = 2.0, 0 end
    for _, match in ipairs(matches) do
        local i, j = match.home, match.away
        a[i][i], a[j][j], a[i][j], a[j][i] = a[i][i] + 1, a[j][j] + 1, a[i][j] - 1, a[j][i] - 1
        if match.margin > 0 then balance[i], balance[j] = balance[i] + 1, balance[j] - 1
        elseif match.margin < 0 then balance[i], balance[j] = balance[i] - 1, balance[j] + 1 end
    end
    for team = 1, team_count do vector[team] = 1 + balance[team] / 2 end
    return M.cholesky_solve(a, vector)
end

function M.massey_ratings(team_count, matches)
    local last, a, vector = team_count + 1, matrix(team_count + 1), {}
    for i = 1, last do vector[i] = 0.0 end
    for _, match in ipairs(matches) do
        local i, j = match.home, match.away
        a[i][i], a[j][j], a[i][j], a[j][i] = a[i][i] + 1, a[j][j] + 1, a[i][j] - 1, a[j][i] - 1
        a[i][last], a[last][i], a[j][last], a[last][j] = a[i][last] + 1, a[last][i] + 1, a[j][last] - 1, a[last][j] - 1
        a[last][last] = a[last][last] + 1
        vector[i], vector[j], vector[last] = vector[i] + match.margin, vector[j] - match.margin, vector[last] + match.margin
    end
    for column = 1, team_count do a[team_count][column] = 1.0 end
    a[team_count][last], vector[team_count] = 0.0, 0.0
    local solution = M.gaussian_solve(a, vector)
    local advantage = table.remove(solution)
    return solution, advantage
end

return M
