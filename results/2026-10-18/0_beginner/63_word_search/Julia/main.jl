function find_word(board, word)
    directions = [
        ("E", 0, 1),
        ("SE", 1, 1),
        ("S", 1, 0),
        ("SW", 1, -1),
        ("W", 0, -1),
        ("NW", -1, -1),
        ("N", -1, 0),
        ("NE", -1, 1),
    ]
    for row = 0:9, column = 0:9
        for (name, dr, dc) in directions
            matched = true
            for offset = 0:(length(word)-1)
                r, c = row+offset*dr, column+offset*dc
                if !(0 <= r < 10 && 0 <= c < 10) || board[r+1][c+1] != word[offset+1]
                    matched = false
                    break
                end
            end
            matched && return string("(", row, ", ", column, ") ", name)
        end
    end
    return "not found"
end

board = [
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
]
for word in ["TIGER", "ZEBRA", "MONKEY", "PANDA", "KOALA", "RABBIT"]
    println(word, ": ", find_word(board, word))
end
