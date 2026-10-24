local state, counts = 12345, {}
for total = 2, 12 do counts[total] = 0 end
for trial = 1, 1000 do
    state = (state * 48271) % 2147483647
    local first = state % 6 + 1
    state = (state * 48271) % 2147483647
    local second = state % 6 + 1
    counts[first+second] = counts[first+second] + 1
end
local best = 2
for total = 2, 12 do
    io.write(string.format("%d: %d\n",total,counts[total]))
    if counts[total] > counts[best] then best = total end
end
io.write(string.format("most frequent: %d\n",best))
