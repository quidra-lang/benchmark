local words = {}
for word in ("we planted beans and carrots in the garden behind our old house"):gmatch("%S+") do words[#words+1] = word end
local longest, shortest, total = words[1], words[1], 0
for _, word in ipairs(words) do
    total = total + #word
    if #word > #longest then longest = word end
    if #word < #shortest then shortest = word end
end
local average = total / #words
io.write(string.format("words: %d\nlongest: %s\nshortest: %s\naverage length: %.2f\n", #words, longest, shortest, math.floor(average*100+0.5)/100))
