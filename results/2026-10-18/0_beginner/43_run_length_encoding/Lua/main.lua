local function encode(source)
    local result,i = {},1
    while i <= #source do
        local j = i+1
        while j <= #source and source:sub(j,j) == source:sub(i,i) do j = j+1 end
        result[#result+1] = tostring(j-i)..source:sub(i,i); i = j
    end
    return table.concat(result)
end
local function decode(encoded)
    local result = {}
    for count,letter in encoded:gmatch("(%d+)([A-Z])") do result[#result+1] = string.rep(letter,tonumber(count)) end
    return table.concat(result)
end
for _, source in ipairs({"AAABBBCCCD","WWWWWWWWWWWWBWWWWWWWWWWWWBBB","ALGORITHM","MISSISSIPPI","XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ"}) do
    local encoded = encode(source)
    io.write(source," -> ",encoded," -> ",decode(encoded),"\n")
end
