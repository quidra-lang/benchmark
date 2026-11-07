local M = {}
function M.line_class(slack, last)
    if last then
        return 1
    elseif slack <= 1 then
        return 0
    elseif slack <= 3 then
        return 1
    elseif slack <= 6 then
        return 2
    end
    return 3
end
function M.line_cost(metrics, start, finish, previous_class, params)
    local slack, last = metrics:slack(start, finish), finish == metrics.finish
    local current_class = M.line_class(slack, last)
    local cost = params.line_penalty
    if slack < 0 then
        cost = cost + params.overfull_penalty
    elseif not last then
        cost = cost + slack * slack
    end
    if metrics.breaks[finish].midword then
        cost = cost + params.hyphen_penalty
        if metrics.breaks[start].midword then
            cost = cost + params.double_hyphen_demerit
        end
    end
    if last and metrics.breaks[start].midword then
        cost = cost + params.final_hyphen_demerit
    end
    if math.abs(current_class - previous_class) >= 2 then
        cost = cost + params.fitness_demerit
    end
    return cost
end
function M.cost(metrics, breaking, params)
    local total, start, previous_class = 0, 0, 1
    for _, finish in ipairs(breaking) do
        total = total + M.line_cost(metrics, start, finish, previous_class, params)
        previous_class = M.line_class(metrics:slack(start, finish), finish == metrics.finish)
        start = finish
    end
    return total
end
function M.break_text(metrics, method, params)
    local breaking = {}
    if method == "greedy" then
        local start = 0
        while start < metrics.finish do
            local chosen = start + 1
            if metrics:slack(start, chosen) >= 0 then
                for finish = chosen + 1, metrics.finish do
                    if metrics:slack(start, finish) < 0 then
                        break
                    end
                    chosen = finish
                end
            end
            breaking[#breaking + 1] = chosen
            start = chosen
        end
        return breaking, M.cost(metrics, breaking, params)
    end
    local states = {[0] = {[1] = {cost = 0}}}
    for finish = 1, metrics.finish do
        states[finish] = {}
        for start = finish - 1, 0, -1 do
            local slack = metrics:slack(start, finish)
            if slack < 0 and finish ~= start + 1 then
                break
            end
            local class = M.line_class(slack, finish == metrics.finish)
            for previous_class = 0, 3 do
                local previous = states[start][previous_class]
                if previous then
                    local cost = previous.cost + M.line_cost(metrics, start, finish, previous_class, params)
                    local best = states[finish][class]
                    if not best or cost < best.cost or (cost == best.cost and (start < best.start or (start == best.start and previous_class < best.previous_class))) then
                        states[finish][class] = {cost = cost, start = start, previous_class = previous_class}
                    end
                end
            end
        end
    end
    local position, class = metrics.finish, 1
    local cost = states[position][class].cost
    while position > 0 do
        table.insert(breaking, 1, position)
        local state = states[position][class]
        position, class = state.start, state.previous_class
    end
    return breaking, cost
end
return M
