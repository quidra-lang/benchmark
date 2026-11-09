local deck = {}
for suit in ("SHDC"):gmatch(".") do
    for rank in ("A23456789TJQK"):gmatch(".") do deck[#deck + 1] = rank .. suit end
end
local state = 2026
for i = 51, 1, -1 do
    state = (state * 48271) % 2147483647
    local j = state % (i + 1)
    deck[i + 1], deck[j + 1] = deck[j + 1], deck[i + 1]
end
for first = 1, 52, 13 do io.write(table.concat(deck, " ", first, first + 12), "\n") end
