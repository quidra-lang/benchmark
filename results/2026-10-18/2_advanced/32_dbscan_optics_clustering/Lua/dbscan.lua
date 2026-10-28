local M = {}
function M.cluster(neighbors, minimum)
    local labels, core, cluster = {}, {}, 0
    for i, row in ipairs(neighbors) do
        labels[i], core[i] = -2, #row >= minimum
    end
    for i = 1, #neighbors do
        if labels[i] == -2 then
            if not core[i] then
                labels[i] = -1
            else
                labels[i] = cluster
                local queue, head = {}, 1
                for _, other in ipairs(neighbors[i]) do
                    queue[#queue + 1] = other
                end
                while head <= #queue do
                    local other = queue[head]
                    head = head + 1
                    if labels[other] == -1 then
                        labels[other] = cluster
                    elseif labels[other] == -2 then
                        labels[other] = cluster
                        if core[other] then
                            for _, next_point in ipairs(neighbors[other]) do
                                queue[#queue + 1] = next_point
                            end
                        end
                    end
                end
                cluster = cluster + 1
            end
        end
    end
    return labels, core
end
return M
