local numbers = {12, 5, 12, 8, 3, 5, 20, 8, 8, 15, 3, 7, 20, 12, 9}
local seen, remaining = {}, {}
for _, n in ipairs(numbers) do
    if not seen[n] then seen[n] = true; remaining[#remaining+1] = n end
end
io.write(table.concat(remaining, " "), "\n", string.format("removed: %d\n", #numbers-#remaining))
