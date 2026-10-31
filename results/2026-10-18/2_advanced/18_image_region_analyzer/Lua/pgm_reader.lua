local M = {}

function M.read_images(path)
    local words = {}
    for line in io.lines(path) do
        line = line:gsub("#.*", "")
        for word in line:gmatch("%S+") do words[#words + 1] = word end
    end
    local images, position = {}, 1
    while position <= #words do
        local image = {
            name = words[position + 1], width = tonumber(words[position + 3]),
            height = tonumber(words[position + 4]), maxval = tonumber(words[position + 5]),
            pixels = {}
        }
        position = position + 6
        for y = 1, image.height do
            local row = {}
            for x = 1, image.width do
                row[x] = tonumber(words[position])
                position = position + 1
            end
            image.pixels[y] = row
        end
        images[#images + 1] = image
    end
    return images
end

return M
