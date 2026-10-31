local I = {}
function I.step(rates, state, multiplier)
    local h, half, sixth = 0.25, 0.25 / 2, 0.25 / 6
    local k1, shifted = rates(state, multiplier), {}
    for i, value in ipairs(state) do shifted[i] = value + half * k1[i] end
    local k2 = rates(shifted, multiplier)
    for i, value in ipairs(state) do shifted[i] = value + half * k2[i] end
    local k3 = rates(shifted, multiplier)
    for i, value in ipairs(state) do shifted[i] = value + h * k3[i] end
    local k4 = rates(shifted, multiplier)
    local result = {}
    for i, value in ipairs(state) do result[i] = value + sixth * (((k1[i] + 2 * k2[i]) + 2 * k3[i]) + k4[i]) end
    return result
end
function I.simulate(rates, initial, multipliers, inflows)
    local state, daily = {}, {}
    for i, value in ipairs(initial) do state[i] = value end
    for _, multiplier in ipairs(multipliers) do
        for _, i in ipairs(inflows) do state[i] = 0.0 end
        for _ = 1, 4 do state = I.step(rates, state, multiplier) end
        daily[#daily + 1] = state
        local copy = {}; for i, value in ipairs(state) do copy[i] = value end; state = copy
    end
    return daily
end
return I
