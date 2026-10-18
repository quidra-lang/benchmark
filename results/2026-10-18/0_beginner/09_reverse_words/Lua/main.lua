local sentence = "every program starts with a single line"
io.write(string.reverse(sentence), "\n")
local words = {}
for word in sentence:gmatch("%S+") do
    words[#words + 1] = word
end
local reversed = {}
for i = #words, 1, -1 do
    reversed[#reversed + 1] = words[i]
end
io.write(table.concat(reversed, " "), "\n")
