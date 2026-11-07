local counts = {}
local sentence = string.lower("Peter Piper picked a peck of pickled peppers!")
for letter in sentence:gmatch("[a-z]") do counts[letter] = (counts[letter] or 0) + 1 end
for code = 97, 122 do
    local letter = string.char(code)
    if counts[letter] then io.write(string.format("%s: %d\n", letter, counts[letter])) end
end
