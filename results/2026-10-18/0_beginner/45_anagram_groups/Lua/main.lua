local groups,indices = {},{}
for _, word in ipairs({"listen","stone","night","silent","notes","apple","thing","enlist","earth","onset","heart","tones"}) do
    local letters = {}
    for letter in word:gmatch(".") do letters[#letters+1] = letter end
    table.sort(letters)
    local signature = table.concat(letters)
    if not indices[signature] then
        groups[#groups+1] = {}
        indices[signature] = #groups
    end
    local group = groups[indices[signature]]
    group[#group+1] = word
end
for _, group in ipairs(groups) do io.write(table.concat(group," "),"\n") end
