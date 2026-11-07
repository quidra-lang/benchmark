local Entropy = require("entropy")
local I = {}
local function integers(line)
    local result = {}
    for word in line:gmatch("%-?%d+") do result[#result + 1] = tonumber(word) end
    return result
end
function I.read_ppm(path)
    local input, image = assert(io.open(path, "r")), {}
    input:read("*l")
    local dimensions = integers(input:read("*l"))
    input:read("*l")
    for y = 1, dimensions[2] do
        local values, row = integers(input:read("*l")), {}
        for x = 1, dimensions[1] do row[x] = { values[3 * x - 2], values[3 * x - 1], values[3 * x] } end
        image[y] = row
    end
    input:close()
    return image
end
function I.write_ppm(path, image)
    local output = assert(io.open(path, "w"))
    output:write("P3\n", #image[1], " ", #image, "\n255\n")
    for _, row in ipairs(image) do
        local values = {}
        for _, pixel in ipairs(row) do for _, value in ipairs(pixel) do values[#values + 1] = value end end
        output:write(table.concat(values, " "), "\n")
    end
    output:close()
end
function I.params(path)
    local result = {}
    for line in io.lines(path) do
        local key, values = line:match("^(%S+) (.*)$")
        if key == "sampling" or key == "huffman" then result[key] = values
        elseif key == "qualities" or key == "truncate" then result[key] = integers(values)
        else result[key] = tonumber(values) end
    end
    return result
end
function I.tables(path)
    local input, transform, basic, huffman = assert(io.open(path, "r")), {}, {}, {}
    input:read("*l")
    for i = 1, 8 do transform[i] = integers(input:read("*l")) end
    for identifier = 1, 2 do
        input:read("*l")
        basic[identifier] = {}
        for i = 1, 8 do basic[identifier][i] = integers(input:read("*l")) end
    end
    for _ = 1, 4 do
        local class, identifier = input:read("*l"):match("^huffman (%d+) (%d+)$")
        local counts, symbols = integers(input:read("*l")), integers(input:read("*l"))
        huffman[Entropy.key(tonumber(class), tonumber(identifier))] = Entropy.table(counts, symbols)
    end
    input:close()
    return transform, basic, huffman
end
function I.read_hex(path)
    local data = {}
    for line in io.lines(path) do for i = 1, #line, 2 do data[#data + 1] = tonumber(line:sub(i, i + 1), 16) end end
    return data
end
function I.write_hex(path, data)
    local output = assert(io.open(path, "w"))
    for first = 1, #data, 32 do
        local bytes = {}
        for i = first, math.min(first + 31, #data) do bytes[#bytes + 1] = string.format("%02x", data[i]) end
        output:write(table.concat(bytes), "\n")
    end
    output:close()
end
return I
