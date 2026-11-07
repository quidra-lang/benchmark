local board = {
    "MMONKENBIR",
    "PMTIGERJPL",
    "TGREJEDUZI",
    "SPYUTEJDEC",
    "WKAPSIDLBN",
    "KUVNGSBPRO",
    "RIBSDACBAM",
    "YWVAUAPKAH",
    "KYCGTHHESR",
    "OCCALAOKKR",
}

local function find_word(word)
    local directions = {
        {"E", 0, 1}, {"SE", 1, 1}, {"S", 1, 0}, {"SW", 1, -1}, {"W", 0, -1}, {"NW", -1, -1},
        {"N", -1, 0}, {"NE", -1, 1},
    }
    for row = 0, 9 do
        for column = 0, 9 do
            for _, direction in ipairs(directions) do
                local matched = true
                for offset = 0, #word - 1 do
                    local r, c = row + offset * direction[2], column + offset * direction[3]
                    if r < 0 or r >= 10 or c < 0 or c >= 10
                        or board[r + 1]:sub(c + 1, c + 1) ~= word:sub(offset + 1, offset + 1) then
                        matched = false
                        break
                    end
                end
                if matched then return string.format("(%d, %d) %s", row, column, direction[1]) end
            end
        end
    end
    return "not found"
end

for _, word in ipairs({"TIGER", "ZEBRA", "MONKEY", "PANDA", "KOALA", "RABBIT"}) do
    io.write(word, ": ", find_word(word), "\n")
end
