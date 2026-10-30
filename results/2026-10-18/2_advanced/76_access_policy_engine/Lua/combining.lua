local combining = {}
local NA, IP, ID, IDP = 'NOT_APPLICABLE', 'INDETERMINATE{P}', 'INDETERMINATE{D}', 'INDETERMINATE{DP}'
local function indeterminate(decision) return decision:sub(1, 13) == 'INDETERMINATE' end
function combining.combine(algorithm, children, evaluate, target)
    local states = {}
    for index = 1, #children do states[index] = {kind = 'skipped'} end
    if algorithm == 'only-one-applicable' then
        local matched
        for index, child in ipairs(children) do
            local result = target(child)
            states[index] = {kind = 'checked', value = result}
            if result.kind == 'INDETERMINATE' then return IDP, result.reason, states end
            if result.kind == 'MATCH' then
                if matched then return IDP, 'multiple applicable ' .. children[matched].identifier .. ' ' .. child.identifier, states end
                matched = index
            end
        end
        if not matched then return NA, nil, states end
        local result = evaluate(children[matched]); states[matched] = {kind = 'evaluated', value = result}
        return result.decision, result.reason, states
    end
    local decisions, first_error = {}, nil
    for index, child in ipairs(children) do
        local result = evaluate(child)
        states[index] = {kind = 'evaluated', value = result}; decisions[result.decision] = true
        if indeterminate(result.decision) and first_error == nil then first_error = result.reason end
        if algorithm == 'first-applicable' and result.decision ~= NA then return result.decision, result.reason, states end
        if (algorithm == 'deny-overrides' or algorithm == 'permit-unless-deny') and result.decision == 'DENY' then return 'DENY', nil, states end
        if (algorithm == 'permit-overrides' or algorithm == 'deny-unless-permit') and result.decision == 'PERMIT' then return 'PERMIT', nil, states end
    end
    if algorithm == 'deny-unless-permit' then return 'DENY', nil, states end
    if algorithm == 'permit-unless-deny' then return 'PERMIT', nil, states end
    if algorithm == 'first-applicable' then return NA, nil, states end
    local result
    if algorithm == 'deny-overrides' then
        if decisions[IDP] or decisions[ID] and (decisions[IP] or decisions.PERMIT) then result = IDP
        elseif decisions[ID] then result = ID elseif decisions.PERMIT then result = 'PERMIT'
        elseif decisions[IP] then result = IP else result = NA end
    else
        if decisions[IDP] or decisions[IP] and (decisions[ID] or decisions.DENY) then result = IDP
        elseif decisions[IP] then result = IP elseif decisions.DENY then result = 'DENY'
        elseif decisions[ID] then result = ID else result = NA end
    end
    return result, indeterminate(result) and first_error or nil, states
end
return combining
