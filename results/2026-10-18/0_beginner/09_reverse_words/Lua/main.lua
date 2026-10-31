local sentence = "every program starts with a single line"
io.write(string.reverse(sentence), "\n")
local words = {}
for word in sentence:gmatch("%S+") do
    table.insert(words, 1, word)
end
io.write(table.concat(words, " "), "\n")
