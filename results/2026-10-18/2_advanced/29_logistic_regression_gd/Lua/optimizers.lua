local logistic = require("logistic")
local M, Minstd = {}, {}
Minstd.__index = Minstd
function M.generator(seed)
    return setmetatable({state = seed}, Minstd)
end
function Minstd:draw()
    self.state = 48271 * self.state % 2147483647
    return self.state
end
function M.shuffle(sequence, generator)
    for i = #sequence, 2, -1 do
        local k = generator:draw() % i + 1
        sequence[i], sequence[k] = sequence[k], sequence[i]
    end
end
function M.move(weights, direction, rate)
    local result = {}
    for j, weight in ipairs(weights) do
        result[j] = weight - rate * direction[j]
    end
    return result
end
local function initial(vectors)
    local weights = {}
    for j = 1, #vectors[1] do
        weights[j] = 0.0
    end
    return weights
end
function M.gradient_descent(vectors, targets, lambda, rate, iterations)
    local weights = initial(vectors)
    local checkpoints = {{iteration = 0, weights = weights}}
    for t = 1, iterations do
        weights = M.move(weights, logistic.gradient(weights, vectors, targets, lambda), rate)
        if t % 100 == 0 then
            checkpoints[#checkpoints + 1] = {iteration = t, weights = weights}
        end
    end
    return checkpoints
end
function M.stochastic_gradient_descent(vectors, targets, lambda, rate, batch_size, epochs, seed)
    local generator, order, weights = M.generator(seed), {}, initial(vectors)
    for i = 1, #vectors do
        order[i] = i
    end
    local checkpoints = {{iteration = 0, weights = weights}}
    for epoch = 1, epochs do
        M.shuffle(order, generator)
        for start = 1, #order, batch_size do
            local batch, batch_targets = {}, {}
            for i = start, math.min(start + batch_size - 1, #order) do
                batch[#batch + 1], batch_targets[#batch_targets + 1] = vectors[order[i]], targets[order[i]]
            end
            weights = M.move(weights, logistic.gradient(weights, batch, batch_targets, lambda), rate)
        end
        checkpoints[#checkpoints + 1] = {iteration = epoch, weights = weights}
    end
    return checkpoints
end
function M.cholesky(matrix)
    local lower = {}
    for i = 1, #matrix do
        lower[i] = {}
        for j = 1, #matrix do
            lower[i][j] = 0.0
        end
    end
    for j = 1, #matrix do
        for i = j, #matrix do
            local total = 0.0
            for k = 1, j - 1 do
                total = total + lower[i][k] * lower[j][k]
            end
            local remainder = matrix[i][j] - total
            if i == j then
                lower[j][j] = math.sqrt(remainder)
            else
                lower[i][j] = remainder / lower[j][j]
            end
        end
    end
    return lower
end
function M.solve(lower, values)
    local middle, solution = {}, {}
    for i = 1, #lower do
        local total = 0.0
        for k = 1, i - 1 do
            total = total + lower[i][k] * middle[k]
        end
        middle[i] = (values[i] - total) / lower[i][i]
    end
    for i = #lower, 1, -1 do
        local total = 0.0
        for k = i + 1, #lower do
            total = total + lower[k][i] * solution[k]
        end
        solution[i] = (middle[i] - total) / lower[i][i]
    end
    return solution
end
function M.newton_direction(weights, vectors, targets, lambda)
    local direction = logistic.gradient(weights, vectors, targets, lambda)
    return direction, M.solve(M.cholesky(logistic.hessian(weights, vectors, lambda)), direction)
end
function M.newton_method(vectors, targets, lambda)
    local weights = initial(vectors)
    local checkpoints = {{iteration = 0, weights = weights}}
    for t = 1, 10 do
        local _, step = M.newton_direction(weights, vectors, targets, lambda)
        weights = M.move(weights, step, 1.0)
        checkpoints[#checkpoints + 1] = {iteration = t, weights = weights}
    end
    return checkpoints
end
return M
