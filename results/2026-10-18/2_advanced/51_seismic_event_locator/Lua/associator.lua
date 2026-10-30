local M = {}
function M.associate(picks, window, minimum)
    local candidates = {}
    for index, first in ipairs(picks) do
        if not first.assigned then
            local selected, stations = {}, {}
            for current = index, #picks do
                local pick = picks[current]
                if pick.sample > first.sample + window then
                    break
                end
                if not pick.assigned and not stations[pick.station] then
                    selected[#selected + 1], stations[pick.station] = current, true
                end
            end
            if #selected >= minimum then
                for _, current in ipairs(selected) do
                    picks[current].assigned = true
                end
                candidates[#candidates + 1] = {number = #candidates + 1, first = index, picks = selected,
                    passes = {}, dropped = {}, event = 0, rejected = false}
            end
        end
    end
    return candidates
end
return M
