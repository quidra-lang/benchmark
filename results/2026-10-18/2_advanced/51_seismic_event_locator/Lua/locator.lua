local M = {pi = 3.141592653589793}
function M.atan2(y, x)
    local result = math.atan(y, x)
    return result <= -M.pi and result + 2.0 * M.pi or result
end
function M.distance(solution, station)
    local dx, dy, dz = solution[1] - station.x, solution[2] - station.y, solution[3] + station.elevation
    return math.sqrt((dx * dx + dy * dy) + dz * dz)
end
function M.residuals(solution, observations, velocity)
    local result = {}
    for _, observation in ipairs(observations) do
        result[#result + 1] = observation.time - solution[4] - M.distance(solution, observation.station) / velocity
    end
    return result
end
function M.rms(solution, observations, velocity)
    local sum = 0.0
    for _, value in ipairs(M.residuals(solution, observations, velocity)) do
        sum = sum + value * value
    end
    return math.sqrt(sum / #observations)
end
function M.grid_search(observations, params)
    local best, minimum, profile = nil, math.huge, {}
    local gx, gy, gz = params.grid_x, params.grid_y, params.grid_z
    for x = gx[1], gx[2], gx[3] do
        for y = gy[1], gy[2], gy[3] do
            for z = gz[1], gz[2], gz[3] do
                local solution = {x + 0.0, y + 0.0, z + 0.0, 0.0}
                local deltas, total = {}, 0.0
                for _, observation in ipairs(observations) do
                    local value = observation.time - M.distance(solution, observation.station) / params.velocity
                    deltas[#deltas + 1], total = value, total + value
                end
                local origin, error = total / #observations, 0.0
                for _, value in ipairs(deltas) do
                    local difference = value - origin
                    error = error + difference * difference
                end
                if error < minimum then
                    solution[4], best, minimum = origin, solution, error
                end
                if not profile[z] or error < profile[z] then
                    profile[z] = error
                end
            end
        end
    end
    local depths = {}
    for z = gz[1], gz[2], gz[3] do
        depths[#depths + 1] = math.sqrt(profile[z] / #observations)
    end
    return {solution = best, rms = math.sqrt(minimum / #observations), profile = depths}
end
function M.cholesky(matrix)
    local lower = {}
    for row = 1, 4 do
        lower[row] = {0.0, 0.0, 0.0, 0.0}
        for column = 1, row do
            local sum = 0.0
            for index = 1, column - 1 do
                sum = sum + lower[row][index] * lower[column][index]
            end
            local difference = matrix[row][column] - sum
            lower[row][column] = row == column and math.sqrt(difference) or difference / lower[column][column]
        end
    end
    return lower
end
function M.solve(lower, right)
    local forward, result = {}, {}
    for row = 1, 4 do
        local sum = 0.0
        for column = 1, row - 1 do
            sum = sum + lower[row][column] * forward[column]
        end
        forward[row] = (right[row] - sum) / lower[row][row]
    end
    for row = 4, 1, -1 do
        local sum = 0.0
        for column = row + 1, 4 do
            sum = sum + lower[column][row] * result[column]
        end
        result[row] = (forward[row] - sum) / lower[row][row]
    end
    return result
end
local function normals(solution, observations, velocity)
    local matrix, right = {}, {0.0, 0.0, 0.0, 0.0}
    for row = 1, 4 do
        matrix[row] = {0.0, 0.0, 0.0, 0.0}
    end
    for _, observation in ipairs(observations) do
        local station = observation.station
        local distance = M.distance(solution, station)
        local residual = observation.time - solution[4] - distance / velocity
        local denominator = velocity * distance
        local derivatives = {(solution[1] - station.x) / denominator,
            (solution[2] - station.y) / denominator, (solution[3] + station.elevation) / denominator, 1.0}
        for row = 1, 4 do
            right[row] = right[row] + derivatives[row] * residual
            for column = 1, 4 do
                matrix[row][column] = matrix[row][column] + derivatives[row] * derivatives[column]
            end
        end
    end
    return matrix, right
end
function M.geiger(initial, observations, velocity)
    local solution, trace = {table.unpack(initial)}, {}
    for iteration = 1, 8 do
        local matrix, right = normals(solution, observations, velocity)
        local change = M.solve(M.cholesky(matrix), right)
        for axis = 1, 4 do
            solution[axis] = solution[axis] + change[axis]
        end
        if solution[3] < 0.0 then
            solution[3] = 0.0
        end
        trace[#trace + 1] = {number = iteration, solution = {table.unpack(solution)}, rms = M.rms(solution, observations, velocity)}
    end
    return {solution = solution, trace = trace, residuals = M.residuals(solution, observations, velocity), rms = M.rms(solution, observations, velocity)}
end
function M.run(observations, params)
    local grid = M.grid_search(observations, params)
    local result = M.geiger(grid.solution, observations, params.velocity)
    result.grid = grid
    return result
end
function M.ellipse(solution, observations, velocity)
    local matrix = normals(solution, observations, velocity)
    local lower, inverse = M.cholesky(matrix), {}
    for column = 1, 4 do
        local unit = {0.0, 0.0, 0.0, 0.0}
        unit[column] = 1.0
        inverse[column] = M.solve(lower, unit)
    end
    local sum = 0.0
    for _, residual in ipairs(M.residuals(solution, observations, velocity)) do
        sum = sum + residual * residual
    end
    local variance, covariance = sum / (#observations - 4), {}
    for row = 1, 4 do
        covariance[row] = {}
        for column = 1, 4 do
            covariance[row][column] = variance * inverse[column][row]
        end
    end
    local xx, yy, xy = covariance[1][1], covariance[2][2], covariance[1][2]
    local midpoint, difference = (xx + yy) / 2.0, (xx - yy) / 2.0
    local radius = math.sqrt(difference * difference + xy * xy)
    local theta = M.atan2(2.0 * xy, xx - yy) / 2.0 * 180.0 / M.pi
    local azimuth = 90.0 - theta
    if azimuth >= 180.0 then
        azimuth = azimuth - 180.0
    elseif azimuth < 0.0 then
        azimuth = azimuth + 180.0
    end
    return {smaj = math.sqrt(midpoint + radius), smin = math.sqrt(midpoint - radius),
        az = azimuth, erz = math.sqrt(covariance[3][3]), ert = math.sqrt(covariance[4][4])}
end
return M
