local M = {}
local function fields(line, pattern)
    local result = {}
    for value in line:gmatch(pattern) do
        result[#result + 1] = value
    end
    return result
end
local function csv(path)
    local result, first = {}, true
    for line in io.lines(path) do
        if first then
            first = false
        else
            result[#result + 1] = fields(line, "[^,]+")
        end
    end
    return result
end
local function sorted_keys(values)
    local result = {}
    for key in pairs(values) do
        result[#result + 1] = key
    end
    table.sort(result)
    return result
end
function M.read()
    local data = {training = {}, test = {}, catalog = {}, values = {}, user_ratings = {}, item_ratings = {},
        user_counts = {}, item_counts = {}, user_means = {}, item_means = {}, catalog_count = 0}
    local user_ids, item_ids, total = {}, {}, 0
    for _, row in ipairs(csv("input/ratings.csv")) do
        local u, i, r, time = tonumber(row[1]), tonumber(row[2]), tonumber(row[3]), tonumber(row[4])
        data.training[#data.training + 1] = {user = u, item = i, rating = r, time = time}
        user_ids[u], item_ids[i] = true, true
        data.values[u] = data.values[u] or {}
        data.values[u][i] = r
        data.user_ratings[u] = data.user_ratings[u] or {}
        data.item_ratings[i] = data.item_ratings[i] or {}
        data.user_ratings[u][#data.user_ratings[u] + 1] = {item = i, rating = r, time = time}
        data.item_ratings[i][#data.item_ratings[i] + 1] = {user = u, rating = r}
        total = total + r
    end
    data.users, data.items = sorted_keys(user_ids), sorted_keys(item_ids)
    data.mean = total / #data.training
    for _, u in ipairs(data.users) do
        table.sort(data.user_ratings[u], function(a, b) return a.item < b.item end)
        local sum = 0
        for _, row in ipairs(data.user_ratings[u]) do
            sum = sum + row.rating
        end
        data.user_counts[u], data.user_means[u] = #data.user_ratings[u], sum / #data.user_ratings[u]
    end
    for _, i in ipairs(data.items) do
        table.sort(data.item_ratings[i], function(a, b) return a.user < b.user end)
        local sum = 0
        for _, row in ipairs(data.item_ratings[i]) do
            sum = sum + row.rating
        end
        data.item_counts[i], data.item_means[i] = #data.item_ratings[i], sum / #data.item_ratings[i]
    end
    for _, row in ipairs(csv("input/items.csv")) do
        data.catalog[tonumber(row[1])] = {title = row[2], genres_text = row[3], genres = fields(row[3], "[^|]+")}
        data.catalog_count = data.catalog_count + 1
    end
    for _, row in ipairs(csv("input/test.csv")) do
        data.test[#data.test + 1] = {user = tonumber(row[1]), item = tonumber(row[2]), rating = tonumber(row[3])}
    end
    local params = {}
    for line in io.lines("input/params.txt") do
        local values = fields(line, "%S+")
        local key = table.remove(values, 1)
        local parsed = {}
        for _, value in ipairs(values) do
            parsed[#parsed + 1] = tonumber(value)
        end
        params[key] = parsed
    end
    data.params = {
        k = params.NEIGHBORS[1], shrinkage = params.SHRINKAGE[1], threshold = params.MIN_SIMILARITY[1],
        item_reg = params.BIAS_REG[1], user_reg = params.BIAS_REG[2], factors = params.FACTORS[1],
        learning_rate = params.LEARNING_RATE[1], regularization = params.REGULARIZATION[1], epochs = params.EPOCHS[1],
        als_reg = params.ALS_REG[1], als_iterations = params.ALS_ITERATIONS[1], seed = params.SEED[1],
        top = params.TOP_N[1], cutoffs = params.CUTOFFS, neighbor_grid = params.NEIGHBOR_GRID,
        user_groups = params.USER_GROUPS, item_groups = params.ITEM_GROUPS, buckets = params.TIME_BUCKETS[1],
        list_size = params.LIST_SIZE[1], recommend_users = params.RECOMMEND_USERS, similar_items = params.SIMILAR_ITEMS
    }
    return data
end
return M
