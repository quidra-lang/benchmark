local a, b = {}, {}
for _, n in ipairs({12, 5, 8, 21, 5, 17, 3, 12, 9}) do a[n] = true end
for _, n in ipairs({8, 14, 21, 6, 14, 3, 25, 6}) do b[n] = true end
local all = {}
for n in pairs(a) do all[n] = true end
for n in pairs(b) do all[n] = true end
local results = {{}, {}, {}, {}}
for n in pairs(all) do
    results[1][#results[1] + 1] = n
    if a[n] and b[n] then results[2][#results[2] + 1] = n end
    if a[n] and not b[n] then results[3][#results[3] + 1] = n end
    if not (a[n] and b[n]) then results[4][#results[4] + 1] = n end
end
for i, label in ipairs({"union", "intersection", "difference", "symmetric difference"}) do
    table.sort(results[i])
    io.write(label, ": ", table.concat(results[i], " "), "\n")
end
