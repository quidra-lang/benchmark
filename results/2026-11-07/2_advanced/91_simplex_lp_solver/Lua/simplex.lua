local Q = require("rational")
return function(tableau, costs, candidates, objective)
    local iterations, lines = 0, {}
    while true do
        local reduced, entering = tableau:reduced(costs), false
        for _, k in ipairs(candidates) do if reduced[k] < Q.zero then entering = k; break end end
        if not entering then return { iterations = iterations, lines = lines } end
        local p, ratio, leaving = false, false, false
        for i, row in ipairs(tableau.values) do
            if row[entering] > Q.zero then
                local theta = tableau.rhs[i] / row[entering]
                if not p or theta < ratio or (theta == ratio and tableau.basic[i] < leaving) then
                    p, ratio, leaving = i, theta, tableau.basic[i]
                end
            end
        end
        if not p then return { iterations = iterations, lines = lines, unbounded = entering } end
        local before = reduced[entering]
        tableau:pivot(p, entering)
        iterations = iterations + 1
        lines[#lines + 1] = string.format("PIVOT %d enter %s reduced %s leave %s row %s ratio %s objective %s",
            iterations, tableau.column_names[entering], before, tableau.column_names[leaving], tableau.row_names[p],
            ratio, objective(tableau:phase_value(costs)))
    end
end
