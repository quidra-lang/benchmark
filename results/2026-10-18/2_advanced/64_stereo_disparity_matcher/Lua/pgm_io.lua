local P = {}
function P.read(path)
    local input = assert(io.open(path, "r"))
    input:read("*l")
    local width, height = input:read("*l"):match("^(%d+) (%d+)$")
    input:read("*l")
    local pixels = {}
    for line in input:lines() do for word in line:gmatch("%d+") do pixels[#pixels + 1] = tonumber(word) end end
    input:close()
    return tonumber(width), tonumber(height), pixels
end
function P.parameters()
    local result = { sample_pixels = {} }
    for line in io.lines("input/params.txt") do
        local words = {}
        for word in line:gmatch("%S+") do words[#words + 1] = word end
        local key = words[1]
        if key == "sample" then result.sample_pixels[#result.sample_pixels + 1] = { tonumber(words[2]), tonumber(words[3]) }
        elseif key == "wta_cost" or key == "sgm_cost" then result[key] = words[2]
        elseif key == "sad_windows" or key == "ssd_windows" or key == "census_windows" then
            result[key] = {}; for i = 2, #words do result[key][#result[key] + 1] = tonumber(words[i]) end
        else result[key] = tonumber(words[2]) end
    end
    return result
end
function P.write(path, width, height, pixels)
    local output = assert(io.open(path, "w"))
    output:write("P2\n", width, " ", height, "\n255\n")
    for y = 0, height - 1 do output:write(table.concat(pixels, " ", y * width + 1, (y + 1) * width), "\n") end
    output:close()
end
return P
