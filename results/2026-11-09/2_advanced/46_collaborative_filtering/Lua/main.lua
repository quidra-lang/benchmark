local ratings = require("ratings")
local neighborhood = require("neighborhood")
local factorization = require("factorization")
local evaluation = require("evaluation")
local report = require("report")
local real = report.real
local methods = {"GLOBAL", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS"}
local rankings = {"POPULAR", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS"}
local function copy(values)
    return {table.unpack(values)}
end
local function append(destination, source)
    for _, value in ipairs(source) do
        destination[#destination + 1] = value
    end
end
local function sorted_keys(values)
    local result = {}
    for key in pairs(values) do
        result[#result + 1] = key
    end
    table.sort(result)
    return result
end
local function contains(values, value)
    for _, item in ipairs(values) do
        if item == value then
            return true
        end
    end
    return false
end
local function training_rmse(data, prediction)
    local sum = 0.0
    for _, row in ipairs(data.training) do
        local error = row.rating - prediction(row.user, row.item)
        sum = sum + error * error
    end
    return math.sqrt(sum / #data.training)
end
local function train_baseline(data)
    local user_bias, item_bias, log = {}, {}, {}
    for _, u in ipairs(data.users) do
        user_bias[u] = 0.0
    end
    for _, i in ipairs(data.items) do
        item_bias[i] = 0.0
    end
    for sweep = 1, 10 do
        for _, i in ipairs(data.items) do
            local sum = 0.0
            for _, row in ipairs(data.item_ratings[i]) do
                sum = sum + (row.rating - data.mean - user_bias[row.user])
            end
            item_bias[i] = sum / (data.params.item_reg + data.item_counts[i])
        end
        for _, u in ipairs(data.users) do
            local sum = 0.0
            for _, row in ipairs(data.user_ratings[u]) do
                sum = sum + (row.rating - data.mean - item_bias[row.item])
            end
            user_bias[u] = sum / (data.params.user_reg + data.user_counts[u])
        end
        log[sweep] = training_rmse(data, function(u, i) return (data.mean + user_bias[u]) + item_bias[i] end)
    end
    return {users = user_bias, items = item_bias, log = log}
end
local Predictor = {}
Predictor.__index = Predictor
function Predictor:baseline(u, i)
    return (self.data.mean + self.baseline_model.users[u]) + self.baseline_model.items[i]
end
function Predictor:predict(method, u, i, count)
    count = count or self.data.params.k
    local data, neighbors = self.data, self.neighbors
    local value, fallback, used, average_similarity, top = self:baseline(u, i), false, 0, nil, nil
    if method == "GLOBAL" then
        value = data.mean
    elseif method == "USER_KNN" or method == "ITEM_KNN" then
        local candidates = {}
        if method == "USER_KNN" then
            for _, row in ipairs(data.item_ratings[i]) do
                local similarity = neighbors.users[u][row.user]
                if similarity and similarity.value > data.params.threshold then
                    candidates[#candidates + 1] = {id = row.user, similarity = similarity.value, rating = row.rating}
                end
            end
        else
            for _, row in ipairs(data.user_ratings[u]) do
                local similarity = neighbors.items[i][row.item]
                if similarity and similarity.value > data.params.threshold then
                    candidates[#candidates + 1] = {id = row.item, similarity = similarity.value, rating = row.rating}
                end
            end
        end
        local selected = neighborhood.select(candidates, count)
        if #selected == 0 then
            fallback = true
        else
            local numerator, denominator = 0.0, 0.0
            for _, candidate in ipairs(selected) do
                local mean = method == "USER_KNN" and data.user_means[candidate.id] or data.item_means[candidate.id]
                numerator = numerator + candidate.similarity * (candidate.rating - mean)
                denominator = denominator + candidate.similarity
            end
            value = (method == "USER_KNN" and data.user_means[u] or data.item_means[i]) + numerator / denominator
            used, average_similarity, top = #selected, denominator / #selected, selected[1].id
        end
    elseif method == "SLOPE_ONE" then
        local numerator, denominator = 0.0, 0
        for _, row in ipairs(data.user_ratings[u]) do
            local common = neighbors.common[i][row.item]
            if common and common >= 1 then
                local deviation = neighbors.difference[i][row.item] / (common + data.params.shrinkage)
                numerator = numerator + (deviation + row.rating) * common
                denominator = denominator + common
            end
        end
        if denominator == 0 then
            fallback = true
        else
            value = numerator / denominator
        end
    elseif method == "SVD" then
        value = ((data.mean + self.svd.user_bias[u]) + self.svd.item_bias[i]) + factorization.dot(self.svd.users[u], self.svd.items[i])
    elseif method == "ALS" then
        value = self:baseline(u, i) + factorization.dot(self.als.users[u], self.als.items[i])
    end
    return {value = value, fallback = fallback, count = used, similarity = average_similarity, top = top}
end
function Predictor:ranked(method, u)
    self.lists[u] = self.lists[u] or {}
    if self.lists[u][method] then
        return self.lists[u][method]
    end
    local items = {}
    if method == "POPULAR" then
        for _, i in ipairs(self.popularity) do
            if not self.data.values[u][i] then
                items[#items + 1] = i
            end
        end
    else
        local predictions = {}
        for _, i in ipairs(self.data.items) do
            if not self.data.values[u][i] then
                items[#items + 1] = i
                predictions[i] = self:predict(method, u, i)
            end
        end
        table.sort(items, function(a, b)
            if predictions[a].value ~= predictions[b].value then
                return predictions[a].value > predictions[b].value
            end
            return a < b
        end)
    end
    self.lists[u][method] = items
    return items
end
local function build_predictor(data)
    local baseline = train_baseline(data)
    local svd = factorization.svd(data)
    local als = factorization.als(data, baseline.users, baseline.items)
    local popularity = copy(data.items)
    table.sort(popularity, function(a, b)
        if data.item_counts[a] ~= data.item_counts[b] then
            return data.item_counts[a] > data.item_counts[b]
        elseif data.item_means[a] ~= data.item_means[b] then
            return data.item_means[a] > data.item_means[b]
        end
        return a < b
    end)
    return setmetatable({data = data, baseline_model = baseline, neighbors = neighborhood.build(data),
        svd = svd, als = als, popularity = popularity, lists = {}}, Predictor)
end
local function test_predictions(predictor)
    local data = predictor.data
    local predictions, clipped, errors, raw = {}, {}, {}, {}
    local csv = {"user,item,actual,GLOBAL,BASELINE,USER_KNN,ITEM_KNN,SLOPE_ONE,SVD,ALS"}
    for method_index, method in ipairs(methods) do
        predictions[method_index], clipped[method_index], errors[method_index], raw[method_index] = {}, {}, {}, {}
    end
    for index, row in ipairs(data.test) do
        local fields = {row.user, row.item, row.rating}
        for method_index, method in ipairs(methods) do
            local prediction = predictor:predict(method, row.user, row.item)
            local value = evaluation.clip(prediction.value)
            predictions[method_index][index], clipped[method_index][index] = prediction, value
            errors[method_index][index], raw[method_index][index] = value - row.rating, prediction.value
            fields[#fields + 1] = real(value)
        end
        csv[#csv + 1] = table.concat(fields, ",")
    end
    local relevant, relevant_counts, evaluated = {}, {}, {}
    for _, row in ipairs(data.test) do
        if row.rating >= 4 then
            relevant[row.user] = relevant[row.user] or {}
            relevant_counts[row.user] = (relevant_counts[row.user] or 0) + 1
            relevant[row.user][row.item] = true
        end
    end
    for _, u in ipairs(data.users) do
        if relevant_counts[u] then
            evaluated[#evaluated + 1] = u
        end
    end
    return {csv = csv, predictions = predictions, clipped = clipped, errors = errors, raw = raw,
        relevant = relevant, relevant_counts = relevant_counts, evaluated = evaluated}
end
local function group_number(value, bounds)
    local result = 1
    for _, bound in ipairs(bounds) do
        if value >= bound then
            result = result + 1
        end
    end
    return result
end
local function error_fields(tested, indices, absolute)
    local fields = {}
    for method_index, method in ipairs(methods) do
        local errors = {}
        for _, index in ipairs(indices) do
            errors[#errors + 1] = tested.errors[method_index][index]
        end
        local value
        if #errors > 0 then
            value = absolute and evaluation.mae(errors) or evaluation.rmse(errors)
        end
        fields[#fields + 1] = method .. " " .. real(value)
    end
    return table.concat(fields, " ")
end
local function median(values)
    local ordered = copy(values)
    table.sort(ordered)
    local count = #ordered
    if count % 2 == 1 then
        return ordered[(count + 1) // 2]
    end
    return (ordered[count // 2] + ordered[count // 2 + 1]) / 2.0
end
local function ranked_metrics(predictor, tested, u, method, count)
    return evaluation.ranking(predictor:ranked(method, u), tested.relevant[u], tested.relevant_counts[u], count)
end
local function bias_order(ids, biases, descending)
    local result = copy(ids)
    table.sort(result, function(a, b)
        if biases[a] ~= biases[b] then
            if descending then
                return biases[a] > biases[b]
            end
            return biases[a] < biases[b]
        end
        return a < b
    end)
    return result
end
local function evaluation_report(predictor, tested)
    local data, params, neighbors = predictor.data, predictor.data.params, predictor.neighbors
    local sections, histogram = {}, {0, 0, 0, 0, 0}
    local first_time, last_time = data.training[1].time, data.training[1].time
    for _, row in ipairs(data.training) do
        histogram[row.rating] = histogram[row.rating] + 1
        first_time, last_time = math.min(first_time, row.time), math.max(last_time, row.time)
    end
    local user_counts, item_counts = {}, {}
    for _, u in ipairs(data.users) do
        user_counts[#user_counts + 1] = data.user_counts[u]
    end
    for _, i in ipairs(data.items) do
        item_counts[#item_counts + 1] = data.item_counts[i]
    end
    table.sort(user_counts)
    table.sort(item_counts)
    local user_pairs, usable_users, item_pairs, usable_items, slope_pairs = 0, 0, 0, 0, 0
    for first = 1, #data.users - 1 do
        for second = first + 1, #data.users do
            local value = neighbors.users[data.users[first]][data.users[second]]
            if value then
                user_pairs = user_pairs + 1
                usable_users = usable_users + (value.value > params.threshold and 1 or 0)
            end
        end
    end
    for first = 1, #data.items - 1 do
        for second = first + 1, #data.items do
            local i, j = data.items[first], data.items[second]
            local value = neighbors.items[i][j]
            if value then
                item_pairs = item_pairs + 1
                usable_items = usable_items + (value.value > params.threshold and 1 or 0)
            end
            if neighbors.common[i][j] then
                slope_pairs = slope_pairs + 1
            end
        end
    end
    sections[#sections + 1] = {
        "data users " .. #data.users .. " items " .. #data.items .. " catalog " .. data.catalog_count .. " ratings " .. #data.training .. " test " .. #data.test,
        "density " .. real(#data.training / (#data.users * #data.items)) .. " global_mean " .. real(data.mean),
        "histogram " .. table.concat(histogram, " "),
        "user_ratings min " .. user_counts[1] .. " median " .. real(median(user_counts)) .. " max " .. user_counts[#user_counts],
        "item_ratings min " .. item_counts[1] .. " median " .. real(median(item_counts)) .. " max " .. item_counts[#item_counts],
        "timestamps first " .. first_time .. " last " .. last_time,
        "cold_items " .. data.catalog_count - #data.items,
        "similarities user_pairs " .. user_pairs .. " usable " .. usable_users .. " item_pairs " .. item_pairs .. " usable " .. usable_items .. " slope_pairs " .. slope_pairs
    }
    local genre_stats = {}
    for _, i in ipairs(data.items) do
        local high = 0
        for _, row in ipairs(data.item_ratings[i]) do
            high = high + (row.rating >= 4 and 1 or 0)
        end
        for _, genre in ipairs(data.catalog[i].genres) do
            local stats = genre_stats[genre] or {items = 0, ratings = 0, high = 0}
            stats.items, stats.ratings, stats.high = stats.items + 1, stats.ratings + data.item_counts[i], stats.high + high
            genre_stats[genre] = stats
        end
    end
    local lines = {"genre_stats"}
    for _, genre in ipairs(sorted_keys(genre_stats)) do
        local stats = genre_stats[genre]
        lines[#lines + 1] = "genre " .. genre .. " items " .. stats.items .. " ratings " .. stats.ratings .. " high " .. stats.high
    end
    sections[#sections + 1] = lines
    lines = {"time_buckets " .. params.buckets}
    for bucket = 1, params.buckets do
        local count, users, sum = 0, {}, 0
        for _, row in ipairs(data.training) do
            local assigned = ((row.time - first_time) * params.buckets) // (last_time - first_time + 1) + 1
            if assigned == bucket then
                count, sum, users[row.user] = count + 1, sum + row.rating, true
            end
        end
        local mean = count > 0 and sum / count or nil
        lines[#lines + 1] = "bucket " .. bucket .. " ratings " .. count .. " users " .. #sorted_keys(users) .. " mean " .. real(mean)
    end
    sections[#sections + 1] = lines
    lines = {"rating_metrics"}
    local test_rmse = {}
    for index, method in ipairs(methods) do
        local clipped, fallback = 0, 0
        for _, prediction in ipairs(tested.predictions[index]) do
            clipped = clipped + ((prediction.value < 1.0 or prediction.value > 5.0) and 1 or 0)
            fallback = fallback + (prediction.fallback and 1 or 0)
        end
        test_rmse[index] = evaluation.rmse(tested.errors[index])
        lines[#lines + 1] = method .. " rmse " .. real(test_rmse[index]) .. " mae " .. real(evaluation.mae(tested.errors[index])) .. " clipped " .. clipped .. " fallback " .. fallback
    end
    sections[#sections + 1] = lines
    local train = {
        GLOBAL = training_rmse(data, function() return data.mean end),
        BASELINE = predictor.baseline_model.log[10], SVD = predictor.svd.log[#predictor.svd.log], ALS = predictor.als.log[#predictor.als.log]
    }
    lines = {"generalization"}
    for _, index in ipairs({1, 2, 6, 7}) do
        local method = methods[index]
        lines[#lines + 1] = method .. " train " .. real(train[method]) .. " test " .. real(test_rmse[index]) .. " gap " .. real(test_rmse[index] - train[method])
    end
    sections[#sections + 1] = lines
    lines = {"neighborhoods k " .. params.k}
    for _, index in ipairs({3, 4}) do
        local with_neighbors, count_sum, similarity_sum = 0, 0, 0.0
        for _, prediction in ipairs(tested.predictions[index]) do
            if not prediction.fallback then
                with_neighbors = with_neighbors + 1
                count_sum = count_sum + prediction.count
                similarity_sum = similarity_sum + prediction.similarity
            end
        end
        local mean_count = with_neighbors > 0 and count_sum / with_neighbors or nil
        local mean_similarity = with_neighbors > 0 and similarity_sum / with_neighbors or nil
        lines[#lines + 1] = methods[index] .. " predictions " .. #data.test .. " with_neighbors " .. with_neighbors .. " mean_neighbors " .. real(mean_count) .. " mean_similarity " .. real(mean_similarity)
    end
    sections[#sections + 1] = lines
    local actual_sum = 0
    for _, row in ipairs(data.test) do
        actual_sum = actual_sum + row.rating
    end
    local actual_mean, actual_squares = actual_sum / #data.test, 0.0
    local actual_same = true
    for _, row in ipairs(data.test) do
        actual_squares = actual_squares + (row.rating - actual_mean) * (row.rating - actual_mean)
        actual_same = actual_same and row.rating == data.test[1].rating
    end
    lines = {"prediction_stats actual mean " .. real(actual_mean) .. " std " .. real(math.sqrt(actual_squares / #data.test))}
    for index, method in ipairs(methods) do
        local sum = 0.0
        for _, value in ipairs(tested.clipped[index]) do
            sum = sum + value
        end
        local mean, squares, cross = sum / #data.test, 0.0, 0.0
        local all_same = true
        for t, value in ipairs(tested.clipped[index]) do
            squares = squares + (value - mean) * (value - mean)
            cross = cross + (value - mean) * (data.test[t].rating - actual_mean)
            all_same = all_same and value == tested.clipped[index][1]
        end
        local correlation
        if not all_same and not actual_same then
            correlation = cross / math.sqrt(squares * actual_squares)
        end
        lines[#lines + 1] = method .. " mean " .. real(mean) .. " std " .. real(math.sqrt(squares / #data.test)) .. " correlation " .. real(correlation)
    end
    sections[#sections + 1] = lines
    lines = {"error_bins edges 0.5 1.0 1.5 2.0"}
    for index, method in ipairs(methods) do
        local bins = {0, 0, 0, 0, 0}
        for _, error in ipairs(tested.errors[index]) do
            local bin = math.min(5, math.floor(math.abs(error) * 2.0) + 1)
            bins[bin] = bins[bin] + 1
        end
        lines[#lines + 1] = method .. " " .. table.concat(bins, " ")
    end
    sections[#sections + 1] = lines
    lines = {"comparison"}
    for a = 1, #methods - 1 do
        for b = a + 1, #methods do
            local wins, ties, losses = 0, 0, 0
            for t = 1, #data.test do
                local first, second = math.abs(tested.errors[a][t]), math.abs(tested.errors[b][t])
                if first < second then
                    wins = wins + 1
                elseif first == second then
                    ties = ties + 1
                else
                    losses = losses + 1
                end
            end
            lines[#lines + 1] = methods[a] .. " " .. methods[b] .. " wins " .. wins .. " ties " .. ties .. " losses " .. losses
        end
    end
    sections[#sections + 1] = lines
    for _, variable in ipairs({"user", "item"}) do
        local bounds = variable == "user" and params.user_groups or params.item_groups
        local counts = variable == "user" and data.user_counts or data.item_counts
        lines = {variable .. "_groups bounds " .. table.concat(bounds, " ")}
        for group = 1, #bounds + 1 do
            local indices = {}
            for t, row in ipairs(data.test) do
                if group_number(counts[row[variable]], bounds) == group then
                    indices[#indices + 1] = t
                end
            end
            local first = group == 1 and 1 or bounds[group - 1]
            local last = group == #bounds + 1 and "-" or bounds[group] - 1
            lines[#lines + 1] = "group " .. group .. " from " .. first .. " to " .. last .. " pairs " .. #indices .. " " .. error_fields(tested, indices, false)
        end
        sections[#sections + 1] = lines
    end
    lines = {"by_rating"}
    for value = 1, 5 do
        local indices = {}
        for t, row in ipairs(data.test) do
            if row.rating == value then
                indices[#indices + 1] = t
            end
        end
        lines[#lines + 1] = "rating " .. value .. " pairs " .. #indices .. " " .. error_fields(tested, indices, true)
    end
    sections[#sections + 1] = lines
    local test_genres = {}
    for t, row in ipairs(data.test) do
        for _, genre in ipairs(data.catalog[row.item].genres) do
            test_genres[genre] = test_genres[genre] or {}
            test_genres[genre][#test_genres[genre] + 1] = t
        end
    end
    lines = {"genres"}
    for _, genre in ipairs(sorted_keys(test_genres)) do
        local indices = test_genres[genre]
        lines[#lines + 1] = "genre " .. genre .. " pairs " .. #indices .. " " .. error_fields(tested, indices, false)
    end
    sections[#sections + 1] = lines
    local relevant_total = 0
    for _, u in ipairs(tested.evaluated) do
        relevant_total = relevant_total + tested.relevant_counts[u]
    end
    lines = {"ranking users " .. #tested.evaluated .. " relevant " .. relevant_total}
    for _, count in ipairs(params.cutoffs) do
        lines[#lines + 1] = "cutoff " .. count
        for _, method in ipairs(rankings) do
            local hits, recall, ndcg, ap, rr, hit_users = 0, 0.0, 0.0, 0.0, 0.0, 0
            for _, u in ipairs(tested.evaluated) do
                local metric = ranked_metrics(predictor, tested, u, method, count)
                hits, recall, ndcg = hits + metric.hits, recall + metric.recall, ndcg + metric.ndcg
                ap, rr, hit_users = ap + metric.ap, rr + metric.rr, hit_users + (metric.hits > 0 and 1 or 0)
            end
            local users = #tested.evaluated
            lines[#lines + 1] = "  " .. method .. " precision " .. real(hits / (count * users)) .. " recall " .. real(recall / users) .. " ndcg " .. real(ndcg / users) .. " map " .. real(ap / users) .. " mrr " .. real(rr / users) .. " hit_rate " .. real(hit_users / users)
        end
    end
    sections[#sections + 1] = lines
    local head = #data.items // 5
    local popular = {}
    for index = 1, head do
        popular[predictor.popularity[index]] = true
    end
    lines = {"beyond_accuracy top_n " .. params.top .. " head " .. head}
    for _, method in ipairs(rankings) do
        local coverage, diversity, novelty, popularity, long_tail, similarity = {}, 0, 0.0, 0, 0, 0.0
        for _, u in ipairs(tested.evaluated) do
            local list, genres, nov, pair_sum = predictor:ranked(method, u), {}, 0.0, 0.0
            for rank = 1, params.top do
                local i = list[rank]
                coverage[i] = true
                for _, genre in ipairs(data.catalog[i].genres) do
                    genres[genre] = true
                end
                nov = nov + math.log(#data.users / data.item_counts[i], 2)
                popularity = popularity + data.item_counts[i]
                long_tail = long_tail + (popular[i] and 0 or 1)
            end
            diversity = diversity + #sorted_keys(genres)
            novelty = novelty + nov / params.top
            for a = 1, params.top - 1 do
                for b = a + 1, params.top do
                    local value = neighbors.items[list[a]][list[b]]
                    pair_sum = pair_sum + (value and value.value or 0.0)
                end
            end
            similarity = similarity + pair_sum / (params.top * (params.top - 1) // 2)
        end
        local users = #tested.evaluated
        lines[#lines + 1] = method .. " coverage " .. real(#sorted_keys(coverage) / #data.items) .. " diversity " .. real(diversity / users) .. " novelty " .. real(novelty / users) .. " popularity " .. real(popularity / (params.top * users)) .. " long_tail " .. real(long_tail / (params.top * users)) .. " similarity " .. real(similarity / users)
    end
    sections[#sections + 1] = lines
    lines = {"ranking_groups top_n " .. params.top .. " bounds " .. table.concat(params.user_groups, " ")}
    for group = 1, #params.user_groups + 1 do
        local users = {}
        for _, u in ipairs(tested.evaluated) do
            if group_number(data.user_counts[u], params.user_groups) == group then
                users[#users + 1] = u
            end
        end
        local fields = {"group " .. group .. " users " .. #users}
        for _, method in ipairs(rankings) do
            local sum = 0.0
            for _, u in ipairs(users) do
                sum = sum + ranked_metrics(predictor, tested, u, method, params.top).ndcg
            end
            fields[#fields + 1] = method .. " " .. real(#users > 0 and sum / #users or nil)
        end
        lines[#lines + 1] = table.concat(fields, " ")
    end
    sections[#sections + 1] = lines
    lines = {"agreement top_n " .. params.top}
    for a = 1, #rankings - 1 do
        for b = a + 1, #rankings do
            local total = 0.0
            for _, u in ipairs(tested.evaluated) do
                local first, second = predictor:ranked(rankings[a], u), predictor:ranked(rankings[b], u)
                local members, intersection = {}, 0
                for rank = 1, params.top do
                    members[first[rank]] = true
                end
                for rank = 1, params.top do
                    intersection = intersection + (members[second[rank]] and 1 or 0)
                end
                total = total + intersection / (2 * params.top - intersection)
            end
            lines[#lines + 1] = rankings[a] .. " " .. rankings[b] .. " jaccard " .. real(total / #tested.evaluated)
        end
    end
    sections[#sections + 1] = lines
    lines = {"neighbor_grid"}
    local best_k, best_error = {}, {}
    for _, count in ipairs(params.neighbor_grid) do
        local fields = {"k " .. count}
        for _, method in ipairs({"USER_KNN", "ITEM_KNN"}) do
            local errors = {}
            for _, row in ipairs(data.test) do
                errors[#errors + 1] = evaluation.clip(predictor:predict(method, row.user, row.item, count).value) - row.rating
            end
            local value = evaluation.rmse(errors)
            fields[#fields + 1] = method .. " " .. real(value)
            if not best_error[method] or value < best_error[method] then
                best_error[method], best_k[method] = value, count
            end
        end
        lines[#lines + 1] = table.concat(fields, " ")
    end
    lines[#lines + 1] = "best USER_KNN " .. best_k.USER_KNN .. " ITEM_KNN " .. best_k.ITEM_KNN
    sections[#sections + 1] = lines
    lines = {"biases"}
    for _, kind in ipairs({"item_high", "item_low", "user_high", "user_low"}) do
        local item = kind:sub(1, 4) == "item"
        local ids = item and data.items or data.users
        local biases = item and predictor.baseline_model.items or predictor.baseline_model.users
        local counts = item and data.item_counts or data.user_counts
        local means = item and data.item_means or data.user_means
        local order = bias_order(ids, biases, kind:sub(-4) == "high")
        for index = 1, params.list_size do
            local id = order[index]
            local line = kind .. " " .. id .. " bias " .. real(biases[id]) .. " count " .. counts[id] .. " mean " .. real(means[id])
            if item then
                line = line .. " " .. data.catalog[id].title
            end
            lines[#lines + 1] = line
        end
    end
    sections[#sections + 1] = lines
    local output = {}
    for index, section in ipairs(sections) do
        if index > 1 then
            output[#output + 1] = ""
        end
        append(output, section)
    end
    return output
end
local function preferred_genres(data, u, liked)
    local counts = {}
    for _, row in ipairs(data.user_ratings[u]) do
        if liked and row.rating >= 4 or not liked and row.rating <= 2 then
            for _, genre in ipairs(data.catalog[row.item].genres) do
                counts[genre] = (counts[genre] or 0) + 1
            end
        end
    end
    local genres = sorted_keys(counts)
    table.sort(genres, function(a, b)
        if counts[a] ~= counts[b] then
            return counts[a] > counts[b]
        end
        return a < b
    end)
    local result = {}
    for index = 1, math.min(3, #genres) do
        result[index] = genres[index]
    end
    local fields = {}
    for _, genre in ipairs(result) do
        fields[#fields + 1] = genre .. " " .. counts[genre]
    end
    return result, #fields == 0 and "-" or table.concat(fields, " ")
end
local function popular_line(rank, i, data)
    return "  " .. rank .. " " .. i .. " count " .. data.item_counts[i] .. " mean " .. real(data.item_means[i]) .. " " .. data.catalog[i].title
end
local function recommendations_report(predictor, tested)
    local data, params, output = predictor.data, predictor.data.params, {}
    for request, u in ipairs(params.recommend_users) do
        if request > 1 then
            output[#output + 1] = ""
        end
        if not data.user_counts[u] then
            append(output, {"user " .. u .. " unknown", "list POPULAR"})
            for rank = 1, params.top do
                output[#output + 1] = popular_line(rank, predictor.popularity[rank], data)
            end
        else
            output[#output + 1] = "user " .. u .. " ratings " .. data.user_counts[u] .. " mean " .. real(data.user_means[u]) .. " bias " .. real(predictor.baseline_model.users[u])
            local liked, liked_text = preferred_genres(data, u, true)
            local _, disliked_text = preferred_genres(data, u, false)
            append(output, {"liked_genres " .. liked_text, "disliked_genres " .. disliked_text})
            local recent = copy(data.user_ratings[u])
            table.sort(recent, function(a, b)
                if a.time ~= b.time then
                    return a.time > b.time
                end
                return a.item < b.item
            end)
            local fields = {"recent"}
            for rank = 1, math.min(3, #recent) do
                fields[#fields + 1] = recent[rank].item .. " " .. recent[rank].rating
            end
            output[#output + 1] = table.concat(fields, " ")
            local users = {}
            for _, v in ipairs(data.users) do
                local value = predictor.neighbors.users[u][v]
                if value and value.value > params.threshold then
                    users[#users + 1] = {id = v, similarity = value.value, common = value.common}
                end
            end
            for _, neighbor in ipairs(neighborhood.select(users, params.list_size)) do
                output[#output + 1] = "neighbor " .. neighbor.id .. " similarity " .. real(neighbor.similarity) .. " common " .. neighbor.common
            end
            for t, row in ipairs(data.test) do
                if row.user == u then
                    fields = {"heldout " .. row.item .. " actual " .. row.rating}
                    for method = 1, #methods do
                        fields[#fields + 1] = real(tested.clipped[method][t])
                    end
                    output[#output + 1] = table.concat(fields, " ")
                end
            end
            for _, method in ipairs(rankings) do
                local list, genre_match = predictor:ranked(method, u), 0
                for rank = 1, params.top do
                    local matched = false
                    for _, genre in ipairs(data.catalog[list[rank]].genres) do
                        if contains(liked, genre) then
                            matched = true
                        end
                    end
                    genre_match = genre_match + (matched and 1 or 0)
                end
                output[#output + 1] = "list " .. method .. " genre_match " .. genre_match
                for rank = 1, params.top do
                    local i = list[rank]
                    if method == "POPULAR" then
                        output[#output + 1] = popular_line(rank, i, data)
                    else
                        local prediction = predictor:predict(method, u, i)
                        local line = "  " .. rank .. " " .. i .. " " .. real(prediction.value)
                        if method == "USER_KNN" or method == "ITEM_KNN" then
                            line = line .. " via " .. (prediction.top or "-")
                        end
                        output[#output + 1] = line .. " " .. data.catalog[i].title
                    end
                end
            end
        end
    end
    return output
end
local function similar_items_report(predictor)
    local data, params, output = predictor.data, predictor.data.params, {}
    local neighbors = predictor.neighbors
    for request, i in ipairs(params.similar_items) do
        if request > 1 then
            output[#output + 1] = ""
        end
        local information = data.catalog[i]
        output[#output + 1] = "item " .. i .. " ratings " .. data.item_counts[i] .. " mean " .. real(data.item_means[i]) .. " bias " .. real(predictor.baseline_model.items[i]) .. " genres " .. information.genres_text .. " title " .. information.title
        local similarity, factors, common, slope = {}, {}, {}, {}
        for _, j in ipairs(data.items) do
            if j ~= i then
                local record = neighbors.items[i][j]
                if record then
                    similarity[#similarity + 1] = {id = j, value = record.value, common = record.common}
                end
                local first, second = predictor.svd.items[i], predictor.svd.items[j]
                local cosine = factorization.dot(first, second) / math.sqrt(factorization.dot(first, first) * factorization.dot(second, second))
                factors[#factors + 1] = {id = j, value = cosine}
                local count = neighbors.common[i][j]
                if count then
                    common[#common + 1] = {id = j, common = count}
                    slope[#slope + 1] = {id = j, common = count, difference = neighbors.difference[j][i], deviation = neighbors.difference[j][i] / (count + params.shrinkage)}
                end
            end
        end
        local function descending(a, b)
            if a.value ~= b.value then
                return a.value > b.value
            end
            return a.id < b.id
        end
        table.sort(similarity, descending)
        table.sort(factors, descending)
        table.sort(common, function(a, b)
            if a.common ~= b.common then
                return a.common > b.common
            end
            return a.id < b.id
        end)
        table.sort(slope, function(a, b)
            if a.deviation ~= b.deviation then
                return a.deviation > b.deviation
            elseif a.common ~= b.common then
                return a.common > b.common
            end
            return a.id < b.id
        end)
        output[#output + 1] = "cosine"
        for rank = 1, math.min(params.list_size, #similarity) do
            local row = similarity[rank]
            output[#output + 1] = "  " .. rank .. " " .. row.id .. " similarity " .. real(row.value) .. " common " .. row.common .. " " .. data.catalog[row.id].title
        end
        output[#output + 1] = "factors"
        for rank = 1, math.min(params.list_size, #factors) do
            local row = factors[rank]
            output[#output + 1] = "  " .. rank .. " " .. row.id .. " similarity " .. real(row.value) .. " " .. data.catalog[row.id].title
        end
        output[#output + 1] = "co_rated"
        for rank = 1, math.min(params.list_size, #common) do
            local row = common[rank]
            output[#output + 1] = "  " .. rank .. " " .. row.id .. " common " .. row.common .. " " .. data.catalog[row.id].title
        end
        output[#output + 1] = "slope_one"
        for rank = 1, math.min(params.list_size, #slope) do
            local row = slope[rank]
            output[#output + 1] = "  " .. rank .. " " .. row.id .. " difference " .. row.difference .. " common " .. row.common .. " " .. data.catalog[row.id].title
        end
    end
    return output
end
local function training_log(predictor)
    local lines = {"method,epoch,train_rmse"}
    for _, entry in ipairs({{"BASELINE", predictor.baseline_model.log}, {"SVD", predictor.svd.log}, {"ALS", predictor.als.log}}) do
        for epoch, value in ipairs(entry[2]) do
            lines[#lines + 1] = entry[1] .. "," .. epoch .. "," .. real(value)
        end
    end
    return lines
end
local data = ratings.read()
local predictor = build_predictor(data)
local tested = test_predictions(predictor)
os.execute("mkdir -p output")
report.save("predictions.csv", tested.csv)
report.save("evaluation.txt", evaluation_report(predictor, tested))
report.save("recommendations.txt", recommendations_report(predictor, tested))
report.save("similar_items.txt", similar_items_report(predictor))
report.save("training_log.csv", training_log(predictor))
