local M = {}
local Generator = {}
Generator.__index = Generator
function M.generator(seed)
    return setmetatable({state = seed}, Generator)
end
function Generator:next()
    self.state = (48271 * self.state) % 2147483647
    return self.state
end
function Generator:initial()
    return ((self:next() % 2001) - 1000) / 10000
end
function M.dot(first, second)
    local result = 0.0
    for index, value in ipairs(first) do
        result = result + value * second[index]
    end
    return result
end
local function factors(ids, count, generator)
    local result = {}
    for _, id in ipairs(ids) do
        result[id] = {}
        for factor = 1, count do
            result[id][factor] = generator:initial()
        end
    end
    return result
end
local function rmse(data, prediction)
    local total = 0.0
    for _, row in ipairs(data.training) do
        local error = row.rating - prediction(row.user, row.item)
        total = total + error * error
    end
    return math.sqrt(total / #data.training)
end
function M.svd(data)
    local params, generator = data.params, M.generator(data.params.seed)
    local user_vectors = factors(data.users, params.factors, generator)
    local item_vectors = factors(data.items, params.factors, generator)
    local model = {users = user_vectors, items = item_vectors, user_bias = {}, item_bias = {}, log = {}}
    for _, u in ipairs(data.users) do
        model.user_bias[u] = 0.0
    end
    for _, i in ipairs(data.items) do
        model.item_bias[i] = 0.0
    end
    local function prediction(u, i)
        return ((data.mean + model.user_bias[u]) + model.item_bias[i]) + M.dot(model.users[u], model.items[i])
    end
    local order = {}
    for index = 1, #data.training do
        order[index] = index
    end
    for epoch = 1, params.epochs do
        for t = #order, 2, -1 do
            local other = generator:next() % t + 1
            order[t], order[other] = order[other], order[t]
        end
        for _, index in ipairs(order) do
            local row = data.training[index]
            local u, i = row.user, row.item
            local error = row.rating - prediction(u, i)
            model.user_bias[u] = model.user_bias[u] + params.learning_rate * (error - params.regularization * model.user_bias[u])
            model.item_bias[i] = model.item_bias[i] + params.learning_rate * (error - params.regularization * model.item_bias[i])
            for f = 1, params.factors do
                local a, b = model.users[u][f], model.items[i][f]
                model.users[u][f] = a + params.learning_rate * (error * b - params.regularization * a)
                model.items[i][f] = b + params.learning_rate * (error * a - params.regularization * b)
            end
        end
        model.log[#model.log + 1] = rmse(data, prediction)
    end
    return model
end
local function zeros(size)
    local result = {}
    for index = 1, size do
        result[index] = 0.0
    end
    return result
end
local function square(size)
    local result = {}
    for index = 1, size do
        result[index] = zeros(size)
    end
    return result
end
function M.solve(a, w)
    local size = #w
    local lower = square(size)
    for row = 1, size do
        for column = 1, row do
            local sum = 0.0
            for t = 1, column - 1 do
                sum = sum + lower[row][t] * lower[column][t]
            end
            local value = a[row][column] - sum
            lower[row][column] = row == column and math.sqrt(value) or value / lower[column][column]
        end
    end
    local z, x = zeros(size), zeros(size)
    for row = 1, size do
        local sum = 0.0
        for t = 1, row - 1 do
            sum = sum + lower[row][t] * z[t]
        end
        z[row] = (w[row] - sum) / lower[row][row]
    end
    for row = size, 1, -1 do
        local sum = 0.0
        for t = row + 1, size do
            sum = sum + lower[t][row] * x[t]
        end
        x[row] = (z[row] - sum) / lower[row][row]
    end
    return x
end
function M.als(data, user_bias, item_bias)
    local params = data.params
    local generator = M.generator(params.seed)
    local model = {users = {}, items = factors(data.items, params.factors, generator), log = {}}
    local function residual(u, i, rating)
        return rating - ((data.mean + user_bias[u]) + item_bias[i])
    end
    local function prediction(u, i)
        return ((data.mean + user_bias[u]) + item_bias[i]) + M.dot(model.users[u], model.items[i])
    end
    for iteration = 1, params.als_iterations do
        for _, u in ipairs(data.users) do
            local a, w = square(params.factors), zeros(params.factors)
            for _, row in ipairs(data.user_ratings[u]) do
                local vector = model.items[row.item]
                local z = residual(u, row.item, row.rating)
                for first = 1, params.factors do
                    w[first] = w[first] + z * vector[first]
                    for second = 1, params.factors do
                        a[first][second] = a[first][second] + vector[first] * vector[second]
                    end
                end
            end
            for first = 1, params.factors do
                a[first][first] = a[first][first] + params.als_reg * data.user_counts[u]
            end
            model.users[u] = M.solve(a, w)
        end
        for _, i in ipairs(data.items) do
            local a, w = square(params.factors), zeros(params.factors)
            for _, row in ipairs(data.item_ratings[i]) do
                local vector = model.users[row.user]
                local z = residual(row.user, i, row.rating)
                for first = 1, params.factors do
                    w[first] = w[first] + z * vector[first]
                    for second = 1, params.factors do
                        a[first][second] = a[first][second] + vector[first] * vector[second]
                    end
                end
            end
            for first = 1, params.factors do
                a[first][first] = a[first][first] + params.als_reg * data.item_counts[i]
            end
            model.items[i] = M.solve(a, w)
        end
        model.log[#model.log + 1] = rmse(data, prediction)
    end
    return model
end
return M
