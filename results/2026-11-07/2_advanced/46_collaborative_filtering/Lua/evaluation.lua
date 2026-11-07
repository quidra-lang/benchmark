local M = {}
function M.clip(value)
    return math.max(1.0, math.min(5.0, value))
end
function M.rmse(errors)
    local sum = 0.0
    for _, error in ipairs(errors) do
        sum = sum + error * error
    end
    return math.sqrt(sum / #errors)
end
function M.mae(errors)
    local sum = 0.0
    for _, error in ipairs(errors) do
        sum = sum + math.abs(error)
    end
    return sum / #errors
end
function M.rank_weight(rank)
    return 1.0 / math.log(rank + 1, 2)
end
function M.ranking(list, relevant, relevant_count, count)
    local hits, dcg, ap, reciprocal = 0, 0.0, 0.0, 0.0
    for rank = 1, count do
        if relevant[list[rank]] then
            hits = hits + 1
            dcg = dcg + M.rank_weight(rank)
            ap = ap + hits / rank
            if reciprocal == 0.0 then
                reciprocal = 1.0 / rank
            end
        end
    end
    local ideal, denominator = 0.0, math.min(count, relevant_count)
    for rank = 1, denominator do
        ideal = ideal + M.rank_weight(rank)
    end
    return {hits = hits, recall = hits / relevant_count, ndcg = dcg / ideal, ap = ap / denominator, rr = reciprocal}
end
return M
