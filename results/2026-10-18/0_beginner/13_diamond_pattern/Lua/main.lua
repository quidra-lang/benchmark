local n = 5

local function row(i)
    io.write(string.rep(" ", n - i), string.rep("*", 2 * i - 1), "\n")
end

for i = 1, n do row(i) end
for i = n - 1, 1, -1 do row(i) end
